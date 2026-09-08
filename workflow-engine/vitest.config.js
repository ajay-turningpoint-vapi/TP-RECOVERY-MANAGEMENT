import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    // Real Redis + real BullMQ retries/backoff/delays genuinely take
    // seconds, especially the stalled-job-recovery and graceful-shutdown
    // suites — this is real execution time, not padding.
    testTimeout: 30000,
    hookTimeout: 30000,
    // BullMQ Worker/QueueEvents connections don't always love running
    // fully in parallel across files in one process; run test files
    // sequentially for determinism (still fast — this is not a large suite).
    fileParallelism: false,
  },
});
