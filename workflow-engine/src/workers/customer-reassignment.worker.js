import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processCustomerReassignment } from '../processors/customer-reassignment.processor.js';

export function createCustomerReassignmentWorker(options = {}) {
  return createDomainWorker(QUEUE_NAMES.CUSTOMER_REASSIGNMENT, (job) => processCustomerReassignment(job), { concurrency: 5, ...options });
}
