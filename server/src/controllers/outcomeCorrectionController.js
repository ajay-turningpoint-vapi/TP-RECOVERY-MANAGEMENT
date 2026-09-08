const asyncHandler = require('../middleware/asyncHandler');
const outcomeCorrectionService = require('../services/outcomeCorrectionService');

const list = asyncHandler(async (req, res) => res.json(await outcomeCorrectionService.listForUser(req.user)));
const request = asyncHandler(async (req, res) => res.json(await outcomeCorrectionService.request(req.params.customerId, req.user, req.body)));
const approve = asyncHandler(async (req, res) => res.json(await outcomeCorrectionService.approve(req.params.id, req.user)));
const reject = asyncHandler(async (req, res) => res.json(await outcomeCorrectionService.reject(req.params.id, req.user, req.body.reason)));

module.exports = { list, request, approve, reject };
