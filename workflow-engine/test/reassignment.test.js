import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents, queueEventsFor } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createCustomerReassignmentWorker } from '../src/workers/customer-reassignment.worker.js';
import { createEscalationWorker } from '../src/workers/escalation.worker.js';
import { getCustomer, getSalesman, auditHistoryForCustomer } from '../src/store/repository.js';

let worker;
let escalationWorker;

beforeAll(async () => {
  await fullReset();
  worker = createCustomerReassignmentWorker();
  escalationWorker = createEscalationWorker();
});

afterAll(async () => {
  await worker.close();
  await escalationWorker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
});

describe('Customer reassignment', () => {
  it('transfers ownership, adjusts workload counts, and never rewrites prior actor attribution', async () => {
    const before = getCustomer('C001');
    expect(before.assignedSalesmanId).toBe('Rahul');
    const fromBefore = getSalesman('Rahul').customers ?? 0;
    const toBefore = getSalesman('Mahesh').customers ?? 0;

    const queue = getQueue(QUEUE_NAMES.CUSTOMER_REASSIGNMENT);
    const result = await addAndWait(queue, 'reassign', { customerId: 'C001', fromSalesmanId: 'Rahul', toSalesmanId: 'Mahesh', reason: 'Rahul overloaded', actor: 'Amit' });
    expect(result.assignedSalesmanId).toBe('Mahesh');
    expect(getCustomer('C001').assignedSalesmanId).toBe('Mahesh');
    expect(getSalesman('Rahul').customers).toBe(fromBefore - 1);
    expect(getSalesman('Mahesh').customers).toBe(toBefore + 1);

    const audit = auditHistoryForCustomer('C001');
    const event = audit.find((e) => e.type === 'RE_CHANGED_OWNER');
    expect(event).toBeTruthy();
    expect(event.previousState).toBe('Rahul');
    expect(event.newState).toBe('Mahesh');
    expect(event.description).toContain('audit history is never rewritten');
  });

  it('customer risk (escalation level) does not reset on reassignment', async () => {
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    await addAndWait(escalationQueue, 'manual', { customerId: 'C002', level: 'L3', reason: 'high risk', plan: 'monitor', ownerId: 'Amit', actor: 'Amit' });
    expect(getCustomer('C002').escalationLevel).toBe('L3');

    const queue = getQueue(QUEUE_NAMES.CUSTOMER_REASSIGNMENT);
    await addAndWait(queue, 'reassign', { customerId: 'C002', fromSalesmanId: 'Rahul', toSalesmanId: 'Mahesh', reason: 'test', actor: 'Amit' });
    expect(getCustomer('C002').escalationLevel).toBe('L3');
  });

  it('fails fast on an unknown customer rather than silently no-oping', async () => {
    const queue = getQueue(QUEUE_NAMES.CUSTOMER_REASSIGNMENT);
    const qe = queueEventsFor(QUEUE_NAMES.CUSTOMER_REASSIGNMENT);
    await qe.waitUntilReady();
    const job = await queue.add('reassign', { customerId: 'NOPE', fromSalesmanId: 'Rahul', toSalesmanId: 'Mahesh' }, { attempts: 1 });
    await expect(job.waitUntilFinished(qe)).rejects.toThrow();
  });
});
