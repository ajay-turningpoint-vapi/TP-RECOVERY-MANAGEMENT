const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

function mapRequest(row) {
  if (!row) return null;
  return {
    id: row.id,
    customerId: row.customer_id,
    salesmanId: row.salesman_id,
    originalOutcome: row.original_outcome,
    originalReason: row.original_reason,
    requestedOutcome: row.requested_outcome,
    requestedReason: row.requested_reason,
    requestNote: row.request_note,
    status: row.status,
    rejectionReason: row.rejection_reason,
    requestedAt: row.requested_at,
    resolvedAt: row.resolved_at,
  };
}

async function findAll() {
  const rows = await query('SELECT * FROM outcome_correction_requests ORDER BY requested_at DESC');
  return rows.map(mapRequest);
}

async function findBySalesman(salesmanId) {
  const rows = await query('SELECT * FROM outcome_correction_requests WHERE salesman_id = :salesmanId ORDER BY requested_at DESC', { salesmanId });
  return rows.map(mapRequest);
}

async function findById(id) {
  const rows = await query('SELECT * FROM outcome_correction_requests WHERE id = :id LIMIT 1', { id });
  return mapRequest(rows[0]);
}

async function insert({ customerId, salesmanId, originalOutcome, originalReason, requestedOutcome, requestedReason, requestNote }, connection) {
  const id = uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO outcome_correction_requests (id, customer_id, salesman_id, original_outcome, original_reason, requested_outcome, requested_reason, request_note)
     VALUES (:id, :customerId, :salesmanId, :originalOutcome, :originalReason, :requestedOutcome, :requestedReason, :requestNote)`,
    { id, customerId, salesmanId, originalOutcome, originalReason, requestedOutcome, requestedReason, requestNote }
  );
  return id;
}

const COLUMN_MAP = {
  status: 'status',
  rejectionReason: 'rejection_reason',
  resolvedAt: 'resolved_at',
};

async function update(id, fields, connection) {
  const keys = Object.keys(fields).filter((k) => COLUMN_MAP[k]);
  if (keys.length === 0) return;
  const setClause = keys.map((k) => `${COLUMN_MAP[k]} = :${k}`).join(', ');
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(`UPDATE outcome_correction_requests SET ${setClause} WHERE id = :id`, { ...fields, id });
}

module.exports = { mapRequest, findAll, findBySalesman, findById, insert, update };
