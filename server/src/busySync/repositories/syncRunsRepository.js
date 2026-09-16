const { query } = require('../../config/db');

const JOB_NAME = 'customer_ageing';

function mapRun(raw) {
  return {
    id: raw.id,
    jobName: raw.job_name,
    branch: raw.branch ?? null,
    startedAt: raw.started_at,
    finishedAt: raw.finished_at,
    status: raw.status,
    rowsFetched: raw.rows_fetched,
    rowsUpserted: raw.rows_upserted,
    rowsDeleted: raw.rows_deleted,
    errorMessage: raw.error_message,
  };
}

/** True if any run for `jobName` (default: the customer-ageing job) is currently 'running' — status reporting only, not the concurrency guard (that's the advisory lock in the sync modules). */
async function isRunInProgress(jobName = JOB_NAME) {
  const rows = await query(`SELECT id FROM sync_runs WHERE job_name = ? AND status = 'running' LIMIT 1`, [jobName]);
  return rows.length > 0;
}

async function startRun(startedAt, branch = null, jobName = JOB_NAME) {
  const result = await query(
    `INSERT INTO sync_runs (job_name, branch, started_at, status) VALUES (?, ?, ?, 'running')`,
    [jobName, branch, startedAt]
  );
  return result.insertId;
}

async function completeRun(runId, outcome) {
  await query(
    `UPDATE sync_runs
     SET status = ?, finished_at = ?, rows_fetched = ?, rows_upserted = ?, rows_deleted = ?, error_message = ?
     WHERE id = ?`,
    [
      outcome.status,
      outcome.finishedAt,
      outcome.rowsFetched,
      outcome.rowsUpserted,
      outcome.rowsDeleted,
      outcome.errorMessage ?? null,
      runId,
    ]
  );
}

/** Latest run for `jobName`, optionally narrowed to one branch. */
async function getLatestRun(branch = null, jobName = JOB_NAME) {
  const rows = branch
    ? await query(`SELECT * FROM sync_runs WHERE job_name = ? AND branch = ? ORDER BY id DESC LIMIT 1`, [jobName, branch])
    : await query(`SELECT * FROM sync_runs WHERE job_name = ? ORDER BY id DESC LIMIT 1`, [jobName]);
  return rows.length > 0 ? mapRun(rows[0]) : null;
}

/**
 * The single most recent run across every job_name / branch — kept for
 * callers that only care about "what's the very latest row", but NOT what
 * /api/sync-status uses: customerAgeingSync.js/customerInvoiceSync.js write
 * one row per branch (5 branches, 2 hosts) under one shared `started_at`
 * per run, sequentially — so the highest-`id` row is just whichever branch
 * happened to finish last, not the run's overall outcome. See
 * getLatestBatchAny() below for the real "did the last run actually
 * succeed, across every branch" answer.
 */
async function getLatestRunAny() {
  const rows = await query(`SELECT * FROM sync_runs ORDER BY id DESC LIMIT 1`);
  return rows.length > 0 ? mapRun(rows[0]) : null;
}

/**
 * The most recent *batch* — every branch's row sharing the same
 * (job_name, started_at) as the single latest row — so a partial failure
 * (e.g. 2 of 5 branches down) is visible instead of masked by whichever
 * branch's row happens to have the highest `id`. Used by the universal
 * /api/sync-status endpoint.
 */
async function getLatestBatchAny() {
  const latest = await query(`SELECT job_name, started_at FROM sync_runs ORDER BY id DESC LIMIT 1`);
  if (latest.length === 0) return [];
  const { job_name: jobName, started_at: startedAt } = latest[0];
  const rows = await query(
    `SELECT * FROM sync_runs WHERE job_name = ? AND started_at = ? ORDER BY id ASC`,
    [jobName, startedAt]
  );
  return rows.map(mapRun);
}

async function getRecentRuns(limit = 20, jobName = JOB_NAME) {
  const rows = await query(`SELECT * FROM sync_runs WHERE job_name = ? ORDER BY id DESC LIMIT ?`, [jobName, limit]);
  return rows.map(mapRun);
}

module.exports = {
  JOB_NAME,
  isRunInProgress,
  startRun,
  completeRun,
  getLatestRun,
  getLatestRunAny,
  getLatestBatchAny,
  getRecentRuns,
};
