const logger = require('../config/logger');
const { runCustomerAgeingSync } = require('../busySync/sync/customerAgeingSync');
const { runCustomerInvoiceSync } = require('../busySync/sync/customerInvoiceSync');
const recoveryReconcileService = require('./recoveryReconcileService');
const syncLockService = require('./syncLockService');
const { emitChange } = require('../realtime/eventBus');

/**
 * THE BUSY sync — one pipeline for every way a sync is started: the daily
 * 12:00 job (workers/busySyncWorker.js), the Admin app's "Sync" button
 * (routes/busySyncAdminRoutes.js) and the CLI (busySync/runSyncNow.js). The
 * Admin button used to run only the customer step, so the reconcile sweep,
 * the Record Outcome rule self-check and the trend metrics were skipped
 * after a manual sync (28 Oct). Same steps, same order, every time:
 *
 *  1. customer ageing sync — per branch; includes the removed-from-BUSY
 *     cleanup and the PTP re-check (early payment counts, one payment
 *     counts once — ptpVerificationService.reverifyStalePtps)
 *  2. invoice sync
 *  3. recoveryReconcileService.reconcileAll — recovery tasks re-pointed,
 *     stuck-parked fix, enforceOutcomeRules (7 Record Outcome rules,
 *     removed-customer leftovers)
 *  4. daily trend metrics
 *
 * `branchLabel` narrows step 1 to one branch (the Admin per-branch button);
 * steps 2–4 are company-wide.
 */
async function runFullBusySync({ branchLabel, logPrefix = '[busySync]' } = {}) {
  // Every client shows the "syncing, please wait" overlay while this is set
  // (GET /api/sync-status) — cleared on success AND failure.
  await syncLockService.beginSync();
  try {
    const resultAgeing = await runCustomerAgeingSync(branchLabel);
    if (resultAgeing.ran) {
      logger.info(`${logPrefix} customerAgeingSync completed. Run IDs: ${(resultAgeing.runIds || []).join(', ')}`);
    } else {
      logger.info(`${logPrefix} customerAgeingSync skipped (already in progress).`);
    }

    const resultInvoice = await runCustomerInvoiceSync();
    if (resultInvoice.ran) {
      logger.info(`${logPrefix} customerInvoiceSync completed. Run IDs: ${(resultInvoice.runIds || []).join(', ')}`);
    } else {
      logger.info(`${logPrefix} customerInvoiceSync skipped (already in progress).`);
    }

    // PTP promote + first verification is its own 12:10 IST job
    // (queues/ptpVerifyQueue.js), not part of the sync.

    try {
      const resultReconcile = await recoveryReconcileService.reconcileAll();
      logger.info(`${logPrefix} recovery reconcile sweep completed.`, resultReconcile);
    } catch (reconcileErr) {
      logger.error(`${logPrefix} recovery reconcile sweep failed`, { message: reconcileErr.message });
    }

    // Metrics only — touches no tasks or customer state.
    try {
      const { recordDailyMetrics } = require('../workers/snapshotWorker');
      await recordDailyMetrics(await require('../repositories/customerRepository').findAll());
      logger.info(`${logPrefix} daily trend metrics recorded.`);
    } catch (metricsErr) {
      logger.error(`${logPrefix} daily trend metrics failed`, { message: metricsErr.message });
    }

    // A sync rewrites customers, the salesman roster, PTPs and invoices
    // wholesale — every client pulls fresh lists once the freeze lifts.
    emitChange(['customers', 'ptps', 'tasks', 'salesmen', 'escalations'], { reason: 'busy.sync' });
    return { resultAgeing, resultInvoice };
  } finally {
    await syncLockService.endSync();
  }
}

/** True while any sync (daily job or manual) holds the app-wide sync lock. */
async function isSyncRunning() {
  return !!(await syncLockService.syncingSince());
}

module.exports = { runFullBusySync, isSyncRunning };
