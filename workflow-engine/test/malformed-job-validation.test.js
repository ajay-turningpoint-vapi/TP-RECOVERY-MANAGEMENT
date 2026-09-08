// Every processor must fail fast on malformed job data (missing required
// fields, unknown job name) rather than silently corrupting store state or
// hanging. This sweeps every domain queue's failure modes in one file so
// the whole validation surface is visible at a glance.
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { closeAllQueueEvents, queueEventsFor } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';

import { createRecoveryOutcomeWorker } from '../src/workers/recovery-outcome.worker.js';
import { createBusySyncWorker } from '../src/workers/busy-sync.worker.js';
import { createEscalationWorker } from '../src/workers/escalation.worker.js';
import { createPaymentClaimWorker } from '../src/workers/payment-claim.worker.js';
import { createDisputeWorker } from '../src/workers/dispute.worker.js';
import { createTaskWorker } from '../src/workers/task.worker.js';
import { createManagementInstructionWorker } from '../src/workers/management-instruction.worker.js';
import { createCustomerReassignmentWorker } from '../src/workers/customer-reassignment.worker.js';
import { createCorrectionRequestWorker } from '../src/workers/correction-request.worker.js';
import { createFivePmControlWorker } from '../src/workers/five-pm-control.worker.js';

let workers = [];

beforeAll(async () => {
  await fullReset();
  workers = [
    createRecoveryOutcomeWorker(),
    createBusySyncWorker(),
    createEscalationWorker(),
    createPaymentClaimWorker(),
    createDisputeWorker(),
    createTaskWorker(),
    createManagementInstructionWorker(),
    createCustomerReassignmentWorker(),
    createCorrectionRequestWorker(),
    createFivePmControlWorker(),
  ];
});

afterAll(async () => {
  await Promise.all(workers.map((w) => w.close()));
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
});

async function expectRejects(queueName, jobName, data) {
  const queue = getQueue(queueName);
  // Pre-warm before adding — these validation failures throw synchronously
  // and fast, which can otherwise race a lazily-created QueueEvents
  // subscription (see rate-limit.test.js's fix for the confirmed, if
  // intermittent, real BullMQ race this guards against).
  const qe = queueEventsFor(queueName);
  await qe.waitUntilReady();
  const job = await queue.add(jobName, data, { attempts: 1 });
  await expect(job.waitUntilFinished(qe, 10000)).rejects.toThrow();
}

