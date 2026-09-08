const asyncHandler = require('../middleware/asyncHandler');
const notificationService = require('../services/notificationService');

const list = asyncHandler(async (req, res) => res.json(await notificationService.listForUser(req.user.id)));
const markRead = asyncHandler(async (req, res) => res.json(await notificationService.markRead(req.params.id, req.user)));
const markAllRead = asyncHandler(async (req, res) => res.json(await notificationService.markAllRead(req.user)));

module.exports = { list, markRead, markAllRead };
