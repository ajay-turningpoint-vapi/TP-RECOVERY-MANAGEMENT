import 'dotenv/config';
import cron from 'node-cron';
import logger from './utils/logger';
import { closePool as closeMariaDbPool } from './config/mariadb';
import { runCustomerAgeingSync } from './sync/customerAgeingSync';
import { runCustomerInvoiceSync } from './sync/customerInvoiceSync';

const SCHEDULE = '0 0 * * *'; // 12:00 AM every day, server-local time

const task = cron.schedule(SCHEDULE, () => {
  runCustomerAgeingSync().catch((err) => {
    // Already logged with full detail inside runCustomerAgeingSync;
    // this catch only exists so an unhandled rejection can't kill the process.
    logger.error(`[scheduler] customer_ageing sync run threw: ${err.message}`);
  });
  runCustomerInvoiceSync().catch((err) => {
    logger.error(`[scheduler] customer_invoice sync run threw: ${err.message}`);
  });
});

logger.info(`[scheduler] customer_ageing & customer_invoice sync registered on cron schedule "${SCHEDULE}".`);

async function shutdown(signal: string) {
  logger.info(`[scheduler] Received ${signal}, shutting down...`);
  task.stop();
  await closeMariaDbPool().catch((err) =>
    logger.error(`[scheduler] Error closing MariaDB pool: ${err.message}`)
  );
  process.exit(0);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

process.on('unhandledRejection', (reason: any) => {
  logger.error(`[scheduler] Unhandled rejection: ${reason?.message || reason}`);
});
process.on('uncaughtException', (err) => {
  logger.error(`[scheduler] Uncaught exception: ${err.message}`, { stack: err.stack });
});
