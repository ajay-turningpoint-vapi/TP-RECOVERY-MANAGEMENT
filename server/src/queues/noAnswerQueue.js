const { Queue } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');

const QUEUE_NAME = 'no-answer-due';

const noAnswerQueue = new Queue(QUEUE_NAME, {
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
 * Schedules a ONE-OFF job to fire at exactly `dueAt` — the 2-hour
 * No-Answer callback window (or the post-escalation 2nd-cycle callback).
 * Mirrors followUpQueue.scheduleFollowUpDue exactly: nothing happens for
 * this customer between recording the outcome and this job firing — no
 * task exists until it does (see customerService.applyOutcome's No
 * Answer branch, which closes any prior open task but never creates the
 * next one inline).
 *
 * jobId is deterministic per (customerId, attemptNumber) so a retried
 * record-outcome call can't stack two jobs for the same attempt.
 */
async function scheduleNoAnswerDue({ customerId, ownerId, attemptNumber, dueAt }) {
  const due = new Date(dueAt);
  const delay = Math.max(0, due.getTime() - Date.now());
  const jobId = `no-answer:${customerId}:${attemptNumber}`;
  await noAnswerQueue.add('no-answer-due', { customerId, ownerId, attemptNumber, dueAt: due.toISOString() }, { delay, jobId });
}

module.exports = { QUEUE_NAME, noAnswerQueue, scheduleNoAnswerDue };
