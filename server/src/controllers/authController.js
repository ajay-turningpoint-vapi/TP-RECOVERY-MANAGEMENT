const asyncHandler = require('../middleware/asyncHandler');
const authService = require('../services/authService');
const userRepository = require('../repositories/userRepository');

const login = asyncHandler(async (req, res) => {
  const { username, password } = req.body;
  const result = await authService.login(username, password);
  res.json(result);
});

/** No `authenticate` middleware on this route — the refresh token itself is the credential, there's no access token to check yet (it may already be expired, which is the whole point of calling this). */
const refresh = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  const result = await authService.refresh(refreshToken);
  res.json(result);
});

const logout = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  await authService.logout(refreshToken);
  res.status(204).send();
});

const me = asyncHandler(async (req, res) => {
  const user = await userRepository.findById(req.user.id);
  res.json(authService.toPublicUser(user));
});

const changePassword = asyncHandler(async (req, res) => {
  const { newPassword } = req.body;
  const result = await authService.changePassword(req.user.id, newPassword);
  res.json(result);
});

module.exports = { login, refresh, logout, me, changePassword };
