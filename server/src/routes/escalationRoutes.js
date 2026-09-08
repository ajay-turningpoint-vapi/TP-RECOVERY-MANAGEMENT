const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/escalationController');
const { ESCALATION_LEVEL } = require('../constants/enums');

const router = Router();
router.use(authenticate);

const raiseSchema = z.object({
  level: z.enum(ESCALATION_LEVEL.filter((l) => l !== 'none')),
  reason: z.string().min(1),
  plan: z.string().optional(),
  ownerId: z.string().optional(),
  deadline: z.coerce.date().optional(),
  moneyAtRisk: z.coerce.number().min(0).optional(),
});
const resolveSchema = z.object({ note: z.string().optional() });

router.get('/', controller.list);
router.get('/customer/:customerId', controller.listForCustomer);
router.post('/customer/:customerId', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(raiseSchema), controller.raise);
router.post('/:id/resolve', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(resolveSchema), controller.resolve);

module.exports = router;
