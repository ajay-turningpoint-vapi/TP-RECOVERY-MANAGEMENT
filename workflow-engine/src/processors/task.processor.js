import { getTask, updateTask, createTask, listOpenTasksForCustomer, appendAuditEvent, getCustomer } from '../store/repository.js';

/**
 * Completes a task, then checks whether recovery should genuinely close for
 * this customer — fixes a gap the workflow audit found unimplemented in the
 * source Dart app (Non-Negotiable Law: "task completion never equals
 * financial closure"). If money remains due and no other open task exists,
 * a follow-up is auto-created rather than letting the customer silently
 * fall out of the recovery queue.
 */
async function complete(data) {
  const { taskId, actor, outcome } = data;
  if (!taskId) throw new Error('task complete job requires taskId');
  const task = await updateTask(taskId, (t) => {
    if (t.status === 'completed') return {}; // idempotent: already completed, no-op
    return { status: 'completed', completedAt: new Date().toISOString(), outcome: outcome || t.outcome };
  });

  const customer = getCustomer(task.customerId);
  const stillOpen = listOpenTasksForCustomer(task.customerId);
  let reopenedTaskId = null;
  if (customer.totalDue > 0 && stillOpen.length === 0) {
    const followUp = createTask({
      type: 'customerCall',
      customerId: task.customerId,
      ownerId: task.ownerId,
      deadline: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      priority: 'Normal',
      reason: `Task ${taskId} completed but ₹${customer.totalDue} remains due — recovery re-opened`,
      source: 'Task Completion Guard',
    });
    reopenedTaskId = followUp.id;
    appendAuditEvent({
      customerId: task.customerId,
      type: 'TASK_COMPLETED_MONEY_STILL_DUE_REOPENED',
      description: `Task ${taskId} completed, but ₹${customer.totalDue} remains due with no other open task — recovery automatically reopened via task ${followUp.id}.`,
      actor: actor || 'System',
      source: 'Task Completion Guard',
      relatedEntityType: 'Task',
      relatedEntityId: taskId,
    });
  } else {
    appendAuditEvent({
      customerId: task.customerId,
      type: 'TASK_COMPLETED',
      description: `Task ${taskId} completed.`,
      actor: actor || 'System',
      source: 'Task Completion',
      relatedEntityType: 'Task',
      relatedEntityId: taskId,
    });
  }

  return { taskId, status: 'completed', reopenedTaskId };
}

async function reassign(data) {
  const { taskId, newOwnerId, reason, actor } = data;
  if (!taskId || !newOwnerId) throw new Error('task reassign job requires taskId, newOwnerId');
  const before = getTask(taskId);
  const updated = await updateTask(taskId, () => ({ ownerId: newOwnerId }));
  appendAuditEvent({
    customerId: updated.customerId,
    type: 'RE_ASSIGNED_TASK',
    description: `Task ${taskId} reassigned from ${before.ownerId} to ${newOwnerId}: ${reason || 'no reason given'}.`,
    actor: actor || 'Recovery Executive',
    previousState: before.ownerId,
    newState: newOwnerId,
    source: 'Salesmen Needing Attention',
    relatedEntityType: 'Task',
    relatedEntityId: taskId,
  });
  return { taskId, ownerId: newOwnerId };
}

async function reschedule(data) {
  const { taskId, newDeadline, reason, actor } = data;
  if (!taskId || !newDeadline) throw new Error('task reschedule job requires taskId, newDeadline');
  const before = getTask(taskId);
  const updated = await updateTask(taskId, () => ({ deadline: new Date(newDeadline).toISOString() }));
  appendAuditEvent({
    customerId: updated.customerId,
    type: 'RE_RESCHEDULED_TASK',
    description: `Task ${taskId} rescheduled: ${reason || 'no reason given'}.`,
    actor: actor || 'Recovery Executive',
    previousState: before.deadline,
    newState: updated.deadline,
    source: 'RE Tasks',
    relatedEntityType: 'Task',
    relatedEntityId: taskId,
  });
  return { taskId, deadline: updated.deadline };
}

async function requestEditApproval(data) {
  const { taskId, newReason, newDeadline, newPriority, actor } = data;
  if (!taskId) throw new Error('task request-edit-approval job requires taskId');
  // Original deadline/reason/priority stay authoritative and untouched
  // until an RE explicitly approves — only the pending* fields change.
  await updateTask(taskId, () => ({
    approvalStatus: 'Pending',
    pendingReason: newReason,
    pendingDeadline: newDeadline ? new Date(newDeadline).toISOString() : undefined,
    pendingPriority: newPriority,
  }));
  return { taskId, approvalStatus: 'Pending' };
}

async function approveEdit(data) {
  const { taskId, actor } = data;
  if (!taskId) throw new Error('task approve-edit job requires taskId');
  const before = getTask(taskId);
  const updated = await updateTask(taskId, (t) => ({
    reason: t.pendingReason ?? t.reason,
    deadline: t.pendingDeadline ?? t.deadline,
    priority: t.pendingPriority ?? t.priority,
    approvalStatus: 'Approved',
    pendingReason: null,
    pendingDeadline: null,
    pendingPriority: null,
  }));
  appendAuditEvent({
    customerId: updated.customerId,
    type: 'TASK_EDIT_APPROVED',
    description: `Task ${taskId} edit approved — deadline changed from ${before.deadline} to ${updated.deadline}.`,
    actor: actor || 'Recovery Executive',
    previousState: before.deadline,
    newState: updated.deadline,
    source: 'RE Tasks',
    relatedEntityType: 'Task',
    relatedEntityId: taskId,
  });
  return { taskId, approvalStatus: 'Approved' };
}

async function rejectEdit(data) {
  const { taskId, actor, reason } = data;
  if (!taskId) throw new Error('task reject-edit job requires taskId');
  const updated = await updateTask(taskId, () => ({
    approvalStatus: 'Rejected',
    pendingReason: null,
    pendingDeadline: null,
    pendingPriority: null,
  }));
  appendAuditEvent({
    customerId: updated.customerId,
    type: 'TASK_EDIT_REJECTED',
    description: `Task ${taskId} edit request rejected: ${reason || 'no reason given'}. Original deadline remains authoritative.`,
    actor: actor || 'Recovery Executive',
    source: 'RE Tasks',
    relatedEntityType: 'Task',
    relatedEntityId: taskId,
  });
  return { taskId, approvalStatus: 'Rejected' };
}

async function reviewPhysicalVisit(data) {
  const { taskId, actor } = data;
  if (!taskId) throw new Error('task review-physical-visit job requires taskId');
  const updated = await updateTask(taskId, () => ({ reviewedByRE: true }));
  appendAuditEvent({
    customerId: updated.customerId,
    type: 'PHYSICAL_VISIT_REVIEWED',
    description: `Physical visit task ${taskId} reviewed by RE.`,
    actor: actor || 'Recovery Executive',
    source: 'RE Tasks',
    relatedEntityType: 'Task',
    relatedEntityId: taskId,
  });
  return { taskId, reviewedByRE: true };
}

const handlers = {
  complete,
  reassign,
  reschedule,
  'request-edit-approval': requestEditApproval,
  'approve-edit': approveEdit,
  'reject-edit': rejectEdit,
  'review-physical-visit': reviewPhysicalVisit,
};

export async function processTask(job) {
  const handler = handlers[job.name];
  if (!handler) throw new Error(`Unknown task job name: "${job.name}"`);
  return handler(job.data);
}
