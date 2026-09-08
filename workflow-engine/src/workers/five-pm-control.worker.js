import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processFivePmControl } from '../processors/five-pm-control.processor.js';

export function createFivePmControlWorker(options = {}) {
  return createDomainWorker(QUEUE_NAMES.FIVE_PM_CONTROL, (job) => processFivePmControl(job), { concurrency: 1, ...options });
}
