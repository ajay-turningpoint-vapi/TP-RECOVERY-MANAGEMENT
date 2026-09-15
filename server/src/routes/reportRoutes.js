const { Router } = require('express');
const { authenticate } = require('../middleware/auth');
const controller = require('../controllers/reportController');

const router = Router();
router.use(authenticate);

router.get('/dashboard', controller.dashboard);
router.get('/trends', controller.trends);
router.get('/re-performance', controller.rePerformance);

module.exports = router;
