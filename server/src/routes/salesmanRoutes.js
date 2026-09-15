const { Router } = require('express');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/salesmanController');

const router = Router();
router.use(authenticate, authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'));

router.get('/', controller.list);
router.post('/:id/dismiss-underperformance', controller.dismissUnderperformance);

module.exports = router;
