import { PoolConnection } from 'mysql2/promise';
import logger from '../utils/logger';
import { withRetry } from '../utils/retry';
import { pool as mariaDbPool } from '../config/mariadb';
import { getBranches } from '../config/branches';
import { MssqlCustomerReportRepository } from '../reports/customer/mssqlCustomerReportRepository';
import { syncSnapshot } from '../repositories/customerAgeingRepository';
import { startRun, completeRun } from '../repositories/syncRunsRepository';

const mssqlReportRepository = new MssqlCustomerReportRepository();

// MySQL/MariaDB named lock — atomic, unlike a "check sync_runs then INSERT"
// pattern (proven racy: two callers can both see no 'running' row and both
// proceed before either INSERT lands). GET_LOCK/RELEASE_LOCK are
// connection-scoped and server-side, so this closes the race even across
// separate processes (cron, the manual `sync-now` CLI, and the admin API
// all calling in at once), not just within one Node process.
const LOCK_NAME = 'busy_sync_customer_ageing';

export interface SyncRunResult {
  /** False when a concurrent run already held the lock and this call did nothing — the caller must not report this as "their" run succeeding. */
  ran: boolean;
  runId?: number;
}

export type SyncPhase = 'idle' | 'connecting' | 'fetching' | 'writing';

export interface SyncProgress {
  phase: SyncPhase;
  runId: number | null;
  rowsFetched: number | null;
}

// Single-process progress state, polled by GET /api/admin/sync/status while
// a run is in flight. Deliberately in-memory, not persisted — it's UI
// polish for "is it doing something right now", not the audit trail
// (sync_runs is the audit trail).
let progress: SyncProgress = { phase: 'idle', runId: null, rowsFetched: null };

export function getSyncProgress(): SyncProgress {
  return progress;
}

async function acquireLock(): Promise<PoolConnection | null> {
  const connection = await mariaDbPool.getConnection();
  const [[lockRow]]: any = await connection.query('SELECT GET_LOCK(?, 0) AS acquired', [LOCK_NAME]);
  if (lockRow.acquired) {
    return connection;
  }
  connection.release();
  return null;
}

async function releaseLock(connection: PoolConnection): Promise<void> {
  try {
    await connection.query('SELECT RELEASE_LOCK(?)', [LOCK_NAME]);
  } catch (err: any) {
    logger.error(`[sync] Failed to release advisory lock: ${err.message}`);
  } finally {
    connection.release();
  }
}

/**
 * Runs one full customer-ageing sync and resolves only once it's fully
 * done (success or failure) — what the midnight cron and the `sync-now`
 * CLI want, since both need the final outcome before deciding what to do
 * next (cron just logs it; the CLI sets its exit code from it).
 *
 * `ran: false` on the result means a concurrent run held the lock and
 * this call was a no-op.
 */
export async function runCustomerAgeingSync(): Promise<SyncRunResult> {
  const lockConnection = await acquireLock();
  if (!lockConnection) {
    logger.warn('[sync] customer_ageing sync already in progress — skipping this trigger.');
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
 * getSyncProgress() below) to render a real progress bar instead of the
 * request hanging until the whole sync completes.
 */
export async function startCustomerAgeingSyncInBackground(): Promise<{ started: boolean }> {
  const lockConnection = await acquireLock();
  if (!lockConnection) {
    return { started: false };
  }

  runLocked()
    .catch((err) => {
      // Already logged with full detail inside runLocked; this catch only
      // exists so the background promise can't produce an unhandled rejection.
      logger.error(`[sync] Background run threw: ${err.message}`);
    })
    .finally(() => releaseLock(lockConnection));

  return { started: true };
}

async function runLocked(): Promise<SyncRunResult> {
  // MariaDB's DATETIME column truncates fractional seconds, but a plain JS
  // Date carries milliseconds — floor to whole seconds so the value we
  // write to last_synced_at and the value we later compare against in the
  // sweep DELETE are byte-for-byte the same, and freshly-upserted rows are
  // never mistaken for stale ones.
  const startedAt = new Date(Math.floor(Date.now() / 1000) * 1000);
  const runId = await startRun(startedAt);
  logger.info(`[sync] customer_ageing run #${runId} started at ${startedAt.toISOString()}`);
  progress = { phase: 'connecting', runId, rowsFetched: null };

  try {
    const branches = getBranches();
    let totalFetched = 0;
    let totalUpserted = 0;
    let totalDeleted = 0;

    // One BUSY DB per branch (some on other servers) — walk them
    // sequentially to bound concurrent load on the ERP box(es).
    for (const branch of branches) {
      progress = { phase: 'fetching', runId, rowsFetched: totalFetched };
      const rows = await withRetry(`BUSY customer report fetch [${branch.id}]`, () =>
        mssqlReportRepository.getCustomers({ branchId: branch.id })
      );

      progress = { phase: 'writing', runId, rowsFetched: totalFetched + rows.length };
      const { upserted, deleted } = await syncSnapshot(rows, startedAt, branch.id);

      totalFetched += rows.length;
      totalUpserted += upserted;
      totalDeleted += deleted;
      logger.info(
        `[sync] run #${runId} branch ${branch.id}: fetched ${rows.length}, upserted ${upserted}, deleted ${deleted}.`
      );
    }

    await completeRun(runId, {
      status: 'success',
      finishedAt: new Date(),
      rowsFetched: totalFetched,
      rowsUpserted: totalUpserted,
      rowsDeleted: totalDeleted,
    });

    logger.info(
      `[sync] customer_ageing run #${runId} succeeded across ${branches.length} branch(es): fetched ${totalFetched}, upserted ${totalUpserted}, deleted ${totalDeleted}.`
    );
    return { ran: true, runId };
  } catch (err: any) {
    logger.error(`[sync] customer_ageing run #${runId} failed: ${err.message}`, {
      stack: err.stack,
    });
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
