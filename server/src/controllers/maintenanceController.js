const asyncHandler = require('../middleware/asyncHandler');
const maintenanceService = require('../services/maintenanceService');

const get = asyncHandler(async (req, res) => {
  res.json(maintenanceService.status());
});

const set = asyncHandler(async (req, res) => {
  const { enabled } = req.body;
  const result = await maintenanceService.setEnabled(enabled, req.user.id);
  res.json(result);
});

module.exports = { get, set };
