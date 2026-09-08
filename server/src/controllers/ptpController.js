const asyncHandler = require('../middleware/asyncHandler');
const ptpService = require('../services/ptpService');

const list = asyncHandler(async (req, res) => {
  res.json(await ptpService.listForUser(req.user));
});

const requestCorrection = asyncHandler(async (req, res) => {
  res.json(await ptpService.requestCorrection(req.params.id, req.user, req.body));
});

const approveCorrection = asyncHandler(async (req, res) => {
  res.json(await ptpService.approveCorrection(req.params.id, req.user));
});

const rejectCorrection = asyncHandler(async (req, res) => {
  res.json(await ptpService.rejectCorrection(req.params.id, req.user, req.body.reason));
});

const markOutcome = asyncHandler(async (req, res) => {
  res.json(await ptpService.markOutcome(req.params.id, req.user, req.body));
});

module.exports = { list, requestCorrection, approveCorrection, rejectCorrection, markOutcome };
