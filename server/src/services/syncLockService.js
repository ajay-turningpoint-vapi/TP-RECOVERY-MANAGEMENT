const { connection } = require('../config/redis');
const { publish } = require('../realtime/eventBus');

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

// Safety valve: if the sync process is KILLED (SIGKILL, OOM, crash) between
// beginSync() and its `finally { endSync() }`, the counter is never
// decremented and — with no expiry — every client stays frozen behind the
// "Syncing with BUSY" curtain forever (observed in the field: a killed
// manual sync left the app locked for 30+ min). Both keys carry a TTL that
// is comfortably longer than any real sync but short enough that a dead
// lock clears itself. endSync() still deletes them immediately on the
// normal path; this only matters when that path never runs.
const LOCK_TTL_SECONDS = 20 * 60;

/** Call before a sync-affecting step starts; pair with endSync() in a finally. */
async function beginSync() {
  const count = await connection.incr(COUNT_KEY);
  // Always (re)arm the TTL — every wrapped section pushes the dead-lock
  // deadline out, so a long-but-healthy multi-step job never expires mid-run.
  await connection.expire(COUNT_KEY, LOCK_TTL_SECONDS);
  if (count === 1) {
    const since = new Date().toISOString();
    await connection.set(SINCE_KEY, since, 'EX', LOCK_TTL_SECONDS);
    // Runs in the worker process — the event reaches API-connected clients
    // via Redis pub/sub and drives the freeze overlay in real time.
    publish({ type: 'sync', phase: 'started', since });
  } else {
    await connection.expire(SINCE_KEY, LOCK_TTL_SECONDS);
  }
}

async function endSync() {
  const count = await connection.decr(COUNT_KEY);
  if (count <= 0) {
    // Both cleared together — never leave a dangling `since` with no
    // matching counter (e.g. after a decr past 0 from a bug elsewhere).
    await Promise.all([connection.del(COUNT_KEY), connection.del(SINCE_KEY)]);
    publish({ type: 'sync', phase: 'finished' });
  } else {
    // Still counting down other wrapped sections — keep the TTL fresh.
    await connection.expire(COUNT_KEY, LOCK_TTL_SECONDS);
  }
}

/**
 * Force-clear the sync lock regardless of the counter — for recovering
 * from a stale lock left by a killed sync process. Publishes `finished`
 * so every connected client drops the freeze overlay immediately.
 */
async function forceClear() {
  await Promise.all([connection.del(COUNT_KEY), connection.del(SINCE_KEY)]);
  publish({ type: 'sync', phase: 'finished' });
}

/** ISO start timestamp if a sync is in progress, else null. */
async function syncingSince() {
  return connection.get(SINCE_KEY);
}

module.exports = { beginSync, endSync, forceClear, syncingSince, LOCK_TTL_SECONDS };
