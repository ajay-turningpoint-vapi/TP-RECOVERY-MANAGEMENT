const { Queue } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');

const QUEUE_NAME = 'follow-up-due';

const followUpQueue = new Queue(QUEUE_NAME, {
  connection,
  prefix: env.redis.prefix,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 60_000 },
    removeOnComplete: { count: 100 },
    removeOnFail: { count: 100 },
  },
});

/**
 * Schedules a ONE-OFF job to fire at exactly `dueAt` — the salesman-picked
 * "Will Confirm" callback time. Replaces the old 2-hourly polling sweep
 * (missedDeadlineService.sweepExpiredFollowUps, removed) with an
 * exact-time trigger: nothing happens for this customer between recording
 * the outcome and this job firing (see customerService.recordOutcome's
 * reconcileState skip for 'Follow-up'/'Follow-up Scheduled') — no task
 * exists and Record Outcome stays locked until this fires.
 *
 * jobId is deterministic per (customerId, dueAt) so a retried/duplicate
 * record-outcome call can't stack two jobs for the same follow-up.
 */
async function scheduleFollowUpDue({ customerId, ownerId, dueAt }) {
  const due = new Date(dueAt);
  const delay = Math.max(0, due.getTime() - Date.now());
  const jobId = `follow-up:${customerId}:${due.getTime()}`;
  await followUpQueue.add('follow-up-due', { customerId, ownerId, dueAt: due.toISOString() }, { delay, jobId });
}

module.exports = { QUEUE_NAME, followUpQueue, scheduleFollowUpDue };
