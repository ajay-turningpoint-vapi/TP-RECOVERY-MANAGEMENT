const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/ptpController');

const router = Router();
router.use(authenticate);

const correctionRequestSchema = z.object({
  amount: z.coerce.number().positive(),
  date: z.coerce.date(),
  paymentMode: z.string().optional(),
  reason: z.string().min(1),
});

const rejectSchema = z.object({ reason: z.string().min(1) });

router.get('/', controller.list);
router.post('/:id/request-correction', validate(correctionRequestSchema), controller.requestCorrection);
router.post('/:id/approve-correction', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), controller.approveCorrection);
router.post('/:id/reject-correction', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(rejectSchema), controller.rejectCorrection);

module.exports = router;
