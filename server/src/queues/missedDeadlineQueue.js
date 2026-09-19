const { Queue } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');

const QUEUE_NAME = 'missed-deadline-sweep';
const REPEATABLE_JOB_ID = 'missed-deadline-sweep-daily';

const missedDeadlineQueue = new Queue(QUEUE_NAME, {
  connection,
  prefix: env.redis.prefix,
  defaultJobOptions: {
    attempts: 2,
    removeOnComplete: { count: 30 },
    removeOnFail: { count: 30 },
  },
});

/**
 * Every 2 hours (on the hour). One tick runs the sweeps in
 * services/missedDeadlineService.js: the No Answer 2-hour cycle (nag the
 * single call task / roll to a Physical Visit after a full day) and hand
 * the RE a same-day follow-up for any lapsed salesman deadline. (Will
 * Confirm / Follow-up rollover is no longer part of this — it's an
 * exact-time job, see src/queues/followUpQueue.js.) `upsertJobScheduler`
 * is idempotent — safe on every boot.
 */
async function scheduleMissedDeadlineSweep() {
  // Replace the old thrice-daily id so it doesn't run alongside this one.
  await missedDeadlineQueue.removeJobScheduler('missed-deadline-sweep-daily').catch(() => {});
  await missedDeadlineQueue.upsertJobScheduler(
    'missed-deadline-sweep-2h',
    { pattern: '0 */2 * * *', tz: env.businessTimezone },
    { name: 'run' }
  );
}

/** Runs the sweep immediately — manual/on-demand trigger and testing. */
async function runMissedDeadlineSweepNow() {
  return missedDeadlineQueue.add('run-now', {});
}

module.exports = {
  QUEUE_NAME,
  missedDeadlineQueue,
  scheduleMissedDeadlineSweep,
  runMissedDeadlineSweepNow,
};
