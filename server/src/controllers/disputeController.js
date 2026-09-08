const asyncHandler = require('../middleware/asyncHandler');
const disputeService = require('../services/disputeService');

const list = asyncHandler(async (req, res) => res.json(await disputeService.listForUser(req.user)));
const approve = asyncHandler(async (req, res) => res.json(await disputeService.approve(req.params.id, req.user, req.body)));
const reject = asyncHandler(async (req, res) => res.json(await disputeService.reject(req.params.id, req.user, req.body.reason)));
const requestInfo = asyncHandler(async (req, res) => res.json(await disputeService.requestInfo(req.params.id, req.user, req.body)));
const resolve = asyncHandler(async (req, res) => res.json(await disputeService.resolve(req.params.id, req.user, req.body)));

module.exports = { list, approve, reject, requestInfo, resolve };
