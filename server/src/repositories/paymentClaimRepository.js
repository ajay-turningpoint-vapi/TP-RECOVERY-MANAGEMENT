const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

function mapClaim(row) {
  if (!row) return null;
  return {
    id: row.id,
    customerId: row.customer_id,
    amount: Number(row.amount),
    claimDate: row.claim_date,
    reference: row.reference,
    status: row.status,
    attachmentPath: row.attachment_path,
  };
}

async function findAll() {
  const rows = await query('SELECT * FROM payment_claims ORDER BY claim_date DESC');
  return rows.map(mapClaim);
}

async function findById(id) {
  const rows = await query('SELECT * FROM payment_claims WHERE id = :id LIMIT 1', { id });
  return mapClaim(rows[0]);
}

async function insert(claim, connection) {
  const id = claim.id || uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO payment_claims (id, customer_id, amount, claim_date, reference, status, attachment_path)
     VALUES (:id, :customerId, :amount, :claimDate, :reference, :status, :attachmentPath)`,
    {
      id,
      customerId: claim.customerId,
      amount: claim.amount,
      claimDate: claim.claimDate,
      reference: claim.reference || null,
      status: claim.status || 'Awaiting Verification',
      attachmentPath: claim.attachmentPath || null,
    }
  );
  return id;
}

async function updateStatus(id, status, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run('UPDATE payment_claims SET status = :status WHERE id = :id', { id, status });
}

const COLUMN_MAP = {
  amount: 'amount',
  claimDate: 'claim_date',
  reference: 'reference',
  status: 'status',
};

async function update(id, fields, connection) {
  const keys = Object.keys(fields).filter((k) => COLUMN_MAP[k]);
  if (keys.length === 0) return;
  const setClause = keys.map((k) => `${COLUMN_MAP[k]} = :${k}`).join(', ');
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(`UPDATE payment_claims SET ${setClause} WHERE id = :id`, { ...fields, id });
}

async function findByCustomer(customerId, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const result = await run('SELECT * FROM payment_claims WHERE customer_id = :customerId ORDER BY claim_date DESC', {
    customerId,
  });
  const rows = connection ? result[0] : result;
  return rows.map(mapClaim);
}

module.exports = { mapClaim, findAll, findById, findByCustomer, insert, updateStatus, update };
