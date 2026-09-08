/**
 * Universal sync-freeze signal — every authenticated role (not just
 * MANAGEMENT, unlike /api/busy-sync/sync/status) polls this to know
 * whether the daily BUSY sync job is currently running, so the client can
 * show a full-screen "syncing, please wait" overlay for its duration. See
 * services/syncLockService.js and workers/busySyncWorker.js.
 */
const { Router } = require('express');
const asyncHandler = require('../middleware/asyncHandler');
const { authenticate } = require('../middleware/auth');
const syncLockService = require('../services/syncLockService');

const router = Router();
router.use(authenticate);

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const since = await syncLockService.syncingSince();
    res.json({ syncing: since !== null, since });
  })
);

module.exports = router;
