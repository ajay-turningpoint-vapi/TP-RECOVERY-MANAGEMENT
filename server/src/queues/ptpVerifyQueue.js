const { Queue } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');

const QUEUE_NAME = 'ptp-verify';
const REPEATABLE_JOB_ID = 'ptp-verify-noon';

const ptpVerifyQueue = new Queue(QUEUE_NAME, {
  connection,
  prefix: env.redis.prefix,
  defaultJobOptions: {
    // One retry pair with exponential 5-minute backoff — if BUSY is
    // briefly unreachable at noon, try again ~5 and ~10 minutes later
    // rather than waiting for tomorrow's pass.
    attempts: 3,
    backoff: { type: 'exponential', delay: 5 * 60 * 1000 },
    removeOnComplete: { count: 30 },
    removeOnFail: { count: 30 },
  },
});

/**
 * Once a day at 12:10 IST (a few minutes after the noon BUSY balance sync
 * so `customer.totalDue` is fresh): promote every Scheduled PTP whose
 * promise time has passed, then verify every Pending-Verification PTP
 * against BUSY receipts and drive the one auto call task. See
 * services/ptpVerificationService.js `verifyDuePtps`.
 */
async function schedulePtpVerify() {
  await ptpVerifyQueue.upsertJobScheduler(
    REPEATABLE_JOB_ID,
    { pattern: '10 12 * * *', tz: env.businessTimezone },
    { name: 'run' }
  );
}

async function runPtpVerifyNow() {
  return ptpVerifyQueue.add('run-now', {});
}

module.exports = { QUEUE_NAME, ptpVerifyQueue, schedulePtpVerify, runPtpVerifyNow };
