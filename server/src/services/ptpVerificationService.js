const env = require('../config/env');
const logger = require('../config/logger');
const { withTransaction } = require('../config/db');
const ptpRepository = require('../repositories/ptpRepository');
const customerRepository = require('../repositories/customerRepository');
const notificationRepository = require('../repositories/notificationRepository');
const { applyPtpOutcomeTx, evaluateBrokenPtpEscalation, reopenRecoveryAfterPtpOutcome } = require('./ptpService');
const receiptTotalsRepository = require('../busySync/reports/mssqlReceiptTotalsRepository');
const { withRetry } = require('../busySync/utils/retry');

// BUSY ERP lags real-world payments by ~1.5 days (store takes a paper entry
// at time of payment → back-office keys the receipt into BUSY later). This
// service replaces the old 11:30 IST "PTP Auto-Reconciliation" job (which
// judged a PTP the very next day, off a customers.total_due delta) with two
// passes run as part of the daily (12:00 IST) BUSY sync job:
//
//   Pass A (promoteDuePtps)  — the instant a PTP's due date arrives, flip
//                              scheduled -> pendingVerification. Pure status
//                              flip, no BUSY call.
//   Pass B (finalizeDuePtps) — once 1 full day has passed since the due
//                              date, query BUSY for real receipts and
//                              journal entries dated [promise_date,
//                              promise_date + 1 day] (see
//                              busySync/reports/receiptTotalsReport.mssql.sql)
//                              and compare TOTAL_AMOUNT against the
//                              promised amount to finalize
//                              kept/partiallyKept/broken.
//
// A drop of at most EPS rupees below the promise still counts as "paid in
// full" (absorbs rounding between BUSY DECIMAL and JS float math) — same
// slack the old job used.
const EPS = 1;

/** 'YYYY-MM-DD' for the given instant in the business timezone (IST). */
function istDateStr(instant) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: env.businessTimezone }).format(instant);
}

