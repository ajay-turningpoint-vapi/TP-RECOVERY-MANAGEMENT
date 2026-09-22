const appSettingsRepository = require('../repositories/appSettingsRepository');
const logger = require('../config/logger');
const { publish } = require('../realtime/eventBus');

const SETTING_KEY = 'maintenance_mode';

// In-memory cache — `middleware/auth.js` checks this on every authenticated
// request, so a DB round trip per request isn't worth it. Seeded from the
// DB at boot (init(), called once from server.js) so a restart doesn't
// silently clear an active maintenance window, and kept in sync the
// instant setEnabled() runs (this app is a single API process, so there's
// no cross-process cache to invalidate).
let cached = { enabled: false, since: null };

async function init() {
  const value = await appSettingsRepository.get(SETTING_KEY);
  const enabled = value === 'true';
  cached = { enabled, since: enabled ? new Date() : null };
  logger.info(`[maintenance] loaded at boot: ${enabled ? 'ON' : 'off'}`);
}

function isEnabled() {
  return cached.enabled;
}

function status() {
  return { enabled: cached.enabled, since: cached.since };
}

/**
 * Flips maintenance mode. While on, `middleware/auth.js`'s `authenticate`
 * rejects every request from a non-MANAGEMENT user with a 503
 * (MAINTENANCE_MODE), and authService.login refuses to even issue tokens
 * to one — MANAGEMENT is the one exception in both places, so a manager
 * always keeps a way back in to turn it off again. Pushes a real-time
 * event (see realtime/sseHub.js's 'maintenance' case) so every already-
 * connected client reacts instantly instead of waiting for its next
 * request to get rejected.
 */
async function setEnabled(enabled, managerId) {
  await appSettingsRepository.set(SETTING_KEY, enabled ? 'true' : 'false', managerId);
  cached = { enabled, since: enabled ? new Date() : null };
  publish({ type: 'maintenance', enabled, scope: { broadcast: true } });
  logger.info(`[maintenance] set to ${enabled ? 'ON' : 'off'} by ${managerId}`);
  return status();
}

module.exports = { init, isEnabled, status, setEnabled };
