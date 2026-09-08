const asyncHandler = require('../middleware/asyncHandler');
const db = require('../config/db');

let dbHealthy = false;
let lastDbCheck = null;

async function refreshDbHealth() {
  try {
    await db.ping();
    dbHealthy = true;
  } catch {
    dbHealthy = false;
  }
  lastDbCheck = new Date().toISOString();
  return dbHealthy;
}

// Liveness: is the process itself up? No dependency checks — used by an
// orchestrator to decide whether to restart the container.
const live = (req, res) => {
  res.json({ status: 'ok', uptimeSeconds: Math.round(process.uptime()) });
};

// Readiness: is the service actually able to serve traffic right now
// (i.e. can it reach the database)? Used to gate load-balancer routing.
const ready = asyncHandler(async (req, res) => {
  const healthy = await refreshDbHealth();
  res.status(healthy ? 200 : 503).json({
    status: healthy ? 'ok' : 'unavailable',
    database: healthy ? 'connected' : 'unreachable',
    lastCheckedAt: lastDbCheck,
  });
});

module.exports = { live, ready };