/** 'YYYY-MM-DD' + N days, calendar-date arithmetic (no timezone drift — treated as a plain date, not an instant). */
function addDaysStr(dateStr, days) {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function autoDescription(outcome, ptp, paid, received) {
  const promised = ptp.amountPromised;
  const busyAmt = `₹${Math.round(paid)}`;
  if (outcome === 'kept') {
    return (
      `System verified this PTP against real BUSY receipts/journal entries dated within its 1-day grace period (promised ` +
      `₹${promised.toFixed(0)}, BUSY total ${busyAmt}). Marked Kept — ₹${Math.round(received)} applied. ` +
      `No manual balance adjustment made; the BUSY sync already reflects this payment.`
    );
  }
  if (outcome === 'partiallyKept') {
    return (
      `System verified this PTP against real BUSY receipts/journal entries dated within its 1-day grace period: BUSY total ` +
      `${busyAmt}, less than the promised ₹${promised.toFixed(0)}. Marked Partially Kept — ₹${Math.round(received)} ` +
      `applied. No manual balance adjustment made; the BUSY sync already reflects this.`
    );
  }
  return (
    `System verified this PTP against real BUSY receipts/journal entries dated within its 1-day grace period and found no qualifying ` +
    `entry (promised ₹${promised.toFixed(0)}, BUSY total ${busyAmt}). Marked Broken automatically; ` +
    `re-evaluating the broken-PTP escalation ladder.`
  );
}

/**
 * Pass A — promote every still-Scheduled PTP whose due date has arrived
 * (today or earlier, IST calendar day) to 'pendingVerification'. A PTP due
 * "today" is promoted at today's 12:00 IST sync run, same as it would have
 * matured under the old job's next-day cutoff logic, just one status
 * earlier in the lifecycle. Idempotent — only ever touches status='scheduled' rows.
 */
async function promoteDuePtps() {
  const todayIst = istDateStr(new Date());
  const cutoff = `${addDaysStr(todayIst, 1)} 00:00:00`; // tomorrow's IST midnight: promise_date < cutoff ⇔ due today or earlier
  const candidates = await ptpRepository.findScheduledPastDue(cutoff);
  for (const ptp of candidates) {
    await ptpRepository.update(ptp.id, { status: 'pendingVerification' });
    logger.info('[ptp-verification] PTP promoted to pendingVerification', {
      ptpId: ptp.id,
      customerId: ptp.customerId,
      dueDate: istDateStr(new Date(ptp.promiseDate)),
    });
  }
  return candidates.length;
}

/**
 * Pass B — finalize every 'pendingVerification' PTP whose 1-day grace
 * period has fully elapsed. For each, queries BUSY receipt totals for that
 * PTP's own eligible window [promise_date, promise_date + 1 day] — a
 * payment dated before the promise or after the grace window is never
 * counted — and matches the customer by ID (never name).
 *
 * `getReceiptTotals` is injectable (defaults to the real MSSQL repository)
 * so tests can stub BUSY responses without a live MSSQL connection.
 *
 * Idempotent — only ever touches status='pendingVerification' rows; once
 * finalized a PTP is kept/partiallyKept/broken and is never a candidate
 * again, so running this repeatedly (e.g. a retried job) never re-verifies
 * an already-decided PTP.
 */
async function finalizeDuePtps(getReceiptTotals = receiptTotalsRepository.getReceiptTotals) {
  const todayIst = istDateStr(new Date());
  const cutoff = `${todayIst} 00:00:00`;
  const candidates = await ptpRepository.findPendingVerificationDue(cutoff);

  const result = { kept: 0, partiallyKept: 0, broken: 0, skippedNoData: 0, errors: 0 };
  const brokenCustomerIds = [];
  // Every resolved PTP — kept, partiallyKept, or broken — can still leave
  // a real balance, so recovery needs re-checking after all three, not
  // just broken. Kept separate from brokenCustomerIds since escalation is
  // still broken-only.
  const decidedCustomerOutcomes = [];

  for (const ptp of candidates) {
    const promised = ptp.amountPromised;
    const dueDate = istDateStr(new Date(ptp.promiseDate));
    const verificationDate = addDaysStr(dueDate, 1);

    try {
      // Eligible window per the business rule: payment must be dated on/
      // after the promise date, and on/before the promise date + 1 day.
      const startDate = dueDate;
      const endDate = verificationDate;
      const rows = await withRetry('BUSY receipt totals fetch', () => getReceiptTotals({ startDate, endDate }));
      const match = rows.find((r) => r.customerId === ptp.customerId); // match by CUSTOMER_ID, never CUSTOMER_NAME
      const paid = match ? match.totalAmount : 0; // no row for the customer ⇒ ₹0, only at this final-verification point

      const decided = await withTransaction(async (conn) => {
        const customer = await customerRepository.findById(ptp.customerId);
        if (!customer) return { skip: 'noData' };

        let outcome;
        let received;
        let brokenReason = null;
        if (paid + EPS >= promised) {
          outcome = 'kept';
          received = Math.min(paid, promised);
        } else if (paid > 0) {
          outcome = 'partiallyKept';
          received = paid;
        } else {
          outcome = 'broken';
          received = 0;
          brokenReason =
            'Auto: no BUSY receipt or journal entry matching or covering the promised amount within the 1-day grace period (verified against BUSY receipt/journal totals).';
        }

        await applyPtpOutcomeTx(conn, {
          ptp,
          customer,
          outcome,
          received,
          brokenReason,
          moveBalance: false,
          actor: 'System',
          source: 'PTP Auto-Verification (BUSY Receipts/Journal)',
          description: autoDescription(outcome, ptp, paid, received),
        });

        return { outcome };
      });

      if (decided.skip === 'noData') {
        result.skippedNoData += 1;
        logger.warn('[ptp-verification] PTP verification skipped — customer not found', { ptpId: ptp.id, customerId: ptp.customerId });
        continue;
      }

      result[decided.outcome] += 1;
      if (decided.outcome === 'broken') brokenCustomerIds.push(ptp.customerId);
      decidedCustomerOutcomes.push({ customerId: ptp.customerId, outcome: decided.outcome });

      logger.info('[ptp-verification] PTP verified', {
        ptpId: ptp.id,
        customerId: ptp.customerId,
        ptpAmount: promised,
        dueDate,
        verificationDate,
        busyReceiptAmount: paid,
        result: decided.outcome,
        ...(decided.outcome === 'partiallyKept' ? { paid, remaining: promised - paid } : {}),
      });
    } catch (err) {
      result.errors += 1;
      logger.error('[ptp-verification] PTP verification failed for one PTP', { ptpId: ptp.id, message: err.message });
    }
  }

  // Post-commit, same as the manual mark-outcome path.
  for (const customerId of brokenCustomerIds) {
    try {
      await evaluateBrokenPtpEscalation(customerId);
    } catch (err) {
      logger.error('[ptp-verification] escalation check failed', { customerId, message: err.message });
    }
  }
  // Reopen recovery for every resolved PTP (kept/partiallyKept/broken) —
  // reopenRecoveryAfterPtpOutcome only actually creates a follow-up when
  // real due remains (ensureFollowUpIfNeeded's own totalDue <= 0 guard),
  // so a customer whose balance is fully cleared never gets a needless
  // task, and one who still owes money keeps getting chased regardless of
  // which way their PTP resolved.
  for (const { customerId, outcome } of decidedCustomerOutcomes) {
    try {
      await reopenRecoveryAfterPtpOutcome(customerId, outcome);
    } catch (err) {
      logger.error('[ptp-verification] reopen recovery after PTP outcome failed', { customerId, outcome, message: err.message });
    }
  }

  if (candidates.length > 0) {
    await notificationRepository.insert({
      severity: result.broken > 0 ? 'warning' : 'info',
      title: 'PTP verification complete',
      body:
        `Verified ${candidates.length} PTP(s) against BUSY receipts/journal entries: ${result.kept} kept, ${result.partiallyKept} ` +
        `partially kept, ${result.broken} broken, ${result.skippedNoData} skipped (no customer), ${result.errors} error(s).`,
    });
  }

  logger.info('[ptp-verification] PTP verification complete', result);
  return { examined: candidates.length, ...result };
}

/**
 * Entry point called from workers/busySyncWorker.js, after the daily
 * customer/invoice BUSY sync steps. Runs Pass A then Pass B. Unlike the old
 * maturity job, this has no dependency on customerAgeingSync's freshness —
 * Pass A is a pure date-based status flip, and Pass B queries BUSY receipts
 * directly for its own fixed window, so it's safe to run every night
 * regardless of whether the customer/ageing sync itself succeeded.
 */
async function verifyDuePtps({ getReceiptTotals } = {}) {
  const promoted = await promoteDuePtps();
  const finalized = await finalizeDuePtps(getReceiptTotals);
  return { promoted, ...finalized };
}

module.exports = { verifyDuePtps, promoteDuePtps, finalizeDuePtps };
