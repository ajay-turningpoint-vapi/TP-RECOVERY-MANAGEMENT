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

function summariseLastSync(run) {
  if (!run) return null;
  const error = run.errorMessage || null;
  const isConnection = run.status === 'failed' && !!error && CONNECTION_ERROR.test(error);
  const branchLabel = run.branch ? ` (${run.branch})` : '';

  const startedMs = run.startedAt ? new Date(run.startedAt).getTime() : 0;
  const runningLooksStalled =
    run.status === 'running' && startedMs > 0 && Date.now() - startedMs > STALLED_AFTER_MS;

  // The one case that is NOT a problem: a fresh `running` row = a sync in
  // progress. Report it plainly so the client can say "syncing…" rather
  // than "sync failed".
  if (run.status === 'running' && !runningLooksStalled) {
    return {
      status: 'inProgress',
      branch: run.branch,
      jobName: run.jobName,
      startedAt: run.startedAt,
      finishedAt: null,
      error: null,
      connectionError: false,
      message: null,
    };
  }

  const RETRY_NOTE = 'It runs again automatically — no action needed.';
  let message = null;
  if (run.status === 'failed') {
    message = isConnection
      ? `Couldn't reach BUSY${branchLabel} — the connection failed. Customer balances, PTPs and tasks may be out of date. ${RETRY_NOTE}`
      : `The last BUSY sync${branchLabel} didn't finish, so customer data may be out of date. ${RETRY_NOTE}`;
  } else if (runningLooksStalled) {
    message = `A BUSY sync${branchLabel} was interrupted before it finished, so customer data may be out of date. ${RETRY_NOTE}`;
  }

  return {
    status: runningLooksStalled ? 'stalled' : run.status, // 'success' | 'failed' | 'stalled'
    branch: run.branch,
    jobName: run.jobName,
    startedAt: run.startedAt,
    finishedAt: run.finishedAt,
    error,
    connectionError: isConnection,
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
      lastSync = summariseLastSync(await syncRunsRepository.getLatestRunAny());
    } catch (_) {
      // Status reporting only — never fail the poll over it.
    }

    res.json({ syncing, since, lastSync });
  })
);

module.exports = router;
