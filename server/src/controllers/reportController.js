const asyncHandler = require('../middleware/asyncHandler');
const reportService = require('../services/reportService');

const dashboard = asyncHandler(async (req, res) => {
  const data = await reportService.getDashboard(req.user);
  res.json(data);
});

const trends = asyncHandler(async (req, res) => {
  const data = await reportService.getTrends();
  res.json(data);
});

const rePerformance = asyncHandler(async (req, res) => {
  const data = await reportService.getRePerformance();
  res.json(data);
});

module.exports = { dashboard, trends, rePerformance };
