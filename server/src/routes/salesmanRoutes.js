const { Router } = require('express');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/salesmanController');

const router = Router();
router.use(authenticate, authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'));

router.get('/', controller.list);

module.exports = router;
