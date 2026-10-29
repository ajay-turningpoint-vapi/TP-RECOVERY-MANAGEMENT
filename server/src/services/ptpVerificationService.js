const env = require('../config/env');
const logger = require('../config/logger');
const { withTransaction } = require('../config/db');
const ptpRepository = require('../repositories/ptpRepository');
const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const notificationRepository = require('../repositories/notificationRepository');
const { applyPtpOutcomeTx, evaluateBrokenPtpEscalation, reopenRecoveryAfterPtpOutcome, reconcileBrokenPtpEscalation } = require('./ptpService');
const receiptTotalsRepository = require('../busySync/reports/mssqlReceiptTotalsRepository');
const { withRetry } = require('../busySync/utils/retry');
const { BRANCHES } = require('../busySync/config/branches');
const { publish, emitChange } = require('../realtime/eventBus');

const BRANCH_BY_LABEL = new Map(BRANCHES.map((b) => [b.label, b]));
const TP_BRANCH = BRANCHES.find((b) => b.key === 'tp') || BRANCHES[0];

/** A PTP's BUSY branch = its customer's branch; anything unrecognised
 * (legacy/seed data) falls back to Turning Point. */
function branchForCustomer(customer) {
  return (customer && BRANCH_BY_LABEL.get(customer.branch)) || TP_BRANCH;
}

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

/**
 * The single source of truth for the kept/partiallyKept/broken threshold —
 * both finalizeDuePtps (first decision) and reverifyStalePtps (the
 * correction pass) call this, so the ₹1 EPS tolerance and the three
 * outcome bands can never drift apart between the two passes.
 */
/**
 * First day of a PTP's payment-check window: the day the salesman recorded
 * the promise. A customer who pays early (after promising, before the
 * promise date) has kept the promise — before 28 Oct only receipts dated on
 * or after the promise date counted, so an early payment read as BROKEN
 * (ASHRAF BHAI NATHANI: paid ₹15,862 on 15 Oct for a 16 Oct promise).
 * Never later than the promise date itself.
 */
function checkWindowStart(ptp, dueDate) {
  if (!ptp.createdAt) return dueDate;
  const recorded = istDateStr(new Date(ptp.createdAt));
  return recorded < dueDate ? recorded : dueDate;
}

/**
 * Money in this PTP's window already credited to ANOTHER kept / partly-kept
 * PTP of the same customer — one BUSY payment must only ever count once
 * (MANISH PARMAR, 28 Oct: one ₹50,000 receipt had been counted for two
 * overlapping promises). Only what was actually received inside the
 * overlapping days can be shared, so per overlap the deduction is
 * min(other PTP's credited amount, receipts in the overlap).
 * `receiptsBetween(start, end)` returns this customer's BUSY receipt total.
 */
async function alreadyCreditedElsewhere(ptp, startDate, endDate, receiptsBetween) {
  const others = await ptpRepository.findByCustomer(ptp.customerId);
  let credited = 0;
  for (const o of others) {
    if (o.id === ptp.id || !['kept', 'partiallyKept'].includes(o.status) || !o.amountReceived) continue;
    const oDue = istDateStr(new Date(o.promiseDate));
    const oStart = checkWindowStart(o, oDue);
    const oEnd = addDaysStr(oDue, 1);
    const from = oStart > startDate ? oStart : startDate;
    const to = oEnd < endDate ? oEnd : endDate;
    if (from > to) continue;
    credited += Math.min(o.amountReceived, await receiptsBetween(from, to));
  }
  return credited;
}

function decideOutcome(promised, paid) {
  if (paid + EPS >= promised) return { outcome: 'kept', received: Math.min(paid, promised) };
  if (paid > 0) return { outcome: 'partiallyKept', received: paid };
  return { outcome: 'broken', received: 0 };
}

