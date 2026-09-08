const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/paymentClaimController');

const router = Router();
router.use(authenticate);

const verifySchema = z.object({ success: z.boolean() });

router.get('/', controller.list);
router.post('/:id/verify', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(verifySchema), controller.verify);

module.exports = router;
