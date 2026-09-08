import { describe, it, expect, afterEach } from 'vitest';
import { Worker } from 'bullmq';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createConnection } from '../src/redis-connection.js';
import { attachDeadLetterHandling } from '../src/events/dead-letter-listener.js';
import { closeAllQueueEvents, waitForCondition } from './helpers.js';
import { createTask, getTask } from '../src/store/repository.js';

let workers = [];

afterEach(async () => {
  await Promise.all(workers.map((w) => w.close(true).catch(() => {})));
  workers = [];
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Stalled-job recovery', () => {
  it('a job whose worker dies mid-processing (no clean close, lock never renewed) is detected as stalled and picked up by another worker', async () => {
    await fullReset();
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });

    // Worker A: picks up the job and then simulates a hard crash — it never
    // calls job.updateProgress/extendLock again and is force-destroyed
    // (not gracefully closed), so its lock is never released or renewed.
    let workerAStartedProcessing = false;
    const connectionA = createConnection();
    const workerA = new Worker(
      QUEUE_NAMES.TASK,
      async () => {
        workerAStartedProcessing = true;
        // Simulate a crash: hang well past the short lock duration/stalled
        // check interval configured below, then never actually finish.
        await new Promise((r) => setTimeout(r, 60000));
      },
      { connection: connectionA, concurrency: 1, lockDuration: 500, stalledInterval: 500, maxStalledCount: 1 },
    );
    workers.push(workerA);

    const queue = getQueue(QUEUE_NAMES.TASK);
    await queue.add('complete', { taskId: task.id, actor: 'Rahul' });

    await waitForCondition(() => workerAStartedProcessing, { timeout: 5000 });

    // Simulate the crash: sever this worker's own connection so its
    // automatic lock-extension can no longer reach Redis, without giving it
    // a chance to gracefully release the job the way `.close()` would.
    connectionA.disconnect(false);

    // Worker B: a healthy worker on the same queue, using the real
    // processTask handler, watching for the same job to complete once
    // BullMQ's stalled-job detection reassigns it.
    const { processTask } = await import('../src/processors/task.processor.js');
    const workerB = new Worker(QUEUE_NAMES.TASK, (job) => processTask(job), {
      connection: createConnection(),
      concurrency: 1,
      lockDuration: 30000,
      stalledInterval: 500,
      maxStalledCount: 1,
    });
    attachDeadLetterHandling(workerB, QUEUE_NAMES.TASK);
    workers.push(workerB);

    await waitForCondition(() => getTask(task.id).status === 'completed', { timeout: 10000 });
    expect(getTask(task.id).status).toBe('completed');
  }, 20000);
});
