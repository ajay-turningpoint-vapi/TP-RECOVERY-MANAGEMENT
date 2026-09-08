import IORedis from 'ioredis';
import { config } from '../src/config.js';

const client = new IORedis({ host: config.redis.host, port: config.redis.port, db: config.redis.db, lazyConnect: true, maxRetriesPerRequest: 1 });

try {
  await client.connect();
  await client.ping();
  console.log(`Redis reachable at ${config.redis.host}:${config.redis.port} (db ${config.redis.db}).`);
  await client.quit();
  process.exit(0);
} catch (err) {
  console.error(`\nRedis is not reachable at ${config.redis.host}:${config.redis.port}.`);
  console.error('Start it with one of:');
  console.error('  redis-server --daemonize yes');
  console.error('  docker compose up -d');
  console.error(`\nUnderlying error: ${err.message}\n`);
  process.exit(1);
}
