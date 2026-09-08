import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processBusySync } from '../processors/busy-sync.processor.js';

// Concurrency 1: overlapping sync runs racing to mature the same PTPs is
// exactly the kind of bug this queue exists to prevent, so only one tick
// is ever in flight at a time.
export function createBusySyncWorker(deps = {}, options = {}) {
  return createDomainWorker(QUEUE_NAMES.BUSY_SYNC, (job) => processBusySync(job, deps), { concurrency: 1, lockDuration: 60000, ...options });
}
