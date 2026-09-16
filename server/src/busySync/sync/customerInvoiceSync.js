const logger = require('../../config/logger');
const { withRetry } = require('../utils/retry');
const { pool: mariaDbPool } = require('../../config/db');
const { getInvoices } = require('../reports/mssqlInvoiceReportRepository');
const { syncInvoiceSnapshot } = require('../repositories/customerInvoiceRepository');
const { startRun, completeRun } = require('../repositories/syncRunsRepository');
const { BRANCHES } = require('../config/branches');

const LOCK_NAME = 'busy_sync_customer_invoice';

let progress = { phase: 'idle', runId: null, rowsFetched: null };

function getInvoiceSyncProgress() {
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
    logger.error(`[sync] Failed to release advisory lock: ${err.message}`);
  } finally {
    connection.release();
  }
}

async function runCustomerInvoiceSync() {
  const lockConnection = await acquireLock();
  if (!lockConnection) {
    logger.warn('[sync] customer_invoice sync already in progress — skipping this trigger.');
    return { ran: false };
  }
  try {
    return await runLocked();
  } finally {
    await releaseLock(lockConnection);
  }
}

async function startCustomerInvoiceSyncInBackground() {
  const lockConnection = await acquireLock();
  if (!lockConnection) {
    return { started: false };
  }

  runLocked()
    .catch((err) => {
      logger.error(`[sync] Background run threw: ${err.message}`);
    })
    .finally(() => releaseLock(lockConnection));

  return { started: true };
}

async function runLocked() {
  const startedAt = new Date(Math.floor(Date.now() / 1000) * 1000);
  const branchErrors = [];
  const runIds = [];

  for (const branch of BRANCHES) {
    const runId = await startRun(startedAt, branch.label, 'customer_invoice');
    runIds.push(runId);
    logger.info(`[sync] customer_invoice run #${runId} (${branch.label}) started at ${startedAt.toISOString()}`);
    progress = { phase: 'connecting', runId, rowsFetched: null, branch: branch.label };

    try {
      progress = { phase: 'fetching', runId, rowsFetched: null, branch: branch.label };
      const rows = await withRetry(`BUSY customer invoice report fetch (${branch.label})`, () =>
        getInvoices({ database: branch.database, parentGroups: branch.parentGroups, conn: branch.conn })
      );

      progress = { phase: 'writing', runId, rowsFetched: rows.length, branch: branch.label };
      const { upserted, deleted } = await syncInvoiceSnapshot(rows, startedAt, branch.label);

      await completeRun(runId, {
        status: 'success',
        finishedAt: new Date(),
        rowsFetched: rows.length,
        rowsUpserted: upserted,
        rowsDeleted: deleted,
      });
      logger.info(
        `[sync] customer_invoice run #${runId} (${branch.label}) succeeded: fetched ${rows.length}, upserted ${upserted}, deleted ${deleted}.`
      );
    } catch (err) {
      logger.error(`[sync] customer_invoice run #${runId} (${branch.label}) failed: ${err.message}`, {
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
      branchErrors.push(branch.label);
    }
  }

  progress = { phase: 'idle', runId: null, rowsFetched: null, branch: null };
  if (branchErrors.length) {
    throw new Error(`BUSY customer_invoice sync failed for: ${branchErrors.join(', ')}`);
  }
  return { ran: true, runIds };
}

module.exports = { getInvoiceSyncProgress, runCustomerInvoiceSync, startCustomerInvoiceSyncInBackground };
