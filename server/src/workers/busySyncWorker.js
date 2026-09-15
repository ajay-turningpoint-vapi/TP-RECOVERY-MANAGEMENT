const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const logger = require('../config/logger');
const { QUEUE_NAME } = require('../queues/busySyncQueue');
const { runCustomerAgeingSync } = require('../busySync/sync/customerAgeingSync');
const { runCustomerInvoiceSync } = require('../busySync/sync/customerInvoiceSync');
const recoveryReconcileService = require('../services/recoveryReconcileService');
const notificationRepository = require('../repositories/notificationRepository');
const syncLockService = require('../services/syncLockService');
const { beat } = require('../services/heartbeatService');
const { publish, emitChange } = require('../realtime/eventBus');

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
          logger.info(`[busySyncWorker] customerAgeingSync completed. Run IDs: ${(resultAgeing.runIds || []).join(', ')}`);
        } else {
          logger.info(`[busySyncWorker] customerAgeingSync skipped (already in progress).`);
        }

        const resultInvoice = await runCustomerInvoiceSync();
        if (resultInvoice.ran) {
          logger.info(`[busySyncWorker] customerInvoiceSync completed. Run IDs: ${(resultInvoice.runIds || []).join(', ')}`);
        } else {
          logger.info(`[busySyncWorker] customerInvoiceSync skipped (already in progress).`);
        }

        // PTP promote + verify now runs as its own scheduled job at 12:10
        // IST (queues/ptpVerifyQueue.js) — a few minutes after this sync so
        // customer balances are fresh, with its own 5-min exponential
        // backoff / retry. It is NOT run here any more.

        // Backstop: with fresh balances, re-point
        // every salesperson's recovery task at the still-uncovered slice of
        // their customer's overdue (and un-park anyone the RE never got to).
        try {
          const resultReconcile = await recoveryReconcileService.reconcileAll();
          logger.info('[busySyncWorker] recovery reconcile sweep completed.', resultReconcile);
        } catch (reconcileErr) {
          logger.error('[busySyncWorker] recovery reconcile sweep failed', { message: reconcileErr.message });
        }

        // A sync rewrites customers, the salesman roster, PTPs and
        // invoices wholesale — every client should pull fresh lists once
        // the freeze lifts.
        emitChange(['customers', 'ptps', 'tasks', 'salesmen', 'escalations'], { reason: 'busy.sync' });

        await beat('busy-sync');
        return { resultAgeing, resultInvoice };
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
          body: `The BUSY customer sync failed after ${attemptsMade} automatic attempt(s): ${err.message}. Customer balances/ageing will not reflect BUSY until the connection is back and a sync succeeds; the next scheduled run is 12:00 IST.`,
        })
        .then(() => publish({ type: 'notification', scope: { broadcast: true } }))
        .catch((notifyErr) => {
          logger.error('Failed to record BUSY sync failure notification', { message: notifyErr.message });
        });
    }
  });

  return worker;
}

module.exports = { createBusySyncWorker };
