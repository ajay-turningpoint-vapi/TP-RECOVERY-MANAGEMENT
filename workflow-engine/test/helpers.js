import { QueueEvents } from 'bullmq';
import { createConnection } from '../src/redis-connection.js';

const queueEventsCache = new Map();

export function queueEventsFor(name) {
  if (!queueEventsCache.has(name)) {
    queueEventsCache.set(name, new QueueEvents(name, { connection: createConnection() }));
  }
  return queueEventsCache.get(name);
}

export async function closeAllQueueEvents() {
  await Promise.all([...queueEventsCache.values()].map((qe) => qe.close()));
  queueEventsCache.clear();
}

export async function addAndWait(queue, name, data, opts) {
  // Warm the QueueEvents subscription BEFORE adding the job, not after —
  // for a job that completes very fast (e.g. a Flow parent picked up by an
  // already-blocking worker), adding the job first can let it finish
  // before a lazily-created QueueEvents connection has even subscribed,
  // permanently missing the "completed" pub/sub message and hanging
  // waitUntilFinished forever. Same race found for real in
  // busy-sync.processor.js's own Flow wait — see the comment there.
  const qe = queueEventsFor(queue.name);
  await qe.waitUntilReady();
  const job = await queue.add(name, data, opts);
  return job.waitUntilFinished(qe);
}

export function waitForCondition(predicate, { timeout = 10000, interval = 100 } = {}) {
  const start = Date.now();
  return (async function poll() {
    while (Date.now() - start < timeout) {
      const result = await predicate();
      if (result) return result;
      await new Promise((r) => setTimeout(r, interval));
    }
    throw new Error('waitForCondition timed out');
  })();
}
