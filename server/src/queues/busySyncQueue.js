const { Queue } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');

const QUEUE_NAME = 'busy-customer-sync';
// Kept as -midnight (not -noon) even though the schedule itself moved to
// 12:00 IST — this is a BullMQ Job Scheduler id, and changing it would
// register a *second* scheduler alongside whatever's already persisted in
// Redis from the old id rather than updating it in place, silently
// doubling the sync. upsertJobScheduler below is what actually moved the
// time; the id is just a stable key at this point, not a description.
const REPEATABLE_JOB_ID = 'busy-customer-sync-midnight';

const busySyncQueue = new Queue(QUEUE_NAME, {
  connection,
  prefix: env.redis.prefix,
  defaultJobOptions: {
    // Was `attempts: 2` with no backoff — the two tries fired back-to-back
    // (seconds apart), so a BUSY source that was briefly unreachable meant
    // customer data stayed stale until the next day's 12:00 run, with the
    // app showing a "sync failed" state that never cleared on its own.
    // Now: 4 tries with exponential backoff (~10m, ~20m, ~40m), so a
    // transient network / BUSY outage heals itself within the hour and the
    // failure message the client shows is genuinely "it will retry
    // automatically", not "wait until tomorrow".
    attempts: 4,
    backoff: { type: 'exponential', delay: 10 * 60 * 1000 },
    removeOnComplete: { count: 30 },
    removeOnFail: { count: 30 },
  },
});

/**
 * Schedules the daily BUSY -> customers/customer_ageing_snapshot sync via
 * BullMQ's Job Scheduler API — same pattern as
 * snapshotQueue.js's scheduleDailySnapshot (upsertJobScheduler, not the
 * deprecated `queue.add({repeat})`). Idempotent — safe to call on every
 * worker-process boot.
 */
async function scheduleBusySync() {
  await busySyncQueue.upsertJobScheduler(
    REPEATABLE_JOB_ID,
    // 12:00 IST every day (moved from 00:00 — by then, real users are
    // already active in the app; see AppStore's sync-freeze overlay,
    // which the client shows for the duration of this job so nobody
    // reads/writes against half-synced data). tz is explicit, not implied
    // from the host OS (see env.businessTimezone's doc comment for why
    // that matters). PTP verification/reconciliation
    // (services/ptpVerificationService.js) runs as part of the same job,
    // right after the sync — see workers/busySyncWorker.js — so it moves
    // with this one schedule rather than needing its own.
    { pattern: '0 12 * * *', tz: env.businessTimezone },
    { name: 'run' }
  );
}

/** Runs the sync immediately — used by the admin dashboard's manual trigger and testing. */
async function runBusySyncNow() {
  return busySyncQueue.add('run-now', {});
}

module.exports = { QUEUE_NAME, busySyncQueue, scheduleBusySync, runBusySyncNow };
