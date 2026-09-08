import { getPaymentClaim, updatePaymentClaim, appendAuditEvent, getBusySyncHealth } from '../store/repository.js';
import { defaultBusyClient } from '../simulators/busy-client.js';

/**
 * Verifies a payment claim. Fixes a gap found in the source Dart
 * implementation, which only gated the "mark Verified" path on BUSY sync
 * health — a claim could still be marked "Failed" while BUSY was down,
 * risking a false negative. Here, sync-unhealthy holds the claim as
 * "Sync Pending" regardless of which direction the RE was verifying.
 */
export async function processPaymentClaim(job, { busyClient = defaultBusyClient } = {}) {
  if (job.name !== 'verify') throw new Error(`Unknown payment-claim job name: "${job.name}"`);
  const { claimId, success, actor } = job.data;
  if (!claimId || typeof success !== 'boolean') {
    throw new Error('payment-claim verify job requires { claimId, success: boolean }');
  }

  const claim = getPaymentClaim(claimId);

  if (!getBusySyncHealth()) {
    const updated = await updatePaymentClaim(claimId, () => ({ status: 'Sync Pending' }));
    appendAuditEvent({
      customerId: claim.customerId,
      type: 'PAYMENT_CLAIM_SYNC_PENDING',
      description: `BUSY financial data is currently stale — verification for claim ${claimId} is held as Sync Pending rather than falsely marking it ${success ? 'Verified' : 'Failed'}.`,
      actor: actor || 'Recovery Executive',
      source: 'Payment Claim Verification',
      relatedEntityType: 'PaymentClaim',
      relatedEntityId: claimId,
    });
    return { status: updated.status };
  }

  if (success) {
    // Real contact with BUSY to confirm — may transiently fail, letting
    // BullMQ's retry/backoff handle it rather than swallowing the error.
    await busyClient.verifyPayment(claim);
  }

  const status = success ? 'Verified' : 'Failed';
  const updated = await updatePaymentClaim(claimId, () => ({ status }));
  appendAuditEvent({
    customerId: claim.customerId,
    type: success ? 'PAYMENT_CLAIM_VERIFIED' : 'PAYMENT_CLAIM_FAILED',
    description: success
      ? `Payment claim ${claimId} reconciled and verified against BUSY.`
      : `Payment claim ${claimId} could not be reconciled against BUSY — marked Failed, customer returns to active recovery.`,
    actor: actor || 'Recovery Executive',
    source: 'Payment Claim Verification',
    relatedEntityType: 'PaymentClaim',
    relatedEntityId: claimId,
  });
  return { status: updated.status };
}
