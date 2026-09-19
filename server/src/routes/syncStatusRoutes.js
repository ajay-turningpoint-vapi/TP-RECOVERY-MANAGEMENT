/**
 * Universal sync-freeze signal — every authenticated role (not just
 * MANAGEMENT, unlike /api/busy-sync/sync/status) polls this to know
 * whether the daily BUSY sync job is currently running, so the client can
 * show a full-screen "syncing, please wait" overlay for its duration. See
 * services/syncLockService.js and workers/busySyncWorker.js.
 *
 * It also reports the OUTCOME of the last finished run (`lastSync`) so that
 * when a sync fails — most commonly because the BUSY ERP source is
 * unreachable — active clients can show a real "couldn't reach BUSY,
 * data may be stale" message instead of silently rendering old data.
 */
const { Router } = require('express');
const asyncHandler = require('../middleware/asyncHandler');
const { authenticate } = require('../middleware/auth');
const syncLockService = require('../services/syncLockService');
const syncRunsRepository = require('../busySync/repositories/syncRunsRepository');

const router = Router();
router.use(authenticate);

// A failed run whose error looks like the BUSY MSSQL source could not be
// reached (vs. a data/logic failure mid-sync) — the client wording differs.
const CONNECTION_ERROR = /failed to connect|econnrefused|etimedout|enotfound|socket hang up|connection (?:failed|lost|closed|is closed)|network|unreachable|timeout/i;

// A `running` row younger than this is almost certainly a sync happening
// RIGHT NOW (the CLI `npm run sync:busy` path doesn't take the Redis lock,
// and even the worker briefly has a `running` row between its per-step
// lock release and the next INCR). Only a `running` row OLDER than this is
// a genuinely stalled / killed job worth warning the user about.
const STALLED_AFTER_MS = 30 * 60 * 1000;

/**
 * `batch` is every branch's `sync_runs` row sharing the last run's
 * (job_name, started_at) — see syncRunsRepository.getLatestBatchAny().
 * customerAgeingSync.js/customerInvoiceSync.js write one row per branch
 * (5 branches across 2 BUSY hosts) per run, so the run's real outcome is
 * "did every branch succeed", not just whichever row has the highest id.
 */
function summariseLastSync(batch) {
  if (!batch || batch.length === 0) return null;

  const runningLooksStalled = (run) => {
    const startedMs = run.startedAt ? new Date(run.startedAt).getTime() : 0;
    return run.status === 'running' && startedMs > 0 && Date.now() - startedMs > STALLED_AFTER_MS;
  };

  const runningFresh = batch.filter((r) => r.status === 'running' && !runningLooksStalled(r));
  // Any branch still genuinely mid-sync ⇒ report the whole batch as in
  // progress, same as before — the client shows "syncing…", not "failed",
  // while other branches in the same run have already finished.
  if (runningFresh.length > 0) {
    const run = runningFresh[0];
    return {
      status: 'inProgress',
      branch: run.branch,
      jobName: run.jobName,
      startedAt: run.startedAt,
      finishedAt: null,
      error: null,
      connectionError: false,
      failedBranches: [],
      message: null,
    };
  }

  const stalled = batch.filter((r) => runningLooksStalled(r));
  const failed = batch.filter((r) => r.status === 'failed');
  const failedBranches = [...stalled, ...failed].map((r) => r.branch).filter(Boolean);

  const jobName = batch[0].jobName;
  const startedAt = batch[0].startedAt;
  const finishedAt = batch.reduce((latest, r) => {
    if (!r.finishedAt) return latest;
    return !latest || new Date(r.finishedAt) > new Date(latest) ? r.finishedAt : latest;
  }, null);

  if (failedBranches.length === 0) {
    return {
      status: 'success',
      branch: null,
      jobName,
      startedAt,
      finishedAt,
      error: null,
      connectionError: false,
      failedBranches: [],
      message: null,
    };
  }

  // Each failed branch keeps its OWN reason — a prior version picked one
  // representative error for the whole batch, so "FP-VAPI timed out but
  // Turning Point had a real data error" would misreport Turning Point as
  // a connection issue too. Group instead: branches whose error looks like
  // a lost connection vs. branches that failed for some other reason vs.
  // branches whose row got stuck 'running' (killed mid-sync) each get
  // their own clause, so the message always names the real branch(es) and
  // the real reason — e.g. "Turning Point branch sync failed — connection
  // lost." — never a vague "some branches failed".
  const connectionBranches = failed.filter((r) => CONNECTION_ERROR.test(r.errorMessage || '')).map((r) => r.branch).filter(Boolean);
  const otherFailedBranches = failed.filter((r) => !CONNECTION_ERROR.test(r.errorMessage || '')).map((r) => r.branch).filter(Boolean);
  const stalledBranches = stalled.map((r) => r.branch).filter(Boolean);

  const branchWord = (list) => (list.length === 1 ? 'branch' : 'branches');
  const clauses = [];
  if (connectionBranches.length > 0) {
    clauses.push(`${connectionBranches.join(', ')} ${branchWord(connectionBranches)} sync failed — connection lost`);
  }
  if (otherFailedBranches.length > 0) {
    clauses.push(`${otherFailedBranches.join(', ')} ${branchWord(otherFailedBranches)} sync failed — didn't finish`);
  }
  if (stalledBranches.length > 0) {
    clauses.push(`${stalledBranches.join(', ')} ${branchWord(stalledBranches)} sync was interrupted before it finished`);
  }

  const isConnection = connectionBranches.length > 0 && otherFailedBranches.length === 0 && stalledBranches.length === 0;
  const RETRY_NOTE = 'It runs again automatically — no action needed.';
  const message = `${clauses.join('; ')}, so that data may be out of date. ${RETRY_NOTE}`;

  const failedRun = failed.find((r) => CONNECTION_ERROR.test(r.errorMessage || '')) || failed[0] || stalled[0];

  return {
    status: stalled.length > 0 && failed.length === 0 ? 'stalled' : 'failed',
    branch: failedBranches.length === 1 ? failedBranches[0] : null,
    jobName,
    startedAt,
    finishedAt,
    error: failedRun ? failedRun.errorMessage : null,
    connectionError: isConnection,
    failedBranches,
    message,
  };
}

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const since = await syncLockService.syncingSince();
    const syncing = since !== null;

    let lastSync = null;
    try {
      lastSync = summariseLastSync(await syncRunsRepository.getLatestBatchAny());
    } catch (_) {
      // Status reporting only — never fail the poll over it.
    }

    res.json({ syncing, since, lastSync });
  })
);

module.exports = router;
