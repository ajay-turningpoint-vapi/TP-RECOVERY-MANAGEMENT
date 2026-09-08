import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createCorrectionRequestWorker } from '../src/workers/correction-request.worker.js';
import { createPtp, getPtp, getCustomer, auditHistoryForCustomer } from '../src/store/repository.js';

let worker;

beforeAll(async () => {
  await fullReset();
  worker = createCorrectionRequestWorker();
});

afterAll(async () => {
  await worker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
});

describe('Correction requests (generic: PTP + outcome)', () => {
  it('PTP correction: request then approve overwrites amount/date and preserves the original in the audit description', async () => {
    const ptp = createPtp({ customerId: 'C001', amountPromised: 50000, promiseDate: new Date().toISOString(), paymentMode: 'Cash' });
    const queue = getQueue(QUEUE_NAMES.CORRECTION_REQUEST);
    const { correctionRequestId } = await addAndWait(queue, 'request', {
      correctionType: 'ptp',
      customerId: 'C001',
      ptpId: ptp.id,
      requestedAmount: 60000,
      requestedDate: new Date(Date.now() + 86400000).toISOString(),
      reason: 'Customer confirmed a higher amount',
      actor: 'Rahul',
    });
    expect(getPtp(ptp.id).correctionStatus).toBe('Pending');

    await addAndWait(queue, 'approve', { correctionRequestId, actor: 'Amit' });
    const updated = getPtp(ptp.id);
    expect(updated.amountPromised).toBe(60000);
    expect(updated.correctionStatus).toBe('Approved');

    const audit = auditHistoryForCustomer('C001');
    const event = audit.find((e) => e.type === 'RE_APPROVED_PTP_CORRECTION');
    expect(event.previousState).toContain('50000');
    expect(event.newState).toContain('60000');
  });

  it('PTP correction: reject leaves the PTP fields unchanged', async () => {
    const ptp = createPtp({ customerId: 'C001', amountPromised: 50000, promiseDate: new Date().toISOString(), paymentMode: 'Cash' });
    const queue = getQueue(QUEUE_NAMES.CORRECTION_REQUEST);
    const { correctionRequestId } = await addAndWait(queue, 'request', {
      correctionType: 'ptp',
      customerId: 'C001',
      ptpId: ptp.id,
      requestedAmount: 99999,
      requestedDate: new Date().toISOString(),
      actor: 'Rahul',
    });
    await addAndWait(queue, 'reject', { correctionRequestId, reason: 'No evidence', actor: 'Amit' });
    expect(getPtp(ptp.id).amountPromised).toBe(50000);
    expect(getPtp(ptp.id).correctionStatus).toBe('Rejected');
  });

  it('outcome correction: approve overwrites the customer\'s recorded outcome', async () => {
    const queue = getQueue(QUEUE_NAMES.CORRECTION_REQUEST);
    const { correctionRequestId } = await addAndWait(queue, 'request', {
      correctionType: 'outcome',
      customerId: 'C002',
      originalOutcome: 'No Answer',
      originalReason: 'No Answer',
      requestedOutcome: 'Follow-up',
      requestedReason: 'Actually spoke, will confirm later',
      note: 'Logged wrong outcome by mistake',
      actor: 'Mahesh',
    });
    await addAndWait(queue, 'approve', { correctionRequestId, actor: 'Amit' });
    expect(getCustomer('C002').primaryNextAction).toBe('Follow-up');
    expect(getCustomer('C002').reasonForAction).toBe('Actually spoke, will confirm later');
  });

  it('approving an already-decided request is a safe no-op, not a double-apply', async () => {
    const ptp = createPtp({ customerId: 'C001', amountPromised: 50000, promiseDate: new Date().toISOString(), paymentMode: 'Cash' });
    const queue = getQueue(QUEUE_NAMES.CORRECTION_REQUEST);
    const { correctionRequestId } = await addAndWait(queue, 'request', { correctionType: 'ptp', customerId: 'C001', ptpId: ptp.id, requestedAmount: 70000, requestedDate: new Date().toISOString() });
    await addAndWait(queue, 'approve', { correctionRequestId, actor: 'Amit' });
    const second = await addAndWait(queue, 'approve', { correctionRequestId, actor: 'Amit' });
    expect(second.skipped).toBe(true);
    expect(getPtp(ptp.id).amountPromised).toBe(70000); // unchanged by the second call
  });
});
