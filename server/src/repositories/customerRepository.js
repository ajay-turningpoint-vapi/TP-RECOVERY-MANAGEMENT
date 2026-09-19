const { query, withTransaction } = require('../config/db');

function mapCustomer(row) {
  if (!row) return null;
  const totalOutstanding = Number(row.total_outstanding);
  const creditLimit = Number(row.credit_limit || 0);
  return {
    id: row.id,
    name: row.name,
    contactNumber: row.contact_number,
    alternateContactNumber: row.alternate_contact_number,
    branch: row.branch,
    assignedSalesmanId: row.assigned_salesman_id,
    totalOutstanding,
    totalDue: Number(row.total_due),
    oldestOverdueDays: row.oldest_overdue_days,
    currentRecoveryState: row.current_recovery_state,
    primaryNextAction: row.primary_next_action,
    reasonForAction: row.reason_for_action,
    escalationLevel: row.escalation_level,
    hasValidNextAction: !!row.has_valid_next_action,
    ownerMappingRequired: !!row.owner_mapping_required,
    creditHealthScore: row.credit_health_score,
    disputedAmount: Number(row.disputed_amount),
    noAnswerAttempts: row.no_answer_attempts,
    refusedReopenCount: row.refused_reopen_count,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    // Real "when was this customer's financial data last refreshed from
    // BUSY" timestamp — falls back to updated_at for any customer that
    // predates the BUSY integration (busy_last_synced_at is null then), so
    // the freshness badge always reflects an actual point in time, never
    // "now" just because the field is missing.
    financialFreshness: row.busy_last_synced_at || row.updated_at,

    // BUSY-sourced fields (see migrations/006_customers_busy_fields.sql,
    // written only by the daily sync — customerAgeingSync.js /
    // upsertFromBusy below). Null/zero for any customer that predates
    // the BUSY integration. availableLimit/outstandingStatus are derived
    // here rather than stored, same pattern as creditHealthBand below.
    address: row.address,
    gstNo: row.gst_no,
    salesman: row.salesman,
    futureDue: Number(row.future_due_amount || 0),
    creditLimit,
    creditDays: row.credit_days,
    availableLimit: creditLimit - totalOutstanding,
    lastPaymentDate: row.last_receipt_date,
    lastPaymentAmount: row.last_receipt_amount == null ? null : Number(row.last_receipt_amount),
    outstandingStatus: totalOutstanding > 0 ? 'OUTSTANDING' : 'SETTLED',
    ageingBuckets: {
      age0_30: Number(row.age_0_30 || 0),
      age31_60: Number(row.age_31_60 || 0),
      age61_90: Number(row.age_61_90 || 0),
      age90Plus: Number(row.age_90_plus || 0),
    },
  };
}

// BUSY-sourced customers that fell out of the source query (paid off,
// reassigned) are soft-deactivated by the sync (busy_still_active = 0),
// not hard-deleted — they keep their real dispute/task/PTP/audit history,
// they just stop showing up in normal active-customer views. Never
// excludes a non-BUSY customer (busy_salesman_code IS NULL).
const ACTIVE_FILTER = '(busy_salesman_code IS NULL OR busy_still_active = 1)';

async function findAll() {
  const rows = await query(`SELECT * FROM customers WHERE ${ACTIVE_FILTER} ORDER BY name`);
  return rows.map(mapCustomer);
}

async function findBySalesman(salesmanId) {
  const rows = await query(
    `SELECT * FROM customers WHERE assigned_salesman_id = :salesmanId AND ${ACTIVE_FILTER} ORDER BY name`,
    { salesmanId }
  );
  return rows.map(mapCustomer);
}

async function findById(id) {
  const rows = await query('SELECT * FROM customers WHERE id = :id LIMIT 1', { id });
  return mapCustomer(rows[0]);
}

async function findByIds(ids) {
  if (!ids || ids.length === 0) return [];
  const rows = await query(`SELECT * FROM customers WHERE id IN (:ids) AND ${ACTIVE_FILTER} ORDER BY name`, { ids });
  return rows.map(mapCustomer);
}

function mapInvoice(raw) {
  return {
    id: raw.ref_code,
    No: raw.invoice_no,
    PartyName: raw.customer_name,
    CustomerId: raw.customer_id,
    Date: raw.invoice_date,
    DueDate: raw.due_date,
    TotalAmount: Number(raw.ref_amount ?? 0),
    PendingAmount: Number(raw.pending_amount ?? 0),
    DueDays: raw.due_days == null ? null : Number(raw.due_days),
    Message: raw.message,
    status: raw.message === 'EXCEEDED CREDIT DAYS' ? 'Outstanding' : 'Due Soon'
  };
}

async function findInvoices(customerId) {
  const rows = await query('SELECT * FROM customer_invoice_snapshot WHERE customer_id = :customerId ORDER BY due_date DESC', { customerId });
  return rows.map(mapInvoice);
}

/**
 * Applies a partial update to a customer row. `fields` uses camelCase keys
 * matching the API/model shape; this function owns the camelCase -> snake_case
 * column mapping so callers never write raw SQL column names.
 *
 * Deliberately only ever RMS-workflow columns — every BUSY-sourced column
 * (see mapCustomer above) is absent from this map on purpose, so no RMS
 * action can ever collide with what the daily sync writes.
 */
