const { withTransaction } = require('../config/db');
const taskRepository = require('../repositories/taskRepository');
const customerRepository = require('../repositories/customerRepository');
const ptpRepository = require('../repositories/ptpRepository');
const auditRepository = require('../repositories/auditRepository');
const userRepository = require('../repositories/userRepository');
const { notifyDecision } = require('./decisionNotify');
const { NotFoundError, ForbiddenError, ValidationError } = require('../errors/AppError');

async function listForUser(user) {
  if (user.role === 'SALESPERSON') {
    return taskRepository.findByOwner(user.id);
  }
  return taskRepository.findAll();
}

async function getOrThrow(id) {
  const task = await taskRepository.findById(id);
  if (!task) throw new NotFoundError('Task');
  return task;
}

/**
 * Never leave a customer with nothing open after something just happened
 * that the salesperson needs to act on. Shared by `completeTask`
 * (reactively, right after a task closes), the daily snapshot job, PTP
 * resolution (`ptpService.reopenRecoveryAfterPtpOutcome`), and RE
 * approve/reject decisions on Payment Already Made / Dispute / Internal
 * Action. `reason`/`source` let each caller describe why it fired without
 * duplicating the actual guard logic.
 *
 * `requireDueBalance` (default true) gates on `customer.totalDue > 0` —
 * the right behavior for "keep chasing until the balance is zero" (PTP
 * outcomes). Callers whose task is "tell the customer what was decided"
 * rather than "chase money" (payment-claim/dispute/internal-action
 * approve/reject) pass `false` so the call task is created every time RE
 * decides, regardless of remaining balance.
 *
 * `note`/`attachmentPath` (both optional) are threaded straight onto the
 * created task — the real decision detail + evidence file, not just the
 * short `reason` string.
 */
async function ensureFollowUpIfNeeded(
  customerId,
  fallbackOwnerId,
  { reason, auditType, source, priority = 'Normal', deadline, note, attachmentPath, requireDueBalance = true },
  conn
) {
  // Sequential, not Promise.all — both queries run on the same in-flight
  // transaction connection, and a single MySQL connection can't multiplex
  // two concurrent queries.
  const hasOpenTask = await taskRepository.hasOpenTaskForCustomer(customerId, conn);
  const hasActivePtp = await ptpRepository.hasActivePtpForCustomer(customerId, conn);
  if (hasOpenTask || hasActivePtp) return false;

  const customer = await customerRepository.findById(customerId);
  if (!customer) return false;
  if (requireDueBalance && customer.totalDue <= 0) return false;

  const ownerId = customer.assignedSalesmanId || fallbackOwnerId;
  if (!ownerId) return false;

  const taskReason = requireDueBalance
    ? `${reason} but ₹${customer.totalDue.toFixed(0)} remains due — recovery re-opened`
    : reason;
  const auditDescription = requireDueBalance
    ? `${reason}, but ₹${customer.totalDue.toFixed(0)} remains due with no other open task or active PTP — recovery automatically reopened.`
    : `${reason} — no other open task or active PTP, so a follow-up call was automatically created for the salesperson.`;

  await taskRepository.insert(
    {
      type: 'customerCall',
      customerId,
      ownerId,
      deadline: deadline ?? defaultCallDeadline(),
      priority,
      reason: taskReason,
      source,
      note,
      attachmentPath,
    },
    conn
  );
  await auditRepository.record(
    customerId,
    {
      type: auditType,
      description: auditDescription,
      actor: 'System',
      source,
      attachmentPath,
    },
    conn
  );
  return true;
}

