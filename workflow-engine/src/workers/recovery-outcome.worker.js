import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processRecoveryOutcome } from '../processors/recovery-outcome.processor.js';

export function createRecoveryOutcomeWorker(options = {}) {
  return createDomainWorker(QUEUE_NAMES.RECOVERY_OUTCOME, (job) => processRecoveryOutcome(job), { concurrency: 10, ...options });
}
