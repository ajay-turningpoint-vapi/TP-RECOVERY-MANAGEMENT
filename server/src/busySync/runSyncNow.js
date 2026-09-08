/**
 * Manual sync trigger for local testing — `npm run sync:busy`. Not the
 * production trigger path (that's the BullMQ worker + the admin dashboard's
 * "Run sync now" button); this exists purely so the sync can be exercised
 * without starting the whole worker process.
 */
require('dotenv').config();
const logger = require('../config/logger');
const { closePool } = require('../config/db');
const { runCustomerAgeingSync } = require('./sync/customerAgeingSync');
const { runCustomerInvoiceSync } = require('./sync/customerInvoiceSync');

async function main() {
  try {
    const resultAgeing = await runCustomerAgeingSync();
    if (!resultAgeing.ran) {
      logger.warn('[sync:busy] Skipped ageing — a sync run was already in progress.');
    }
    
    const resultInvoice = await runCustomerInvoiceSync();
    if (!resultInvoice.ran) {
      logger.warn('[sync:busy] Skipped invoice — a sync run was already in progress.');
    }
    process.exitCode = 0;
  } catch (err) {
    logger.error(`[sync:busy] Run failed: ${err.message}`);
    process.exitCode = 1;
  } finally {
    await closePool().catch(() => {});
    process.exit(process.exitCode);
  }
}

main();
