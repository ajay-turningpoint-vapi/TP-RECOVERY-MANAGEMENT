const env = require('./config/env');
const logger = require('./config/logger');
const createApp = require('./app');
const db = require('./config/db');
const sseHub = require('./realtime/sseHub');
const heartbeatService = require('./services/heartbeatService');
const maintenanceService = require('./services/maintenanceService');

async function main() {
  // Fail fast, loudly, if the database is unreachable at boot — better to
  // never start serving traffic than to serve it broken.
  try {
    await db.ping();
    logger.info(`Connected to MariaDB at ${env.db.host}:${env.db.port}/${env.db.database}`);
  } catch (err) {
    logger.error('Could not reach MariaDB at startup — refusing to start.', { message: err.message });
    process.exit(1);
  }

  await maintenanceService.init();

  const app = createApp();
  // Redis pub/sub → SSE fan-out. Lives here, not in createApp(), so the
  // test suite (which builds the app directly and never listens) doesn't
  // open a subscriber connection that keeps its process alive.
  sseHub.init();
  const server = app.listen(env.port, () => {
    logger.info(`TP-RMS server listening on port ${env.port} (${env.nodeEnv})`);
  });

  // Watchdog: the API process (more likely up than the worker) checks
  // hourly that the scheduled jobs are still beating, and raises a critical
  // notification once per stale period if one has gone silent.
  const heartbeatTimer = setInterval(() => {
    heartbeatService.checkAll().catch((err) => logger.warn('[heartbeat] checkAll threw', { message: err.message }));
  }, 60 * 60 * 1000);
  heartbeatTimer.unref();
  heartbeatService.checkAll().catch(() => {});

  function shutdown(signal) {
    logger.info(`${signal} received — shutting down gracefully...`);
    // End every open SSE stream first — otherwise server.close() waits on
    // them (they never finish on their own) and the 10s force-timer fires.
    sseHub.closeAll();
    server.close(async () => {
      try {
        await db.closePool();
      } finally {
        logger.info('Shutdown complete.');
        process.exit(0);
      }
    });
    // Force-exit if graceful shutdown hangs.
    setTimeout(() => process.exit(1), 10_000).unref();
  }

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  process.on('unhandledRejection', (reason) => {
    logger.error('Unhandled promise rejection', { message: reason?.message || String(reason), stack: reason?.stack });
  });

  process.on('uncaughtException', (err) => {
    logger.error('Uncaught exception — exiting', { message: err.message, stack: err.stack });
    process.exit(1);
  });
}

main();
