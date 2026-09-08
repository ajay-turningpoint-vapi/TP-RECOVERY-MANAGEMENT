const { Queue } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');

const QUEUE_NAME = 'daily-snapshot';
const REPEATABLE_JOB_ID = 'daily-snapshot-5pm';

const snapshotQueue = new Queue(QUEUE_NAME, {
  connection,
  prefix: env.redis.prefix,
  defaultJobOptions: {
    attempts: 2,
    removeOnComplete: { count: 30 },
    removeOnFail: { count: 30 },
  },
});

/**
 * Schedules the recurring 5 PM control-batch snapshot via BullMQ's Job
 * Scheduler API (the `{repeat}` option on `queue.add()` is deprecated as
 * of BullMQ v5+ and does NOT reliably wait for the cron match — verified
 * here: it ran the job immediately with delay:0 instead of waiting for
 * 17:00). `upsertJobScheduler` is idempotent — safe to call on every boot.
 */
async function scheduleDailySnapshot() {
  await snapshotQueue.upsertJobScheduler(
    REPEATABLE_JOB_ID,
    // 17:00 IST every day — tz is explicit, not implied from the host OS
    // (see env.businessTimezone's doc comment for why that matters).
    { pattern: '0 17 * * *', tz: env.businessTimezone },
    { name: 'run' }
  );
}

/** Runs the snapshot immediately — used for manual/on-demand triggers and testing. */
async function runSnapshotNow() {
  return snapshotQueue.add('run-now', {});
}

module.exports = { QUEUE_NAME, snapshotQueue, scheduleDailySnapshot, runSnapshotNow };
