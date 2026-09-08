const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/disputeController');

const router = Router();
router.use(authenticate);

const approveSchema = z.object({
  resolutionOwner: z.string().min(1),
  deadline: z.coerce.date(),
  description: z.string().min(1),
});
const rejectSchema = z.object({ reason: z.string().min(1) });
const infoSchema = z.object({
  salesmanId: z.string().min(1),
  desc: z.string().min(1),
  deadline: z.coerce.date(),
});
const resolveSchema = z.object({
  outcome: z.enum(['Resolved', 'Returned to Recovery']),
  note: z.string().optional(),
});

router.get('/', controller.list);
router.post('/:id/approve', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(approveSchema), controller.approve);
router.post('/:id/reject', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(rejectSchema), controller.reject);
router.post('/:id/request-info', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(infoSchema), controller.requestInfo);
router.post('/:id/resolve', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(resolveSchema), controller.resolve);

module.exports = router;
