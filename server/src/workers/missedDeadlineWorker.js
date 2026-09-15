const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const { ping: pingDb } = require('../config/db');
const { QUEUE_NAME } = require('../queues/missedDeadlineQueue');
const { sweepMissedDeadlines, sweepExpiredFollowUps, sweepNoAnswerCycle, sweepRESlaBreaches } = require('../services/missedDeadlineService');
const { beat } = require('../services/heartbeatService');
const notificationRepository = require('../repositories/notificationRepository');
const logger = require('../config/logger');

function createMissedDeadlineWorker() {
  const worker = new Worker(
    QUEUE_NAME,
    async () => {
      await pingDb();
      const noAnswer = await sweepNoAnswerCycle();
      // Roll expired "Will Confirm" tasks into a fresh call task BEFORE the
      // missed-deadline sweep, so that sees the fresh task, not the stale one.
      const rolled = await sweepExpiredFollowUps();
      const result = await sweepMissedDeadlines();
      const reSla = await sweepRESlaBreaches();
      await beat('sweeps-2h');
      logger.info('[missedDeadlineWorker] sweep complete', { ...noAnswer, ...rolled, ...result, ...reSla });
      return { ...noAnswer, ...rolled, ...result, ...reSla };
    },
    { connection, prefix: env.redis.prefix, concurrency: 1 }
  );

  worker.on('failed', (job, err) => {
    logger.error('Missed-deadline sweep job failed', { jobId: job?.id, message: err.message });
    const attemptsMade = job?.attemptsMade ?? 0;
    const maxAttempts = job?.opts?.attempts ?? 1;
    if (job && attemptsMade >= maxAttempts) {
      notificationRepository
        .insert({
          severity: 'critical',
          title: 'Missed-deadline sweep failed',
          body: `The sweep that hands the RE a same-day follow-up for lapsed salesman deadlines failed after ${attemptsMade} attempt(s): ${err.message}.`,
        })
        .catch((notifyErr) => {
          logger.error('Failed to record missed-deadline sweep failure notification', { message: notifyErr.message });
        });
    }
  });

  return worker;
}

module.exports = { createMissedDeadlineWorker };
