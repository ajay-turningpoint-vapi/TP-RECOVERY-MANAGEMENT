import { Worker } from 'bullmq';
import { createConnection } from '../redis-connection.js';
import { attachDeadLetterHandling } from '../events/dead-letter-listener.js';
import { logger } from '../logger.js';

export function createDomainWorker(queueName, processor, options = {}) {
  const worker = new Worker(queueName, processor, {
    connection: createConnection(),
    concurrency: options.concurrency ?? 5,
    // Lock duration must comfortably exceed the slowest realistic job for
    // this queue, or BullMQ will consider a healthy-but-slow job "stalled"
    // and hand it to another worker mid-flight.
    lockDuration: options.lockDuration ?? 30000,
    lockRenewTime: options.lockRenewTime,
    maxStalledCount: options.maxStalledCount ?? 2,
    stalledInterval: options.stalledInterval ?? 30000,
    limiter: options.limiter,
  });

  worker.on('completed', (job) => logger.debug({ queueName, jobId: job.id, jobName: job.name }, 'Job completed'));
  worker.on('error', (err) => logger.error({ queueName, err: err?.message }, 'Worker-level error'));
  attachDeadLetterHandling(worker, queueName);
  return worker;
}
