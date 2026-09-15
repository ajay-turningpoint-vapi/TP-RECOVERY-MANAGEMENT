/**
 * GET /api/events — one long-lived Server-Sent Events stream per client.
 * Replaces the old 10s/45s/90s client polling: the server pushes tiny
 * "these lists changed" events (realtime/eventBus.js) via Redis pub/sub
 * and the client re-fetches just those lists.
 *
 * Auth reuses the standard `Authorization: Bearer` header (the Flutter
 * client controls its own headers, so no ?token= variant is needed).
 */
const { Router } = require('express');
const { authenticate } = require('../middleware/auth');
const syncLockService = require('../services/syncLockService');
const sseHub = require('../realtime/sseHub');
const logger = require('../config/logger');

const HEARTBEAT_MS = 20_000;

const router = Router();
router.use(authenticate);

router.get('/', async (req, res) => {
  res.status(200);
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no'); // disable nginx proxy buffering
  res.flushHeaders();

  const entry = sseHub.add(res, req.user);
  logger.info('[sse] client connected', { userId: req.user.id, role: req.user.role, clients: sseHub.clientCount() });
  res.write(': connected\n\n');

  // Push the current sync-freeze state immediately so a client that
  // connects mid-sync shows the overlay without waiting for the next
  // begin/end transition.
  try {
    const since = await syncLockService.syncingSince();
    if (since) sseHub.write(res, 'sync', { type: 'sync', phase: 'started', since });
  } catch (err) {
    logger.warn('[sse] initial sync-state read failed', { message: err.message });
  }

  const heartbeat = setInterval(() => {
    try {
      res.write(': ping\n\n');
    } catch (_) {
      /* cleaned up by the close handler */
    }
  }, HEARTBEAT_MS);

  req.on('close', () => {
    clearInterval(heartbeat);
    sseHub.remove(entry);
  });
});

module.exports = router;
