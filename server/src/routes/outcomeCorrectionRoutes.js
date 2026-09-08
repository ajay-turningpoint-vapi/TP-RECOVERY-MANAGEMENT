const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/outcomeCorrectionController');

const router = Router();
router.use(authenticate);

const requestSchema = z.object({
  requestedOutcome: z.string().min(1),
  requestedReason: z.string().min(1),
  requestNote: z.string().min(1),
});
const rejectSchema = z.object({ reason: z.string().min(1) });

router.get('/', controller.list);
router.post('/customer/:customerId', validate(requestSchema), controller.request);
router.post('/:id/approve', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), controller.approve);
router.post('/:id/reject', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(rejectSchema), controller.reject);

module.exports = router;
