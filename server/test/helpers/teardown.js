const { closePool } = require('../../src/config/db');
const { connection: redisConnection } = require('../../src/config/redis');
const { notificationQueue } = require('../../src/queues/notificationQueue');
const { snapshotQueue } = require('../../src/queues/snapshotQueue');

/**
 * Every test file that boots the app pulls in the full route tree
 * (routes/index.js mounts everything), which pulls in the BullMQ queues,
 * which open a Redis connection — even for a test file that never touches
 * escalations/disputes/notifications directly. Without closing all of it,
 * the process never exits after tests finish (an open socket keeps the
 * event loop alive), which is exactly what happened here the first time.
 */
async function teardownAll(app) {
  if (app) await app.close();
  await notificationQueue.close();
  await snapshotQueue.close();
  await redisConnection.quit();
  await closePool();
}

module.exports = { teardownAll };
