import { Queue } from 'bullmq';
import { createConnection } from '../redis-connection.js';
import { QUEUE_NAMES } from './names.js';

const queues = new Map();
const connections = [];

// Standard retention: keep a bounded window of completed/failed jobs so
// Redis memory doesn't grow unbounded in a long-running process, while
// still keeping enough failed-job history to debug from (dead-letter
// handling additionally persists full context for failed jobs — see
// events/dead-letter-listener.js — so aggressive completed-job pruning
// here is safe).
const DEFAULT_JOB_OPTIONS = {
  attempts: 5,
  backoff: { type: 'exponential', delay: 2000 },
  removeOnComplete: { count: 1000, age: 24 * 3600 },
  removeOnFail: { count: 5000 },
};

export function getQueue(name, overrideDefaults = {}) {
  if (queues.has(name)) return queues.get(name);
  const connection = createConnection();
  connections.push(connection);
  const queue = new Queue(name, {
    connection,
    defaultJobOptions: { ...DEFAULT_JOB_OPTIONS, ...overrideDefaults },
  });
  queues.set(name, queue);
  return queue;
}

export function allQueues() {
  return Object.values(QUEUE_NAMES).map((name) => getQueue(name));
}

export async function closeAllQueues() {
  await Promise.all([...queues.values()].map((q) => q.close()));
  await Promise.all(connections.map((c) => c.quit().catch(() => c.disconnect())));
  queues.clear();
  connections.length = 0;
}

export { QUEUE_NAMES };
