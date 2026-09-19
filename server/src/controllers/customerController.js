const asyncHandler = require('../middleware/asyncHandler');
const customerService = require('../services/customerService');

const list = asyncHandler(async (req, res) => {
  const customers = await customerService.listForUser(req.user);
  res.json(customers);
});

const getOne = asyncHandler(async (req, res) => {
  const customer = await customerService.getDetail(req.params.id, req.user);
  res.json(customer);
});

const getNext = asyncHandler(async (req, res) => {
  const customer = await customerService.getNext(req.user);
  res.json(customer);
});

const getAuditHistory = asyncHandler(async (req, res) => {
  const page = await customerService.getAuditHistoryPage(req.params.id, req.user, {
    cursor: req.query.cursor,
    limit: req.query.limit,
  });
  res.json(page);
});

const recordOutcome = asyncHandler(async (req, res) => {
  const customer = await customerService.recordOutcome(req.params.id, req.user, req.body);
  res.json(customer);
});

const takeControl = asyncHandler(async (req, res) => {
  const customer = await customerService.takeControl(req.params.id, req.user);
  res.json(customer);
});

const releaseControl = asyncHandler(async (req, res) => {
  const customer = await customerService.releaseControl(req.params.id, req.user);
  res.json(customer);
});

const reassign = asyncHandler(async (req, res) => {
  const customer = await customerService.reassignCustomer(req.params.id, req.user, req.body);
  res.json(customer);
});

const assignInstruction = asyncHandler(async (req, res) => {
  const customer = await customerService.assignManagementInstruction(req.params.id, req.user, req.body);
  res.json(customer);
});

module.exports = { list, getOne, getNext, getAuditHistory, recordOutcome, takeControl, releaseControl, reassign, assignInstruction };
