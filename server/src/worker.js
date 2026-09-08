const env = require('./config/env');
const logger = require('./config/logger');
const db = require('./config/db');
const redis = require('./config/redis');
const { createNotificationWorker } = require('./workers/notificationWorker');
const { createBusySyncWorker } = require('./workers/busySyncWorker');
const { scheduleBusySync } = require('./queues/busySyncQueue');

/**
 * Separate process from the API server (`server.js`) — run as its own
 * deployment unit (`npm run worker`) so a slow/failing background job can
 * never starve HTTP request handling, and either side can scale or
 * restart independently.
 */
async function main() {
  try {
    await db.ping();
    await redis.ping();
    logger.info(`Worker connected to MariaDB (${env.db.database}) and Redis.`);
  } catch (err) {
    logger.error('Worker could not reach MariaDB/Redis at startup — refusing to start.', { message: err.message });
    process.exit(1);
  }

  const notificationWorker = createNotificationWorker();
  const busySyncWorker = createBusySyncWorker();
  await scheduleBusySync();

  // The 5 PM control-batch snapshot (workers/snapshotWorker.js,
  // queues/snapshotQueue.js) is deliberately disabled — not scheduled and
  // its worker not started. It had been auto-reopening a "no open action"
  // follow-up task (and a matching SNAPSHOT_REOPENED_RECOVERY audit event)
  // for every at-risk customer once per day, every day, accumulating into
  // 500+ tasks nobody was actually working — cleared out on 2026-09-06
  // along with its notifications and daily_metrics_snapshot rows. The code
  // is left in place (not deleted) in case this safety net is wanted back
  // later — re-enable by restoring the createSnapshotWorker/
  // scheduleDailySnapshot calls removed here.
  logger.info('Worker process running — processing notifications and BUSY customer sync queues (PTP verification runs as part of BUSY sync). 5 PM control snapshot is disabled.');

  function shutdown(signal) {
    logger.info(`${signal} received — shutting down worker gracefully...`);
    Promise.all([notificationWorker.close(), busySyncWorker.close()])
      .then(() => db.closePool())
      .then(() => redis.connection.quit())
      .catch((err) => logger.error('Error during worker shutdown', { message: err.message }))
      .finally(() => process.exit(0));
    setTimeout(() => process.exit(1), 10_000).unref();
  }

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  process.on('unhandledRejection', (reason) => {
    logger.error('Unhandled promise rejection in worker', { message: reason?.message || String(reason), stack: reason?.stack });
  });

  process.on('uncaughtException', (err) => {
    logger.error('Uncaught exception in worker — exiting', { message: err.message, stack: err.stack });
    process.exit(1);
  });
}

main();
