import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createDisputeWorker } from '../src/workers/dispute.worker.js';
import { createRecoveryOutcomeWorker } from '../src/workers/recovery-outcome.worker.js';
import { addAndWait, closeAllQueueEvents, waitForCondition } from './helpers.js';
import { getCustomer } from '../src/store/repository.js';

let disputeWorker;
let recoveryWorker;

beforeEach(async () => {
  await fullReset();
  disputeWorker = createDisputeWorker();
  recoveryWorker = createRecoveryOutcomeWorker();
});

afterEach(async () => {
  await disputeWorker.close();
  await recoveryWorker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Delayed jobs', () => {
  it('a delayed job does not run before its delay elapses', async () => {
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    const { disputeId } = await addAndWait(getQueue(QUEUE_NAMES.RECOVERY_OUTCOME), 'dispute-raised', { customerId: 'C001', actor: 'Rahul', amount: 25000, reason: 'Timing' });
    await addAndWait(disputeQueue, 'approve', { disputeId, resolutionOwner: 'Amit', deadline: new Date(Date.now() + 86400000).toISOString(), description: 'x' });
    await addAndWait(disputeQueue, 'move-to-resolution', { disputeId });
    await addAndWait(disputeQueue, 'mark-awaiting-verification', { disputeId });

    const beforeResolve = getCustomer('C001').primaryNextAction;
    await addAndWait(disputeQueue, 'resolve', { disputeId, verifyAfterMs: 800, paidConfirmed: false });

    // Immediately after `resolve` returns, the delayed follow-up must NOT
    // have run yet — it fires at t+800ms.
    expect(getCustomer('C001').primaryNextAction).toBe(beforeResolve);

    await waitForCondition(() => getCustomer('C001').primaryNextAction === 'CALL CUSTOMER', { timeout: 5000 });
    expect(getCustomer('C001').currentRecoveryState).toBe('Waiting / Monitoring');
  }, 15000);

  it('the delayed job sits in the "delayed" state immediately after being scheduled, then transitions to completed only once the delay elapses', async () => {
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    const { disputeId } = await addAndWait(getQueue(QUEUE_NAMES.RECOVERY_OUTCOME), 'dispute-raised', { customerId: 'C002', actor: 'Rahul', amount: 25000, reason: 'Timing 2' });
    await addAndWait(disputeQueue, 'approve', { disputeId, resolutionOwner: 'Amit', deadline: new Date(Date.now() + 86400000).toISOString(), description: 'x' });
    await addAndWait(disputeQueue, 'move-to-resolution', { disputeId });
    await addAndWait(disputeQueue, 'mark-awaiting-verification', { disputeId });
    await addAndWait(disputeQueue, 'resolve', { disputeId, verifyAfterMs: 500, paidConfirmed: true });

    const jobs = await disputeQueue.getDelayed();
    const followUp = jobs.find((j) => j.name === 'return-to-recovery-check' && j.data.disputeId === disputeId);
    expect(followUp).toBeTruthy();
    expect(await followUp.getState()).toBe('delayed');

    await waitForCondition(async () => (await followUp.getState()) === 'completed', { timeout: 5000 });
  }, 15000);
});
