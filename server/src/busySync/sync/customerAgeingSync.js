const logger = require('../../config/logger');
const { withRetry } = require('../utils/retry');
const { pool: mariaDbPool } = require('../../config/db');
const mssqlCustomerReportRepository = require('../reports/mssqlCustomerReportRepository');
const { syncSnapshot } = require('../repositories/customerAgeingRepository');
const { upsertFromBusy } = require('../../repositories/customerRepository');
const { startRun, completeRun } = require('../repositories/syncRunsRepository');
const syncLockService = require('../../services/syncLockService');

// MySQL/MariaDB named lock — atomic, unlike a "check sync_runs then INSERT"
// pattern (proven racy: two callers can both see no 'running' row and both
// proceed before either INSERT lands). GET_LOCK/RELEASE_LOCK are
// connection-scoped and server-side, so this closes the race even across
// separate processes (the BullMQ worker, a manual admin trigger, and any
// future CLI all calling in at once), not just within one Node process.
const LOCK_NAME = 'busy_sync_customer_ageing';

/** @type {{ phase: 'idle'|'connecting'|'fetching'|'writing', runId: number|null, rowsFetched: number|null }} */
let progress = { phase: 'idle', runId: null, rowsFetched: null };

function getSyncProgress() {
  return progress;
}

async function acquireLock() {
  const connection = await mariaDbPool.getConnection();
  const [[lockRow]] = await connection.query('SELECT GET_LOCK(?, 0) AS acquired', [LOCK_NAME]);
  if (lockRow.acquired) {
    return connection;
  }
  connection.release();
  return null;
}

async function releaseLock(connection) {
  try {
    await connection.query('SELECT RELEASE_LOCK(?)', [LOCK_NAME]);
  } catch (err) {
    logger.error(`[busy-sync] Failed to release advisory lock: ${err.message}`);
  } finally {
    connection.release();
  }
}

/**
 * Runs one full customer-ageing sync and resolves only once it's fully
 * done (success or failure) — what the BullMQ worker and any CLI want,
 * since both need the final outcome before deciding what to do next.
 *
 * `ran: false` on the result means a concurrent run held the lock and
 * this call was a no-op.
 */
async function runCustomerAgeingSync() {
  const lockConnection = await acquireLock();
  if (!lockConnection) {
    logger.warn('[busy-sync] customer_ageing sync already in progress — skipping this trigger.');
    return { ran: false };
  }
  try {
    return await runLocked();
  } finally {
    await releaseLock(lockConnection);
  }
}

/**
 * Starts a sync but resolves as soon as the concurrency lock is decided,
 * without waiting for the sync itself to finish — what the admin
 * dashboard's manual-trigger button wants, so the browser gets an
 * immediate response and then polls GET /sync/status (which reads
 * getSyncProgress() below) to render a real progress bar.
 */
async function startCustomerAgeingSyncInBackground() {
  const lockConnection = await acquireLock();
  if (!lockConnection) {
    return { started: false };
  }

  runLocked()
    .catch((err) => {
      logger.error(`[busy-sync] Background run threw: ${err.message}`);
    })
    .finally(() => releaseLock(lockConnection));

  return { started: true };
}

async function runLocked() {
  // Covers this run whether it came from the scheduled worker job (already
  // wrapped once around all three daily-sync steps — see
  // workers/busySyncWorker.js) or the MANAGEMENT admin dashboard's manual
  // trigger (which calls this directly, standalone). Reference-counted, so
  // nesting inside the worker's own wrap is safe — see
  // services/syncLockService.js's doc comment.
  await syncLockService.beginSync();
  try {
    return await runLockedInner();
  } finally {
    await syncLockService.endSync();
  }
}

async function runLockedInner() {
  // MariaDB's DATETIME column truncates fractional seconds, but a plain JS
  // Date carries milliseconds — floor to whole seconds so the value we
  // write to last_synced_at and the value we later compare against in the
  // sweep DELETE are byte-for-byte the same, and freshly-upserted rows are
  // never mistaken for stale ones.
  const startedAt = new Date(Math.floor(Date.now() / 1000) * 1000);
  const runId = await startRun(startedAt);
  logger.info(`[busy-sync] customer_ageing run #${runId} started at ${startedAt.toISOString()}`);
  progress = { phase: 'connecting', runId, rowsFetched: null };

  try {
    progress = { phase: 'fetching', runId, rowsFetched: null };
    const rows = await withRetry('BUSY customer report fetch', () => mssqlCustomerReportRepository.getCustomers());

    progress = { phase: 'writing', runId, rowsFetched: rows.length };
    // Two independent stages: the raw disposable mirror (staging/audit,
    // hard-delete sweep) and the real RMS customers table (soft-deactivate
    // — see customerRepository.upsertFromBusy's doc comment for why).
    // Each is its own transaction; a failure in one doesn't corrupt the
    // other, and both are safely re-run by the next sync attempt either way.
    const { upserted, deleted } = await syncSnapshot(rows, startedAt);
    const { deactivated } = await upsertFromBusy(rows, startedAt);
    logger.info(
      `[busy-sync] customer_ageing run #${runId}: customers table — ${rows.length} upserted, ${deactivated} deactivated.`
    );

    await completeRun(runId, {
      status: 'success',
      finishedAt: new Date(),
      rowsFetched: rows.length,
      rowsUpserted: upserted,
      rowsDeleted: deleted,
    });

    logger.info(
      `[busy-sync] customer_ageing run #${runId} succeeded: fetched ${rows.length}, upserted ${upserted}, deleted ${deleted}.`
    );
    return { ran: true, runId };
  } catch (err) {
    logger.error(`[busy-sync] customer_ageing run #${runId} failed: ${err.message}`, { stack: err.stack });
    await completeRun(runId, {
      status: 'failed',
      finishedAt: new Date(),
      rowsFetched: 0,
      rowsUpserted: 0,
      rowsDeleted: 0,
      errorMessage: err.message || String(err),
    });
    throw err;
  } finally {
    progress = { phase: 'idle', runId: null, rowsFetched: null };
  }
}

module.exports = { runCustomerAgeingSync, startCustomerAgeingSyncInBackground, getSyncProgress };
