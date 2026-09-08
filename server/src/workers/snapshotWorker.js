const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const { withTransaction, ping: pingDb } = require('../config/db');
const { QUEUE_NAME } = require('../queues/snapshotQueue');
const customerRepository = require('../repositories/customerRepository');
const ptpRepository = require('../repositories/ptpRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const metricsRepository = require('../repositories/metricsRepository');
const salesmanService = require('../services/salesmanService');
const scoringService = require('../services/scoringService');
const taskService = require('../services/taskService');
const notificationRepository = require('../repositories/notificationRepository');
const logger = require('../config/logger');

const MATURED_STATUSES = ['kept', 'partiallyKept', 'broken'];

/**
 * Records one real row of today's company-wide metrics — the honest
 * replacement for the client's former hardcoded-zero trend history. Only
 * ever as many rows exist as days this job has genuinely run; no
 * backfill, no fabricated placeholder history.
 */
async function recordDailyMetrics(customers) {
  const [roster, allPtps, allTasks, allAudit] = await Promise.all([
    salesmanService.listRoster(),
    ptpRepository.findAll(),
    taskRepository.findAll(),
    auditRepository.listAll(),
  ]);

  const avgRecoveryScore = roster.length === 0 ? 0 : roster.reduce((s, r) => s + r.recoveryScore, 0) / roster.length;
  const maturedPtps = allPtps.filter((p) => MATURED_STATUSES.includes(p.status));
  const brokenPtpCount = allPtps.filter((p) => p.status === 'broken').length;
  const collectionExpected = allPtps.reduce((s, p) => s + p.amountPromised, 0);
  const collectionActual = maturedPtps.reduce((s, p) => s + (p.amountReceived || 0), 0);

  const tasksByCustomer = scoringService.groupBy(allTasks, (t) => t.customerId);
  const auditByCustomer = scoringService.groupBy(allAudit, (a) => a.customerId);
  const noFollowUpCount = customers.filter(
    (c) => c.totalDue > 0 && scoringService.daysSinceLastFollowUp(c, tasksByCustomer.get(c.id) || [], auditByCustomer.get(c.id) || []) >= 4
  ).length;

  await metricsRepository.upsertToday({
    avgRecoveryScore: Number(avgRecoveryScore.toFixed(2)),
    ptpAmountTotal: allPtps.reduce((s, p) => s + p.amountPromised, 0),
    brokenPtpCount,
    collectionExpected,
    collectionActual,
    noFollowUpCount,
  });
}

/**
 * The 5 PM control-batch snapshot: a safety net over the whole customer
 * book, not just the customer a single request happens to be touching.
 * Anything left with money due and no open task/PTP — a broken PTP that
 * never got a follow-up task, a manually-edited record, anything — gets
 * one created here, same guard as `taskService.completeTask`.
 *
 * Runs one customer per transaction rather than one big transaction, so a
 * problem with a single customer can't roll back the whole batch.
 */
async function runSnapshot() {
  await pingDb();
  const customers = await customerRepository.findAll();
  const atRisk = customers.filter((c) => c.totalDue > 0);

  let reopenedCount = 0;
  for (const customer of atRisk) {
    try {
      const reopened = await withTransaction((conn) =>
        taskService.ensureFollowUpIfNeeded(
          customer.id,
          null,
          {
            reason: '5 PM control snapshot found no open action',
            auditType: 'SNAPSHOT_REOPENED_RECOVERY',
            source: 'Daily Snapshot',
          },
          conn
        )
      );
      if (reopened) reopenedCount += 1;
    } catch (err) {
      logger.error('Snapshot failed for customer', { customerId: customer.id, message: err.message });
    }
  }

  await recordDailyMetrics(customers);

  await notificationRepository.insert({
    severity: reopenedCount > 0 ? 'warning' : 'info',
    title: '5 PM control snapshot complete',
    body: `Checked ${atRisk.length} customer(s) with money due. Reopened recovery on ${reopenedCount} that had no open task or PTP.`,
  });

  logger.info('Daily snapshot complete', { checked: atRisk.length, reopened: reopenedCount });
  return { checked: atRisk.length, reopened: reopenedCount };
}

function createSnapshotWorker() {
  const worker = new Worker(QUEUE_NAME, async () => runSnapshot(), { connection, prefix: env.redis.prefix, concurrency: 1 });

  worker.on('failed', (job, err) => {
    logger.error('Snapshot job failed', { jobId: job?.id, message: err.message });

    // Same reasoning as busySyncWorker's failure notification: 'failed'
    // fires on every attempt, so only alert once retries are exhausted —
    // a run that throws before reaching its own success-notification never
    // tells anyone anything otherwise (no reopened-recovery safety net ran
    // today, silently).
    const attemptsMade = job?.attemptsMade ?? 0;
    const maxAttempts = job?.opts?.attempts ?? 1;
    if (job && attemptsMade >= maxAttempts) {
      notificationRepository
        .insert({
          severity: 'critical',
          title: '5 PM control snapshot failed',
          body: `The daily 5 PM control-batch snapshot failed after ${attemptsMade} attempt(s): ${err.message}. Today's automatic "no open action" safety-net check did not run.`,
        })
        .catch((notifyErr) => {
          logger.error('Failed to record snapshot failure notification', { message: notifyErr.message });
        });
    }
  });

  return worker;
}

module.exports = { createSnapshotWorker, runSnapshot };
