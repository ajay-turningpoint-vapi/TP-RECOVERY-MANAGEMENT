import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processPaymentClaim } from '../processors/payment-claim.processor.js';

// Rate-limited to simulate a throttled external BUSY verification API —
// at most `max` verification calls per `duration` ms across all workers on
// this queue.
export function createPaymentClaimWorker(deps = {}, options = {}) {
  return createDomainWorker(QUEUE_NAMES.PAYMENT_CLAIM, (job) => processPaymentClaim(job, deps), {
    concurrency: 5,
    limiter: options.limiter ?? { max: 10, duration: 1000 },
    ...options,
  });
}
