import IORedis from 'ioredis';
import { config } from './config.js';

// BullMQ requires maxRetriesPerRequest: null on any connection it manages,
// and works best with one dedicated ioredis connection per Queue/Worker/
// QueueEvents instance rather than a single shared client — sharing one
// client across blocking (BRPOPLPUSH-style) and non-blocking commands is a
// classic BullMQ misconfiguration that causes commands to hang under load.
export function createConnection(overrides = {}) {
  return new IORedis({
    host: config.redis.host,
    port: config.redis.port,
    db: config.redis.db,
    maxRetriesPerRequest: null,
    enableReadyCheck: true,
    ...overrides,
  });
}
