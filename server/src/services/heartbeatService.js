const { connection } = require('../config/redis');
const notificationRepository = require('../repositories/notificationRepository');
const logger = require('../config/logger');

const KEY = (name) => `hb:${name}`;
const ALERTED = (name) => `hb:alerted:${name}`;

// Each scheduled job that MUST keep running, and how long "silent" is
// suspicious for it. If a job hasn't beaten within its window the API
// server (which runs this check, and is more likely up than the worker)
// raises a critical notification — once — until the job beats again.
const JOBS = {
  'busy-sync': 26 * 60 * 60 * 1000, // daily noon
  'ptp-verify': 26 * 60 * 60 * 1000, // daily 12:10
  'sweeps-2h': 5 * 60 * 60 * 1000, // every 2h
};

/** A job calls this on every successful run. */
async function beat(name) {
  try {
    await connection.set(KEY(name), String(Date.now()));
    await connection.del(ALERTED(name));
  } catch (err) {
    logger.warn('[heartbeat] beat failed', { name, message: err.message });
  }
}

/** Run periodically on the API server. Alerts once per stale period. */
async function checkAll() {
  const now = Date.now();
  for (const [name, maxAgeMs] of Object.entries(JOBS)) {
    try {
      const last = Number(await connection.get(KEY(name)));
      // No heartbeat yet (fresh deploy) — give it one window before alerting.
      const age = last ? now - last : maxAgeMs / 2;
      if (age <= maxAgeMs) continue;
      if (await connection.get(ALERTED(name))) continue; // already alerted this stale period
      await connection.set(ALERTED(name), '1', 'EX', 24 * 60 * 60);
      const hrs = Math.round(age / 3600000);
      await notificationRepository.insert({
        severity: 'critical',
        title: `Background job "${name}" has not run`,
        body: `The "${name}" job last succeeded ~${hrs}h ago (limit ${Math.round(maxAgeMs / 3600000)}h). PTP verification / follow-up sweeps may be stalled — check the worker process.`,
      });
      logger.error(`[heartbeat] "${name}" stale by ~${hrs}h — critical notification raised.`);
    } catch (err) {
      logger.warn('[heartbeat] check failed', { name, message: err.message });
    }
  }
}

module.exports = { beat, checkAll };
