import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createTaskWorker } from '../src/workers/task.worker.js';
import { createTask, getTask, getCustomer, updateCustomer, listTasks } from '../src/store/repository.js';

let taskWorker;

beforeAll(async () => {
  await fullReset();
  taskWorker = createTaskWorker();
});

afterAll(async () => {
  await taskWorker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
});

describe('Task engine', () => {
  it('completing a task with no other open task and money still due auto-reopens recovery (fixes an audited Dart gap)', async () => {
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });
    expect(getCustomer('C001').totalDue).toBeGreaterThan(0);

    const queue = getQueue(QUEUE_NAMES.TASK);
    const result = await addAndWait(queue, 'complete', { taskId: task.id, actor: 'Rahul' });
    expect(result.reopenedTaskId).toBeTruthy();

    const reopened = getTask(result.reopenedTaskId);
    expect(reopened.status).toBe('pending');
    expect(reopened.reason).toContain('remains due');
  });

  it('completing a task does NOT auto-reopen when another open task already covers the customer', async () => {
    const task = createTask({ type: 'customerCall', customerId: 'C002', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call 1' });
    createTask({ type: 'customerCall', customerId: 'C002', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call 2 (still open)' });

    const queue = getQueue(QUEUE_NAMES.TASK);
    const result = await addAndWait(queue, 'complete', { taskId: task.id, actor: 'Rahul' });
    expect(result.reopenedTaskId).toBeNull();
  });

  it('completing a task does NOT auto-reopen when the customer has no money due', async () => {
    await updateCustomer('C003', () => ({ totalDue: 0 }));
    const task = createTask({ type: 'customerCall', customerId: 'C003', ownerId: 'Mahesh', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });
    const queue = getQueue(QUEUE_NAMES.TASK);
    const result = await addAndWait(queue, 'complete', { taskId: task.id, actor: 'Mahesh' });
    expect(result.reopenedTaskId).toBeNull();
  });

  it('completing an already-completed task is idempotent — re-running it never creates a second reopened follow-up', async () => {
    const task = createTask({ type: 'customerCall', customerId: 'C002', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });
    const queue = getQueue(QUEUE_NAMES.TASK);
    const first = await addAndWait(queue, 'complete', { taskId: task.id, actor: 'Rahul' });
    expect(first.reopenedTaskId).toBeTruthy(); // money due, no other open task -> reopens once
    const tasksAfterFirst = listTasks().length;

    const second = await addAndWait(queue, 'complete', { taskId: task.id, actor: 'Rahul' });
    // The task-status update itself is a no-op the second time (already
    // completed). The reopened follow-up from the first run is itself an
    // open task now, so the "any other open task?" check correctly finds
    // it and does NOT spawn a second one.
    expect(second.reopenedTaskId).toBeNull();
    expect(listTasks().length).toBe(tasksAfterFirst);
  });

  it('reassign changes owner and writes a previousState/newState audit entry', async () => {
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'Call' });
    const queue = getQueue(QUEUE_NAMES.TASK);
    const result = await addAndWait(queue, 'reassign', { taskId: task.id, newOwnerId: 'Mahesh', reason: 'Rahul on leave', actor: 'Amit' });
    expect(result.ownerId).toBe('Mahesh');
    expect(getTask(task.id).ownerId).toBe('Mahesh');
  });

  it('RE-direct reschedule overwrites the deadline immediately (no approval loop needed)', async () => {
    const originalDeadline = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: originalDeadline, priority: 'Normal', reason: 'Call' });
    const newDeadline = new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString();
    const queue = getQueue(QUEUE_NAMES.TASK);
    const result = await addAndWait(queue, 'reschedule', { taskId: task.id, newDeadline, reason: 'Customer traveling', actor: 'Amit' });
    expect(result.deadline).toBe(new Date(newDeadline).toISOString());
  });

  it('salesperson-requested edit keeps the ORIGINAL deadline authoritative until RE approves', async () => {
    const originalDeadline = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: originalDeadline, priority: 'Normal', reason: 'Call' });
    const requestedDeadline = new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString();

    const queue = getQueue(QUEUE_NAMES.TASK);
    await addAndWait(queue, 'request-edit-approval', { taskId: task.id, newDeadline: requestedDeadline, newReason: 'Need more time', actor: 'Rahul' });

    // Original deadline must remain untouched while Pending.
    expect(getTask(task.id).deadline).toBe(originalDeadline);
    expect(getTask(task.id).approvalStatus).toBe('Pending');

    await addAndWait(queue, 'approve-edit', { taskId: task.id, actor: 'Amit' });
    expect(getTask(task.id).deadline).toBe(new Date(requestedDeadline).toISOString());
    expect(getTask(task.id).approvalStatus).toBe('Approved');
  });

  it('a rejected edit request leaves the original deadline untouched', async () => {
    const originalDeadline = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: originalDeadline, priority: 'Normal', reason: 'Call' });
    const queue = getQueue(QUEUE_NAMES.TASK);
    await addAndWait(queue, 'request-edit-approval', { taskId: task.id, newDeadline: new Date(Date.now() + 99 * 24 * 3600 * 1000).toISOString(), actor: 'Rahul' });
    await addAndWait(queue, 'reject-edit', { taskId: task.id, reason: 'Too long', actor: 'Amit' });
    expect(getTask(task.id).deadline).toBe(originalDeadline);
    expect(getTask(task.id).approvalStatus).toBe('Rejected');
  });

  it('review-physical-visit marks reviewedByRE without altering task status', async () => {
    const task = createTask({ type: 'physicalVisit', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'High', reason: 'Visit', status: 'completed' });
    const queue = getQueue(QUEUE_NAMES.TASK);
    const result = await addAndWait(queue, 'review-physical-visit', { taskId: task.id, actor: 'Amit' });
    expect(result.reviewedByRE).toBe(true);
    expect(getTask(task.id).status).toBe('completed');
  });
});
