import { getQueue, QUEUE_NAMES } from '../queues/index.js';
import { logger } from '../logger.js';

/**
 * Standard BullMQ dead-letter pattern: a Worker's own `attempts`/`backoff`
 * handle transient failures, but once a job's retries are genuinely
 * exhausted it should not just vanish into `failed` — this captures full
 * context (queue, job name, data, error, attempt count) into a dedicated
 * dead-letter queue for manual inspection/replay, so nothing is silently
 * lost in production.
 */
// BullMQ's `worker.on('failed', ...)` callback is fire-and-forget from the
// event emitter's perspective — nothing awaits it, including
// `worker.close()`. Left alone, a graceful shutdown can close the
// dead-letter queue's Redis connection while an async dead-letter write
// from a job that just failed is still in flight, silently dropping it (a
// real "lost the crash report while crashing" bug). Every in-flight write
// is tracked here so shutdown can await them all first — see
// flushPendingDeadLetters(), called from queues/index.js's
// closeAllQueues().
const pending = new Set();

export function attachDeadLetterHandling(worker, queueName) {
  worker.on('failed', (job, err) => {
    const task = handleFailure(job, err, queueName);
    pending.add(task);
    task.finally(() => pending.delete(task));
  });
}

async function handleFailure(job, err, queueName) {
  if (!job) {
    logger.error({ queueName, err: err?.message }, 'Job failed with no job reference (stalled beyond recovery)');
    return;
  }
  const exhausted = job.attemptsMade >= (job.opts.attempts || 1);
  logger.warn({ queueName, jobId: job.id, jobName: job.name, attemptsMade: job.attemptsMade, exhausted, err: err?.message }, 'Job failed');
  if (!exhausted) return; // will be retried by BullMQ — not dead yet

  try {
    const deadLetterQueue = getQueue(QUEUE_NAMES.DEAD_LETTER);
    await deadLetterQueue.add('dead-job', {
      originalQueue: queueName,
      originalJobId: job.id,
      originalJobName: job.name,
      data: job.data,
      error: { message: err?.message, stack: err?.stack },
      attemptsMade: job.attemptsMade,
      failedAt: new Date().toISOString(),
    });
  } catch (dlqErr) {
    // Must never throw out of an event handler — log and move on.
    logger.error({ err: dlqErr?.message }, 'Failed to record dead-letter entry');
  }
}

export async function flushPendingDeadLetters() {
  await Promise.allSettled([...pending]);
}
