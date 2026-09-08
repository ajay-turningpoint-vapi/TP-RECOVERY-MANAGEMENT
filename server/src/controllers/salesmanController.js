const asyncHandler = require('../middleware/asyncHandler');
const salesmanService = require('../services/salesmanService');

const list = asyncHandler(async (req, res) => {
  const roster = await salesmanService.listRoster();
  res.json(roster);
});

module.exports = { list };
