const asyncHandler = require('../middleware/asyncHandler');
const outcomeEditService = require('../services/outcomeEditService');

const list = asyncHandler(async (req, res) => res.json(await outcomeEditService.listForUser(req.user)));
const request = asyncHandler(async (req, res) =>
  res.json(await outcomeEditService.request(req.params.customerId, req.user, req.body))
);
const approve = asyncHandler(async (req, res) => res.json(await outcomeEditService.approve(req.params.id, req.user)));
const reject = asyncHandler(async (req, res) =>
  res.json(await outcomeEditService.reject(req.params.id, req.user, req.body.reason))
);

module.exports = { list, request, approve, reject };
