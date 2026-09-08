const { Queue } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');

const QUEUE_NAME = 'notifications';

const notificationQueue = new Queue(QUEUE_NAME, {
  connection,
  prefix: env.redis.prefix,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 2000 },
    removeOnComplete: { count: 500 },
    removeOnFail: { count: 500 },
  },
});

/**
 * Fire-and-forget: callers enqueue a notification and move on, instead of
 * writing it to the notifications table inline on the request path. Keeps
 * a slow/failing notification write from ever blocking the action that
 * triggered it (e.g. approving a dispute).
 */
async function enqueueNotification(notification) {
  await notificationQueue.add('create', notification);
}

module.exports = { QUEUE_NAME, notificationQueue, enqueueNotification };
