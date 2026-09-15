const env = require('./config/env');
const logger = require('./config/logger');
const db = require('./config/db');
const redis = require('./config/redis');
const { createNotificationWorker } = require('./workers/notificationWorker');
const { createBusySyncWorker } = require('./workers/busySyncWorker');
const { scheduleBusySync } = require('./queues/busySyncQueue');
const { createMissedDeadlineWorker } = require('./workers/missedDeadlineWorker');
const { scheduleMissedDeadlineSweep } = require('./queues/missedDeadlineQueue');
const { createPtpVerifyWorker } = require('./workers/ptpVerifyWorker');
const { schedulePtpVerify } = require('./queues/ptpVerifyQueue');

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

  // 10:00 / 14:00 / 18:00 IST — hand the RE a same-day follow-up for any
  // salesman call/visit whose deadline lapsed with nothing recorded.
  const missedDeadlineWorker = createMissedDeadlineWorker();
  await scheduleMissedDeadlineSweep();

  // 12:10 IST — promote matured PTPs, verify them against BUSY and drive
  // the one auto call task. Retries twice with 5-min exponential backoff.
  const ptpVerifyWorker = createPtpVerifyWorker();
  await schedulePtpVerify();

  // The 5 PM control-batch snapshot is PERMANENTLY PAUSED — not scheduled,
  // worker not started. Its task-reopening half (a "no open action"
  // follow-up for every at-risk customer, every day → 500+ unworked tasks,
  // cleared 2026-09-06) has been removed from the code entirely. The one
  // nightly recovery backstop is now recoveryReconcileService.reconcileAll,
  // which runs after the noon BUSY sync and only retargets the single
  // source='Recovery' task. snapshotWorker.runSnapshot now records trend
  // metrics only (no task / state changes) and is invoked on demand, if at all.
  logger.info('Worker process running — notifications, BUSY sync (+ PTP verify), 2-hourly sweeps. 5 PM control snapshot is permanently paused.');

  function shutdown(signal) {
    logger.info(`${signal} received — shutting down worker gracefully...`);
    Promise.all([notificationWorker.close(), busySyncWorker.close(), missedDeadlineWorker.close(), ptpVerifyWorker.close()])
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
