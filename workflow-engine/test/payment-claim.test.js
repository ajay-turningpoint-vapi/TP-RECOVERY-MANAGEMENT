import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createRecoveryOutcomeWorker } from '../src/workers/recovery-outcome.worker.js';
import { createPaymentClaimWorker } from '../src/workers/payment-claim.worker.js';
import { BusyClient } from '../src/simulators/busy-client.js';
import { getPaymentClaim, setBusySyncHealth } from '../src/store/repository.js';

let recoveryWorker;
let paymentClaimWorker;

async function claimPayment(customerId, amount) {
  const recoveryQueue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
  const { paymentClaimId } = await addAndWait(recoveryQueue, 'verification-pending', { customerId, actor: 'Rahul', amount });
  return paymentClaimId;
}

beforeAll(async () => {
  await fullReset();
  recoveryWorker = createRecoveryOutcomeWorker();
});

afterAll(async () => {
  await recoveryWorker.close();
  if (paymentClaimWorker) await paymentClaimWorker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
  setBusySyncHealth(true);
  if (paymentClaimWorker) await paymentClaimWorker.close();
  paymentClaimWorker = createPaymentClaimWorker({ busyClient: new BusyClient({ healthy: true }) }, { limiter: undefined });
});

describe('Payment claim verification', () => {
  it('records a real Awaiting Verification claim from a recovery-outcome job — never immediately Paid', async () => {
    const claimId = await claimPayment('C001', 45000);
    const claim = getPaymentClaim(claimId);
    expect(claim.status).toBe('Awaiting Verification');
    expect(claim.amount).toBe(45000);
  });

  it('RE verification marks it Verified when BUSY is healthy', async () => {
    const claimId = await claimPayment('C001', 20000);
    const queue = getQueue(QUEUE_NAMES.PAYMENT_CLAIM);
    const result = await addAndWait(queue, 'verify', { claimId, success: true, actor: 'Amit' });
    expect(result.status).toBe('Verified');
  });

  it('RE verification can mark it Failed when BUSY is healthy', async () => {
    const claimId = await claimPayment('C001', 20000);
    const queue = getQueue(QUEUE_NAMES.PAYMENT_CLAIM);
    const result = await addAndWait(queue, 'verify', { claimId, success: false, actor: 'Amit' });
    expect(result.status).toBe('Failed');
  });

  it('never marks Verified while BUSY sync is unhealthy — holds as Sync Pending instead', async () => {
    const claimId = await claimPayment('C001', 20000);
    setBusySyncHealth(false);
    const queue = getQueue(QUEUE_NAMES.PAYMENT_CLAIM);
    const result = await addAndWait(queue, 'verify', { claimId, success: true, actor: 'Amit' });
    expect(result.status).toBe('Sync Pending');
    expect(getPaymentClaim(claimId).status).toBe('Sync Pending');
  });

  it('closes the audit gap found in the source app: never marks Failed while BUSY sync is unhealthy either — holds as Sync Pending, not a false negative', async () => {
    const claimId = await claimPayment('C001', 20000);
    setBusySyncHealth(false);
    const queue = getQueue(QUEUE_NAMES.PAYMENT_CLAIM);
    const result = await addAndWait(queue, 'verify', { claimId, success: false, actor: 'Amit' });
    expect(result.status).toBe('Sync Pending');
    expect(getPaymentClaim(claimId).status).not.toBe('Failed');
  });
});
