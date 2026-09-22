const asyncHandler = require('../middleware/asyncHandler');
const adminService = require('../services/adminService');

const resetSalesmanPassword = asyncHandler(async (req, res) => {
  const { newPassword } = req.body;
  await adminService.resetSalesmanPassword(req.params.id, newPassword);
  res.status(204).send();
});

module.exports = { resetSalesmanPassword };
