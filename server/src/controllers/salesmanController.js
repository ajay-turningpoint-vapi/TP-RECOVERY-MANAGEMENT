const asyncHandler = require('../middleware/asyncHandler');
const salesmanService = require('../services/salesmanService');

const list = asyncHandler(async (req, res) => {
  const roster = await salesmanService.listRoster();
  res.json(roster);
});

const dismissUnderperformance = asyncHandler(async (req, res) => {
  res.json(await salesmanService.dismissUnderperformance(req.params.id, req.user));
});

module.exports = { list, dismissUnderperformance };
