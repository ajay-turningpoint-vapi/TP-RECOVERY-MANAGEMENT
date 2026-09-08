const { connection } = require('../config/redis');

// A single Redis-backed flag spanning the *entire* daily BUSY sync —
// customer ageing sync, invoice sync, and PTP verification/reconciliation
// all run back-to-back inside one worker job (see workers/busySyncWorker.js),
// and the ageing sync alone can also be kicked off separately by the
// MANAGEMENT admin dashboard's manual trigger (see
// busySync/sync/customerAgeingSync.js's runLocked, which every caller goes
// through). Every active client polls this (GET /api/sync-status) and
// shows a full-screen "syncing, please wait" overlay for as long as it's
// set, since real customer/PTP/task data is being rewritten underneath
// them and reads/writes during that window could see a half-synced state.
//
// Reference-counted (INCR/DECR), not a plain boolean SET/DEL: the worker's
// three-step job and a manual ageing-only trigger can overlap in principle,
// and even within one worker job each step is wrapped individually for
// safety — a plain boolean would have the *inner* step's cleanup clear the
// flag while the *outer* job still has more steps to run, reopening the
// app to users mid-sync. The counter only truly reaches "not syncing" once
// every wrapped section has actually finished.
const COUNT_KEY = 'sync:in-progress:count';
const SINCE_KEY = 'sync:in-progress:since';

/** Call before a sync-affecting step starts; pair with endSync() in a finally. */
async function beginSync() {
  const count = await connection.incr(COUNT_KEY);
  if (count === 1) {
    await connection.set(SINCE_KEY, new Date().toISOString());
  }
}

async function endSync() {
  const count = await connection.decr(COUNT_KEY);
  if (count <= 0) {
    // Both cleared together — never leave a dangling `since` with no
    // matching counter (e.g. after a decr past 0 from a bug elsewhere).
    await Promise.all([connection.del(COUNT_KEY), connection.del(SINCE_KEY)]);
  }
}

/** ISO start timestamp if a sync is in progress, else null. */
async function syncingSince() {
  return connection.get(SINCE_KEY);
}

module.exports = { beginSync, endSync, syncingSince };
