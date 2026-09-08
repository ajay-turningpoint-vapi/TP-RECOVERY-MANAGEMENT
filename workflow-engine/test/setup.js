import IORedis from 'ioredis';
import { config } from '../src/config.js';
import { state } from '../src/store/state.js';
import { closeAllQueues } from '../src/queues/index.js';
import { flushPendingDeadLetters } from '../src/events/dead-letter-listener.js';

// config.redis.db resolves to REDIS_TEST_DB (default 1) whenever
// NODE_ENV=test, which is how every test file reaches this module — see
// src/config.js. Flushing here only ever targets that isolated DB index.
export async function flushTestRedis() {
  const client = new IORedis({ host: config.redis.host, port: config.redis.port, db: config.redis.db, maxRetriesPerRequest: null });
  await client.flushdb();
  await client.quit();
}

export function resetState() {
  state.reset();
}

export async function fullReset() {
  resetState();
  await flushTestRedis();
}

export async function teardownQueues() {
  await flushPendingDeadLetters();
  await closeAllQueues();
}
