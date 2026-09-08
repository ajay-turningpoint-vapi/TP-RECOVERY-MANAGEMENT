const { Router } = require('express');
const { authenticate } = require('../middleware/auth');
const controller = require('../controllers/notificationController');

const router = Router();
router.use(authenticate);

router.get('/', controller.list);
router.post('/:id/read', controller.markRead);
router.post('/read-all', controller.markAllRead);

module.exports = router;