async function completeTask(taskId, user, { attachmentPath } = {}) {
  const task = await getOrThrow(taskId);
  if (user.role === 'SALESPERSON' && task.ownerId !== user.id) {
    throw new ForbiddenError('You can only complete your own tasks');
  }
  // A Physical Visit is a real in-person visit — a bare "Mark Done" with no
  // proof it happened isn't an acceptable close, for either the dedicated
  // Record Outcome flow (see customerService.applyOutcome's physicalVisit
  // check) or this generic completion path. Photo evidence must be
  // genuinely on file, not just claimed, so it's real (not optional)
  // history for the customer.
  if (user.role === 'SALESPERSON' && task.type === 'physicalVisit' && !attachmentPath) {
    throw new ValidationError('A photo from the visit is required to complete a Physical Visit task.');
  }

  await withTransaction(async (conn) => {
    await taskRepository.update(taskId, { status: 'completed', completedAt: new Date() }, conn);
    // Always logged — was previously only recorded when
    // ensureFollowUpIfNeeded's guard actually reopened recovery, so a
    // completed task with nothing else to do left no trace at all in
    // Customer History. Every single thing that happens to a customer
    // must show up in their unified timeline. attachmentPath (the visit
    // photo, when present) rides along so it's preserved in history too.
    await auditRepository.record(
      task.customerId,
      {
        type: 'TASK_COMPLETED',
        description: `${user.fullName} completed the "${task.type}" task: "${task.reason}".`,
        actor: user.fullName,
        previousState: task.status,
        newState: 'completed',
        source: 'Task Completion',
        attachmentPath: attachmentPath || null,
      },
      conn
    );
  });

  // A salesperson marking a call / visit task "done" WITHOUT recording an
  // outcome must not break the chase chain — recording an outcome
  // supersedes the task, so a bare completion means "no outcome". Re-drive
  // the single `source='Recovery'` task (retarget or adopt this one, never
  // duplicate) while real money is still actionable. driveRecoveryTask is
  // now the sole authority for this, replacing the old in-transaction
  // ensureFollowUpIfNeeded (whose separate `source='Task Completion Guard'`
  // task collided with the recovery task) — it self-guards on actionable
  // balance and an open physical visit / RE follow-up, so it is a no-op
  // when nothing is owed or another step already holds the account.
  const isSalesperson =
    !task.ownerId || (await userRepository.findById(task.ownerId))?.role === 'SALESPERSON';
  if (['customerCall', 'physicalVisit'].includes(task.type) && isSalesperson) {
    const customer = await customerRepository.findById(task.customerId);
    const reController = customer && customer.currentRecoveryState === 'RE Control';

    if (task.source === 'No Answer' && customer && Number(customer.totalDue) > 0 && !reController) {
      // You don't "complete" a No-Answer task, you record an outcome.
      // A bare completion = "still nothing to record" — put the single
      // No-Answer task straight back, re-due 2 hours out (its own faster
      // cadence, not the same-day-6PM default), so `sweepNoAnswerCycle`
      // keeps owning the customer (2-hourly → all-day → physical visit →
      // L2). A generic Recovery task here would bypass that escalation
      // counter.
      const stillOpen = (await taskRepository.findByCustomer(task.customerId)).some(
        (t) => t.source === 'No Answer' && !['completed', 'closed', 'cancelled'].includes(t.status)
      );
      if (!stillOpen) {
        await taskRepository.insert({
          type: 'customerCall',
          customerId: task.customerId,
          ownerId: task.ownerId,
          deadline: new Date(Date.now() + 2 * 60 * 60 * 1000),
          priority: 'Normal',
          reason: task.reason,
          source: 'No Answer',
        });
        await auditRepository.record(task.customerId, {
          type: 'NO_ANSWER_TASK_REOPENED',
          description: 'No-Answer task was completed with no outcome recorded — re-opened so the non-response cycle keeps running.',
          actor: 'System',
          source: 'No Answer',
        });
      }
    } else {
      const { driveRecoveryTask } = require('./recoveryTaskService');
      await driveRecoveryTask(task.customerId, {
        headline: 'Previous task closed with no outcome — call the customer again.',
        priority: 'Normal',
        deadlineHour: 18,
      });
    }
  }

  return taskRepository.findById(taskId);
}

