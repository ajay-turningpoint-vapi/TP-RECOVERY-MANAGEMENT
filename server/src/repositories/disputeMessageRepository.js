const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

function mapMessage(row) {
  return {
    id: row.id,
    disputeId: row.dispute_id,
    authorId: row.author_id,
    authorName: row.author_name,
    authorRole: row.author_role,
    kind: row.kind, // 'question' | 'answer' | 'note'
    body: row.body,
    attachmentPath: row.attachment_path || null,
    createdAt: row.created_at,
  };
}

async function add({ disputeId, authorId, authorName, authorRole, kind, body, attachmentPath = null }, connection) {
  const id = uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO dispute_messages (id, dispute_id, author_id, author_name, author_role, kind, body, attachment_path)
     VALUES (:id, :disputeId, :authorId, :authorName, :authorRole, :kind, :body, :attachmentPath)`,
    { id, disputeId, authorId, authorName, authorRole, kind, body, attachmentPath }
  );
  return id;
}

async function listForDispute(disputeId) {
  const rows = await query(
    'SELECT * FROM dispute_messages WHERE dispute_id = :disputeId ORDER BY created_at ASC',
    { disputeId }
  );
  return rows.map(mapMessage);
}

/** All messages, grouped by dispute id — for the dispute list payload (avoids N+1). */
async function listAllGrouped() {
  const rows = await query('SELECT * FROM dispute_messages ORDER BY created_at ASC');
  const byDispute = {};
  for (const row of rows) {
    (byDispute[row.dispute_id] ||= []).push(mapMessage(row));
  }
  return byDispute;
}

module.exports = { add, listForDispute, listAllGrouped };
