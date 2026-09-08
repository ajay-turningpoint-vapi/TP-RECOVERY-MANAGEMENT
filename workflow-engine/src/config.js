const num = (v, fallback) => (v === undefined || v === '' ? fallback : Number(v));

export const config = {
  redis: {
    host: process.env.REDIS_HOST || '127.0.0.1',
    port: num(process.env.REDIS_PORT, 6379),
    db: num(process.env.NODE_ENV === 'test' ? process.env.REDIS_TEST_DB : process.env.REDIS_DB, process.env.NODE_ENV === 'test' ? 1 : 0),
  },
  noAnswer: {
    threshold: num(process.env.NO_ANSWER_THRESHOLD, 3),
    visitDeadlineHours: num(process.env.NO_ANSWER_VISIT_DEADLINE_HOURS, 24),
  },
  busySync: {
    intervalMs: num(process.env.BUSY_SYNC_INTERVAL_MS, 300000),
  },
  fivePmControl: {
    cron: process.env.FIVE_PM_CONTROL_CRON || '0 17 * * *',
  },
  logLevel: process.env.LOG_LEVEL || 'info',
};
