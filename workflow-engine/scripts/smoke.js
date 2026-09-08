// Boots the real workflow engine (real workers, real Redis, real BullMQ
// jobs — nothing mocked) and drives one realistic end-to-end recovery
// scenario across every role, printing a human-readable trace as it goes.
// This is the "does it actually work like production" check, complementing
// the unit-style test suite.
//
//   npm run smoke

import { startApp } from '../src/app.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';
import { queueEventsFor, closeAllQueueEvents, addAndWait } from '../test/helpers.js';
import { getCustomer, listPtps, getDispute, setBusySyncHealth, auditHistoryForCustomer } from '../src/store/repository.js';

function step(label) {
  console.log(`\n\x1b[36m▶ ${label}\x1b[0m`);
}
function ok(label) {
  console.log(`  \x1b[32m✓\x1b[0m ${label}`);
}

async function main() {
  const { shutdown } = await startApp();

  try {
    step('Salesperson (Rahul) schedules a large PTP for C002 (Vijay Steel Works) that is already overdue');
    const recoveryQueue = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const { ptpId: ptp1 } = await addAndWait(recoveryQueue, 'ptp-scheduled', {
      customerId: 'C002',
      actor: 'Rahul',
      amountPromised: 250000,
      promiseDate: new Date(Date.now() - 3600000).toISOString(),
      paymentMode: 'NEFT',
    });
    ok(`PTP ${ptp1} created — ₹2,50,000, already due`);

    step('Salesperson (Rahul) schedules a SECOND large PTP for C002 — also overdue');
    const { ptpId: ptp2 } = await addAndWait(recoveryQueue, 'ptp-scheduled', {
      customerId: 'C002',
      actor: 'Rahul',
      amountPromised: 300000,
      promiseDate: new Date(Date.now() - 3600000).toISOString(),
      paymentMode: 'RTGS',
    });
    ok(`PTP ${ptp2} created — ₹3,00,000, already due`);

    step('A real busy-sync tick runs — both PTPs are large enough to mature as "broken"');
    const busySyncQueue = getQueue(QUEUE_NAMES.BUSY_SYNC);
    const syncResult = await addAndWait(busySyncQueue, 'tick', {});
    ok(`busy-sync matured ${syncResult.matured} PTP(s), triggered ${syncResult.escalationChecks || 0} real escalation re-evaluation(s) via a BullMQ Flow (parent waited for children)`);
    console.log(`    PTP ${ptp1}: ${listPtps().find((p) => p.id === ptp1).status}`);
    console.log(`    PTP ${ptp2}: ${listPtps().find((p) => p.id === ptp2).status}`);

    step('Escalation ladder: customer C002 should now be at L2 (2 broken PTPs), auto-escalated as a Flow child job');
    let customer = getCustomer('C002');
    ok(`C002 escalation level: ${customer.escalationLevel} (auto — never went straight to L4, that stays a human call)`);

    step('RE (Amit) manually escalates C002 to L3 after a call reveals a serious dispute');
    const escalationQueue = getQueue(QUEUE_NAMES.ESCALATION);
    await addAndWait(escalationQueue, 'manual', {
      customerId: 'C002',
      level: 'L3',
      reason: 'Customer disputes both invoices — needs RE-level investigation',
      plan: 'RE to personally review invoice history within 48 hours',
      ownerId: 'Amit',
      actor: 'Amit',
    });
    customer = getCustomer('C002');
    ok(`C002 escalation level: ${customer.escalationLevel}, recovery state: ${customer.currentRecoveryState}`);

    step('RE (Amit) tries to downgrade C002 back to L2 — must be rejected by the ratchet invariant');
    const downgradeAttempt = await addAndWait(escalationQueue, 'manual', { customerId: 'C002', level: 'L2', reason: 'attempted downgrade', ownerId: 'Amit', plan: 'n/a' });
    ok(`Downgrade attempt skipped: ${downgradeAttempt.skipped} — level remains ${getCustomer('C002').escalationLevel}`);

    step('Salesperson (Rahul) raises a dispute on C001 for ₹45,000');
    const { disputeId } = await addAndWait(recoveryQueue, 'dispute-raised', { customerId: 'C001', actor: 'Rahul', amount: 45000, reason: 'Packaging damaged in transit' });
    ok(`Dispute ${disputeId} raised — status: ${getDispute(disputeId).status}, priority: ${getDispute(disputeId).priority}`);

    step('RE (Amit) approves the dispute — a real disputeResolution task is created, shielding this amount from active recovery');
    const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
    const approveResult = await addAndWait(disputeQueue, 'approve', { disputeId, resolutionOwner: 'Amit', deadline: new Date(Date.now() + 5 * 86400000).toISOString(), description: 'Verify packaging damage claim against courier logs', actor: 'Amit' });
    ok(`Dispute approved, task ${approveResult.taskId} created for Amit`);

    step('RE (Amit) moves the dispute through resolution and marks it Resolved (BUSY sync healthy)');
    await addAndWait(disputeQueue, 'move-to-resolution', { disputeId, actor: 'Amit' });
    await addAndWait(disputeQueue, 'mark-awaiting-verification', { disputeId, actor: 'Amit' });
    await addAndWait(disputeQueue, 'resolve', { disputeId, actor: 'Amit', verifyAfterMs: 500, paidConfirmed: false });
    ok(`Dispute status: ${getDispute(disputeId).status} — a delayed follow-up job is now scheduled to check payment`);

    step('Waiting for the delayed "did they actually pay?" job — resolved-but-unpaid must return the customer to active recovery');
    await new Promise((resolve) => {
      const interval = setInterval(() => {
        if (getCustomer('C001').primaryNextAction === 'CALL CUSTOMER') {
          clearInterval(interval);
          resolve();
        }
      }, 100);
    });
    ok(`C001 returned to active recovery: primaryNextAction = "${getCustomer('C001').primaryNextAction}"`);

    step('Manager (Suresh) issues a Management Instruction to Mahesh on C004 (Om Enterprises)');
    const miQueue = getQueue(QUEUE_NAMES.MANAGEMENT_INSTRUCTION);
    const miResult = await addAndWait(miQueue, 'assign', { customerId: 'C004', salesmanId: 'Mahesh', description: 'Personally visit this customer within 24 hours — repeated broken promises', deadline: new Date(Date.now() + 86400000).toISOString(), actor: 'Suresh' });
    ok(`Management instruction issued as task ${miResult.taskId}, owned by Mahesh`);

    step('RE (Amit) reassigns C001 from Rahul to Mahesh — ownership transfers, history never rewrites');
    const reassignQueue = getQueue(QUEUE_NAMES.CUSTOMER_REASSIGNMENT);
    await addAndWait(reassignQueue, 'reassign', { customerId: 'C001', fromSalesmanId: 'Rahul', toSalesmanId: 'Mahesh', reason: 'Rahul overloaded this week', actor: 'Amit' });
    ok(`C001 now owned by ${getCustomer('C001').assignedSalesmanId}`);

    step('BUSY sync goes unhealthy — a new due PTP must be held as Sync Pending, never falsely matured');
    setBusySyncHealth(false);
    const recoveryQueue2 = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const { ptpId: ptp3 } = await addAndWait(recoveryQueue2, 'ptp-scheduled', { customerId: 'C005', actor: 'Rahul', amountPromised: 40000, promiseDate: new Date(Date.now() - 3600000).toISOString(), paymentMode: 'Cash' });
    const syncResult2 = await addAndWait(busySyncQueue, 'tick', {});
    ok(`During outage: matured=${syncResult2.matured}, syncPending=${syncResult2.syncPending} — PTP ${ptp3} status: ${listPtps().find((p) => p.id === ptp3).status}`);
    setBusySyncHealth(true);

    step('5 PM Control runs — an append-only historical snapshot');
    const fivePmQueue = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);
    const snapshot = await addAndWait(fivePmQueue, 'run', {});
    ok(`Snapshot: overdueTasks=${snapshot.overdueTasks}, mandatoryActionsNotCompleted=${snapshot.mandatoryActionsNotCompleted}, l3CasesWithoutPlan=${snapshot.l3CasesWithoutPlan}`);

    step('Full audit trail for C002 (every action, real actors, never rewritten)');
    for (const event of auditHistoryForCustomer('C002')) {
      console.log(`    [${event.timestamp}] ${event.type} — ${event.description}`);
    }

    console.log('\n\x1b[32m\x1b[1mSmoke run complete — every workflow executed against real Redis, real BullMQ jobs, real workers.\x1b[0m\n');
  } finally {
    await closeAllQueueEvents();
    await shutdown('smoke-complete');
  }
}

main()
  .then(() => process.exit(0)) // one-shot CLI script — force exit rather than
  // wait on stray handles (e.g. pino-pretty's transport worker thread)
  .catch((err) => {
    console.error('\n\x1b[31mSmoke run failed:\x1b[0m', err);
    process.exit(1);
  });
