import { listTasks, listPtps, listCustomers, appendFivePmControlSnapshot } from '../store/repository.js';
import { state } from '../store/state.js';

function isOverdue(task, now) {
  return task.status !== 'completed' && task.status !== 'closed' && new Date(task.deadline).getTime() < now.getTime();
}

/**
 * Inserts a new daily control snapshot. Never mutates or removes a past
 * snapshot — later completion of the underlying issues does not erase the
 * original missed-control event, matching the audited invariant from the
 * source Dart implementation (`runFivePmControl`).
 */
export async function processFivePmControl(job) {
  if (job.name !== 'run') throw new Error(`Unknown five-pm-control job name: "${job.name}"`);
  const now = new Date();

  const tasks = listTasks();
  const overdueTasks = tasks.filter((t) => isOverdue(t, now)).length;
  const mandatoryActionsNotCompleted = tasks.filter((t) => t.priority === 'Critical' && t.status !== 'completed').length;

  const brokenPtps = listPtps().filter((p) => p.status === 'broken');
  const customers = listCustomers();
  const customerById = new Map(customers.map((c) => [c.id, c]));
  const brokenPtpWithoutNextAction = brokenPtps.filter((p) => !(customerById.get(p.customerId)?.hasValidNextAction)).length;

  const ownerlessExposure = customers.filter((c) => c.ownerMappingRequired).reduce((sum, c) => sum + c.totalDue, 0);

  const l3CasesWithoutPlan = [...state.escalationCases.values()].filter((c) => c.resolvedAt == null && c.level === 'L3' && !c.plan).length;

  const snapshot = appendFivePmControlSnapshot({
    overdueTasks,
    mandatoryActionsNotCompleted,
    brokenPtpWithoutNextAction,
    ownerlessExposure,
    l3CasesWithoutPlan,
  });

  return snapshot;
}
