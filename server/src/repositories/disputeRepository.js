const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

function mapDispute(row) {
  if (!row) return null;
  return {
    id: row.id,
    customerId: row.customer_id,
    amount: Number(row.amount),
    totalDueAtRaise: Number(row.total_due_at_raise),
    reason: row.reason,
    status: row.status,
    statusDetail: row.status_detail,
    invoiceNumber: row.invoice_number,
    priority: row.priority,
    resolutionOwner: row.resolution_owner,
    rejectionReason: row.rejection_reason,
    infoRequestNote: row.info_request_note,
    raisedDate: row.raised_date,
    lastUpdated: row.last_updated,
    attachmentPath: row.attachment_path,
    resolutionDeadline: row.resolution_deadline,
    department: row.department,
  };
}

async function findAll() {
  const rows = await query('SELECT * FROM disputes ORDER BY raised_date DESC');
  return rows.map(mapDispute);
}

async function findById(id) {
  const rows = await query('SELECT * FROM disputes WHERE id = :id LIMIT 1', { id });
  return mapDispute(rows[0]);
}

async function findPendingApproval() {
  const rows = await query("SELECT * FROM disputes WHERE status = 'Pending Approval'");
  return rows.map(mapDispute);
}

/** Distinct customer ids of every dispute this user is (or was) the resolution owner on. */
async function findCustomerIdsByResolutionOwner(userId) {
  const rows = await query('SELECT DISTINCT customer_id FROM disputes WHERE resolution_owner = :userId', { userId });
  return rows.map((r) => r.customer_id);
}

/** Whether this user is (or was) the resolution owner on any dispute for this customer. */
async function isResolutionOwner(customerId, userId) {
  const rows = await query(
    'SELECT 1 FROM disputes WHERE customer_id = :customerId AND resolution_owner = :userId LIMIT 1',
    { customerId, userId }
  );
  return rows.length > 0;
}

async function insert(dispute, connection) {
  const id = dispute.id || uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO disputes (id, customer_id, amount, total_due_at_raise, reason, status, priority, invoice_number, attachment_path)
     VALUES (:id, :customerId, :amount, :totalDueAtRaise, :reason, :status, :priority, :invoiceNumber, :attachmentPath)`,
    {
      id,
      customerId: dispute.customerId,
      amount: dispute.amount,
      totalDueAtRaise: dispute.totalDueAtRaise || 0,
      reason: dispute.reason,
      status: dispute.status || 'Pending Approval',
      priority: dispute.priority || 'Medium',
      invoiceNumber: dispute.invoiceNumber || null,
      attachmentPath: dispute.attachmentPath || null,
    }
  );
  return id;
}

const COLUMN_MAP = {
  amount: 'amount',
  reason: 'reason',
  priority: 'priority',
  status: 'status',
  statusDetail: 'status_detail',
  resolutionOwner: 'resolution_owner',
  rejectionReason: 'rejection_reason',
  infoRequestNote: 'info_request_note',
  resolutionDeadline: 'resolution_deadline',
  department: 'department',
};

async function update(id, fields, connection) {
  const keys = Object.keys(fields).filter((k) => COLUMN_MAP[k]);
  if (keys.length === 0) return;
  const setClause = keys.map((k) => `${COLUMN_MAP[k]} = :${k}`).join(', ');
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(`UPDATE disputes SET ${setClause} WHERE id = :id`, { ...fields, id });
}

module.exports = { mapDispute, findAll, findById, findPendingApproval, findCustomerIdsByResolutionOwner, isResolutionOwner, insert, update };
