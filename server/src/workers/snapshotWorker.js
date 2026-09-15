const { Worker } = require('bullmq');
const { connection } = require('../config/redis');
const env = require('../config/env');
const { ping: pingDb } = require('../config/db');
const { QUEUE_NAME } = require('../queues/snapshotQueue');
const customerRepository = require('../repositories/customerRepository');
const ptpRepository = require('../repositories/ptpRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const metricsRepository = require('../repositories/metricsRepository');
const salesmanService = require('../services/salesmanService');
const scoringService = require('../services/scoringService');
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
 * The 5 PM control-batch snapshot is PERMANENTLY PAUSED as a recovery
 * actor. It used to auto-create a "no open action" follow-up task for
 * every at-risk customer once a day, every day — hundreds of tasks nobody
 * worked. That half is gone: the ONLY nightly recovery backstop is
 * `recoveryReconcileService.reconcileAll` (runs after the noon BUSY sync),
 * which retargets the single `source='Recovery'` task and never mass-creates.
 *
 * All this job does now is record one row of today's company-wide trend
 * metrics (`recordDailyMetrics`). It touches no tasks and no customer
 * state. It is also not scheduled or started by `worker.js` — it stays
 * here only so the trends report has a way to be refreshed if wanted.
 */
async function runSnapshot() {
  await pingDb();
  const customers = await customerRepository.findAll();
  await recordDailyMetrics(customers);
  const checked = customers.filter((c) => c.totalDue > 0).length;

  await notificationRepository.insert({
    severity: 'info',
    title: 'Daily trend metrics recorded',
    body: `Recorded today's company-wide recovery metrics across ${checked} customer(s) with money due. No tasks or customer state were changed.`,
  });

  logger.info('Daily metrics snapshot complete', { checked });
  return { checked, metricsRecorded: true };
}

function createSnapshotWorker() {
  const worker = new Worker(QUEUE_NAME, async () => runSnapshot(), { connection, prefix: env.redis.prefix, concurrency: 1 });

  worker.on('failed', (job, err) => {
    logger.error('Snapshot (metrics) job failed', { jobId: job?.id, message: err.message });
    const attemptsMade = job?.attemptsMade ?? 0;
    const maxAttempts = job?.opts?.attempts ?? 1;
    if (job && attemptsMade >= maxAttempts) {
      notificationRepository
        .insert({
          severity: 'warning',
          title: 'Daily trend metrics not recorded',
          body: `The daily metrics snapshot failed after ${attemptsMade} attempt(s): ${err.message}. Trend history has a gap for today.`,
        })
        .catch((notifyErr) => {
          logger.error('Failed to record snapshot failure notification', { message: notifyErr.message });
        });
    }
  });

  return worker;
}

module.exports = { createSnapshotWorker, runSnapshot };
