const env = require('./config/env');
const logger = require('./config/logger');
const createApp = require('./app');
const db = require('./config/db');

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

  const app = createApp();
  const server = app.listen(env.port, () => {
    logger.info(`TP-RMS server listening on port ${env.port} (${env.nodeEnv})`);
  });

  function shutdown(signal) {
    logger.info(`${signal} received — shutting down gracefully...`);
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
