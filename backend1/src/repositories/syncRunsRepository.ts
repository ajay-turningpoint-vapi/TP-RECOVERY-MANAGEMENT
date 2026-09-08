import { query } from '../config/mariadb';

const JOB_NAME = 'customer_ageing';

export interface SyncRun {
  id: number;
  jobName: string;
  startedAt: Date;
  finishedAt: Date | null;
  status: 'running' | 'success' | 'failed';
  rowsFetched: number;
  rowsUpserted: number;
  rowsDeleted: number;
  errorMessage: string | null;
}

function mapRun(raw: any): SyncRun {
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

/** True if a run for this job is already marked 'running' — used as the concurrency guard. */
export async function isRunInProgress(jobName = JOB_NAME): Promise<boolean> {
  const rows = await query<any[]>(
    `SELECT id FROM sync_runs WHERE job_name = ? AND status = 'running' LIMIT 1`,
    [jobName]
  );
  return rows.length > 0;
}

export async function startRun(startedAt: Date, jobName = JOB_NAME): Promise<number> {
  const result: any = await query(
    `INSERT INTO sync_runs (job_name, started_at, status) VALUES (?, ?, 'running')`,
    [jobName, startedAt]
  );
  return result.insertId;
}

export async function completeRun(
  runId: number,
  outcome: {
    status: 'success' | 'failed';
    finishedAt: Date;
    rowsFetched: number;
    rowsUpserted: number;
    rowsDeleted: number;
    errorMessage?: string | null;
  }
): Promise<void> {
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

export async function getLatestRun(jobName = JOB_NAME): Promise<SyncRun | null> {
  const rows = await query<any[]>(
    `SELECT * FROM sync_runs WHERE job_name = ? ORDER BY id DESC LIMIT 1`,
    [jobName]
  );
  return rows.length > 0 ? mapRun(rows[0]) : null;
}

export async function getRecentRuns(limit = 20, jobName = JOB_NAME): Promise<SyncRun[]> {
  const rows = await query<any[]>(
    `SELECT * FROM sync_runs WHERE job_name = ? ORDER BY id DESC LIMIT ?`,
    [jobName, limit]
  );
  return rows.map(mapRun);
}
