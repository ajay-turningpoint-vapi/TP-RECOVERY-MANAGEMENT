// The comprehensive end-to-end pass: every Salesperson outcome type, every
// RE action, every Manager action, run in one continuous real session
// against real Redis with real workers — then verified as "report" data by
// querying the repository the way a future reports API would. This is the
// single test that stands in for "test every component, every role, every
// workflow" rather than relying on the smaller domain files alone.
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { fullReset, teardownQueues } from './setup.js';
import { addAndWait, closeAllQueueEvents } from './helpers.js';
import { getQueue, QUEUE_NAMES } from '../src/queues/index.js';

import { createRecoveryOutcomeWorker } from '../src/workers/recovery-outcome.worker.js';
import { createBusySyncWorker } from '../src/workers/busy-sync.worker.js';
import { createEscalationWorker } from '../src/workers/escalation.worker.js';
import { createPaymentClaimWorker } from '../src/workers/payment-claim.worker.js';
import { createDisputeWorker } from '../src/workers/dispute.worker.js';
import { createTaskWorker } from '../src/workers/task.worker.js';
import { createManagementInstructionWorker } from '../src/workers/management-instruction.worker.js';
import { createCustomerReassignmentWorker } from '../src/workers/customer-reassignment.worker.js';
import { createCorrectionRequestWorker } from '../src/workers/correction-request.worker.js';
import { createFivePmControlWorker } from '../src/workers/five-pm-control.worker.js';

import { BusyClient } from '../src/simulators/busy-client.js';
import {
  getCustomer,
  listCustomers,
  listTasks,
  listPtps,
  listDisputes,
  auditHistoryForCustomer,
  setBusySyncHealth,
  listFivePmControlSnapshots,
} from '../src/store/repository.js';

let workers = [];

beforeAll(async () => {
  await fullReset();
  workers = [
    createRecoveryOutcomeWorker(),
    createBusySyncWorker({ busyClient: new BusyClient({ healthy: true }) }),
    createEscalationWorker(),
    createPaymentClaimWorker({ busyClient: new BusyClient({ healthy: true }) }, { limiter: undefined }),
    createDisputeWorker(),
    createTaskWorker(),
    createManagementInstructionWorker(),
    createCustomerReassignmentWorker(),
    createCorrectionRequestWorker(),
    createFivePmControlWorker(),
  ];
});

afterAll(async () => {
  await Promise.all(workers.map((w) => w.close()));
  await closeAllQueueEvents();
  await teardownQueues();
});

