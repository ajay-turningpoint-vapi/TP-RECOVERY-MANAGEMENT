import { logger } from './logger.js';
import { closeAllQueues } from './queues/index.js';
import { registerRepeatables } from './schedulers/register-repeatables.js';
import { closeBusySyncProcessorResources } from './processors/busy-sync.processor.js';
import { flushPendingDeadLetters } from './events/dead-letter-listener.js';

import { createRecoveryOutcomeWorker } from './workers/recovery-outcome.worker.js';
import { createBusySyncWorker } from './workers/busy-sync.worker.js';
import { createEscalationWorker } from './workers/escalation.worker.js';
import { createPaymentClaimWorker } from './workers/payment-claim.worker.js';
import { createDisputeWorker } from './workers/dispute.worker.js';
import { createTaskWorker } from './workers/task.worker.js';
import { createManagementInstructionWorker } from './workers/management-instruction.worker.js';
import { createCustomerReassignmentWorker } from './workers/customer-reassignment.worker.js';
import { createCorrectionRequestWorker } from './workers/correction-request.worker.js';
import { createFivePmControlWorker } from './workers/five-pm-control.worker.js';

/** Boots every worker + the two repeatable schedulers. Returns a handle
 * whose `shutdown()` gracefully closes everything — waiting for in-flight
 * jobs to finish rather than abandoning them, per BullMQ's documented
 * graceful-shutdown contract. */
export async function startApp() {
  const workers = [
    createRecoveryOutcomeWorker(),
    createBusySyncWorker(),
    createEscalationWorker(),
    createPaymentClaimWorker(),
    createDisputeWorker(),
    createTaskWorker(),
    createManagementInstructionWorker(),
    createCustomerReassignmentWorker(),
    createCorrectionRequestWorker(),
    createFivePmControlWorker(),
  ];

  await registerRepeatables();
  logger.info({ workerCount: workers.length }, 'TP-RMS workflow engine started');

  let shuttingDown = false;
  async function shutdown(signal) {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info({ signal }, 'Shutting down — waiting for in-flight jobs to finish');
    await Promise.all(workers.map((w) => w.close()));
    await flushPendingDeadLetters();
    await closeBusySyncProcessorResources();
    await closeAllQueues();
    logger.info('Shutdown complete');
  }

  return { workers, shutdown };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { shutdown } = await startApp();
  process.on('SIGTERM', () => shutdown('SIGTERM').then(() => process.exit(0)));
  process.on('SIGINT', () => shutdown('SIGINT').then(() => process.exit(0)));
}
