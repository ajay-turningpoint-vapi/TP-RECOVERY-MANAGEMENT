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
const { publish, emitChange } = require('../realtime/eventBus');

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
    // This CLI path doesn't take the Redis sync lock (deliberately — it
    // doesn't freeze active clients), so it also never fires the `sync`
    // pub/sub event the API clients use to re-poll /api/sync-status. Fire
    // one here so a connected app refreshes its data AND clears / updates
    // the "sync failed" banner to match the run we just did.
    try {
      publish({ type: 'sync', phase: 'finished' });
      emitChange(['customers', 'ptps', 'tasks', 'salesmen', 'escalations'], { reason: 'busy.sync.cli' });
      // Give the fire-and-forget Redis publishes a moment to flush before exit.
      await new Promise((r) => setTimeout(r, 300));
    } catch (_) {
      /* best effort */
    }
    await closePool().catch(() => {});
    process.exit(process.exitCode);
  }
}

main();
