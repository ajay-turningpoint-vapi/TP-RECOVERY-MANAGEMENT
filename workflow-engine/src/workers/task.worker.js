import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processTask } from '../processors/task.processor.js';

export function createTaskWorker(options = {}) {
  return createDomainWorker(QUEUE_NAMES.TASK, (job) => processTask(job), { concurrency: 10, ...options });
}
