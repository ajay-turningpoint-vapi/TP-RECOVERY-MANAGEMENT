import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processDispute } from '../processors/dispute.processor.js';

export function createDisputeWorker(options = {}) {
  return createDomainWorker(QUEUE_NAMES.DISPUTE, (job) => processDispute(job), { concurrency: 5, ...options });
}
