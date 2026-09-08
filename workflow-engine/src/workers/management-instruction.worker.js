import { createDomainWorker } from './create-worker.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { processManagementInstruction } from '../processors/management-instruction.processor.js';

export function createManagementInstructionWorker(options = {}) {
  return createDomainWorker(QUEUE_NAMES.MANAGEMENT_INSTRUCTION, (job) => processManagementInstruction(job), { concurrency: 5, ...options });
}
