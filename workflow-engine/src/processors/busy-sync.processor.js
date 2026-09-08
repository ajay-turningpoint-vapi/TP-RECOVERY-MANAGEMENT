import { FlowProducer, QueueEvents } from 'bullmq';
import { createConnection } from '../redis-connection.js';
import { QUEUE_NAMES } from '../queues/names.js';
import { listDuePtps, updatePtp, appendAuditEvent, getBusySyncHealth, recordBusySyncRun } from '../store/repository.js';
import { defaultBusyClient } from '../simulators/busy-client.js';

let flowProducer;
function getFlowProducer() {
  if (!flowProducer) flowProducer = new FlowProducer({ connection: createConnection() });
  return flowProducer;
}

// The Flow parent deliberately lives on the ESCALATION queue, not
// BUSY_SYNC. Putting it on BUSY_SYNC would self-deadlock: this "tick" job
// is already occupying busy-sync's single concurrency slot (concurrency:1,
// by design, to prevent overlapping sync runs) while it awaits the parent
// — if the parent also needed the busy-sync worker to free up before it
// could be processed, it never would be. The escalation queue has spare
// concurrency (5) and no such self-reference, so its worker picks the
// parent up as soon as the children finish. Found via the smoke script,
// which genuinely hung on this before the fix — exactly the kind of bug a
// unit test with only kept/partiallyKept PTPs (never broken) would miss.
let queueEvents;
let queueEventsReady;
function getEscalationQueueEvents() {
  if (!queueEvents) {
    queueEvents = new QueueEvents(QUEUE_NAMES.ESCALATION, { connection: createConnection() });
    queueEventsReady = queueEvents.waitUntilReady();
  }
  return queueEvents;
}

/**
 * Must be awaited BEFORE the Flow is added, not just before
 * `waitUntilFinished` is called. QueueEvents subscribes to Redis pub/sub
 * asynchronously — if the flow's parent+child jobs are created (and, for
 * fast jobs like ours, complete) before that subscription is live, the
 * "completed" event fires into the void and `waitUntilFinished` hangs
 * forever waiting for a message that already happened. This is a genuine
 * race BullMQ does not protect against on its own; found via the smoke
 * script hanging on a real (not simulated) run, where the escalation
 * flow's parent/child jobs both completed in Redis in under a millisecond
 * — faster than a lazily-created QueueEvents connection could subscribe.
 */
async function ensureEscalationQueueEventsReady() {
  getEscalationQueueEvents();
  await queueEventsReady;
}

export async function closeBusySyncProcessorResources() {
  if (flowProducer) {
    await flowProducer.close();
    flowProducer = undefined;
  }
  if (queueEvents) {
    await queueEvents.close();
    queueEvents = undefined;
  }
}

/**
 * Matures every due PTP against the (simulated) BUSY system, then — for any
 * customer whose PTP just came back broken — spawns and awaits a real
 * BullMQ Flow (parent = an escalation-queue summary job, children = one
 * "evaluate" escalation job per affected customer) so escalation
 * re-evaluation genuinely finishes before this tick reports done.
 *
 * Fixes a gap found in the source Dart implementation: when BUSY sync is
 * unhealthy, due PTPs are held as `financialSyncPending` instead of being
 * matured against stale/fabricated data — they must never be falsely
 * marked kept/broken while the sync is down.
 */
export async function processBusySync(job, { busyClient = defaultBusyClient } = {}) {
  const due = listDuePtps();
  const healthy = getBusySyncHealth();
  const results = { checked: due.length, matured: 0, syncPending: 0 };
  const affectedCustomers = new Set();

  for (const ptp of due) {
    if (!healthy) {
      await updatePtp(ptp.id, () => ({ status: 'financialSyncPending' }));
      appendAuditEvent({
        customerId: ptp.customerId,
        type: 'PTP_SYNC_PENDING',
        description: `PTP ${ptp.id} was due but BUSY sync is currently unhealthy — held as Sync Pending rather than falsely matured.`,
        source: 'BUSY Sync Engine',
        relatedEntityType: 'PTP',
        relatedEntityId: ptp.id,
      });
      results.syncPending += 1;
      continue;
    }

    // Transient failures (network blips, etc.) propagate and let BullMQ's
    // own retry/backoff on this job handle them — do not swallow here.
    const outcome = await busyClient.reconcilePtp(ptp);
    await updatePtp(ptp.id, () => ({
      status: outcome.outcome,
      amountReceived: outcome.amountReceived,
      brokenReason: outcome.brokenReason || null,
    }));
    appendAuditEvent({
      customerId: ptp.customerId,
      type: `PTP_${outcome.outcome.toUpperCase()}`,
      description: `BUSY reconciled PTP ${ptp.id} as ${outcome.outcome}.`,
      source: 'BUSY Sync Engine',
      relatedEntityType: 'PTP',
      relatedEntityId: ptp.id,
    });
    results.matured += 1;
    if (outcome.outcome === 'broken') affectedCustomers.add(ptp.customerId);
  }

  recordBusySyncRun();

  if (affectedCustomers.size > 0) {
    await ensureEscalationQueueEventsReady();
    const fp = getFlowProducer();
    const { job: parentJob } = await fp.add({
      name: 'summary',
      queueName: QUEUE_NAMES.ESCALATION,
      data: { customerIds: [...affectedCustomers], source: 'busy-sync' },
      children: [...affectedCustomers].map((customerId) => ({
        name: 'evaluate',
        queueName: QUEUE_NAMES.ESCALATION,
        data: { customerId },
        opts: { attempts: 3, backoff: { type: 'exponential', delay: 1000 } },
      })),
    });
    await parentJob.waitUntilFinished(getEscalationQueueEvents());
    results.escalationChecks = affectedCustomers.size;
  }

  return results;
}
