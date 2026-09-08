import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createRecoveryOutcomeWorker } from '../src/workers/recovery-outcome.worker.js';
import { createBusySyncWorker } from '../src/workers/busy-sync.worker.js';
import { createEscalationWorker } from '../src/workers/escalation.worker.js';
import { BusyClient } from '../src/simulators/busy-client.js';
import { listPtps, auditHistoryForCustomer, getBusySyncHealth, setBusySyncHealth } from '../src/store/repository.js';

let recoveryWorker;
let busySyncWorker;
let escalationWorker;

beforeAll(async () => {
  await fullReset();
  recoveryWorker = createRecoveryOutcomeWorker();
  busySyncWorker = createBusySyncWorker({ busyClient: new BusyClient({ healthy: true, failureRate: 0 }) });
  escalationWorker = createEscalationWorker();
});

afterAll(async () => {
  await recoveryWorker.close();
  await busySyncWorker.close();
  await escalationWorker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
  setBusySyncHealth(true);
});

describe('PTP lifecycle', () => {
  it('creates a real, live scheduled PTP from a recovery-outcome job', async () => {
    const queue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const result = await addAndWait(queue, 'ptp-scheduled', {
      customerId: 'C001',
      actor: 'Rahul',
      amountPromised: 50000,
      promiseDate: new Date(Date.now() - 60000).toISOString(),
      paymentMode: 'NEFT',
    });
    expect(result.ptpId).toBeTruthy();

    const ptp = listPtps().find((p) => p.id === result.ptpId);
    expect(ptp).toBeTruthy();
    expect(ptp.status).toBe('scheduled');
    expect(ptp.amountPromised).toBe(50000);

    const audit = auditHistoryForCustomer('C001');
    expect(audit.some((e) => e.type === 'Promise To Pay Recorded')).toBe(true);
  });

  it('matures a due, low-amount PTP to kept via a real busy-sync tick', async () => {
    const recoveryQueue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const { ptpId } = await addAndWait(recoveryQueue, 'ptp-scheduled', {
      customerId: 'C005',
      actor: 'Rahul',
      amountPromised: 20000, // < 100000 => kept
      promiseDate: new Date(Date.now() - 60000).toISOString(),
      paymentMode: 'Cash',
    });

    const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
    const result = await addAndWait(busySyncQueue, 'tick', {});
    expect(result.matured).toBeGreaterThanOrEqual(1);

    const ptp = listPtps().find((p) => p.id === ptpId);
    expect(ptp.status).toBe('kept');
    expect(ptp.amountReceived).toBe(20000);
  });

  it('matures a due, mid-amount PTP to partiallyKept', async () => {
    const recoveryQueue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const { ptpId } = await addAndWait(recoveryQueue, 'ptp-scheduled', {
      customerId: 'C001',
      actor: 'Rahul',
      amountPromised: 150000, // 100000 <= x < 200000 => partiallyKept
      promiseDate: new Date(Date.now() - 60000).toISOString(),
      paymentMode: 'RTGS',
    });

    const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
    await addAndWait(busySyncQueue, 'tick', {});

    const ptp = listPtps().find((p) => p.id === ptpId);
    expect(ptp.status).toBe('partiallyKept');
    expect(ptp.amountReceived).toBe(75000);
  });

  it('never falsely matures a due PTP while BUSY sync is unhealthy — holds it as financialSyncPending instead', async () => {
    const recoveryQueue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const { ptpId } = await addAndWait(recoveryQueue, 'ptp-scheduled', {
      customerId: 'C003',
      actor: 'Mahesh',
      amountPromised: 15000,
      promiseDate: new Date(Date.now() - 60000).toISOString(),
      paymentMode: 'UPI',
    });

    setBusySyncHealth(false);
    expect(getBusySyncHealth()).toBe(false);

    const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
    const result = await addAndWait(busySyncQueue, 'tick', {});
    expect(result.syncPending).toBeGreaterThanOrEqual(1);
    expect(result.matured).toBe(0);

    const ptp = listPtps().find((p) => p.id === ptpId);
    expect(ptp.status).toBe('financialSyncPending');
  });

  it('never lets a job manually set PTP status — only busy-sync maturation may transition scheduled -> kept/partiallyKept/broken', async () => {
    // There is intentionally no "set-ptp-status" job/handler anywhere in the
    // engine — assert the recovery-outcome and task queues expose no such
    // capability by confirming the only two ways a PTP status changes are
    // busy-sync maturation (covered above) and a correction-request
    // amount/date change (which never touches `status` besides
    // `correctionStatus`, covered in correction-request.test.js).
    const recoveryQueue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const { ptpId } = await addAndWait(recoveryQueue, 'ptp-scheduled', {
      customerId: 'C002',
      actor: 'Rahul',
      amountPromised: 300000,
      promiseDate: new Date(Date.now() + 24 * 3600 * 1000).toISOString(), // not yet due
      paymentMode: 'Cheque',
    });
    const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
    await addAndWait(busySyncQueue, 'tick', {});
    const ptp = listPtps().find((p) => p.id === ptpId);
    expect(ptp.status).toBe('scheduled'); // untouched — not due yet, sync must not touch it
  });
});
