const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const { QUEUE_NAME } = require('../queues/notificationQueue');
const notificationRepository = require('../repositories/notificationRepository');
const { publish } = require('../realtime/eventBus');
const logger = require('../config/logger');

function createNotificationWorker() {
  const worker = new Worker(
    QUEUE_NAME,
    async (job) => {
      await notificationRepository.insert(job.data);
      // Tell connected clients to re-pull /api/notifications (keeps the
      // client-side OS-notification dedup logic as the single source of
      // truth for what's "new").
      const userId = job.data && job.data.userId;
      publish({ type: 'notification', scope: userId ? { userId } : { broadcast: true } });
    },
    { connection, prefix: env.redis.prefix, concurrency: 5 }
  );

  worker.on('failed', (job, err) => {
    logger.error('Notification job failed', { jobId: job?.id, message: err.message });
  });

  return worker;
}

module.exports = { createNotificationWorker };