async function requestExtension(taskId, user, { reason, deadline, priority }) {
  const task = await getOrThrow(taskId);
  if (task.ownerId !== user.id) throw new ForbiddenError('You can only edit your own tasks');

  await withTransaction(async (conn) => {
    await taskRepository.update(
      taskId,
      {
        approvalStatus: 'Pending',
        pendingReason: reason,
        pendingDeadline: deadline,
        pendingPriority: priority || task.priority,
      },
      conn
    );
    await auditRepository.record(
      task.customerId,
      {
        type: 'TASK_EXTENSION_REQUESTED',
        description: `${user.fullName} requested a deadline extension on the "${task.type}" task, from ${new Date(task.deadline).toISOString()} to ${new Date(deadline).toISOString()}. Reason: "${reason}". Awaiting RE decision.`,
        actor: user.fullName,
        previousState: new Date(task.deadline).toISOString(),
        newState: 'Pending',
        source: 'Task Extension Request',
      },
      conn
    );
  });
  return taskRepository.findById(taskId);
}

async function approveEdit(taskId, user) {
  const task = await getOrThrow(taskId);
  const newDeadline = task.pendingDeadline || task.deadline;

  await withTransaction(async (conn) => {
    await taskRepository.update(
      taskId,
      {
        deadline: newDeadline,
        priority: task.pendingPriority || task.priority,
        reason: task.pendingReason || task.reason,
        approvalStatus: 'Approved',
        pendingReason: null,
        pendingDeadline: null,
        pendingPriority: null,
      },
      conn
    );
    await auditRepository.record(
      task.customerId,
      {
        type: 'RE_APPROVED_TASK_EDIT',
        description: `${user.fullName} approved ${task.ownerId}'s request to edit the "${task.type}" task: deadline changed from ${new Date(task.deadline).toISOString()} to ${new Date(newDeadline).toISOString()}.`,
        actor: user.fullName,
        previousState: new Date(task.deadline).toISOString(),
        newState: new Date(newDeadline).toISOString(),
        source: 'RE Tasks',
      },
      conn
    );
  });
  await notifyDecision(task.ownerId, {
    approved: true,
    title: 'Task extension approved',
    body: `${user.fullName} approved your extension on the "${task.type}" task — new deadline ${new Date(newDeadline).toLocaleString('en-IN')}.`,
    customerId: task.customerId,
  });
  return taskRepository.findById(taskId);
}

async function rejectEdit(taskId, user) {
  const task = await getOrThrow(taskId);

  await withTransaction(async (conn) => {
    await taskRepository.update(taskId, { approvalStatus: 'Rejected', pendingReason: null, pendingDeadline: null, pendingPriority: null }, conn);
    await auditRepository.record(
      task.customerId,
      {
        type: 'RE_REJECTED_TASK_EDIT',
        description: `${user.fullName} rejected ${task.ownerId}'s request to edit the "${task.type}" task. The task's original deadline of ${new Date(task.deadline).toISOString()} stands unchanged.`,
        actor: user.fullName,
        previousState: 'Pending',
        newState: 'Rejected',
        source: 'RE Tasks',
      },
      conn
    );
  });
  await notifyDecision(task.ownerId, {
    approved: false,
    title: 'Task extension rejected',
    body: `${user.fullName} rejected your extension request on the "${task.type}" task. The original deadline stands.`,
    customerId: task.customerId,
  });
  return taskRepository.findById(taskId);
}

/**
 * RE/Manager directly rescheduling a task's deadline. Deliberately separate
 * from requestExtension/approveEdit: RE already has approval authority, so
 * routing this through the Pending-approval flow would mean RE approving
 * their own request — a self-directed approval loop. Only the
 * salesperson's own extension requests go through requestExtension/approveEdit.
 */
