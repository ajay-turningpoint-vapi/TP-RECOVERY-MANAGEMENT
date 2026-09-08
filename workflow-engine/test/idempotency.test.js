import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createTaskWorker } from '../src/workers/task.worker.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { createTask, listTasks } from '../src/store/repository.js';

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

describe('Idempotency', () => {
  it('BullMQ v5 deduplication: a second job added with the same deduplication id while the first is still in-flight is coalesced, not double-processed', async () => {
    const queue = getQueue(QUEUE_NAMES.TASK);
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });

    const dedupId = `complete-${task.id}`;
    const [job1, job2] = await Promise.all([
      queue.add('complete', { taskId: task.id, actor: 'Rahul' }, { deduplication: { id: dedupId } }),
      queue.add('complete', { taskId: task.id, actor: 'Rahul' }, { deduplication: { id: dedupId } }),
    ]);

    // BullMQ's deduplication returns the SAME job for both calls while the
    // dedup window is active (default: while the job is active/waiting).
    expect(job1.id).toBe(job2.id);
  });

  it('processor-level idempotency: re-completing an already-completed task is a safe no-op, not a duplicate side effect', async () => {
    const task = createTask({ type: 'customerCall', customerId: 'C002', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });
    const queue = getQueue(QUEUE_NAMES.TASK);
    const first = await addAndWait(queue, 'complete', { taskId: task.id, actor: 'Rahul' });
    const countAfterFirst = listTasks().length;
    const second = await addAndWait(queue, 'complete', { taskId: task.id, actor: 'Rahul' });
    expect(second.reopenedTaskId).toBeNull();
    expect(listTasks().length).toBe(countAfterFirst);
    expect(first.taskId).toBe(second.taskId);
  });
});