describe('Full cross-role E2E: every outcome type, every role, then verified as report data', () => {
  it('runs the complete Salesperson -> RE -> Manager workflow set and produces internally-consistent report data', async () => {
    await fullReset();
    setBusySyncHealth(true);

    const recoveryQ = getQueue(QUEUE_NAMES.RECOVERY_OUTCOME);
    const escalationQ = getQueue(QUEUE_NAMES.ESCALATION);
    const paymentClaimQ = getQueue(QUEUE_NAMES.PAYMENT_CLAIM);
    const disputeQ = getQueue(QUEUE_NAMES.DISPUTE);
    const taskQ = getQueue(QUEUE_NAMES.TASK);
    const busySyncQ = getQueue(QUEUE_NAMES.BUSY_SYNC);
    const miQ = getQueue(QUEUE_NAMES.MANAGEMENT_INSTRUCTION);
    const reassignQ = getQueue(QUEUE_NAMES.CUSTOMER_REASSIGNMENT);
    const correctionQ = getQueue(QUEUE_NAMES.CORRECTION_REQUEST);
    const fivePmQ = getQueue(QUEUE_NAMES.FIVE_PM_CONTROL);

    // ============ SALESPERSON: every recovery-outcome type ============

    // 1. PTP Scheduled
    const { ptpId: ptpKept } = await addAndWait(recoveryQ, 'ptp-scheduled', {
      customerId: 'C001', actor: 'Rahul', amountPromised: 20000, promiseDate: new Date(Date.now() - 60000).toISOString(), paymentMode: 'Cash',
    });

    // 2. Follow-up / Will Confirm
    const { taskId: followUpTaskId } = await addAndWait(recoveryQ, 'follow-up', {
      customerId: 'C005', actor: 'Rahul', reason: 'Customer will confirm tomorrow', followUpAt: new Date(Date.now() + 86400000).toISOString(),
    });

    // 3. No Answer x3 -> auto Physical Visit
    await addAndWait(recoveryQ, 'no-answer', { customerId: 'C003', actor: 'Mahesh' });
    await addAndWait(recoveryQ, 'no-answer', { customerId: 'C003', actor: 'Mahesh' });
    const noAnswerResult = await addAndWait(recoveryQ, 'no-answer', { customerId: 'C003', actor: 'Mahesh' });
    expect(noAnswerResult.physicalVisitTaskId).toBeTruthy();

    // 4. Unable To Commit
    const { taskId: unableTaskId } = await addAndWait(recoveryQ, 'unable-to-commit', { customerId: 'C004', actor: 'Mahesh', reason: 'Customer refused to commit' });

    // 5. Internal Action Required
    const { taskId: internalTaskId } = await addAndWait(recoveryQ, 'internal-action', { customerId: 'C001', actor: 'Rahul', details: 'Ledger mismatch — needs finance review' });

    // 6. Verification Pending (Payment Already Made)
    const { paymentClaimId } = await addAndWait(recoveryQ, 'verification-pending', { customerId: 'C002', actor: 'Rahul', amount: 15000 });

    // 7. Dispute Raised
    const { disputeId } = await addAndWait(recoveryQ, 'dispute-raised', { customerId: 'C001', actor: 'Rahul', amount: 45000, reason: 'Packaging damaged' });

    // Two more broken-bound PTPs on the same customer, to drive real
    // escalation via busy-sync maturation below.
    await addAndWait(recoveryQ, 'ptp-scheduled', { customerId: 'C002', actor: 'Rahul', amountPromised: 250000, promiseDate: new Date(Date.now() - 60000).toISOString(), paymentMode: 'NEFT' });
    await addAndWait(recoveryQ, 'ptp-scheduled', { customerId: 'C002', actor: 'Rahul', amountPromised: 300000, promiseDate: new Date(Date.now() - 60000).toISOString(), paymentMode: 'RTGS' });

    // ============ BUSY SYNC: matures everything due ============
    const syncResult = await addAndWait(busySyncQ, 'tick', {});
    expect(syncResult.matured).toBeGreaterThanOrEqual(3); // ptpKept + the two broken ones
    expect(getCustomer('C002').escalationLevel).toBe('L2'); // auto-escalated via the real Flow

    // ============ RE: dispute review, payment verification, escalation, corrections ============

    // RE approves the dispute -> real disputeResolution task
    const approveResult = await addAndWait(disputeQ, 'approve', { disputeId, resolutionOwner: 'Amit', deadline: new Date(Date.now() + 5 * 86400000).toISOString(), description: 'Verify damage claim', actor: 'Amit' });

    // RE raises + rejects a second dispute (covers the Rejected branch)
    const { disputeId: disputeId2 } = await addAndWait(recoveryQ, 'dispute-raised', { customerId: 'C005', actor: 'Rahul', amount: 10000, reason: 'Frivolous claim' });
    await addAndWait(disputeQ, 'reject', { disputeId: disputeId2, reason: 'No evidence', actor: 'Amit' });

    // RE requests more info on a third dispute
    const { disputeId: disputeId3 } = await addAndWait(recoveryQ, 'dispute-raised', { customerId: 'C004', actor: 'Mahesh', amount: 12000, reason: 'Need invoice copy' });
    await addAndWait(disputeQ, 'request-info', { disputeId: disputeId3, salesmanId: 'Mahesh', description: 'Send invoice', deadline: new Date(Date.now() + 2 * 86400000).toISOString(), actor: 'Amit' });

    // RE takes the first dispute through the full back-half + resolves it
    await addAndWait(disputeQ, 'move-to-resolution', { disputeId, actor: 'Amit' });
    await addAndWait(disputeQ, 'mark-awaiting-verification', { disputeId, actor: 'Amit' });
    await addAndWait(disputeQ, 'resolve', { disputeId, actor: 'Amit', verifyAfterMs: 100, paidConfirmed: true });

    // RE verifies the payment claim (healthy BUSY -> Verified)
    const verifyResult = await addAndWait(paymentClaimQ, 'verify', { claimId: paymentClaimId, success: true, actor: 'Amit' });
    expect(verifyResult.status).toBe('Verified');

    // RE manually escalates a different customer straight to L4
    await addAndWait(escalationQ, 'manual', { customerId: 'C003', level: 'L4', reason: 'Legal action', plan: 'Escalate to management', ownerId: 'Suresh', actor: 'Amit' });

    // RE resolves the L2 escalation on C002 (level is retained, case closes)
    const { openEscalationCaseForCustomer } = await import('../src/store/repository.js');
    const openCase = openEscalationCaseForCustomer('C002');
    expect(openCase).toBeTruthy();
    await addAndWait(escalationQ, 'resolve', { escalationCaseId: openCase.id, resolutionNote: 'Customer paid outstanding balance', actor: 'Amit' });
    expect(getCustomer('C002').escalationLevel).toBe('L2'); // retained, not reset

    // RE requests + approves a PTP correction
    const { createPtp } = await import('../src/store/repository.js');
    const ptpForCorrection = createPtp({ customerId: 'C001', amountPromised: 50000, promiseDate: new Date().toISOString(), paymentMode: 'Cheque' });
    const { correctionRequestId: ptpCorrId } = await addAndWait(correctionQ, 'request', { correctionType: 'ptp', customerId: 'C001', ptpId: ptpForCorrection.id, requestedAmount: 55000, requestedDate: new Date().toISOString(), actor: 'Rahul' });
    await addAndWait(correctionQ, 'approve', { correctionRequestId: ptpCorrId, actor: 'Amit' });

    // RE requests + rejects an outcome correction
    const { correctionRequestId: outcomeCorrId } = await addAndWait(correctionQ, 'request', { correctionType: 'outcome', customerId: 'C003', originalOutcome: 'No Answer', originalReason: 'No Answer', requestedOutcome: 'Follow-up', requestedReason: 'Actually spoke', actor: 'Mahesh' });
    await addAndWait(correctionQ, 'reject', { correctionRequestId: outcomeCorrId, reason: 'No supporting note', actor: 'Amit' });

    // RE completes several tasks
    await addAndWait(taskQ, 'complete', { taskId: followUpTaskId, actor: 'Rahul' });
    await addAndWait(taskQ, 'complete', { taskId: unableTaskId, actor: 'Mahesh' });
    await addAndWait(taskQ, 'complete', { taskId: internalTaskId, actor: 'Amit' });

    // RE reassigns a task and reschedules another
    const tasksForReassign = listTasks().filter((t) => t.status !== 'completed');
    if (tasksForReassign.length > 0) {
      await addAndWait(taskQ, 'reassign', { taskId: tasksForReassign[0].id, newOwnerId: 'Mahesh', reason: 'Rahul overloaded', actor: 'Amit' });
      await addAndWait(taskQ, 'reschedule', { taskId: tasksForReassign[0].id, newDeadline: new Date(Date.now() + 3 * 86400000).toISOString(), reason: 'Customer traveling', actor: 'Amit' });
    }

    // Salesperson requests a task edit, RE approves it
    const remainingOpen = listTasks().filter((t) => t.status !== 'completed');
    if (remainingOpen.length > 0) {
      const target = remainingOpen[0];
      await addAndWait(taskQ, 'request-edit-approval', { taskId: target.id, newDeadline: new Date(Date.now() + 10 * 86400000).toISOString(), newReason: 'Need more time', actor: 'Mahesh' });
      await addAndWait(taskQ, 'approve-edit', { taskId: target.id, actor: 'Amit' });
    }

    // RE reassigns a customer's portfolio ownership
    await addAndWait(reassignQ, 'reassign', { customerId: 'C001', fromSalesmanId: 'Rahul', toSalesmanId: 'Mahesh', reason: 'Load balancing', actor: 'Amit' });

    // ============ MANAGER: management instruction + 5 PM control ============
    const { taskId: miTaskId } = await addAndWait(miQ, 'assign', { customerId: 'C004', salesmanId: 'Mahesh', description: 'Personally visit within 24 hours', deadline: new Date(Date.now() + 86400000).toISOString(), actor: 'Suresh' });

    const snapshot1 = await addAndWait(fivePmQ, 'run', {});
    await addAndWait(taskQ, 'complete', { taskId: miTaskId, actor: 'Mahesh' });
    const snapshot2 = await addAndWait(fivePmQ, 'run', {});

    // ============ BUSY outage scenario, exercised end-to-end too ============
    setBusySyncHealth(false);
    const { paymentClaimId: claimDuringOutage } = await addAndWait(recoveryQ, 'verification-pending', { customerId: 'C005', actor: 'Rahul', amount: 8000 });
    const outageVerify = await addAndWait(paymentClaimQ, 'verify', { claimId: claimDuringOutage, success: true, actor: 'Amit' });
    expect(outageVerify.status).toBe('Sync Pending');
    setBusySyncHealth(true);

    // ================= REPORT-STYLE AGGREGATE VERIFICATION =================
    // Exactly the kind of queries a future reports API would run — confirm
    // they return real, internally-consistent numbers derived from
    // everything the 3 roles just did above.

    const allCustomers = listCustomers();
    expect(allCustomers.length).toBe(5); // seed set, none created/deleted

    const allDisputes = listDisputes();
    expect(allDisputes.length).toBe(3);
    const disputeStatusCounts = allDisputes.reduce((acc, d) => ({ ...acc, [d.status]: (acc[d.status] || 0) + 1 }), {});
    expect(disputeStatusCounts['Resolved']).toBe(1);
    expect(disputeStatusCounts['Rejected']).toBe(1);
    expect(disputeStatusCounts['Need More Information']).toBe(1);

    const allPtps = listPtps();
    const ptpStatusCounts = allPtps.reduce((acc, p) => ({ ...acc, [p.status]: (acc[p.status] || 0) + 1 }), {});
    expect(ptpStatusCounts['kept']).toBeGreaterThanOrEqual(1); // ptpKept
    expect(ptpStatusCounts['broken']).toBeGreaterThanOrEqual(2); // the two C002 PTPs
    expect(allPtps.find((p) => p.id === ptpForCorrection.id).amountPromised).toBe(55000); // corrected

    const allTasks = listTasks();
    const taskTypeCounts = allTasks.reduce((acc, t) => ({ ...acc, [t.type]: (acc[t.type] || 0) + 1 }), {});
    expect(taskTypeCounts['physicalVisit']).toBeGreaterThanOrEqual(1);
    expect(taskTypeCounts['disputeResolution']).toBeGreaterThanOrEqual(2); // approve + request-info
    expect(taskTypeCounts['managementInstruction']).toBe(1);
    const completedTasks = allTasks.filter((t) => t.status === 'completed');
    expect(completedTasks.length).toBeGreaterThanOrEqual(4);

    // C001 changed hands mid-scenario — its full audit trail (raised by
    // Rahul, later actions by Amit/Mahesh) must still be intact and never
    // rewritten, per the reassignment invariant.
    const c001Audit = auditHistoryForCustomer('C001');
    expect(c001Audit.some((e) => e.actor === 'Rahul')).toBe(true);
    expect(c001Audit.some((e) => e.type === 'RE_CHANGED_OWNER')).toBe(true);
    expect(getCustomer('C001').assignedSalesmanId).toBe('Mahesh');

    // 5 PM Control: two real, distinct, append-only historical snapshots.
    const snapshots = listFivePmControlSnapshots();
    expect(snapshots.length).toBe(2);
    expect(snapshots[0].id).not.toBe(snapshots[1].id);
    expect(snapshot1.id).toBe(snapshots[0].id);
    expect(snapshot2.id).toBe(snapshots[1].id);

    // Escalation: C002 auto-escalated to L2 and stayed there after its case
    // resolved; C003 was manually pushed straight to L4.
    expect(getCustomer('C002').escalationLevel).toBe('L2');
    expect(getCustomer('C003').escalationLevel).toBe('L4');
  }, 30000);
});
