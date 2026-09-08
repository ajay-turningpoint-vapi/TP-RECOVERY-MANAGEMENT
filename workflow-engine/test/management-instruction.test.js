import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents, queueEventsFor } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createManagementInstructionWorker } from '../src/workers/management-instruction.worker.js';
import { getTask, auditHistoryForCustomer } from '../src/store/repository.js';

let worker;

beforeAll(async () => {
  await fullReset();
  worker = createManagementInstructionWorker();
});

afterAll(async () => {
  await worker.close();
  await closeAllQueueEvents();
  await teardownQueues();
});

beforeEach(async () => {
  await fullReset();
});

describe('Management Instruction', () => {
  it('issues a real, critical task to the named salesperson', async () => {
    const queue = getQueue(QUEUE_NAMES.MANAGEMENT_INSTRUCTION);
    const result = await addAndWait(queue, 'assign', {
      customerId: 'C004',
      salesmanId: 'Mahesh',
      description: 'Personally visit this customer within 24 hours',
      deadline: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      actor: 'Suresh',
    });
    const task = getTask(result.taskId);
    expect(task.type).toBe('managementInstruction');
    expect(task.ownerId).toBe('Mahesh');
    expect(task.priority).toBe('Critical');

    const audit = auditHistoryForCustomer('C004');
    expect(audit.some((e) => e.type === 'RE_CREATED_INSTRUCTION')).toBe(true);
  });

  it('rejects a malformed job (missing required fields) rather than silently creating a broken task', async () => {
    const queue = getQueue(QUEUE_NAMES.MANAGEMENT_INSTRUCTION);
    const qe = queueEventsFor(QUEUE_NAMES.MANAGEMENT_INSTRUCTION);
    await qe.waitUntilReady();
    const job = await queue.add('assign', { customerId: 'C001' }, { attempts: 1 });
    await expect(job.waitUntilFinished(qe)).rejects.toThrow();
  });
});