describe('Malformed job validation — every domain queue fails fast, never silently no-ops', () => {
  it('recovery-outcome: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.RECOVERY_OUTCOME, 'not-a-real-outcome', { customerId: 'C001' });
  });
  it('recovery-outcome: ptp-scheduled rejects missing amountPromised', async () => {
    await expectRejects(QUEUE_NAMES.RECOVERY_OUTCOME, 'ptp-scheduled', { customerId: 'C001', promiseDate: new Date().toISOString(), paymentMode: 'Cash' });
  });
  it('recovery-outcome: dispute-raised rejects missing amount', async () => {
    await expectRejects(QUEUE_NAMES.RECOVERY_OUTCOME, 'dispute-raised', { customerId: 'C001', reason: 'x' });
  });
  it('recovery-outcome: verification-pending rejects missing amount', async () => {
    await expectRejects(QUEUE_NAMES.RECOVERY_OUTCOME, 'verification-pending', { customerId: 'C001' });
  });
  it('recovery-outcome: internal-action rejects missing details', async () => {
    await expectRejects(QUEUE_NAMES.RECOVERY_OUTCOME, 'internal-action', { customerId: 'C001' });
  });
  it('recovery-outcome: rejects an unknown customerId (fails fast, no silent no-op)', async () => {
    await expectRejects(QUEUE_NAMES.RECOVERY_OUTCOME, 'no-answer', { customerId: 'NOPE', actor: 'Rahul' });
  });

  it('escalation: manual rejects missing level', async () => {
    await expectRejects(QUEUE_NAMES.ESCALATION, 'manual', { customerId: 'C001' });
  });
  it('escalation: resolve rejects missing escalationCaseId', async () => {
    await expectRejects(QUEUE_NAMES.ESCALATION, 'resolve', { resolutionNote: 'x' });
  });
  it('escalation: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.ESCALATION, 'not-real', { customerId: 'C001' });
  });

  it('payment-claim: verify rejects a non-boolean success', async () => {
    await expectRejects(QUEUE_NAMES.PAYMENT_CLAIM, 'verify', { claimId: 'PC_X', success: 'yes' });
  });
  it('payment-claim: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.PAYMENT_CLAIM, 'not-real', {});
  });

  it('dispute: approve rejects missing deadline', async () => {
    await expectRejects(QUEUE_NAMES.DISPUTE, 'approve', { disputeId: 'DSP_X', resolutionOwner: 'Amit' });
  });
  it('dispute: request-info rejects missing salesmanId', async () => {
    await expectRejects(QUEUE_NAMES.DISPUTE, 'request-info', { disputeId: 'DSP_X', deadline: new Date().toISOString() });
  });
  it('dispute: move-to-resolution rejects a dispute not yet Approved', async () => {
    const { createDispute } = await import('../src/store/repository.js');
    const dispute = createDispute({ customerId: 'C001', customer: 'Sharma Hardware Traders', amount: 1000, reason: 'x' });
    await expectRejects(QUEUE_NAMES.DISPUTE, 'move-to-resolution', { disputeId: dispute.id });
  });
  it('dispute: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.DISPUTE, 'not-real', {});
  });

  it('task: complete rejects an unknown taskId', async () => {
    await expectRejects(QUEUE_NAMES.TASK, 'complete', { taskId: 'NOPE' });
  });
  it('task: reassign rejects missing newOwnerId', async () => {
    const { createTask } = await import('../src/store/repository.js');
    const task = createTask({ type: 'customerCall', customerId: 'C001', ownerId: 'Rahul', deadline: new Date().toISOString(), priority: 'Normal', reason: 'x' });
    await expectRejects(QUEUE_NAMES.TASK, 'reassign', { taskId: task.id });
  });
  it('task: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.TASK, 'not-real', {});
  });

  it('management-instruction: rejects missing description', async () => {
    await expectRejects(QUEUE_NAMES.MANAGEMENT_INSTRUCTION, 'assign', { customerId: 'C001', salesmanId: 'Rahul', deadline: new Date().toISOString() });
  });
  it('management-instruction: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.MANAGEMENT_INSTRUCTION, 'not-real', {});
  });

  it('customer-reassignment: rejects an unknown toSalesmanId', async () => {
    await expectRejects(QUEUE_NAMES.CUSTOMER_REASSIGNMENT, 'reassign', { customerId: 'C001', fromSalesmanId: 'Rahul', toSalesmanId: 'NOPE' });
  });
  it('customer-reassignment: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.CUSTOMER_REASSIGNMENT, 'not-real', {});
  });

  it('correction-request: request rejects an invalid correctionType', async () => {
    await expectRejects(QUEUE_NAMES.CORRECTION_REQUEST, 'request', { correctionType: 'bogus', customerId: 'C001' });
  });
  it('correction-request: ptp correction rejects an unknown ptpId', async () => {
    await expectRejects(QUEUE_NAMES.CORRECTION_REQUEST, 'request', { correctionType: 'ptp', customerId: 'C001', ptpId: 'NOPE', requestedAmount: 1, requestedDate: new Date().toISOString() });
  });
  it('correction-request: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.CORRECTION_REQUEST, 'not-real', {});
  });

  it('five-pm-control: rejects an unknown job name', async () => {
    await expectRejects(QUEUE_NAMES.FIVE_PM_CONTROL, 'not-real', {});
  });
});
