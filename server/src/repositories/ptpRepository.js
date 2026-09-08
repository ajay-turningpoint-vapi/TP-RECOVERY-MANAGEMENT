const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

function mapPtp(row) {
  if (!row) return null;
  return {
    id: row.id,
    customerId: row.customer_id,
    amountPromised: Number(row.amount_promised),
    promiseDate: row.promise_date,
    paymentMode: row.payment_mode,
    status: row.status,
    correctionRequestedAmount: row.correction_requested_amount === null ? null : Number(row.correction_requested_amount),
    correctionRequestedDate: row.correction_requested_date,
    correctionReason: row.correction_reason,
    correctionStatus: row.correction_status,
    amountReceived: row.amount_received === null || row.amount_received === undefined ? null : Number(row.amount_received),
    brokenReason: row.broken_reason,
    totalDueAtPromise: row.total_due_at_promise === null || row.total_due_at_promise === undefined ? null : Number(row.total_due_at_promise),
    totalOutstandingAtPromise:
      row.total_outstanding_at_promise === null || row.total_outstanding_at_promise === undefined
        ? null
        : Number(row.total_outstanding_at_promise),
  };
}

async function findAll() {
  const rows = await query('SELECT * FROM ptps ORDER BY promise_date');
  return rows.map(mapPtp);
}

async function findByCustomer(customerId) {
  const rows = await query('SELECT * FROM ptps WHERE customer_id = :customerId ORDER BY promise_date', { customerId });
  return rows.map(mapPtp);
}

async function findById(id) {
  const rows = await query('SELECT * FROM ptps WHERE id = :id LIMIT 1', { id });
  return mapPtp(rows[0]);
}

async function findPendingCorrections() {
  const rows = await query("SELECT * FROM ptps WHERE correction_status = 'Pending'");
  return rows.map(mapPtp);
}

async function hasActivePtpForCustomer(customerId, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const result = await run(
    `SELECT COUNT(*) AS cnt FROM ptps WHERE customer_id = :customerId AND status IN ('scheduled', 'pendingVerification', 'financialSyncPending')`,
    { customerId }
  );
  const rows = connection ? result[0] : result;
  return rows[0].cnt > 0;
}

async function insert(ptp, connection) {
  const id = ptp.id || uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO ptps (id, customer_id, amount_promised, promise_date, payment_mode, status,
                       total_due_at_promise, total_outstanding_at_promise)
     VALUES (:id, :customerId, :amountPromised, :promiseDate, :paymentMode, :status,
             :totalDueAtPromise, :totalOutstandingAtPromise)`,
    {
      id,
      customerId: ptp.customerId,
      amountPromised: ptp.amountPromised,
      promiseDate: ptp.promiseDate,
      paymentMode: ptp.paymentMode,
      status: ptp.status || 'scheduled',
      totalDueAtPromise: ptp.totalDueAtPromise ?? null,
      totalOutstandingAtPromise: ptp.totalOutstandingAtPromise ?? null,
    }
  );
  return id;
}

const COLUMN_MAP = {
  amountPromised: 'amount_promised',
  promiseDate: 'promise_date',
  paymentMode: 'payment_mode',
  status: 'status',
  correctionRequestedAmount: 'correction_requested_amount',
  correctionRequestedDate: 'correction_requested_date',
  correctionReason: 'correction_reason',
  correctionStatus: 'correction_status',
  amountReceived: 'amount_received',
  brokenReason: 'broken_reason',
  totalDueAtPromise: 'total_due_at_promise',
  totalOutstandingAtPromise: 'total_outstanding_at_promise',
};

/**
 * PTPs whose due date has arrived: still Scheduled, promise_date's calendar
 * day has started (caller passes tomorrow's IST midnight as the cutoff, so
 * `promise_date < cutoff` means "today or earlier"), and not frozen by a
 * pending correction request. Promoted to 'pendingVerification' — see
 * services/ptpVerificationService.js Pass A.
 */
async function findScheduledPastDue(cutoff, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const result = await run(
    `SELECT * FROM ptps
     WHERE status = 'scheduled'
       AND promise_date < :cutoff
       AND (correction_status IS NULL OR correction_status <> 'Pending')
     ORDER BY promise_date`,
    { cutoff }
  );
  const rows = connection ? result[0] : result;
  return rows.map(mapPtp);
}

/**
 * PTPs whose 1-day grace period has fully elapsed: still
 * 'pendingVerification', promise_date + 1 day already at/before the
 * cutoff, and not frozen by a pending correction request. Finalized to
 * kept/partiallyKept/broken against a real BUSY receipt check — see
 * services/ptpVerificationService.js Pass B.
 */
async function findPendingVerificationDue(cutoff, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  // Compares calendar days only (DATE(...) strips the time-of-day on both
  // sides) — the grace period is "1 calendar day after the due date", not
  // a 24-hour instant, so a promise_date stored with a specific time (e.g.
  // noon) must still become eligible at the verification date's midnight
  // sync, not half a day later.
  const result = await run(
    `SELECT * FROM ptps
     WHERE status = 'pendingVerification'
       AND DATE_ADD(DATE(promise_date), INTERVAL 1 DAY) <= DATE(:cutoff)
       AND (correction_status IS NULL OR correction_status <> 'Pending')
     ORDER BY promise_date`,
    { cutoff }
  );
  const rows = connection ? result[0] : result;
  return rows.map(mapPtp);
}

async function update(id, fields, connection) {
  const keys = Object.keys(fields).filter((k) => COLUMN_MAP[k]);
  if (keys.length === 0) return;
  const setClause = keys.map((k) => `${COLUMN_MAP[k]} = :${k}`).join(', ');
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(`UPDATE ptps SET ${setClause} WHERE id = :id`, { ...fields, id });
}

module.exports = {
  mapPtp,
  findAll,
  findByCustomer,
  findById,
  findPendingCorrections,
  findScheduledPastDue,
  findPendingVerificationDue,
  hasActivePtpForCustomer,
  insert,
  update,
};
