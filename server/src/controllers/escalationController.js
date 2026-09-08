const asyncHandler = require('../middleware/asyncHandler');
const escalationService = require('../services/escalationService');

const list = asyncHandler(async (req, res) => res.json(await escalationService.listForUser(req.user)));
const listForCustomer = asyncHandler(async (req, res) => res.json(await escalationService.listForCustomer(req.params.customerId)));
const raise = asyncHandler(async (req, res) => res.json(await escalationService.raise(req.params.customerId, req.user, req.body)));
const resolve = asyncHandler(async (req, res) => res.json(await escalationService.resolve(req.params.id, req.user, req.body.note)));

module.exports = { list, listForCustomer, raise, resolve };
