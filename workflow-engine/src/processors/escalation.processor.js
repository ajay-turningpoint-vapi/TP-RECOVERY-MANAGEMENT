import {
  getCustomer,
  updateCustomer,
  appendAuditEvent,
  pushNotification,
  upsertEscalationCase,
  resolveEscalationCase,
  listPtps,
} from '../store/repository.js';

const LEVEL_ORDER = { none: 0, L1: 1, L2: 2, L3: 3, L4: 4 };

export async function escalateCustomer({ customerId, level, reason, plan, ownerId, deadline, actor = 'System', autoTriggered = false, source }) {
  const customer = getCustomer(customerId);
  if ((LEVEL_ORDER[level] ?? 0) <= (LEVEL_ORDER[customer.escalationLevel] ?? 0)) {
    // Ratchet-only invariant: never downgrade, never redundantly "escalate" to
    // a level the customer has already reached or passed.
    return { skipped: true, currentLevel: customer.escalationLevel };
  }

  const { case: escalationCase, created } = await upsertEscalationCase(customerId, {
    level,
    reason,
    plan,
    ownerId,
    deadline: deadline ? new Date(deadline).toISOString() : null,
    moneyAtRisk: customer.totalDue,
    historyEntry: `Escalated to ${level}: ${reason}`,
  });

  await updateCustomer(customerId, (c) => ({
    escalationLevel: level,
    currentRecoveryState: level === 'L3' || level === 'L4' ? 'RE Control' : c.currentRecoveryState,
    primaryNextAction: level === 'L4' ? 'MANAGEMENT ATTENTION' : 'RE INTERVENTION',
  }));

  appendAuditEvent({
    customerId,
    type: 'ESCALATED',
    description: autoTriggered
      ? `System auto-escalated to ${level} after repeated broken PTPs: ${reason}`
      : `${actor} escalated to ${level}: ${reason}`,
    actor: autoTriggered ? 'System' : actor,
    previousState: customer.escalationLevel,
    newState: level,
    source: source || (autoTriggered ? 'Broken PTP Escalation Engine' : 'RE Escalation Control'),
    relatedEntityType: 'EscalationCase',
    relatedEntityId: escalationCase.id,
  });

  pushNotification({
    customerId,
    severity: level === 'L4' ? 'critical' : 'warning',
    title: level === 'L4' ? 'L4 — Management Attention' : `${level} — Escalation`,
    message: reason,
  });

  return { skipped: false, escalationCaseId: escalationCase.id, created };
}

/** Auto-evaluation: never sets L4 — that stays a human judgment call, matching
 * the source Dart engine's explicit design (see plan doc). Only ever moves a
 * customer up the ladder based on confirmed broken-PTP count. */
export async function evaluateBrokenPtpEscalation({ customerId }) {
  const brokenCount = listPtps().filter((p) => p.customerId === customerId && p.status === 'broken').length;
  if (brokenCount < 2) return { skipped: true, brokenCount };

  const targetLevel = brokenCount >= 3 ? 'L3' : 'L2';
  const deadline = new Date(Date.now() + (targetLevel === 'L3' ? 2 : 3) * 24 * 3600 * 1000);
  const reason = `${brokenCount} broken PTP(s) reconciled against BUSY`;
  const plan = targetLevel === 'L3' ? 'RE to personally contact customer within 48 hours and secure a revised commitment.' : 'RE to review account and confirm next recovery step within 72 hours.';

  const result = await escalateCustomer({
    customerId,
    level: targetLevel,
    reason,
    plan,
    ownerId: 'Recovery Executive',
    deadline,
    autoTriggered: true,
  });

  return { ...result, brokenCount, targetLevel };
}

export async function processEscalation(job) {
  if (job.name === 'summary') {
    // The Flow *parent* job spawned by busy-sync.processor.js, processed
    // only after every "evaluate" child below has completed. It carries no
    // independent work — its sole purpose is to give busy-sync's
    // `waitUntilFinished` something to await that resolves once escalation
    // re-evaluation has genuinely finished for every affected customer.
    return { customerIds: job.data.customerIds };
  }
  if (job.name === 'evaluate') {
    return evaluateBrokenPtpEscalation(job.data);
  }
  if (job.name === 'manual') {
    if (!job.data.customerId || !job.data.level) throw new Error('escalation manual job requires customerId and level');
    return escalateCustomer(job.data);
  }
  if (job.name === 'resolve') {
    if (!job.data.escalationCaseId) throw new Error('escalation resolve job requires escalationCaseId');
    const updated = await resolveEscalationCase(job.data.escalationCaseId, job.data.resolutionNote || 'Resolved');
    appendAuditEvent({
      customerId: updated.customerId,
      type: 'RE_RESOLVED_ESCALATION',
      description: `Escalation case resolved: ${job.data.resolutionNote || 'Resolved'}. Historical escalation level is retained, not reset.`,
      actor: job.data.actor || 'Recovery Executive',
      source: 'Escalation Resolution',
      relatedEntityType: 'EscalationCase',
      relatedEntityId: updated.id,
    });
    return { escalationCaseId: updated.id, resolvedAt: updated.resolvedAt };
  }
  throw new Error(`Unknown escalation job name: "${job.name}"`);
}
