import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { loginAdmin, requireAdmin } from '../auth/adminAuth';
import { getLatestRun, getRecentRuns, isRunInProgress } from '../repositories/syncRunsRepository';
import { getTotalCustomerCount } from '../repositories/customerAgeingRepository';
import {
  startCustomerAgeingSyncInBackground,
  getSyncProgress,
} from '../sync/customerAgeingSync';
import { MssqlCustomerReportRepository } from '../reports/customer/mssqlCustomerReportRepository';
import { MariaDbCustomerReportRepository } from '../reports/customer/mariaDbCustomerReportRepository';
import { compareCustomerReports } from '../validation/customerReportComparator';
import mssqlDb from '../config/mssql';
import { ping as pingMariaDb } from '../config/mariadb';
import logger from '../utils/logger';

const router = Router();
const mssqlReportRepository = new MssqlCustomerReportRepository();
const mariaDbReportRepository = new MariaDbCustomerReportRepository();

// Brute-force guard on the one login endpoint — 10 attempts per 15
// minutes per IP. Deliberately generous (a real admin fat-fingering a
// password a few times shouldn't get locked out) while still shutting
// down a credential-stuffing script.
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many login attempts. Try again in a few minutes.' },
});

router.post('/login', loginLimiter, async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) {
    res.status(400).json({ message: 'username and password are required.' });
    return;
  }

  const token = await loginAdmin(username, password);
  if (!token) {
    res.status(401).json({ message: 'Invalid credentials.' });
    return;
  }

  res.json({ token });
});

// Everything below requires a valid admin JWT.
router.use(requireAdmin);

/** Full sync system status: BUSY/MariaDB connectivity, last run, live progress while a run is in flight, total mirrored rows. */
router.get('/sync/status', async (req, res) => {
  try {
    const [latestRun, running, totalCustomers, mariaDbHealthy] = await Promise.all([
      getLatestRun(),
      isRunInProgress(),
      getTotalCustomerCount(),
      pingMariaDb().then(() => true).catch(() => false),
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
  } catch (err: any) {
    logger.error(`[admin] /sync/status failed: ${err.message}`);
    res.status(500).json({ message: 'Failed to load sync status.', error: err.message });
  }
});

/** Recent sync_runs history (most recent first). */
router.get('/sync/runs', async (req, res) => {
  try {
    const limit = req.query.limit ? parseInt(String(req.query.limit), 10) : 20;
    const runs = await getRecentRuns(limit);
    res.json({ runs });
  } catch (err: any) {
    logger.error(`[admin] /sync/runs failed: ${err.message}`);
    res.status(500).json({ message: 'Failed to load sync history.', error: err.message });
  }
});

/**
 * Starts a sync run and returns immediately (202) once the concurrency
 * lock is decided — it does NOT wait for the sync to finish. The
 * dashboard polls GET /sync/status (isRunning + progress) to show a real
 * progress bar rather than the request hanging open for the whole run.
 */
router.post('/sync/trigger', async (req, res) => {
  try {
    const { started } = await startCustomerAgeingSyncInBackground();
    if (!started) {
      res.status(409).json({ message: 'A sync run is already in progress.' });
      return;
    }
    res.status(202).json({ message: 'Sync started.' });
  } catch (err: any) {
    logger.error(`[admin] /sync/trigger failed: ${err.message}`);
    res.status(500).json({ message: 'Failed to start sync.', error: err.message });
  }
});

/** On-demand BUSY-vs-MariaDB validation (the comparator, run live). */
router.post('/sync/validate', async (req, res) => {
  try {
    const [busyRows, mariaDbRows] = await Promise.all([
      mssqlReportRepository.getCustomers(),
      mariaDbReportRepository.getCustomers(),
    ]);
    const result = compareCustomerReports(busyRows, mariaDbRows);
    // Cap the differences payload sent to the browser — the comparator
    // already computed the true counts, this just avoids a huge response.
    res.json({ ...result, differences: result.differences.slice(0, 100) });
  } catch (err: any) {
    logger.error(`[admin] /sync/validate failed: ${err.message}`);
    res.status(500).json({ message: 'Validation failed.', error: err.message });
  }
});

export default router;
