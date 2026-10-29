const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const logger = require('../config/logger');
const { QUEUE_NAME } = require('../queues/busySyncQueue');
const notificationRepository = require('../repositories/notificationRepository');
const { beat } = require('../services/heartbeatService');
const { publish } = require('../realtime/eventBus');
const { runFullBusySync } = require('../services/busySyncPipeline');

function createBusySyncWorker() {
  const worker = new Worker(
    QUEUE_NAME,
    async () => {
      // Same pipeline as the Admin "Sync" button and the CLI — see
      // services/busySyncPipeline.js.
      const result = await runFullBusySync({ logPrefix: '[busySyncWorker]' });
      await beat('busy-sync');
      return result;
    },
    { connection, prefix: env.redis.prefix, concurrency: 1 }
  );

  worker.on('failed', (job, err) => {
    logger.error('BUSY customer sync job failed', { jobId: job?.id, message: err.message });

    // BullMQ fires 'failed' on every attempt, not just the last one —
    // alerting here unconditionally would raise a false alarm for a
    // transient error the retry (attempts: 2) goes on to fix by itself.
    // Only once every attempt is exhausted does this become something a
    // real person needs to act on — real customer data is now stale until
    // someone intervenes, which previously had zero user-facing signal
    // (only a server log line and a sync_runs row nobody proactively
    // checks).
    const attemptsMade = job?.attemptsMade ?? 0;
    const maxAttempts = job?.opts?.attempts ?? 1;
    if (job && attemptsMade >= maxAttempts) {
      notificationRepository
        .insert({
          severity: 'critical',
          title: 'BUSY sync failed — customer data may be stale',
          body: `The BUSY customer sync failed after ${attemptsMade} automatic attempt(s): ${err.message}. Customer balances/ageing will not reflect BUSY until the connection is back and a sync succeeds; the next scheduled run is 12:00 IST.`,
        })
        .then(() => publish({ type: 'notification', scope: { broadcast: true } }))
        .catch((notifyErr) => {
          logger.error('Failed to record BUSY sync failure notification', { message: notifyErr.message });
        });
    }
  });

  return worker;
}

module.exports = { createBusySyncWorker };
