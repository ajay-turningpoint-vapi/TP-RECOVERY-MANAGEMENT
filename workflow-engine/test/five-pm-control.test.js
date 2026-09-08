import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createFivePmControlWorker } from '../src/workers/five-pm-control.worker.js';
import { createTask, listFivePmControlSnapshots } from '../src/store/repository.js';

let worker;

beforeAll(async () => {
  await fullReset();
  worker = createFivePmControlWorker();
});

afterAll(async () => {
  await worker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
});

describe('5 PM Control', () => {
  it('produces a real snapshot reflecting current overdue/critical task counts', async () => {
    createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date(Date.now() - 3600000).toISOString(), priority: 'Critical', reason: 'Overdue critical task' });
    const queue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
    const snapshot = await addAndWait(queue, 'run', {});
    expect(snapshot.overdueTasks).toBeGreaterThanOrEqual(1);
    expect(snapshot.mandatoryActionsNotCompleted).toBeGreaterThanOrEqual(1);
  });

  it('is append-only — running it twice keeps both historical snapshots, never overwriting the first', async () => {
    const queue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
    await addAndWait(queue, 'run', {});
    await addAndWait(queue, 'run', {});
    const snapshots = listFivePmControlSnapshots();
    expect(snapshots.length).toBe(2);
    expect(snapshots[0].id).not.toBe(snapshots[1].id);
  });

  it('a later-completed task does not retroactively erase the original missed-control event', async () => {
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date(Date.now() - 3600000).toISOString(), priority: 'Normal', reason: 'Overdue' });
    const queue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
    const firstSnapshot = await addAndWait(queue, 'run', {});
    expect(firstSnapshot.overdueTasks).toBeGreaterThanOrEqual(1);

    const taskQueueModule = await import('../src/workers/task.worker.js');
    const taskWorker = taskQueueModule.createTaskWorker();
    const taskQueue = getQueue(QUEUE_NAMES.TASK);
    await addAndWait(taskQueue, 'complete', { taskId: task.id, actor: 'Rahul' });
    await taskWorker.close();

    const snapshots = listFivePmControlSnapshots();
    // The original historical snapshot is untouched even though the
    // underlying task is now completed.
    expect(snapshots[0].overdueTasks).toBe(firstSnapshot.overdueTasks);
  });
});
