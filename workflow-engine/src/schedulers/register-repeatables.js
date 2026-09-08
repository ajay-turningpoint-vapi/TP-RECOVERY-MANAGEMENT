import { getQueue, QUEUE_NAMES } from '../queues/index.js';
import { config } from '../config.js';

/**
 * Registers the two recurring, spec-mandated jobs using BullMQ's current
 * Job Scheduler API (`upsertJobScheduler`) rather than the deprecated
 * `repeat` option — upsert is idempotent by `schedulerId`, so calling this
 * on every app boot never creates duplicate repeat schedules.
 */
export async function registerRepeatables({ busySyncIntervalMs = config.busySync.intervalMs, fivePmControlCron = config.fivePmControl.cron } = {}) {
  const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
  await busySyncQueue.upsertJobScheduler(
    'busy-sync-tick',
    { every: busySyncIntervalMs },
    { name: 'tick', opts: { attempts: 5, backoff: { type: 'exponential', delay: 2000 } } },
  );

  const fivePmQueue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
  await fivePmQueue.upsertJobScheduler(
    'five-pm-control-daily',
    { pattern: fivePmControlCron },
    { name: 'run', opts: { attempts: 3, backoff: { type: 'exponential', delay: 2000 } } },
  );
}

export async function removeRepeatables() {
  const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
  await busySyncQueue.removeJobScheduler('busy-sync-tick');
  const fivePmQueue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
  await fivePmQueue.removeJobScheduler('five-pm-control-daily');
}