async function reschedule(taskId, user, { reason, newDeadline }) {
  const task = await getOrThrow(taskId);
  const oldDeadline = task.deadline;

  await withTransaction(async (conn) => {
    await taskRepository.update(taskId, { deadline: newDeadline }, conn);
    await auditRepository.record(
      task.customerId,
      {
        type: 'RE_RESCHEDULED_TASK',
        description: `${user.fullName} rescheduled the "${task.type}" task for ${task.ownerId} from ${new Date(oldDeadline).toISOString()} to ${new Date(newDeadline).toISOString()}. Reason: ${reason}.`,
        actor: user.fullName,
        previousState: new Date(oldDeadline).toISOString(),
        newState: new Date(newDeadline).toISOString(),
        source: 'RE Tasks',
      },
      conn
    );
  });
  await notifyDecision(task.ownerId, {
    approved: true,
    title: 'Task rescheduled by RE',
    body: `${user.fullName} moved your "${task.type}" task to ${new Date(newDeadline).toLocaleString('en-IN')}. Reason: ${reason}.`,
    customerId: task.customerId,
  });
  return taskRepository.findById(taskId);
}

/** RE/Manager marking a completed physical visit as reviewed. */
async function markReviewed(taskId, user) {
  const task = await getOrThrow(taskId);
  await withTransaction(async (conn) => {
    await taskRepository.update(taskId, { reviewedByRE: true }, conn);
    await auditRepository.record(
      task.customerId,
      {
        type: 'RE_REVIEWED_VISIT',
        description: `${user ? user.fullName : 'RE'} reviewed and signed off ${task.ownerId}'s completed physical visit.`,
        actor: user ? user.fullName : 'RE',
        source: 'Visit Review',
      },
      conn
    );
  });
  await notifyDecision(task.ownerId, {
    approved: true,
    title: 'Visit reviewed',
    body: `${user ? `${user.fullName} ` : ''}reviewed and signed off your completed "${task.type}" visit.`,
    customerId: task.customerId,
  });
  return taskRepository.findById(taskId);
}

async function reassignTask(taskId, user, { newOwnerId, reason }) {
  const task = await getOrThrow(taskId);
  const oldOwner = task.ownerId;

  await withTransaction(async (conn) => {
    await taskRepository.update(taskId, { ownerId: newOwnerId }, conn);
    await auditRepository.record(
      task.customerId,
      {
        type: 'RE_ASSIGNED_TASK',
        description: `${user.fullName} reassigned the "${task.type}" task (due ${new Date(task.deadline).toISOString()}) from ${oldOwner} to ${newOwnerId}. Reason: ${reason}`,
        actor: user.fullName,
        previousState: oldOwner,
        newState: newOwnerId,
        source: 'Salesmen Needing Attention',
      },
      conn
    );
  });
  await notifyDecision(oldOwner, {
    approved: false,
    title: 'Task reassigned away',
    body: `${user.fullName} moved the "${task.type}" task to another owner. Reason: ${reason}.`,
    customerId: task.customerId,
  });
  await notifyDecision(newOwnerId, {
    approved: true,
    title: 'New task assigned to you',
    body: `${user.fullName} assigned you a "${task.type}" task (due ${new Date(task.deadline).toLocaleString('en-IN')}). Reason: ${reason}.`,
    customerId: task.customerId,
  });
  return taskRepository.findById(taskId);
}

function addDays(date, days) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

/**
 * Default due time for an auto-created "call customer" task: 9:00 PM
 * (server-local). Today at 21:00 if it's still before then, otherwise
 * tomorrow at 21:00.
 */
function defaultCallDeadline(now = new Date()) {
  const d = new Date(now);
  d.setHours(21, 0, 0, 0);
  if (d <= now) d.setDate(d.getDate() + 1);
  return d;
}

module.exports = { listForUser, completeTask, requestExtension, approveEdit, rejectEdit, reassignTask, reschedule, markReviewed, ensureFollowUpIfNeeded, defaultCallDeadline };
