const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate } = require('../middleware/auth');
const { loginLimiter } = require('../middleware/rateLimit');
const controller = require('../controllers/authController');

const router = Router();

const loginSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(1),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

const logoutSchema = z.object({
  refreshToken: z.string().min(1).optional(),
});

const changePasswordSchema = z.object({
  newPassword: z.string().min(8, 'New password must be at least 8 characters'),
});

router.post('/login', loginLimiter, validate(loginSchema), controller.login);
// No `authenticate` here — see authController.refresh's own comment: the
// refresh token is the credential, and the whole point is that the access
// token may already be expired.
router.post('/refresh', loginLimiter, validate(refreshSchema), controller.refresh);
router.post('/logout', validate(logoutSchema), controller.logout);
router.get('/me', authenticate, controller.me);
router.post('/change-password', authenticate, validate(changePasswordSchema), controller.changePassword);

module.exports = router;
