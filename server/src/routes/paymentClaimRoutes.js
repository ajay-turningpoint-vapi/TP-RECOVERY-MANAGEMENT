const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const idempotency = require('../middleware/idempotency');
const controller = require('../controllers/paymentClaimController');

const router = Router();
router.use(authenticate);
// Only activates for a request carrying X-Idempotency-Key (the offline
// write-queue's retries) — every existing caller is unaffected.
router.use(idempotency());

const verifySchema = z.object({ success: z.boolean() });

router.get('/', controller.list);
router.post('/:id/verify', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(verifySchema), controller.verify);

module.exports = router;
