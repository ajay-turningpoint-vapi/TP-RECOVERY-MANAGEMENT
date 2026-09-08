const { Router } = require('express');
const healthController = require('../controllers/healthController');

const router = Router();

router.get('/health', healthController.live);
router.get('/health/ready', healthController.ready);

router.use('/api/auth', require('./authRoutes'));
router.use('/api/customers', require('./customerRoutes'));
router.use('/api/tasks', require('./taskRoutes'));
router.use('/api/ptps', require('./ptpRoutes'));
router.use('/api/disputes', require('./disputeRoutes'));
router.use('/api/payment-claims', require('./paymentClaimRoutes'));
router.use('/api/salesmen', require('./salesmanRoutes'));
router.use('/api/escalations', require('./escalationRoutes'));
router.use('/api/notifications', require('./notificationRoutes'));
router.use('/api/reports', require('./reportRoutes'));
router.use('/api/outcome-corrections', require('./outcomeCorrectionRoutes'));
router.use('/api/outcome-edits', require('./outcomeEditRoutes'));
router.use('/api/busy-sync', require('./busySyncAdminRoutes'));
router.use('/api/sync-status', require('./syncStatusRoutes'));
router.use('/api/attachments', require('./attachmentRoutes'));

module.exports = router;
