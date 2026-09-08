import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { createFivePmControlWorker } from '../src/workers/five-pm-control.worker.js';
import { closeAllQueueEvents, waitForCondition } from './helpers.js';
import { listFivePmControlSnapshots } from '../src/store/repository.js';

let worker;

beforeEach(async () => {
  await fullReset();
  worker = createFivePmControlWorker();
});

afterEach(async () => {
  await worker.close();
  const queue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
  await queue.removeJobScheduler('test-repeatable').catch(() => {});
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Repeatable jobs / job schedulers', () => {
  it('upsertJobScheduler fires multiple real, independent runs on a short interval', async () => {
    const queue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
    await queue.upsertJobScheduler('test-repeatable', { every: 200 }, { name: 'run', opts: {} });

    await waitForCondition(() => listFivePmControlSnapshots().length >= 3, { timeout: 5000 });
    const snapshots = listFivePmControlSnapshots();
    expect(snapshots.length).toBeGreaterThanOrEqual(3);
    // Each run produced a distinct, real snapshot — not the same job re-run.
    const ids = new Set(snapshots.map((s) => s.id));
    expect(ids.size).toBe(snapshots.length);
  }, 15000);

  it('upsertJobScheduler is idempotent by schedulerId — calling it again does not create a duplicate schedule', async () => {
    const queue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
    await queue.upsertJobScheduler('test-repeatable', { every: 500 }, { name: 'run', opts: {} });
    await queue.upsertJobScheduler('test-repeatable', { every: 500 }, { name: 'run', opts: {} });
    const schedulers = await queue.getJobSchedulers();
    const matching = schedulers.filter((s) => s.key === 'test-repeatable');
    expect(matching.length).toBe(1);
  });

  it('removeJobScheduler stops future runs', async () => {
    const queue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
    await queue.upsertJobScheduler('test-repeatable', { every: 150 }, { name: 'run', opts: {} });
    await waitForCondition(() => listFivePmControlSnapshots().length >= 1, { timeout: 5000 });
    await queue.removeJobScheduler('test-repeatable');
    const countAfterRemoval = listFivePmControlSnapshots().length;
    await new Promise((r) => setTimeout(r, 500));
    expect(listFivePmControlSnapshots().length).toBe(countAfterRemoval);
  }, 15000);
});
