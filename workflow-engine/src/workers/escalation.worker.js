import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processEscalation } from '../processors/escalation.processor.js';

export function createEscalationWorker(options = {}) {
  return createDomainWorker(QUEUE_NAMES.ESCALATION, (job) => processEscalation(job), { concurrency: 5, ...options });
}
