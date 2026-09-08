const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '..', '..', '.env') });

function required(name) {
  const value = process.env[name];
  if (value === undefined || value === '') {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const PLACEHOLDER_JWT_SECRET = 'change-this-to-a-long-random-string-before-any-real-deployment';

const env = {
  nodeEnv: process.env.NODE_ENV || 'development',
  isProduction: process.env.NODE_ENV === 'production',
  isTest: process.env.NODE_ENV === 'test',
  port: parseInt(process.env.PORT || '4000', 10),

  db: {
    host: required('MARIADB_HOST'),
    port: parseInt(process.env.MARIADB_PORT || '3306', 10),
    user: required('MARIADB_USER'),
    password: process.env.MARIADB_PASSWORD || '',
    database: required('MARIADB_DATABASE'),
    connectionLimit: parseInt(process.env.MARIADB_CONNECTION_LIMIT || '10', 10),
  },

  jwt: {
    secret: required('JWT_SECRET'),
    // Short-lived on purpose now that refresh tokens exist (see
    // refreshTokenRepository.js / authService.js) — a leaked access token
    // used to stay valid for 12h with no way to revoke it; now it's only
    // ever useful for a short window, and the real, revocable session
    // lives in the refresh_tokens table instead.
    expiresIn: process.env.JWT_EXPIRES_IN || '1h',
  },

  refreshToken: {
    ttlDays: parseInt(process.env.REFRESH_TOKEN_TTL_DAYS || '30', 10),
  },

  redis: {
    url: process.env.REDIS_URL || 'redis://127.0.0.1:6379',
    // Namespaces BullMQ's Redis keys so the test suite's jobs can never be
    // picked up by the real dev/prod worker (or vice versa) — they share
    // the same Redis instance in this environment, but a different key
    // prefix makes them entirely separate queues.
    prefix: process.env.NODE_ENV === 'test' ? 'bull-test' : 'bull',
  },

  corsOrigins: (process.env.CORS_ORIGINS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),

  // The real-world timezone every "00:00" / "17:00" business schedule
  // means — passed explicitly to every BullMQ cron pattern (see
  // queues/busySyncQueue.js, queues/snapshotQueue.js) rather than relying
  // on the host OS's timezone. This dev machine happens to already be IST,
  // so an implicit (unset) tz works here today — but most cloud VM images
  // default to UTC, and an implicit tz would silently fire the daily
  // sync at 5:30am IST and the "5 PM" snapshot at 10:30pm IST the moment
  // this deploys to a real server. Never rely on host tz for business-hour
  // scheduling.
  businessTimezone: process.env.BUSINESS_TIMEZONE || 'Asia/Kolkata',

  logLevel: process.env.LOG_LEVEL || 'info',
};

// A placeholder secret in production means every JWT this server issues can
// be forged by anyone who has read this file on GitHub — refuse to boot
// rather than silently run insecure.
if (env.isProduction && env.jwt.secret === PLACEHOLDER_JWT_SECRET) {
  throw new Error('JWT_SECRET is still the placeholder value — set a real random secret before running in production.');
}

module.exports = env;
