const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const { ping: pingDb } = require('../config/db');
const { QUEUE_NAME } = require('../queues/followUpQueue');
const { resolveFollowUp } = require('../services/followUpService');
const notificationRepository = require('../repositories/notificationRepository');
const logger = require('../config/logger');

function createFollowUpWorker() {
  const worker = new Worker(
    QUEUE_NAME,
    async (job) => {
      await pingDb();
      return resolveFollowUp(job.data);
    },
    { connection, prefix: env.redis.prefix, concurrency: 5 }
  );

  worker.on('failed', (job, err) => {
    logger.error('Follow-up due job failed', { jobId: job?.id, message: err.message });
    const attemptsMade = job?.attemptsMade ?? 0;
    const maxAttempts = job?.opts?.attempts ?? 1;
    if (job && attemptsMade >= maxAttempts) {
      notificationRepository
        .insert({
          severity: 'critical',
          title: 'Follow-up due job failed',
          body: `A "Will Confirm" callback task could not be created for customer ${job.data?.customerId} after ${attemptsMade} attempt(s): ${err.message}.`,
        })
        .catch((notifyErr) => {
          logger.error('Failed to record follow-up due failure notification', { message: notifyErr.message });
        });
    }
  });

  return worker;
}

module.exports = { createFollowUpWorker };
