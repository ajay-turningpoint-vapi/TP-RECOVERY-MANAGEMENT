const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

function mapTask(row) {
  if (!row) return null;
  return {
    id: row.id,
    type: row.type,
    customerId: row.customer_id,
    ownerId: row.owner_id,
    deadline: row.deadline,
    priority: row.priority,
    reason: row.reason,
    status: row.status,
    outcome: row.outcome,
    approvalStatus: row.approval_status,
    pendingReason: row.pending_reason,
    pendingDeadline: row.pending_deadline,
    pendingPriority: row.pending_priority,
    source: row.source,
    completedAt: row.completed_at,
    reviewedByRE: !!row.reviewed_by_re,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    note: row.note,
    attachmentPath: row.attachment_path,
  };
}

async function findAll() {
  const rows = await query('SELECT * FROM tasks ORDER BY deadline');
  return rows.map(mapTask);
}

async function findByOwner(ownerId) {
  const rows = await query('SELECT * FROM tasks WHERE owner_id = :ownerId ORDER BY deadline', { ownerId });
  return rows.map(mapTask);
}

async function findByCustomer(customerId, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const result = await run('SELECT * FROM tasks WHERE customer_id = :customerId', { customerId });
  const rows = connection ? result[0] : result;
  return rows.map(mapTask);
}

async function findById(id) {
  const rows = await query('SELECT * FROM tasks WHERE id = :id LIMIT 1', { id });
  return mapTask(rows[0]);
}

async function insert(task, connection) {
  const id = task.id || uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO tasks (id, type, customer_id, owner_id, deadline, priority, reason, status, source, note, attachment_path)
     VALUES (:id, :type, :customerId, :ownerId, :deadline, :priority, :reason, :status, :source, :note, :attachmentPath)`,
    {
      id,
      type: task.type,
      customerId: task.customerId,
      ownerId: task.ownerId,
      deadline: task.deadline,
      priority: task.priority || 'Normal',
      reason: task.reason,
      status: task.status || 'pending',
      source: task.source || 'System',
      note: task.note || null,
      attachmentPath: task.attachmentPath || null,
    }
  );
  return id;
}

const COLUMN_MAP = {
  ownerId: 'owner_id',
  deadline: 'deadline',
  priority: 'priority',
  reason: 'reason',
  status: 'status',
  outcome: 'outcome',
  approvalStatus: 'approval_status',
  pendingReason: 'pending_reason',
  pendingDeadline: 'pending_deadline',
  pendingPriority: 'pending_priority',
  completedAt: 'completed_at',
  reviewedByRE: 'reviewed_by_re',
  note: 'note',
  attachmentPath: 'attachment_path',
};

async function update(id, fields, connection) {
  const keys = Object.keys(fields).filter((k) => COLUMN_MAP[k]);
  if (keys.length === 0) return;
  const setClause = keys.map((k) => `${COLUMN_MAP[k]} = :${k}`).join(', ');
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(`UPDATE tasks SET ${setClause} WHERE id = :id`, { ...fields, id });
}

/**
 * Closes out (marks TaskStatus.completed) every still-open task for a
 * customer. Used both by recordOutcome's "one outcome record per customer"
 * rule and by RE/Manager intervention (take control, management
 * instruction) — see customerService.
 */
async function supersedeOpenTasks(customerId, outcomeNote, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `UPDATE tasks
     SET status = 'completed', outcome = :outcomeNote, completed_at = NOW()
     WHERE customer_id = :customerId AND status NOT IN ('completed', 'closed')`,
    { customerId, outcomeNote }
  );
}

async function hasOpenTaskForCustomer(customerId, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const result = await run(
    `SELECT COUNT(*) AS cnt FROM tasks WHERE customer_id = :customerId AND status NOT IN ('completed', 'closed')`,
    { customerId }
  );
  const rows = connection ? result[0] : result;
  return rows[0].cnt > 0;
}

module.exports = { mapTask, findAll, findByOwner, findByCustomer, findById, insert, update, supersedeOpenTasks, hasOpenTaskForCustomer };
