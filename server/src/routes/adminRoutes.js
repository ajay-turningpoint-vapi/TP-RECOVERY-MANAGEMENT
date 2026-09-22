const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/adminController');

const router = Router();
router.use(authenticate, authorize('ADMIN'));

const resetPasswordSchema = z.object({ newPassword: z.string().min(8, 'New password must be at least 8 characters') });
router.post('/salesmen/:id/reset-password', validate(resetPasswordSchema), controller.resetSalesmanPassword);

module.exports = router;
