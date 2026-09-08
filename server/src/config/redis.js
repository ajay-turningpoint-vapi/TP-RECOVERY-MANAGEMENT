const IORedis = require('ioredis');
const env = require('./env');
const logger = require('./logger');

// BullMQ requires this exact setting on any connection it's handed —
// it does its own retry/backoff and will misbehave if ioredis retries
// requests underneath it.
const connection = new IORedis(env.redis.url, {
  maxRetriesPerRequest: null,
  enableReadyCheck: false,
});

connection.on('error', (err) => {
  logger.error('Redis connection error', { message: err.message });
});

async function ping() {
  await connection.ping();
}

module.exports = { connection, ping };
