import 'dotenv/config';
import logger from './utils/logger';
import { closePool as closeMariaDbPool } from './config/mariadb';
import { runCustomerAgeingSync } from './sync/customerAgeingSync';
import { runCustomerInvoiceSync } from './sync/customerInvoiceSync';

async function main() {
  try {
    const resultAgeing = await runCustomerAgeingSync();
    if (!resultAgeing.ran) {
      logger.warn('[sync-now] Skipped customer ageing — a sync run was already in progress.');
    }

    const resultInvoice = await runCustomerInvoiceSync();
    if (!resultInvoice.ran) {
      logger.warn('[sync-now] Skipped customer invoice — a sync run was already in progress.');
    }
    process.exitCode = 0;
  } catch (err: any) {
    logger.error(`[sync-now] Run failed: ${err.message}`);
    process.exitCode = 1;
  } finally {
    await closeMariaDbPool().catch(() => {});
    process.exit(process.exitCode);
  }
}

main();
