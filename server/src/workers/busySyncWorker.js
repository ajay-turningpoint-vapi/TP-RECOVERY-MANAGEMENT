const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const logger = require('../config/logger');
const { QUEUE_NAME } = require('../queues/busySyncQueue');
const { runCustomerAgeingSync } = require('../busySync/sync/customerAgeingSync');
const { runCustomerInvoiceSync } = require('../busySync/sync/customerInvoiceSync');
const { verifyDuePtps } = require('../services/ptpVerificationService');
const notificationRepository = require('../repositories/notificationRepository');
const syncLockService = require('../services/syncLockService');

function createBusySyncWorker() {
  const worker = new Worker(
    QUEUE_NAME,
    async () => {
      // Set for the full job (ageing sync + invoice sync + PTP
      // verification), not just the two steps sync_runs already tracks
      // individually — see syncLockService's doc comment. Every active
      // client polls this (GET /api/sync-status) and shows a full-screen
      // "syncing, please wait" overlay for as long as it's set, since real
      // customer/PTP/task data is being rewritten underneath them.
      await syncLockService.beginSync();
      try {
        const resultAgeing = await runCustomerAgeingSync();
        if (resultAgeing.ran) {
          logger.info(`[busySyncWorker] customerAgeingSync completed. Run ID: ${resultAgeing.runId}`);
        } else {
          logger.info(`[busySyncWorker] customerAgeingSync skipped (already in progress).`);
        }

        const resultInvoice = await runCustomerInvoiceSync();
        if (resultInvoice.ran) {
          logger.info(`[busySyncWorker] customerInvoiceSync completed. Run ID: ${resultInvoice.runId}`);
        } else {
          logger.info(`[busySyncWorker] customerInvoiceSync skipped (already in progress).`);
        }

        // PTP verification against real BUSY receipts (see
        // services/ptpVerificationService.js) — has no dependency on the two
        // syncs above succeeding, so it always runs as the third daily-sync step.
        const resultVerification = await verifyDuePtps();
        logger.info(`[busySyncWorker] ptpVerification completed.`, resultVerification);

        return { resultAgeing, resultInvoice, resultVerification };
      } finally {
        // Cleared on success AND failure — a failed sync must never leave
        // the whole app frozen indefinitely for every user.
        await syncLockService.endSync();
      }
    },
    { connection, prefix: env.redis.prefix, concurrency: 1 }
  );

  worker.on('failed', (job, err) => {
    logger.error('BUSY customer sync job failed', { jobId: job?.id, message: err.message });

    // BullMQ fires 'failed' on every attempt, not just the last one —
    // alerting here unconditionally would raise a false alarm for a
    // transient error the retry (attempts: 2) goes on to fix by itself.
    // Only once every attempt is exhausted does this become something a
    // real person needs to act on — real customer data is now stale until
    // someone intervenes, which previously had zero user-facing signal
    // (only a server log line and a sync_runs row nobody proactively
    // checks).
    const attemptsMade = job?.attemptsMade ?? 0;
    const maxAttempts = job?.opts?.attempts ?? 1;
    if (job && attemptsMade >= maxAttempts) {
      notificationRepository
        .insert({
          severity: 'critical',
          title: 'BUSY sync failed — customer data may be stale',
          body: `The daily BUSY customer sync failed after ${attemptsMade} attempt(s): ${err.message}. Real customer balances/ageing will not reflect BUSY until this is resolved and a sync succeeds.`,
        })
        .catch((notifyErr) => {
          logger.error('Failed to record BUSY sync failure notification', { message: notifyErr.message });
        });
    }
  });

  return worker;
}

module.exports = { createBusySyncWorker };
