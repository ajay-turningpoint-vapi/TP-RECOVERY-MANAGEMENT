import { describe, it, expect, afterEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createDomainWorker } from '../src/workers/create-worker.js';
import { closeAllQueueEvents, queueEventsFor } from './helpers.js';
import { createTask } from '../src/store/repository.js';

let worker;

afterEach(async () => {
  if (worker) await worker.close().catch(() => {});
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Graceful shutdown', () => {
  it('worker.close() waits for the in-flight job to finish rather than abandoning it', async () => {
    await fullReset();
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });

    let jobStarted = false;
    let jobFinished = false;
    worker = createDomainWorker(QUEUE_NAMES.TASK, async (job) => {
      jobStarted = true;
      await new Promise((r) => setTimeout(r, 800)); // simulate slow, real work
      jobFinished = true;
      return { taskId: job.data.taskId, status: 'completed' };
    });

    const queue = getQueue(QUEUE_NAMES.TASK);
    const job = await queue.add('complete', { taskId: task.id });

    await new Promise((resolve) => {
      const check = setInterval(() => {
        if (jobStarted) {
          clearInterval(check);
          resolve();
        }
      }, 20);
    });

    // Signal shutdown WHILE the job is still running.
    const closePromise = worker.close();
    expect(jobFinished).toBe(false); // still running at the moment we asked to close

    await closePromise;
    // close() must not have returned until the in-flight job genuinely
    // completed — not abandoned it mid-flight.
    expect(jobFinished).toBe(true);

    // The job has almost certainly already finished by this point (we just
    // awaited jobFinished above) — pre-warm before relying on
    // waitUntilFinished, matching the fix for the race found via
    // rate-limit.test.js.
    const qe1 = queueEventsFor(QUEUE_NAMES.TASK);
    await qe1.waitUntilReady();
    const finalStatus = await job.waitUntilFinished(qe1, 5000);
    expect(finalStatus.status).toBe('completed');
  }, 15000);

  it('after close(), the worker no longer picks up newly added jobs', async () => {
    await fullReset();
    let processedCount = 0;
    worker = createDomainWorker(QUEUE_NAMES.TASK, async () => {
      processedCount += 1;
      return {};
    });

    const queue = getQueue(QUEUE_NAMES.TASK);
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });
    const qe2 = queueEventsFor(QUEUE_NAMES.TASK);
    await qe2.waitUntilReady();
    const job1 = await queue.add('complete', { taskId: task.id });
    await job1.waitUntilFinished(qe2, 5000);
    expect(processedCount).toBe(1);

    await worker.close();

    // Job added after shutdown must sit unprocessed by this (closed) worker.
    await queue.add('complete', { taskId: task.id });
    await new Promise((r) => setTimeout(r, 300));
    expect(processedCount).toBe(1); // unchanged — closed worker never picked it up
  });
});
