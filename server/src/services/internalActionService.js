const { withTransaction } = require('../config/db');
const taskRepository = require('../repositories/taskRepository');
const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const { notifyDecision, salesmanForCustomer } = require('./decisionNotify');
const { driveRecoveryTask } = require('./recoveryTaskService');
const { NotFoundError, ValidationError } = require('../errors/AppError');

/**
 * "Internal Action" outcomes never had a real approve/reject step —
 * recording the outcome just created one `financialTeamFollowUp` task
 * assigned directly to RE, closed via the generic completeTask. This adds
 * a real decision (mirroring disputeService's shape): whichever way RE
 * decides, the salesperson gets a call-customer follow-up so recovery
 * never goes silent on it.
 */
async function getOpenInternalActionTask(taskId) {
  const task = await taskRepository.findById(taskId);
  if (!task) throw new NotFoundError('Task');
  if (task.type !== 'financialTeamFollowUp') {
    throw new ValidationError('This task is not an Internal Action task');
  }
  if (['completed', 'closed'].includes(task.status)) {
    throw new ValidationError(`This Internal Action is already "${task.status}" — it can only be decided once`);
  }
  return task;
}

async function approve(taskId, user, { note, attachmentPath }) {
  const task = await getOpenInternalActionTask(taskId);
  // Evidence the RE attached in the approve form takes precedence; fall
  // back to whatever the original internal-action task carried.
  const evidencePath = attachmentPath || task.attachmentPath;

  await withTransaction(async (conn) => {
    await taskRepository.update(taskId, { status: 'completed', outcome: `Approved: ${note || ''}`.trim(), completedAt: new Date() }, conn);
    await auditRepository.record(
      task.customerId,
      {
        type: 'INTERNAL_ACTION_APPROVED',
        description: `${user.fullName} approved this internal action.${note ? ` Note: "${note}".` : ''}`,
        actor: user.fullName,
        previousState: task.status,
        newState: 'completed',
        source: 'Internal Action Review',
        attachmentPath: evidencePath,
      },
      conn
    );
  });

  await notifyDecision(await salesmanForCustomer(task.customerId), {
    approved: true,
    title: 'Internal action approved',
    body: `${user.fullName} approved the internal action on this account.`,
    customerId: task.customerId,
  });
  // Drive the one `source='Recovery'` call task (also re-enables Record
  // Outcome in the app), due 9 PM — the RE-decision default.
  await driveRecoveryTask(task.customerId, {
    headline: 'Internal action approved — continue recovery.',
    priority: 'Normal',
    deadlineHour: 21,
  });
  return taskRepository.findById(taskId);
}

async function reject(taskId, user, { reason, attachmentPath }) {
  const task = await getOpenInternalActionTask(taskId);
  const evidencePath = attachmentPath || task.attachmentPath;

  await withTransaction(async (conn) => {
    await taskRepository.update(taskId, { status: 'completed', outcome: `Rejected: ${reason || ''}`.trim(), completedAt: new Date() }, conn);
    await auditRepository.record(
      task.customerId,
      {
        type: 'INTERNAL_ACTION_REJECTED',
        description: `${user.fullName} rejected this internal action.${reason ? ` Reason: "${reason}".` : ''}`,
        actor: user.fullName,
        previousState: task.status,
        newState: 'completed',
        source: 'Internal Action Review',
        attachmentPath: evidencePath,
      },
      conn
    );
  });

  await notifyDecision(await salesmanForCustomer(task.customerId), {
    approved: false,
    title: 'Internal action rejected',
    body: `${user.fullName} rejected the internal action on this account.${reason ? ` Reason: "${reason}".` : ''}`,
    customerId: task.customerId,
  });
  await driveRecoveryTask(task.customerId, {
    headline: 'Internal action reviewed — continue recovery.',
    priority: 'Normal',
    deadlineHour: 21,
  });
  return taskRepository.findById(taskId);
}

module.exports = { approve, reject };
