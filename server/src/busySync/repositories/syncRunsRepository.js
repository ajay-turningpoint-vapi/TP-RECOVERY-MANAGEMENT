const { query } = require('../../config/db');

const JOB_NAME = 'customer_ageing';

function mapRun(raw) {
  return {
    id: raw.id,
    jobName: raw.job_name,
    startedAt: raw.started_at,
    finishedAt: raw.finished_at,
    status: raw.status,
    rowsFetched: raw.rows_fetched,
    rowsUpserted: raw.rows_upserted,
    rowsDeleted: raw.rows_deleted,
    errorMessage: raw.error_message,
  };
}

/** True if a run for this job is already marked 'running' — used for status reporting (not the concurrency guard itself — see sync/customerAgeingSync.js's advisory lock). */
async function isRunInProgress() {
  const rows = await query(`SELECT id FROM sync_runs WHERE job_name = ? AND status = 'running' LIMIT 1`, [JOB_NAME]);
  return rows.length > 0;
}

async function startRun(startedAt) {
  const result = await query(`INSERT INTO sync_runs (job_name, started_at, status) VALUES (?, ?, 'running')`, [
    JOB_NAME,
    startedAt,
  ]);
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

async function getLatestRun() {
  const rows = await query(`SELECT * FROM sync_runs WHERE job_name = ? ORDER BY id DESC LIMIT 1`, [JOB_NAME]);
  return rows.length > 0 ? mapRun(rows[0]) : null;
}

async function getRecentRuns(limit = 20) {
  const rows = await query(`SELECT * FROM sync_runs WHERE job_name = ? ORDER BY id DESC LIMIT ?`, [JOB_NAME, limit]);
  return rows.map(mapRun);
}

module.exports = { isRunInProgress, startRun, completeRun, getLatestRun, getRecentRuns };
