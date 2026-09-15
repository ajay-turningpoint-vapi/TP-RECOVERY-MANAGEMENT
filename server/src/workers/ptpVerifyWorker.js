const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const { ping: pingDb } = require('../config/db');
const { QUEUE_NAME } = require('../queues/ptpVerifyQueue');
const { verifyDuePtps } = require('../services/ptpVerificationService');
const { beat } = require('../services/heartbeatService');
const notificationRepository = require('../repositories/notificationRepository');
const logger = require('../config/logger');

function createPtpVerifyWorker() {
  const worker = new Worker(
    QUEUE_NAME,
    async () => {
      await pingDb();
      const result = await verifyDuePtps();
      await beat('ptp-verify');
      logger.info('[ptpVerifyWorker] noon PTP promote + verify complete', result);
      return result;
    },
    { connection, prefix: env.redis.prefix, concurrency: 1 }
  );

  worker.on('failed', (job, err) => {
    logger.error('PTP verify job failed', { jobId: job?.id, message: err.message });
    const attemptsMade = job?.attemptsMade ?? 0;
    const maxAttempts = job?.opts?.attempts ?? 1;
    if (job && attemptsMade >= maxAttempts) {
      notificationRepository
        .insert({
          severity: 'critical',
          title: 'PTP verification failed',
          body: `The noon PTP promote + verify pass failed after ${attemptsMade} attempt(s): ${err.message}. Matured PTPs were not judged today.`,
        })
        .catch((notifyErr) => {
          logger.error('Failed to record PTP verify failure notification', { message: notifyErr.message });
        });
    }
  });

  return worker;
}

module.exports = { createPtpVerifyWorker };