const COLUMN_MAP = {
  contactNumber: 'contact_number',
  alternateContactNumber: 'alternate_contact_number',
  branch: 'branch',
  assignedSalesmanId: 'assigned_salesman_id',
  totalOutstanding: 'total_outstanding',
  totalDue: 'total_due',
  oldestOverdueDays: 'oldest_overdue_days',
  currentRecoveryState: 'current_recovery_state',
  primaryNextAction: 'primary_next_action',
  reasonForAction: 'reason_for_action',
  escalationLevel: 'escalation_level',
  hasValidNextAction: 'has_valid_next_action',
  ownerMappingRequired: 'owner_mapping_required',
  creditHealthScore: 'credit_health_score',
  disputedAmount: 'disputed_amount',
  noAnswerAttempts: 'no_answer_attempts',
  refusedReopenCount: 'refused_reopen_count',
};

async function update(id, fields, connection) {
  const keys = Object.keys(fields).filter((k) => COLUMN_MAP[k]);
  if (keys.length === 0) return;
  const setClause = keys.map((k) => `${COLUMN_MAP[k]} = :${k}`).join(', ');
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(`UPDATE customers SET ${setClause} WHERE id = :id`, { ...fields, id });
}

/**
 * The daily sync's second stage (see busySync/sync/customerAgeingSync.js):
 * upserts real BUSY customer rows straight into the RMS `customers` table,
 * so BUSY data IS the RMS customer base rather than a separate overlay.
 *
 * Column ownership: only ever writes the BUSY-sourced columns (+ the
 * RMS-workflow defaults, and ONLY on first insert — see the ON DUPLICATE
 * KEY UPDATE clause below, which never touches them again once a
 * customer exists). Runs in its own transaction — independently atomic
 * from the snapshot table's own upsert+sweep in customerAgeingRepository.js.
 *
 * @param {Array} rows CustomerReport-shaped rows (customerId, customerName, mobile, gstNo, address, salesman, salesmanCode, ledgerClosingBalance, amountAlreadyDue, futureDueAmount, age0_30/31_60/61_90/90Plus, maxDaysOverdue, lastReceiptDate, lastReceiptAmount, creditLimit, creditDays)
 * @param {Date} syncStartedAt
 * @param {{ label: string }} branch  which BUSY branch these rows came from (config/branches.js)
 */
async function upsertFromBusy(rows, syncStartedAt, branch = { label: 'Turning Point' }) {
  const branchLabel = branch.label;
  return withTransaction(async (connection) => {
    // Batch-resolve salesman_code -> users.id once rather than one SELECT
    // per customer row.
    const [salesmenRows] = await connection.query(
      'SELECT id, busy_salesman_code FROM users WHERE busy_salesman_code IS NOT NULL'
    );
    const salesmanIdByCode = new Map(salesmenRows.map((r) => [r.busy_salesman_code, r.id]));

    for (const row of rows) {
      const id = String(row.customerId);
      const assignedSalesmanId = row.salesmanCode != null ? salesmanIdByCode.get(row.salesmanCode) ?? null : null;

      await connection.query(
        `INSERT INTO customers (
           id, name, contact_number, assigned_salesman_id, branch,
           total_outstanding, total_due, oldest_overdue_days,
           future_due_amount, age_0_30, age_31_60, age_61_90, age_90_plus,
           last_receipt_date, last_receipt_amount, credit_limit, credit_days,
           gst_no, address, salesman, busy_salesman_code, busy_last_synced_at, busy_still_active,
           current_recovery_state, primary_next_action, reason_for_action, escalation_level, has_valid_next_action
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'Action Required', 'CALL CUSTOMER', '', 'none', 1)
         ON DUPLICATE KEY UPDATE
           name = VALUES(name),
           contact_number = VALUES(contact_number),
           assigned_salesman_id = VALUES(assigned_salesman_id),
           branch = VALUES(branch),
           total_outstanding = VALUES(total_outstanding),
           total_due = VALUES(total_due),
           oldest_overdue_days = VALUES(oldest_overdue_days),
           future_due_amount = VALUES(future_due_amount),
           age_0_30 = VALUES(age_0_30),
           age_31_60 = VALUES(age_31_60),
           age_61_90 = VALUES(age_61_90),
           age_90_plus = VALUES(age_90_plus),
           last_receipt_date = VALUES(last_receipt_date),
           last_receipt_amount = VALUES(last_receipt_amount),
           credit_limit = VALUES(credit_limit),
           credit_days = VALUES(credit_days),
           gst_no = VALUES(gst_no),
           address = VALUES(address),
           salesman = VALUES(salesman),
           busy_salesman_code = VALUES(busy_salesman_code),
           busy_last_synced_at = VALUES(busy_last_synced_at),
           busy_still_active = 1`,
        [
          id,
          row.customerName,
          row.mobile || null,
          assignedSalesmanId,
          branchLabel,
          row.ledgerClosingBalance || 0,
          row.amountAlreadyDue || 0,
          row.maxDaysOverdue || 0,
          row.futureDueAmount || 0,
          row.age0_30 || 0,
          row.age31_60 || 0,
          row.age61_90 || 0,
          row.age90Plus || 0,
          row.lastReceiptDate,
          row.lastReceiptAmount,
          row.creditLimit || 0,
          row.creditDays || 0,
          row.gstNo || '',
          row.address || null,
          row.salesman || null,
          row.salesmanCode,
          syncStartedAt,
        ]
      );
    }

    // Scoped to this branch: each branch's run has its own timestamp, so a
    // global sweep would deactivate the other branch's customers as soon
    // as the second branch syncs.
    const [deactivateResult] = await connection.query(
      'UPDATE customers SET busy_still_active = 0 WHERE branch = ? AND busy_salesman_code IS NOT NULL AND busy_last_synced_at < ?',
      [branchLabel, syncStartedAt]
    );

    return { upserted: rows.length, deactivated: deactivateResult.affectedRows };
  });
}

module.exports = { mapCustomer, mapInvoice, findAll, findBySalesman, findById, findByIds, findInvoices, update, upsertFromBusy };
