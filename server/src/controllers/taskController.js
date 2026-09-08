const asyncHandler = require('../middleware/asyncHandler');
const taskService = require('../services/taskService');
const internalActionService = require('../services/internalActionService');

const list = asyncHandler(async (req, res) => {
  res.json(await taskService.listForUser(req.user));
});

const complete = asyncHandler(async (req, res) => {
  res.json(await taskService.completeTask(req.params.id, req.user));
});

const requestExtension = asyncHandler(async (req, res) => {
  res.json(await taskService.requestExtension(req.params.id, req.user, req.body));
});

const approveEdit = asyncHandler(async (req, res) => {
  res.json(await taskService.approveEdit(req.params.id, req.user));
});

const rejectEdit = asyncHandler(async (req, res) => {
  res.json(await taskService.rejectEdit(req.params.id, req.user));
});

const reassign = asyncHandler(async (req, res) => {
  res.json(await taskService.reassignTask(req.params.id, req.user, req.body));
});

const reschedule = asyncHandler(async (req, res) => {
  res.json(await taskService.reschedule(req.params.id, req.user, req.body));
});

const markReviewed = asyncHandler(async (req, res) => {
  res.json(await taskService.markReviewed(req.params.id, req.user));
});

const approveInternalAction = asyncHandler(async (req, res) => {
  res.json(await internalActionService.approve(req.params.id, req.user, req.body));
});

const rejectInternalAction = asyncHandler(async (req, res) => {
  res.json(await internalActionService.reject(req.params.id, req.user, req.body));
});

module.exports = {
  list,
  complete,
  requestExtension,
  approveEdit,
  rejectEdit,
  reassign,
  reschedule,
  markReviewed,
  approveInternalAction,
  rejectInternalAction,
};