function autoDescription(outcome, ptp, paid, received) {
  const promised = ptp.amountPromised;
  const busyAmt = `₹${Math.round(paid)}`;
  if (outcome === 'kept') {
    return (
      `System verified this PTP against real BUSY receipts/journal entries dated between the day the PTP was recorded and 1 day after the promise date (promised ` +
      `₹${promised.toFixed(0)}, BUSY total ${busyAmt}). Marked Kept — ₹${Math.round(received)} applied. ` +
      `No manual balance adjustment made; the BUSY sync already reflects this payment.`
    );
  }
  if (outcome === 'partiallyKept') {
    return (
      `System verified this PTP against real BUSY receipts/journal entries dated between the day the PTP was recorded and 1 day after the promise date: BUSY total ` +
      `${busyAmt}, less than the promised ₹${promised.toFixed(0)}. Marked Partially Kept — ₹${Math.round(received)} ` +
      `applied. No manual balance adjustment made; the BUSY sync already reflects this.`
    );
  }
  return (
    `System verified this PTP against real BUSY receipts/journal entries dated between the day the PTP was recorded and 1 day after the promise date and found no qualifying ` +
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
  // Promote the instant the promise datetime is reached (the `ptp-promote`
  // pass runs every 15 min), not just at the daily calendar cutoff.
  const candidates = await ptpRepository.findScheduledDueByTime();
  for (const ptp of candidates) {
    await ptpRepository.update(ptp.id, { status: 'pendingVerification' });
    try {
      await auditRepository.record(ptp.customerId, {
        type: 'PTP_PENDING_VERIFICATION',
        description: `Promise time passed (₹${Math.round(ptp.amountPromised)} due ${new Date(ptp.promiseDate).toLocaleString('en-IN')}) → PTP now Pending Verification.`,
        actor: 'System',
        source: 'PTP Verification',
      });
    } catch (err) {
      logger.warn('[ptp-verification] promote audit failed', { ptpId: ptp.id, message: err.message });
    }
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
 * PTP's own eligible window [day the PTP was recorded, promise_date + 1 day]
 * (see checkWindowStart) — a payment dated before the promise was made or
 * after the grace day is never counted — and matches the customer by ID
 * (never name).
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
  // Two PTPs with the same due date in the same branch would otherwise
  // fire the identical BUSY query twice — memoise per (database, window).
  const receiptTotalsCache = new Map();
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
      // Resolve the PTP's branch first — the receipt totals must be
      // queried against THAT branch's BUSY company database + PARENTGRP
      // list, or a Claart customer's real payment is invisible and the
      // PTP is wrongly auto-broken.
      const customerForBranch = await customerRepository.findById(ptp.customerId);
      if (!customerForBranch) {
        result.skippedNoData += 1;
        logger.warn('[ptp-verification] PTP verification skipped — customer not found', { ptpId: ptp.id, customerId: ptp.customerId });
        continue;
      }
      const branch = branchForCustomer(customerForBranch);

      // Eligible window: from the day the promise was recorded (early
      // payment counts) to the promise date + 1 day.
      const startDate = checkWindowStart(ptp, dueDate);
      const endDate = verificationDate;
      const cacheKey = `${branch.key}|${startDate}|${endDate}`;
      let rows = receiptTotalsCache.get(cacheKey);
      if (!rows) {
        rows = await withRetry('BUSY receipt totals fetch', () =>
          getReceiptTotals({
            startDate,
            endDate,
            database: branch.database,
            parentGroups: branch.parentGroups,
            conn: branch.conn,
          })
        );
        receiptTotalsCache.set(cacheKey, rows);
      }
      const match = rows.find((r) => r.customerId === ptp.customerId); // match by CUSTOMER_ID, never CUSTOMER_NAME
      const paidInWindow = match ? match.totalAmount : 0; // no row for the customer ⇒ ₹0, only at this final-verification point
      // One payment counts once: minus what overlapping kept PTPs already took.
      const receiptsBetween = async (from, to) => {
        const key = `${branch.key}|${from}|${to}`;
        let r = receiptTotalsCache.get(key);
        if (!r) {
          r = await withRetry('BUSY receipt totals fetch (overlap)', () =>
            getReceiptTotals({ startDate: from, endDate: to, database: branch.database, parentGroups: branch.parentGroups, conn: branch.conn })
          );
          receiptTotalsCache.set(key, r);
        }
        const hit = r.find((x) => x.customerId === ptp.customerId);
        return hit ? hit.totalAmount : 0;
      };
      let paid = Math.max(0, paidInWindow - (await alreadyCreditedElsewhere(ptp, startDate, endDate, receiptsBetween)));
      if (paid <= EPS) paid = 0;

      const decided = await withTransaction(async (conn) => {
        const customer = await customerRepository.findById(ptp.customerId);
        if (!customer) return { skip: 'noData' };

        const { outcome, received } = decideOutcome(promised, paid);
        const brokenReason =
          outcome === 'broken'
            ? 'Auto: no BUSY receipt or journal entry matching or covering the promised amount between the day the PTP was recorded and 1 day after the promise date (verified against BUSY receipt/journal totals).'
            : null;

        await applyPtpOutcomeTx(conn, {
          ptp,
          customer,
          outcome,
          received,
          paid,
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
      const receivedAmt = decided.outcome === 'broken' ? 0 : decided.outcome === 'kept' ? Math.min(paid, promised) : paid;
      decidedCustomerOutcomes.push({
        customerId: ptp.customerId,
        outcome: decided.outcome,
        promised,
        received: receivedAmt,
      });
      try {
        const label = decided.outcome === 'kept' ? 'KEPT' : decided.outcome === 'partiallyKept' ? 'PARTIAL' : 'BROKEN';
        await auditRepository.record(ptp.customerId, {
          type: 'PTP_VERIFIED',
          description: `BUSY check: ₹${Math.round(receivedAmt)} of ₹${Math.round(promised)} → ${label}.`,
          actor: 'System',
          source: 'PTP Verification',
        });
      } catch (auditErr) {
        logger.warn('[ptp-verification] verify audit failed', { ptpId: ptp.id, message: auditErr.message });
      }

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

  // Post-commit, after every PTP in this run has been decided.
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
  for (const { customerId, outcome, promised, received } of decidedCustomerOutcomes) {
    try {
      await reopenRecoveryAfterPtpOutcome(customerId, outcome, { promised, received });
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
    publish({ type: 'notification', scope: { broadcast: true } });
    // PTP statuses, customer balances/states, follow-up tasks and
    // escalations all moved during this pass.
    emitChange(['ptps', 'customers', 'tasks', 'escalations'], { reason: 'ptp.verification' });
  }

  logger.info('[ptp-verification] PTP verification complete', result);
  return { examined: candidates.length, ...result };
}

// Only these two statuses are ever reverify candidates; the ladder below
// is what "an upgrade" means for each — never a downgrade, and a 'kept'
// PTP is already the best outcome so it's never a candidate at all.
const OUTCOME_RANK = { broken: 0, partiallyKept: 1, kept: 2 };

/**
 * Correction pass: re-checks every 'broken' / 'partiallyKept' PTP within
 * the lookback window (env.ptpReverifyLookbackDays) against BUSY, for the
 * exact same eligible window finalizeDuePtps originally used
 * (promise_date to promise_date + 1 day) — never "BUSY as of today". BUSY
 * back-office receipt entry lags real payments by ~1.5 days (see this
 * file's header comment), so a PTP finalized broken before the receipt
 * was keyed in can heal itself here once it is.
 *
 * Upgrade-only: only writes when the recheck strictly improves on the
 * PTP's current outcome (broken → partiallyKept/kept, partiallyKept →
 * kept) via the SAME decideOutcome threshold finalizeDuePtps uses. Same
 * or worse → skipped silently, no audit noise, no write at all. Uses the
 * same applyPtpOutcomeTx(..., moveBalance: false) — BUSY sync's own
 * upsertFromBusy already moved the customer's balance, so this must never
 * double-count it — just a distinct `source` so the audit trail shows
 * this as a re-verify upgrade, not the original automatic verification.
 *
 * `branchLabel` scopes the scan to one branch's customers (the branch
 * that's mid-sync right now) so a 5-branch sync doesn't re-ask BUSY for
 * every other branch's stale PTPs on every single branch's pass; omit it
 * to scan all branches (e.g. a manual one-off run).
 *
 * `getReceiptTotals` is injectable, same pattern as finalizeDuePtps, so
 * tests can stub BUSY responses.
 */
async function reverifyStalePtps({ branchLabel, getReceiptTotals = receiptTotalsRepository.getReceiptTotals } = {}) {
  const sinceCutoff = addDaysStr(istDateStr(new Date()), -env.ptpReverifyLookbackDays);
  const candidates = await ptpRepository.findReverifiableCandidates(`${sinceCutoff} 00:00:00`);

  const result = { examined: 0, upgradedToKept: 0, upgradedToPartiallyKept: 0, unchanged: 0, skippedNoData: 0, errors: 0 };
  const upgradedCustomerIds = [];
  const receiptTotalsCache = new Map();

  for (const ptp of candidates) {
    const promised = ptp.amountPromised;
    const dueDate = istDateStr(new Date(ptp.promiseDate));
    const verificationDate = addDaysStr(dueDate, 1);

    try {
      const customerForBranch = await customerRepository.findById(ptp.customerId);
      if (!customerForBranch) {
        result.skippedNoData += 1;
        continue;
      }
      const branch = branchForCustomer(customerForBranch);
      if (branchLabel && branch.label !== branchLabel) continue;

      result.examined += 1;

      const startDate = checkWindowStart(ptp, dueDate);
      const endDate = verificationDate;
      const cacheKey = `${branch.key}|${startDate}|${endDate}`;
      let rows = receiptTotalsCache.get(cacheKey);
      if (!rows) {
        rows = await withRetry('BUSY receipt totals fetch (re-verify)', () =>
          getReceiptTotals({
            startDate,
            endDate,
            database: branch.database,
            parentGroups: branch.parentGroups,
            conn: branch.conn,
          })
        );
        receiptTotalsCache.set(cacheKey, rows);
      }
      const match = rows.find((r) => r.customerId === ptp.customerId);
      const paidInWindow = match ? match.totalAmount : 0;
      // One payment counts once: minus what overlapping kept PTPs already took.
      const receiptsBetween = async (from, to) => {
        const key = `${branch.key}|${from}|${to}`;
        let r = receiptTotalsCache.get(key);
        if (!r) {
          r = await withRetry('BUSY receipt totals fetch (overlap)', () =>
            getReceiptTotals({ startDate: from, endDate: to, database: branch.database, parentGroups: branch.parentGroups, conn: branch.conn })
          );
          receiptTotalsCache.set(key, r);
        }
        const hit = r.find((x) => x.customerId === ptp.customerId);
        return hit ? hit.totalAmount : 0;
      };
      let paid = Math.max(0, paidInWindow - (await alreadyCreditedElsewhere(ptp, startDate, endDate, receiptsBetween)));
      if (paid <= EPS) paid = 0;

      const { outcome, received } = decideOutcome(promised, paid);
      if (OUTCOME_RANK[outcome] <= OUTCOME_RANK[ptp.status]) {
        result.unchanged += 1;
        continue;
      }

      await withTransaction(async (conn) => {
        const customer = await customerRepository.findById(ptp.customerId);
        if (!customer) return;
        await applyPtpOutcomeTx(conn, {
          ptp,
          customer,
          outcome,
          received,
          paid,
          brokenReason: null,
          moveBalance: false,
          actor: 'System',
          source: 'PTP Re-Verification (Manual Sync)',
          description:
            `Re-checked against BUSY receipts/journal entries dated between the day the PTP was recorded and 1 day after the promise date ` +
            `(promised ₹${promised.toFixed(0)}, BUSY total ₹${Math.round(paid)}) — a late-entered receipt upgraded ` +
            `this PTP from ${ptp.status} to ${outcome}. ₹${Math.round(received)} applied; no manual balance ` +
            `adjustment made, the BUSY sync already reflects this payment.`,
        });
      });

      if (outcome === 'kept') result.upgradedToKept += 1;
      else result.upgradedToPartiallyKept += 1;
      upgradedCustomerIds.push({ customerId: ptp.customerId, outcome, promised, received });

      try {
        await auditRepository.record(ptp.customerId, {
          type: 'PTP_REVERIFIED',
          description: `Re-verify on sync: ₹${Math.round(received)} of ₹${Math.round(promised)} → upgraded ${ptp.status} to ${outcome}.`,
          actor: 'System',
          source: 'PTP Re-Verification (Manual Sync)',
        });
      } catch (auditErr) {
        logger.warn('[ptp-verification] re-verify audit failed', { ptpId: ptp.id, message: auditErr.message });
      }

      logger.info('[ptp-verification] PTP re-verified and upgraded', {
        ptpId: ptp.id,
        customerId: ptp.customerId,
        from: ptp.status,
        to: outcome,
        busyReceiptAmount: paid,
      });
    } catch (err) {
      result.errors += 1;
      logger.error('[ptp-verification] PTP re-verify failed for one PTP', { ptpId: ptp.id, message: err.message });
    }
  }

  // Broken-count dropping can both still-escalate (if it didn't drop
  // below a threshold) and, now that an upgrade just happened, needs the
  // normal post-outcome recovery-task follow-up same as finalizeDuePtps.
  for (const { customerId, outcome, promised, received } of upgradedCustomerIds) {
    try {
      await evaluateBrokenPtpEscalation(customerId);
    } catch (err) {
      logger.error('[ptp-verification] re-verify escalation check failed', { customerId, message: err.message });
    }
    // The upgrade just dropped this customer's broken-PTP count — walk
    // back (lower or resolve) any escalation that count itself caused.
    // Only ever touches cause: 'BrokenPTP' escalations; a Customer
    // Refused / Non-Contact / manual escalation on the same customer is
    // never auto-touched.
    try {
      await reconcileBrokenPtpEscalation(customerId);
    } catch (err) {
      logger.error('[ptp-verification] re-verify escalation reconcile failed', { customerId, message: err.message });
    }
    try {
      await reopenRecoveryAfterPtpOutcome(customerId, outcome, { promised, received });
    } catch (err) {
      logger.error('[ptp-verification] re-verify reopen recovery failed', { customerId, outcome, message: err.message });
    }
  }

  if (upgradedCustomerIds.length > 0) {
    emitChange(['ptps', 'customers', 'tasks', 'escalations'], { reason: 'ptp.reverify' });
  }

  logger.info('[ptp-verification] PTP re-verify pass complete', result);
  return result;
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

module.exports = { verifyDuePtps, promoteDuePtps, finalizeDuePtps, reverifyStalePtps, checkWindowStart, alreadyCreditedElsewhere, decideOutcome, branchForCustomer };
