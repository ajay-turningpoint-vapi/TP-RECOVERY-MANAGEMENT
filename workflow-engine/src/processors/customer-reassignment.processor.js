import { getCustomer, updateCustomer, appendAuditEvent, getSalesman } from '../store/repository.js';
import { state } from '../store/state.js';
import { withLock } from '../store/mutex.js';

export async function processCustomerReassignment(job) {
  if (job.name !== 'reassign') throw new Error(`Unknown customer-reassignment job name: "${job.name}"`);
  const { customerId, fromSalesmanId, toSalesmanId, reason, actor } = job.data;
  if (!customerId || !fromSalesmanId || !toSalesmanId) {
    throw new Error('customer-reassignment reassign job requires customerId, fromSalesmanId, toSalesmanId');
  }
  getCustomer(customerId);
  getSalesman(fromSalesmanId);
  getSalesman(toSalesmanId);

  appendAuditEvent({
    customerId,
    type: 'RE_CHANGED_OWNER',
    description: `Ownership transferred from ${fromSalesmanId} to ${toSalesmanId}: ${reason || 'no reason given'}. ${fromSalesmanId} remains the recorded actor on every action taken before this point — audit history is never rewritten. ${toSalesmanId} now sees this customer's complete company history. Customer risk does not reset.`,
    actor: actor || 'Recovery Executive',
    previousState: fromSalesmanId,
    newState: toSalesmanId,
    source: 'Customer Reassignment',
    relatedEntityType: 'Customer',
    relatedEntityId: customerId,
  });

  await updateCustomer(customerId, () => ({ assignedSalesmanId: toSalesmanId }));

  // Salesmen roster workload counts are derived/aggregate — adjust under
  // the same customer lock so a concurrent reassignment of a *different*
  // customer between the same two salesmen can't race the counters.
  await withLock(`salesman-roster:${fromSalesmanId}:${toSalesmanId}`, () => {
    const from = state.salesmen.get(fromSalesmanId);
    const to = state.salesmen.get(toSalesmanId);
    if (from) state.salesmen.set(fromSalesmanId, { ...from, customers: (from.customers || 0) - 1 });
    if (to) state.salesmen.set(toSalesmanId, { ...to, customers: (to.customers || 0) + 1 });
  });

  return { customerId, assignedSalesmanId: toSalesmanId };
}
