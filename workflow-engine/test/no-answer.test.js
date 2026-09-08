import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createRecoveryOutcomeWorker } from '../src/workers/recovery-outcome.worker.js';
import { listTasks } from '../src/store/repository.js';

let recoveryWorker;

beforeAll(async () => {
  await fullReset();
  recoveryWorker = createRecoveryOutcomeWorker();
});

afterAll(async () => {
  await recoveryWorker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
});

describe('No Answer attempt progression', () => {
  it('does not create a physical visit task before the configured threshold', async () => {
    const queue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const r1 = await addAndWait(queue, 'no-answer', { customerId: 'C001', actor: 'Rahul' });
    expect(r1.attempts).toBe(1);
    expect(r1.physicalVisitTaskId).toBeNull();

    const r2 = await addAndWait(queue, 'no-answer', { customerId: 'C001', actor: 'Rahul' });
    expect(r2.attempts).toBe(2);
    expect(r2.physicalVisitTaskId).toBeNull();
  });

  it('auto-creates a Physical Visit task on the configured threshold (3rd attempt) and resets the counter', async () => {
    const queue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    await addAndWait(queue, 'no-answer', { customerId: 'C002', actor: 'Rahul' });
    await addAndWait(queue, 'no-answer', { customerId: 'C002', actor: 'Rahul' });
    const r3 = await addAndWait(queue, 'no-answer', { customerId: 'C002', actor: 'Rahul' });
    expect(r3.attempts).toBe(3);
    expect(r3.physicalVisitTaskId).toBeTruthy();

    const task = listTasks().find((t) => t.id === r3.physicalVisitTaskId);
    expect(task.type).toBe('physicalVisit');
    expect(task.ownerId).toBe('Rahul');

    // Counter reset — the next attempt starts back at 1, not 4.
    const r4 = await addAndWait(queue, 'no-answer', { customerId: 'C002', actor: 'Rahul' });
    expect(r4.attempts).toBe(1);
  });

  it('tracks attempt counters independently per customer', async () => {
    const queue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    await addAndWait(queue, 'no-answer', { customerId: 'C001', actor: 'Rahul' });
    await addAndWait(queue, 'no-answer', { customerId: 'C001', actor: 'Rahul' });
    const other = await addAndWait(queue, 'no-answer', { customerId: 'C003', actor: 'Mahesh' });
    expect(other.attempts).toBe(1); // unaffected by C001's count
  });
});
