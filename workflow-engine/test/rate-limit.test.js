import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createPaymentClaimWorker } from '../src/workers/payment-claim.worker.js';
import { BusyClient } from '../src/simulators/busy-client.js';
import { createPaymentClaim } from '../src/store/repository.js';
import { closeAllQueueEvents, queueEventsFor } from './helpers.js';

let worker;

beforeEach(async () => {
  await fullReset();
});

afterEach(async () => {
  if (worker) await worker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Rate limiting', () => {
  it('throttles verification throughput to the configured limiter (simulating a rate-limited BUSY API)', async () => {
    // 3 jobs per 300ms window — a burst of 9 jobs must take at least 2 full
    // extra windows (~600ms) to drain, proving the limiter genuinely
    // throttles rather than just being configured and ignored.
    worker = createPaymentClaimWorker({ busyClient: new BusyClient({ healthy: true }) }, { limiter: { max: 3, duration: 300 } });

    const claims = Array.from({ length: 9 }, (_, i) => createPaymentClaim({ customerId: 'C001', customer: 'Sharma Hardware Traders', amount: 1000 * (i + 1), date: '2026-08-24', reference: `ref-${i}` }));

    const queue = getQueue(QUEUE_NAMES.PAYMENT_CLAIM);
    // Warm the QueueEvents subscription BEFORE adding any job — without a
    // limiter these jobs can complete in well under a millisecond, faster
    // than a lazily-created subscription can attach, which permanently
    // misses the "completed" pub/sub message and hangs waitUntilFinished
    // forever (found for real via this exact test, intermittently).
    const qe = queueEventsFor(QUEUE_NAMES.PAYMENT_CLAIM);
    await qe.waitUntilReady();
    const start = Date.now();
    const jobs = await Promise.all(claims.map((c) => queue.add('verify', { claimId: c.id, success: true, actor: 'Amit' })));
    await Promise.all(jobs.map((j) => j.waitUntilFinished(qe, 20000)));
    const elapsed = Date.now() - start;

    // 9 jobs at 3-per-300ms => at least 2 waiting windows after the first
    // batch of 3, i.e. >= ~600ms. Allow slack for scheduling jitter.
    expect(elapsed).toBeGreaterThanOrEqual(500);
  }, 25000);

  it('without a limiter, the same burst completes far faster (control case proving the limiter is what caused the throttling above)', async () => {
    worker = createPaymentClaimWorker({ busyClient: new BusyClient({ healthy: true }) }, { limiter: undefined });

    const claims = Array.from({ length: 9 }, (_, i) => createPaymentClaim({ customerId: 'C001', customer: 'Sharma Hardware Traders', amount: 1000 * (i + 1), date: '2026-08-24', reference: `ref-${i}` }));

    const queue = getQueue(QUEUE_NAMES.PAYMENT_CLAIM);
    // Warm the QueueEvents subscription BEFORE adding any job — without a
    // limiter these jobs can complete in well under a millisecond, faster
    // than a lazily-created subscription can attach, which permanently
    // misses the "completed" pub/sub message and hangs waitUntilFinished
    // forever (found for real via this exact test, intermittently).
    const qe = queueEventsFor(QUEUE_NAMES.PAYMENT_CLAIM);
    await qe.waitUntilReady();
    const start = Date.now();
    const jobs = await Promise.all(claims.map((c) => queue.add('verify', { claimId: c.id, success: true, actor: 'Amit' })));
    await Promise.all(jobs.map((j) => j.waitUntilFinished(qe, 20000)));
    const elapsed = Date.now() - start;

    expect(elapsed).toBeLessThan(500);
  }, 25000);
});
