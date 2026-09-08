import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createTaskWorker } from '../src/workers/task.worker.js';
import { closeAllQueueEvents, waitForCondition, queueEventsFor } from './helpers.js';
import { flushPendingDeadLetters } from '../src/events/dead-letter-listener.js';
import { createTask } from '../src/store/repository.js';

let worker;

beforeEach(async () => {
  await fullReset();
  worker = createTaskWorker();
});

afterEach(async () => {
  await worker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Dead-letter handling on exhausted retries', () => {
  it('a job that exhausts every retry attempt lands in the dead-letter queue with full context — not silently lost', async () => {
    const queue = getQueue(QUEUE_NAMES.TASK);
    // "complete" on a task id that will never exist — every attempt fails
    // with the same NotFoundError, so it genuinely exhausts attempts rather
    // than eventually succeeding.
    const qe = queueEventsFor(QUEUE_NAMES.TASK);
    await qe.waitUntilReady();
    const job = await queue.add('complete', { taskId: 'TASK_DOES_NOT_EXIST', actor: 'Rahul' }, { attempts: 2, backoff: { type: 'fixed', delay: 30 } });

    await expect(job.waitUntilFinished(qe, 10000)).rejects.toThrow();
    await flushPendingDeadLetters();

    const dlq = getQueue(QUEUE_NAMES.DEAD_LETTER);
    const dlqJobs = await waitForCondition(async () => {
      const waiting = await dlq.getJobs(['waiting', 'delayed', 'completed'], 0, 50);
      return waiting.length > 0 ? waiting : null;
    }, { timeout: 5000 });

    const entry = dlqJobs.find((j) => j.data.originalJobId === job.id);
    expect(entry).toBeTruthy();
    expect(entry.data.originalQueue).toBe(QUEUE_NAMES.TASK);
    expect(entry.data.originalJobName).toBe('complete');
    expect(entry.data.data.taskId).toBe('TASK_DOES_NOT_EXIST');
    expect(entry.data.attemptsMade).toBe(2);
    expect(entry.data.error.message).toContain('Task not found');
  }, 15000);

  it('a job that succeeds within its attempts never lands in the dead-letter queue', async () => {
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });
    const queue = getQueue(QUEUE_NAMES.TASK);
    const qe = queueEventsFor(QUEUE_NAMES.TASK);
    await qe.waitUntilReady();
    const job = await queue.add('complete', { taskId: task.id, actor: 'Rahul' });
    await job.waitUntilFinished(qe, 10000);
    await flushPendingDeadLetters();

    const dlq = getQueue(QUEUE_NAMES.DEAD_LETTER);
    const dlqJobs = await dlq.getJobs(['waiting', 'delayed', 'completed'], 0, 50);
    expect(dlqJobs.some((j) => j.data.originalJobId === job.id)).toBe(false);
  });
});
