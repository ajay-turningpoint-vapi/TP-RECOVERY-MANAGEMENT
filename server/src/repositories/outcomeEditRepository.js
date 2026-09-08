const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

function parseJson(value) {
  if (value == null) return null;
  if (typeof value === 'object') return value; // mysql2 already parsed JSON columns
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function mapRequest(row) {
  if (!row) return null;
  return {
    id: row.id,
    customerId: row.customer_id,
    salesmanId: row.salesman_id,
    outcomeKind: row.outcome_kind,
    artifactId: row.artifact_id,
    originalPayload: parseJson(row.original_payload),
    requestedPayload: parseJson(row.requested_payload),
    editReason: row.edit_reason,
    status: row.status,
    rejectionReason: row.rejection_reason,
    requestedAt: row.requested_at,
    resolvedAt: row.resolved_at,
  };
}

async function findAll() {
  const rows = await query('SELECT * FROM outcome_edit_requests ORDER BY requested_at DESC');
  return rows.map(mapRequest);
}

async function findBySalesman(salesmanId) {
  const rows = await query(
    'SELECT * FROM outcome_edit_requests WHERE salesman_id = :salesmanId ORDER BY requested_at DESC',
    { salesmanId }
  );
  return rows.map(mapRequest);
}

async function findById(id) {
  const rows = await query('SELECT * FROM outcome_edit_requests WHERE id = :id LIMIT 1', { id });
  return mapRequest(rows[0]);
}

async function findPendingForArtifact(customerId, artifactId, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const result = await run(
    `SELECT * FROM outcome_edit_requests
     WHERE status = 'Pending' AND customer_id = :customerId
       AND (artifact_id = :artifactId OR (:artifactId IS NULL AND artifact_id IS NULL))`,
    { customerId, artifactId: artifactId ?? null }
  );
  const rows = connection ? result[0] : result;
  return rows.map(mapRequest);
}

async function insert(
  { customerId, salesmanId, outcomeKind, artifactId, originalPayload, requestedPayload, editReason },
  connection
) {
  const id = uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO outcome_edit_requests
       (id, customer_id, salesman_id, outcome_kind, artifact_id, original_payload, requested_payload, edit_reason)
     VALUES (:id, :customerId, :salesmanId, :outcomeKind, :artifactId, :originalPayload, :requestedPayload, :editReason)`,
    {
      id,
      customerId,
      salesmanId,
      outcomeKind,
      artifactId: artifactId ?? null,
      originalPayload: JSON.stringify(originalPayload ?? {}),
      requestedPayload: JSON.stringify(requestedPayload ?? {}),
      editReason,
    }
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
  await run(`UPDATE outcome_edit_requests SET ${setClause} WHERE id = :id`, { ...fields, id });
}

module.exports = { mapRequest, findAll, findBySalesman, findById, findPendingForArtifact, insert, update };
