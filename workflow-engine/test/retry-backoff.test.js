import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createBusySyncWorker } from '../src/workers/busy-sync.worker.js';
import { BusyClient } from '../src/simulators/busy-client.js';
import { queueEventsFor, closeAllQueueEvents } from './helpers.js';
import { createPtp } from '../src/store/repository.js';

let worker;

beforeEach(async () => {
  await fullReset();
});

afterEach(async () => {
  if (worker) await worker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Retry + exponential backoff', () => {
  it('a transiently-failing BUSY call is retried and eventually succeeds within the configured attempts', async () => {
    createPtp({ customerId: 'C001', amountPromised: 30000, promiseDate: new Date(Date.now() - 60000).toISOString(), paymentMode: 'Cash' });

    // Fails the first 2 calls, succeeds on the 3rd — well within the
    // queue's default attempts: 5.
    let callCount = 0;
    const flakyClient = {
      async reconcilePtp(ptp) {
        callCount += 1;
        if (callCount < 3) {
          const err = new Error('simulated transient BUSY failure');
          err.transient = true;
          throw err;
        }
        return new BusyClient().reconcilePtp(ptp);
      },
    };
    worker = createBusySyncWorker({ busyClient: flakyClient });

    const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
    const qe1 = queueEventsFor(QUEUE_NAMES.BUSY_SYNC);
    await qe1.waitUntilReady();
    const tick = await busySyncQueue.add('tick', {}, { backoff: { type: 'exponential', delay: 50 } });
    const result = await tick.waitUntilFinished(qe1, 15000);
    expect(result.matured).toBe(1);
    expect(callCount).toBe(3); // failed twice, succeeded on the 3rd real attempt
  }, 20000);

  it('a job that fails every attempt is marked failed after exhausting the configured attempt count, not retried forever', async () => {
    const alwaysFailingClient = {
      async reconcilePtp() {
        const err = new Error('BUSY is permanently down in this test');
        err.transient = true;
        throw err;
      },
    };
    worker = createBusySyncWorker({ busyClient: alwaysFailingClient });
    createPtp({ customerId: 'C002', amountPromised: 30000, promiseDate: new Date(Date.now() - 60000).toISOString(), paymentMode: 'Cash' });

    const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
    const qe2 = queueEventsFor(QUEUE_NAMES.BUSY_SYNC);
    await qe2.waitUntilReady();
    const tick = await busySyncQueue.add('tick', {}, { attempts: 3, backoff: { type: 'exponential', delay: 30 } });
    await expect(tick.waitUntilFinished(qe2, 15000)).rejects.toThrow();

    const finalState = await tick.getState();
    expect(finalState).toBe('failed');
    const refreshed = await busySyncQueue.getJob(tick.id);
    expect(refreshed.attemptsMade).toBe(3);
  }, 20000);
});
