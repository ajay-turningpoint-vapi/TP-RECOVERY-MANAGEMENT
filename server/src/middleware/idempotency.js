const idempotencyRepository = require('../repositories/idempotencyRepository');
const logger = require('../config/logger');

/**
 * Opt-in idempotency guard for mutating routes — see
 * db/migrations/033_idempotency_keys.sql. A caller that sends no
 * `X-Idempotency-Key` header (every existing screen, today) behaves
 * exactly as before; only the offline write-queue (lib/services/
 * pending_action_queue.dart) sends one, keyed by the queued action's own
 * client-generated UUID, so a retry after a lost response replays the
 * original result instead of re-executing the mutation (double-recording
 * an outcome, double-creating a PTP, etc.).
 *
 * Mounted per-router (after `authenticate`, before the controllers) on
 * every route file the write-queue's actions touch — see customerRoutes,
 * ptpRoutes, disputeRoutes, paymentClaimRoutes, taskRoutes.
 */
function idempotency() {
  return async function (req, res, next) {
    const key = req.get('X-Idempotency-Key');
    if (!key || req.method === 'GET') return next();

    try {
      const existing = await idempotencyRepository.find(key);
      if (existing) {
        res.status(existing.statusCode).json(JSON.parse(existing.responseBody));
        return;
      }
    } catch (err) {
      // A lookup failure must never block the request — fall through and
      // execute normally, same as if no key had been sent at all.
      logger.error('[idempotency] lookup failed', { message: err.message });
      return next();
    }

    // Wrap res.json so whichever handler eventually responds (the
    // controller, or errorHandler.js on a thrown error — both call
    // res.json on this same response object) gets its result persisted
    // once, before it goes out.
    const originalJson = res.json.bind(res);
    res.json = (body) => {
      idempotencyRepository.save(key, req.originalUrl, res.statusCode, body).catch((err) => {
        logger.error('[idempotency] failed to persist response', { message: err.message });
      });
      return originalJson(body);
    };
    next();
  };
}

module.exports = idempotency;
