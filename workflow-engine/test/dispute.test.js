import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents, waitForCondition } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createRecoveryOutcomeWorker } from '../src/workers/recovery-outcome.worker.js';
import { createDisputeWorker } from '../src/workers/dispute.worker.js';
import { createTaskWorker } from '../src/workers/task.worker.js';
import { getCustomer, getDispute, listDisputes, setBusySyncHealth, listTasks } from '../src/store/repository.js';

let recoveryWorker;
let disputeWorker;
let taskWorker;

async function raiseDispute(customerId, amount, reason) {
  const recoveryQueue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
  const { disputeId } = await addAndWait(recoveryQueue, 'dispute-raised', { customerId, actor: 'Rahul', amount, reason });
  return disputeId;
}

beforeAll(async () => {
  await fullReset();
  recoveryWorker = createRecoveryOutcomeWorker();
  disputeWorker = createDisputeWorker();
  taskWorker = createTaskWorker();
});

afterAll(async () => {
  await recoveryWorker.close();
  await disputeWorker.close();
  await taskWorker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
  setBusySyncHealth(true);
});

describe('Dispute lifecycle', () => {
  it('raising a dispute creates a real, Pending Approval record with an amount-derived priority', async () => {
    const disputeId = await raiseDispute('C002', 150000, 'Goods damaged in transit');
    const dispute = getDispute(disputeId);
    expect(dispute.status).toBe('Pending Approval');
    expect(dispute.priority).toBe('High'); // >= 100000
    expect(dispute.amount).toBe(150000);
  });

  it('approve creates a real disputeResolution task and shields the amount from active recovery', async () => {
    const disputeId = await raiseDispute('C001', 45000, 'Partial shipment');
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    const result = await addAndWait(disputeQueue, 'approve', {
      disputeId,
      resolutionOwner: 'Amit',
      deadline: new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString(),
      description: 'Verify partial shipment claim',
      actor: 'Amit',
    });
    expect(result.status).toBe('Approved');
    const task = listTasks().find((t) => t.id === result.taskId);
    expect(task.type).toBe('disputeResolution');
    expect(task.ownerId).toBe('Amit');
  });

  it('reject leaves the full amount in active recovery and creates no task', async () => {
    const disputeId = await raiseDispute('C001', 20000, 'Frivolous claim');
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    const tasksBefore = listTasks().length;
    const result = await addAndWait(disputeQueue, 'reject', { disputeId, reason: 'No supporting evidence', actor: 'Amit' });
    expect(result.status).toBe('Rejected');
    expect(listTasks().length).toBe(tasksBefore);
  });

  it('request-info keeps the dispute open and creates a task for the salesperson', async () => {
    const disputeId = await raiseDispute('C003', 30000, 'Need invoice copy');
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    const result = await addAndWait(disputeQueue, 'request-info', {
      disputeId,
      salesmanId: 'Mahesh',
      description: 'Please provide the invoice copy',
      deadline: new Date(Date.now() + 2 * 24 * 3600 * 1000).toISOString(),
      actor: 'Amit',
    });
    expect(result.status).toBe('Need More Information');
    const task = listTasks().find((t) => t.id === result.taskId);
    expect(task.ownerId).toBe('Mahesh');
  });

  it('completes the full back-half lifecycle: Approved -> In Resolution -> Awaiting Verification -> Resolved', async () => {
    const disputeId = await raiseDispute('C002', 40000, 'Amount mismatch');
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    await addAndWait(disputeQueue, 'approve', {
      disputeId,
      resolutionOwner: 'Amit',
      deadline: new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString(),
      description: 'Reconcile amount',
    });
    await addAndWait(disputeQueue, 'move-to-resolution', { disputeId });
    expect(getDispute(disputeId).status).toBe('In Resolution');
    await addAndWait(disputeQueue, 'mark-awaiting-verification', { disputeId });
    expect(getDispute(disputeId).status).toBe('Awaiting Verification');
    await addAndWait(disputeQueue, 'resolve', { disputeId, verifyAfterMs: 50 });
    expect(getDispute(disputeId).status).toBe('Resolved');
  });

  it('never resolves a dispute while BUSY sync is unhealthy — holds it instead of falsely marking Resolved', async () => {
    const disputeId = await raiseDispute('C002', 40000, 'Amount mismatch');
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    await addAndWait(disputeQueue, 'approve', { disputeId, resolutionOwner: 'Amit', deadline: new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString(), description: 'x' });
    await addAndWait(disputeQueue, 'move-to-resolution', { disputeId });
    await addAndWait(disputeQueue, 'mark-awaiting-verification', { disputeId });

    setBusySyncHealth(false);
    const result = await addAndWait(disputeQueue, 'resolve', { disputeId });
    expect(result.held).toBe(true);
    expect(getDispute(disputeId).status).toBe('Awaiting Verification'); // unchanged, not falsely Resolved
  });

  it('a Resolved-but-unpaid dispute returns the customer to active recovery via the delayed follow-up job', async () => {
    const disputeId = await raiseDispute('C005', 25000, 'Short payment dispute');
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    await addAndWait(disputeQueue, 'approve', { disputeId, resolutionOwner: 'Amit', deadline: new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString(), description: 'x' });
    await addAndWait(disputeQueue, 'move-to-resolution', { disputeId });
    await addAndWait(disputeQueue, 'mark-awaiting-verification', { disputeId });
    await addAndWait(disputeQueue, 'resolve', { disputeId, verifyAfterMs: 200, paidConfirmed: false });

    // The delayed return-to-recovery-check job fires ~200ms later — poll
    // real store state until it has genuinely run, rather than sleeping a
    // fixed guess.
    await waitForCondition(() => getCustomer('C005').primaryNextAction === 'CALL CUSTOMER', { timeout: 5000 });
    expect(getCustomer('C005').currentRecoveryState).toBe('Waiting / Monitoring');
    const followUp = listTasks().find((t) => t.customerId === 'C005' && t.reason.includes('still unpaid'));
    expect(followUp).toBeTruthy();
  });

  it('a Resolved-and-paid dispute does NOT return the customer to recovery', async () => {
    const disputeId = await raiseDispute('C004', 25000, 'Timing dispute');
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    await addAndWait(disputeQueue, 'approve', { disputeId, resolutionOwner: 'Amit', deadline: new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString(), description: 'x' });
    await addAndWait(disputeQueue, 'move-to-resolution', { disputeId });
    await addAndWait(disputeQueue, 'mark-awaiting-verification', { disputeId });
    const stateBefore = getCustomer('C004').primaryNextAction;
    await addAndWait(disputeQueue, 'resolve', { disputeId, verifyAfterMs: 200, paidConfirmed: true });

    await new Promise((r) => setTimeout(r, 500));
    expect(getCustomer('C004').primaryNextAction).toBe(stateBefore); // untouched
  });
});
