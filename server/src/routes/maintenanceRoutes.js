const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/maintenanceController');

const router = Router();

// Deliberately no `authenticate` here — a not-yet-signed-in client (the
// login screen) needs to know maintenance is on before it can even attempt
// a login, and an already-blocked client needs to keep polling this to
// know when it's safe to reconnect.
router.get('/', controller.get);

const setSchema = z.object({ enabled: z.boolean() });
router.post('/', authenticate, authorize('ADMIN'), validate(setSchema), controller.set);

module.exports = router;
