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
    isRoutine: !!row.is_routine,
    completedAt: row.completed_at,
    reviewedByRE: !!row.reviewed_by_re,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    note: row.note,
    attachmentPath: row.attachment_path,
    disputeId: row.dispute_id || null,
  };
}

// Newest-created first — a task's deadline says nothing about how fresh it
// is (a just-assigned task can easily have a later deadline than the
// existing backlog), so sorting by deadline buried brand-new tasks wherever
// their due date happened to fall instead of surfacing them at the top of
// the list the moment they're created.
async function findAll() {
  const rows = await query('SELECT * FROM tasks ORDER BY created_at DESC');
  return rows.map(mapTask);
}

// Same ACTIVE_FILTER customerRepository.js uses for customers — a BUSY-
// sourced customer (busy_salesman_code set) who paid off / closed drops
// out of BUSY's feed and is soft-deactivated (busy_still_active = 0); a
// non-BUSY customer (busy_salesman_code NULL) is always active.
const ACTIVE_CUSTOMER_JOIN = '(c.busy_salesman_code IS NULL OR c.busy_still_active = 1)';

/**
 * Same rows as findAll(), minus any task whose customer has since gone
 * inactive. closeOrphanedTasks (customerRepository.upsertFromBusy) already
 * auto-completes an inactive customer's still-OPEN tasks at sync time, so
 * by the time a customer is inactive every one of their tasks is already
 * 'completed'/'closed' history — nothing actionable is ever filtered out
 * here, only stale completed rows that have nothing current to show (the
 * RE/Manager Tasks list — taskService.listForUser's non-salesperson
 * branch — is the only consumer; every other caller of findAll() keeps
 * seeing the complete, unfiltered table, since escalation/reconcile/report
 * logic elsewhere may still need a just-deactivated customer's tasks for
 * one more pass).
 */
async function findAllForActiveCustomers() {
  const rows = await query(
    `SELECT t.* FROM tasks t
     JOIN customers c ON c.id = t.customer_id
     WHERE ${ACTIVE_CUSTOMER_JOIN}
     ORDER BY t.created_at DESC`
  );
  return rows.map(mapTask);
}

async function findByOwner(ownerId) {
  const rows = await query('SELECT * FROM tasks WHERE owner_id = :ownerId ORDER BY created_at DESC', { ownerId });
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

/**
 * The ONE place a task row is created. Refuses (returns null) when the
 * customer no longer appears in BUSY (busy_still_active = 0): a removed
 * customer must never get a task again, from any path — an RE acting on a
 * leftover dispute, a delayed No-Answer / Will-Confirm job firing later,
 * a sweep. Done in the same INSERT … SELECT statement, so it holds inside
 * transactions too.
 */
async function insert(task, connection) {
  const id = task.id || uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const result = await run(
    `INSERT INTO tasks (id, type, customer_id, owner_id, deadline, priority, reason, status, source, is_routine, note, attachment_path, dispute_id)
     SELECT :id, :type, :customerId, :ownerId, :deadline, :priority, :reason, :status, :source, :isRoutine, :note, :attachmentPath, :disputeId
     FROM customers WHERE id = :customerId AND busy_still_active = 1`,
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
      // Defaults true (routine/hidden from the salesperson's Tasks tab) —
      // only recoveryTaskService's event-driven path explicitly passes
      // false, for a task the salesperson needs to see right now.
      isRoutine: task.isRoutine === false ? 0 : 1,
      note: task.note || null,
      attachmentPath: task.attachmentPath || null,
      disputeId: task.disputeId || null,
    }
  );
  const header = Array.isArray(result) ? result[0] : result;
  if (!header || header.affectedRows === 0) {
    require('../config/logger').warn('[taskRepository] task NOT created — customer no longer in BUSY', { customerId: task.customerId, type: task.type, source: task.source });
    return null;
  }
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
  isRoutine: 'is_routine',
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
  // Close the salesperson's own open call/visit tasks when a fresh outcome
  // is recorded — but NEVER the RE-owned work items (payment-claim / dispute
  // / internal-action reviews, escalation nudges, SLA breaches). Those close
  // on the RE's decision, not on the salesman recording anything.
  await run(
    `UPDATE tasks
     SET status = 'completed', outcome = :outcomeNote, completed_at = NOW()
     WHERE customer_id = :customerId
       AND status NOT IN ('completed', 'closed')
       AND type NOT IN ('financialTeamFollowUp', 'disputeResolution', 'managementInstruction')
       AND dispute_id IS NULL
       AND (source IS NULL OR source NOT IN ('Dispute Review', 'Missed Deadline', 'RE Instruction', 'Escalation', 'RE SLA', 'Missed Follow-up'))`,
    { customerId, outcomeNote }
  );
}

/**
 * Closes out (status = 'completed') every still-open task for a set of
 * customers in one bulk UPDATE — used when a BUSY sync finds a customer
 * has vanished from the feed entirely (balance cleared / account closed)
 * and deactivates it. Unlike supersedeOpenTasks, this closes EVERY open
 * task type including the RE-owned ones (dispute/financial/management) —
 * there's no "ask the RE" case here, the customer itself is gone, so
 * nothing should stay open waiting on it.
 *
 * Deliberately 'completed', not 'closed': the mobile app's task screens
 * (tasks_screen.dart and most of app_store.dart's counters) only ever
 * check `status == TaskStatus.completed` to decide a task is done —
 * `'closed'` is a valid DB/Dart enum value but is checked in only a
 * handful of places, so a task closed with that status would still show
 * as open/pending everywhere else in the app.
 */
async function closeOrphanedTasks(customerIds, note, connection) {
  if (!customerIds || customerIds.length === 0) return 0;
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const out = await run(
    `UPDATE tasks
     SET status = 'completed', outcome = :note, completed_at = NOW()
     WHERE customer_id IN (:customerIds)
       AND status NOT IN ('completed', 'closed')`,
    { customerIds, note }
  );
  // connection.query → [header, fields]; the pool's query() → header.
  const result = Array.isArray(out) ? out[0] : out;
  return result.affectedRows;
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

module.exports = { mapTask, findAll, findAllForActiveCustomers, findByOwner, findByCustomer, findById, insert, update, supersedeOpenTasks, closeOrphanedTasks, hasOpenTaskForCustomer };
