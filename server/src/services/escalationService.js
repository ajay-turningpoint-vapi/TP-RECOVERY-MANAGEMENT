const { withTransaction } = require('../config/db');
const escalationRepository = require('../repositories/escalationRepository');
const customerRepository = require('../repositories/customerRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const { enqueueNotification } = require('../queues/notificationQueue');
const { notifyDecision, salesmanForCustomer } = require('./decisionNotify');
const { driveRecoveryTask } = require('./recoveryTaskService');
const { NotFoundError } = require('../errors/AppError');

const LEVEL_SEVERITY = { none: 0, L1: 1, L2: 2, L3: 3, L4: 4 };

async function listForUser(user) {
  if (user.role === 'SALESPERSON') {
    const customers = await customerRepository.findBySalesman(user.id);
    const ids = new Set(customers.map((c) => c.id));
    const all = await escalationRepository.findAll();
    return all.filter((e) => ids.has(e.customerId));
  }
  return escalationRepository.findOpen();
}

async function listForCustomer(customerId) {
  return escalationRepository.findByCustomer(customerId);
}

async function getOrThrow(id) {
  const escalation = await escalationRepository.findById(id);
  if (!escalation) throw new NotFoundError('Escalation case');
  return escalation;
}

/**
 * Raises (or re-raises) an escalation on a customer. Only bumps the
 * customer's escalation_level when the new level is more severe than
 * whatever is already recorded — an L1 raised after an L3 already exists
 * shouldn't quietly downgrade the customer's badge.
 */
async function raise(customerId, user, { level, reason, plan, ownerId, deadline, moneyAtRisk }) {
  const customer = await customerRepository.findById(customerId);
  if (!customer) throw new NotFoundError('Customer');

  let escalationId;
  await withTransaction(async (conn) => {
    escalationId = await escalationRepository.insert(
      { customerId, level, reason, plan, ownerId, deadline, moneyAtRisk },
      conn
    );

    if (LEVEL_SEVERITY[level] > LEVEL_SEVERITY[customer.escalationLevel]) {
      await customerRepository.update(customerId, { escalationLevel: level }, conn);
    }

    await auditRepository.record(
      customerId,
      {
        type: 'ESCALATION_RAISED',
        description: `${user.fullName} raised a ${level} escalation: "${reason}"${ownerId ? ` — assigned to ${ownerId}` : ''}.`,
        actor: user.fullName,
        previousState: customer.escalationLevel,
        newState: level,
        source: 'Escalation',
      },
      conn
    );
  });

  if (ownerId) {
    // Queued, not written inline — a slow notification insert should never
    // delay the response to the RE who just raised this escalation.
    await enqueueNotification({
      userId: ownerId,
      severity: level === 'L3' || level === 'L4' ? 'critical' : 'warning',
      title: `${level} escalation assigned — ${customer.name}`,
      body: reason,
      customerId,
    });
  }

  return escalationRepository.findById(escalationId);
}

/**
 * Closes an escalation case. If it was the customer's last open case, the
 * customer's escalation_level resets to 'none' — otherwise it's left as-is
 * (another open case may still be more severe).
 */
async function resolve(escalationId, user, note) {
  const escalation = await getOrThrow(escalationId);

  await withTransaction(async (conn) => {
    await escalationRepository.update(escalationId, { isOpen: false }, conn);

    const stillOpen = await escalationRepository.findOpenByCustomer(escalation.customerId, conn);
    if (stillOpen.length === 0) {
      await customerRepository.update(escalation.customerId, { escalationLevel: 'none' }, conn);
    }

    // If this was a Customer Refused escalation, stop its growing-cadence
    // call task (missedDeadlineService.sweepRefusedCycle), the RE alert
    // task it may have raised once the cadence hit its steady 5-day
    // interval (source='Refused Cycle'), and reset the counter —
    // driveRecoveryTask below replaces the salesperson's task with a
    // single ordinary Recovery task instead.
    const openRefused = (await taskRepository.findByCustomer(escalation.customerId, conn)).filter(
      (t) => ['Customer Refused', 'Refused Cycle'].includes(t.source) && !['completed', 'closed', 'cancelled'].includes(t.status)
    );
    for (const t of openRefused) {
      await taskRepository.update(t.id, { status: 'completed', completedAt: new Date(), outcome: `${escalation.level} escalation resolved.` }, conn);
    }
    if (openRefused.length > 0) {
      await customerRepository.update(escalation.customerId, { refusedReopenCount: 0 }, conn);
    }

    await auditRepository.record(
      escalation.customerId,
      {
        type: 'ESCALATION_RESOLVED',
        description: `${user.fullName} resolved the ${escalation.level} escalation. ${note ? `Note: "${note}".` : ''}`.trim(),
        actor: user.fullName,
        previousState: escalation.level,
        newState: stillOpen.length === 0 ? 'none' : escalation.level,
        source: 'Escalation',
      },
      conn
    );

  });

  // Hand the account back to the salesman: drive the one `source='Recovery'`
  // call task to the current outstanding, due 6 PM. This also re-enables
  // Record Outcome for the customer in the app — replacing whatever
  // special-cadence task (e.g. Customer Refused's growing reopen, closed
  // above) was driving it before.
  {
    const customer = await customerRepository.findById(escalation.customerId);
    await driveRecoveryTask(escalation.customerId, {
      headline: `${escalation.level} escalation resolved — re-engage ${(customer && customer.name) || 'the customer'}.`,
      priority: 'Normal',
      deadlineHour: 18,
    });
  }

  await notifyDecision(await salesmanForCustomer(escalation.customerId), {
    approved: true,
    title: 'Escalation resolved',
    body: `${user.fullName} resolved the ${escalation.level} escalation on your customer.${note ? ` Note: "${note}".` : ''}`,
    customerId: escalation.customerId,
  });
  return escalationRepository.findById(escalationId);
}

module.exports = { listForUser, listForCustomer, raise, resolve };
