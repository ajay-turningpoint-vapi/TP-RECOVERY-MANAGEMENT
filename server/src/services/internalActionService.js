const { withTransaction } = require('../config/db');
const taskRepository = require('../repositories/taskRepository');
const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const taskService = require('./taskService');
const { notifyDecision, salesmanForCustomer } = require('./decisionNotify');
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

async function approve(taskId, user, { note }) {
  const task = await getOpenInternalActionTask(taskId);

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
        attachmentPath: task.attachmentPath,
      },
      conn
    );

    const created = await taskService.ensureFollowUpIfNeeded(
      task.customerId,
      null,
      {
        reason: 'Internal action approved',
        auditType: 'INTERNAL_ACTION_APPROVED_FOLLOWUP',
        source: 'Internal Action Review',
        priority: 'Normal',
        note: `${user.fullName} approved the internal action on this account.${note ? ` ${note}` : ''}`,
        attachmentPath: task.attachmentPath,
        requireDueBalance: false,
      },
      conn
    );
    if (created) {
      await customerRepository.update(task.customerId, { currentRecoveryState: 'Action Required', primaryNextAction: 'CALL CUSTOMER' }, conn);
    }
  });

  await notifyDecision(await salesmanForCustomer(task.customerId), {
    approved: true,
    title: 'Internal action approved',
    body: `${user.fullName} approved the internal action on this account.`,
    customerId: task.customerId,
  });
  return taskRepository.findById(taskId);
}

async function reject(taskId, user, { reason }) {
  const task = await getOpenInternalActionTask(taskId);

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
        attachmentPath: task.attachmentPath,
      },
      conn
    );

    const created = await taskService.ensureFollowUpIfNeeded(
      task.customerId,
      null,
      {
        reason: 'Internal action rejected',
        auditType: 'INTERNAL_ACTION_REJECTED_FOLLOWUP',
        source: 'Internal Action Review',
        priority: 'Normal',
        note: `${user.fullName} rejected the internal action on this account.${reason ? ` Reason: "${reason}".` : ''}`,
        attachmentPath: task.attachmentPath,
        requireDueBalance: false,
      },
      conn
    );
    if (created) {
      await customerRepository.update(task.customerId, { currentRecoveryState: 'Action Required', primaryNextAction: 'CALL CUSTOMER' }, conn);
    }
  });

  await notifyDecision(await salesmanForCustomer(task.customerId), {
    approved: false,
    title: 'Internal action rejected',
    body: `${user.fullName} rejected the internal action on this account.${reason ? ` Reason: "${reason}".` : ''}`,
    customerId: task.customerId,
  });
  return taskRepository.findById(taskId);
}

module.exports = { approve, reject };
