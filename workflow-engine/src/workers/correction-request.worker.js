import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processCorrectionRequest } from '../processors/correction-request.processor.js';

export function createCorrectionRequestWorker(options = {}) {
  return createDomainWorker(QUEUE_NAMES.CORRECTION_REQUEST, (job) => processCorrectionRequest(job), { concurrency: 5, ...options });
}
