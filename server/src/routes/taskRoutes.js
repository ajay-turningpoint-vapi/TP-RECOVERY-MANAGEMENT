const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const idempotency = require('../middleware/idempotency');
const controller = require('../controllers/taskController');

const router = Router();
router.use(authenticate);
// Only activates for a request carrying X-Idempotency-Key (the offline
// write-queue's retries) — every existing caller is unaffected.
router.use(idempotency());

const extensionSchema = z.object({
  reason: z.string().min(1),
  deadline: z.coerce.date(),
  priority: z.string().optional(),
});

const reassignSchema = z.object({
  newOwnerId: z.string().min(1),
  reason: z.string().min(1),
});

const rescheduleSchema = z.object({
  reason: z.string().min(1),
  newDeadline: z.coerce.date(),
});

const internalActionApproveSchema = z.object({
  note: z.string().optional(),
  attachmentPath: z.string().optional(),
});

const internalActionRejectSchema = z.object({
  reason: z.string().optional(),
  attachmentPath: z.string().optional(),
});

router.get('/', controller.list);
router.post('/:id/complete', controller.complete);
router.post('/:id/request-extension', validate(extensionSchema), controller.requestExtension);
router.post('/:id/approve-edit', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), controller.approveEdit);
router.post('/:id/reject-edit', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), controller.rejectEdit);
router.post('/:id/reassign', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(reassignSchema), controller.reassign);
router.post('/:id/reschedule', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(rescheduleSchema), controller.reschedule);
router.post('/:id/review', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), controller.markReviewed);
router.post('/:id/approve-internal-action', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(internalActionApproveSchema), controller.approveInternalAction);
router.post('/:id/reject-internal-action', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(internalActionRejectSchema), controller.rejectInternalAction);

module.exports = router;
