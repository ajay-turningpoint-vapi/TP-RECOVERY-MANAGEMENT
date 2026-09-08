const asyncHandler = require('../middleware/asyncHandler');
const paymentClaimService = require('../services/paymentClaimService');

const list = asyncHandler(async (req, res) => res.json(await paymentClaimService.listForUser(req.user)));
const verify = asyncHandler(async (req, res) => res.json(await paymentClaimService.verify(req.params.id, req.user, req.body.success)));

module.exports = { list, verify };
