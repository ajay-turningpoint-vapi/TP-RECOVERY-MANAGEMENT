import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createRecoveryOutcomeWorker } from '../src/workers/recovery-outcome.worker.js';
import { createBusySyncWorker } from '../src/workers/busy-sync.worker.js';
import { createEscalationWorker } from '../src/workers/escalation.worker.js';
import { BusyClient } from '../src/simulators/busy-client.js';
import { getCustomer, listPtps, updatePtp, openEscalationCaseForCustomer, createPtp } from '../src/store/repository.js';

let recoveryWorker;
let busySyncWorker;
let escalationWorker;

async function createAndBreakPtp(customerId, count) {
  const recoveryQueue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
  for (let i = 0; i < count; i += 1) {
    const { ptpId } = await addAndWait(recoveryQueue, 'ptp-scheduled', {
      customerId,
      actor: 'Rahul',
      amountPromised: 250000, // >= 200000 => broken on maturation
      promiseDate: new Date(Date.now() - 60000).toISOString(),
      paymentMode: 'NEFT',
    });
    // Mature it directly rather than via a fresh busy-sync tick each time,
    // so we control exactly how many broken PTPs exist before evaluating.
    await updatePtp(ptpId, () => ({ status: 'broken', amountReceived: 0, brokenReason: 'test' }));
  }
}

beforeAll(async () => {
  await fullReset();
  recoveryWorker = createRecoveryOutcomeWorker();
  busySyncWorker = createBusySyncWorker({ busyClient: new BusyClient({ healthy: true }) });
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
});

describe('Escalation ladder', () => {
  it('does not escalate on a single broken PTP', async () => {
    await createAndBreakPtp('C001', 1);
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    const result = await addAndWait(escalationQueue, 'evaluate', { customerId: 'C001' });
    expect(result.skipped).toBe(true);
    expect(getCustomer('C001').escalationLevel).toBe('none');
  });

  it('escalates to L2 on the 2nd broken PTP', async () => {
    await createAndBreakPtp('C001', 2);
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    const result = await addAndWait(escalationQueue, 'evaluate', { customerId: 'C001' });
    expect(result.skipped).toBe(false);
    expect(result.targetLevel).toBe('L2');
    expect(getCustomer('C001').escalationLevel).toBe('L2');
    const openCase = openEscalationCaseForCustomer('C001');
    expect(openCase).toBeTruthy();
    expect(openCase.moneyAtRisk).toBe(getCustomer('C001').totalDue);
  });

  it('escalates to L3 on the 3rd broken PTP', async () => {
    await createAndBreakPtp('C001', 3);
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    const result = await addAndWait(escalationQueue, 'evaluate', { customerId: 'C001' });
    expect(result.targetLevel).toBe('L3');
    expect(getCustomer('C001').escalationLevel).toBe('L3');
    expect(getCustomer('C001').currentRecoveryState).toBe('RE Control');
  });

  it('never auto-escalates to L4 — that remains a human judgment call', async () => {
    await createAndBreakPtp('C001', 10); // absurdly high broken count
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    const result = await addAndWait(escalationQueue, 'evaluate', { customerId: 'C001' });
    expect(result.targetLevel).not.toBe('L4');
    expect(getCustomer('C001').escalationLevel).not.toBe('L4');
  });

  it('ratchet invariant: never downgrades an existing case, even if re-evaluated with a lower count', async () => {
    await createAndBreakPtp('C001', 3);
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    await addAndWait(escalationQueue, 'evaluate', { customerId: 'C001' });
    expect(getCustomer('C001').escalationLevel).toBe('L3');

    // Manually attempt to move it back down to L2 — must be rejected.
    const manual = await addAndWait(escalationQueue, 'manual', { customerId: 'C001', level: 'L2', reason: 'attempted downgrade', ownerId: 'RE', plan: 'n/a' });
    expect(manual.skipped).toBe(true);
    expect(getCustomer('C001').escalationLevel).toBe('L3');
  });

  it('resolving an escalation case retains the historical escalation level on the customer', async () => {
    await createAndBreakPtp('C001', 2);
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    const { escalationCaseId } = await addAndWait(escalationQueue, 'evaluate', { customerId: 'C001' });
    expect(getCustomer('C001').escalationLevel).toBe('L2');

    await addAndWait(escalationQueue, 'resolve', { escalationCaseId, resolutionNote: 'Customer paid in full' });
    const openCase = openEscalationCaseForCustomer('C001');
    expect(openCase).toBeNull(); // case is closed
    expect(getCustomer('C001').escalationLevel).toBe('L2'); // but level is retained, not reset
  });

  it('regression: a real busy-sync tick that matures 2+ broken PTPs completes without deadlocking, and genuinely escalates via its BullMQ Flow', async () => {
    // busy-sync runs at concurrency:1 and its FlowProducer parent job lives
    // on the escalation queue specifically so this can never self-deadlock
    // (see the comment in busy-sync.processor.js) — this test proves the
    // full real chain end-to-end: busy-sync tick -> Flow parent+children on
    // the escalation queue -> parent completes -> tick job itself resolves.
    createPtp({ customerId: 'C003', amountPromised: 250000, promiseDate: new Date(Date.now() - 60000).toISOString(), paymentMode: 'NEFT' });
    createPtp({ customerId: 'C003', amountPromised: 300000, promiseDate: new Date(Date.now() - 60000).toISOString(), paymentMode: 'RTGS' });

    const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
    const result = await addAndWait(busySyncQueue, 'tick', {}); // must not hang
    expect(result.matured).toBe(2);
    expect(result.escalationChecks).toBe(1);
    expect(getCustomer('C003').escalationLevel).toBe('L2');
  }, 15000);

  it('manual escalation can jump straight to L4 (a human judgment call)', async () => {
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    const result = await addAndWait(escalationQueue, 'manual', {
      customerId: 'C004',
      level: 'L4',
      reason: 'Legal action initiated',
      plan: 'Escalate to management for write-off decision',
      ownerId: 'Suresh',
      actor: 'Amit',
    });
    expect(result.skipped).toBe(false);
    expect(getCustomer('C004').escalationLevel).toBe('L4');
    expect(getCustomer('C004').primaryNextAction).toBe('MANAGEMENT ATTENTION');
  });
});
