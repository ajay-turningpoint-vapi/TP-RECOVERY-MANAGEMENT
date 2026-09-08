/**
 * BUSY sync system status/controls — merged from the standalone backend1/
 * admin dashboard. Authenticates via the same /api/auth/login as
 * everyone else (no separate admin login); gated to MANAGEMENT.
 */
const { Router } = require('express');
const asyncHandler = require('../middleware/asyncHandler');
const { authenticate, authorize } = require('../middleware/auth');
const mssqlDb = require('../busySync/config/mssqlClient').mssqlDb;
const db = require('../config/db');
const syncRunsRepository = require('../busySync/repositories/syncRunsRepository');
const customerAgeingRepository = require('../busySync/repositories/customerAgeingRepository');
const { startCustomerAgeingSyncInBackground, getSyncProgress } = require('../busySync/sync/customerAgeingSync');
const mssqlCustomerReportRepository = require('../busySync/reports/mssqlCustomerReportRepository');
const mariaDbCustomerReportRepository = require('../busySync/reports/mariaDbCustomerReportRepository');
const { compareCustomerReports } = require('../busySync/validation/customerReportComparator');

const router = Router();
router.use(authenticate, authorize('MANAGEMENT'));

router.get(
  '/sync/status',
  asyncHandler(async (req, res) => {
    const [latestRun, running, totalCustomers, mariaDbHealthy] = await Promise.all([
      syncRunsRepository.getLatestRun(),
      syncRunsRepository.isRunInProgress(),
      customerAgeingRepository.getTotalCustomerCount(),
      db
        .ping()
        .then(() => true)
        .catch(() => false),
    ]);

    res.json({
      isRunning: running,
      progress: running ? getSyncProgress() : null,
      lastRun: latestRun,
      totalCustomers,
      connectivity: {
        mssqlConnected: mssqlDb.isConnected,
        mssqlLastError: mssqlDb.lastError,
        mariaDbHealthy,
      },
    });
  })
);

router.get(
  '/sync/runs',
  asyncHandler(async (req, res) => {
    const limit = req.query.limit ? parseInt(req.query.limit, 10) : 20;
    const runs = await syncRunsRepository.getRecentRuns(limit);
    res.json({ runs });
  })
);

router.post(
  '/sync/trigger',
  asyncHandler(async (req, res) => {
    const { started } = await startCustomerAgeingSyncInBackground();
    if (!started) {
      res.status(409).json({ message: 'A sync run is already in progress.' });
      return;
    }
    res.status(202).json({ message: 'Sync started.' });
  })
);

router.post(
  '/sync/validate',
  asyncHandler(async (req, res) => {
    const [busyRows, mariaDbRows] = await Promise.all([
      mssqlCustomerReportRepository.getCustomers(),
      mariaDbCustomerReportRepository.getCustomers(),
    ]);
    const result = compareCustomerReports(busyRows, mariaDbRows);
    res.json({ ...result, differences: result.differences.slice(0, 100) });
  })
);

module.exports = router;
