import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { closeAllQueueEvents, queueEventsFor } from './helpers.js';
import { createEscalationWorker } from '../src/workers/escalation.worker.js';

let worker;
const processedOrder = [];

beforeEach(async () => {
  await fullReset();
  processedOrder.length = 0;
});

afterEach(async () => {
  if (worker) await worker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Job priority', () => {
  it('a higher-priority (L4-style, priority 1) job is processed before lower-priority ones queued ahead of it, once a single-concurrency worker is free', async () => {
    // A concurrency:1 worker with no jobs running yet — add several
    // "routine" jobs first, then a "critical" one, and confirm the
    // critical one is still processed first (lower `priority` number =
    // higher precedence in BullMQ).
    const queue = getQueue(QUEUE_NAMES.ESCALATION);
    const qe = queueEventsFor(QUEUE_NAMES.ESCALATION);
    await qe.waitUntilReady();

    // A blocking first job holds the single worker slot momentarily so the
    // rest genuinely queue up and get ordered by priority before any of
    // them are picked.
    await queue.add('manual', { customerId: 'C001', level: 'L2', reason: 'blocker', plan: 'x', ownerId: 'Amit' }, { priority: 10 });

    worker = createEscalationWorker({ concurrency: 1 });
    worker.on('completed', (job) => processedOrder.push(job.data.customerId));

    await new Promise((r) => setTimeout(r, 50)); // let the blocker start processing
    await queue.pause(true); // pause new job PICKUP (local) so the burst below queues up untouched
    const routine = await Promise.all([
      queue.add('manual', { customerId: 'C002', level: 'L2', reason: 'routine', plan: 'x', ownerId: 'Amit' }, { priority: 10 }),
      queue.add('manual', { customerId: 'C003', level: 'L2', reason: 'routine', plan: 'x', ownerId: 'Amit' }, { priority: 10 }),
    ]);
    const critical = await queue.add('manual', { customerId: 'C004', level: 'L4', reason: 'critical', plan: 'x', ownerId: 'Suresh' }, { priority: 1 });
    await queue.resume();

    await critical.waitUntilFinished(qe, 10000);
    await Promise.all(routine.map((j) => j.waitUntilFinished(qe, 10000)));

    // C001 (the blocker) is always first. Among the rest, the critical
    // C004 job must land before the two routine ones.
    const withoutBlocker = processedOrder.filter((id) => id !== 'C001');
    expect(withoutBlocker[0]).toBe('C004');
  }, 20000);
});
