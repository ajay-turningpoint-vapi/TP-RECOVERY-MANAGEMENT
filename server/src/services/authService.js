const userRepository = require('../repositories/userRepository');
const refreshTokenRepository = require('../repositories/refreshTokenRepository');
const { verifyPassword, hashPassword } = require('../utils/password');
const { signToken } = require('../utils/jwt');
const env = require('../config/env');
const { UnauthorizedError } = require('../errors/AppError');

function toPublicUser(user) {
  return {
    id: user.id,
    username: user.username,
    role: user.role,
    fullName: user.full_name,
    designation: user.designation,
    branch: user.branch,
  };
}

function refreshTokenExpiry() {
  return new Date(Date.now() + env.refreshToken.ttlDays * 24 * 60 * 60 * 1000);
}

/** Issues both tokens for a user who's already been authenticated by whatever means (password, or a just-rotated refresh token). */
async function issueTokenPair(publicUser) {
  const accessToken = signToken(publicUser);
  const refreshToken = refreshTokenRepository.generateRawToken();
  await refreshTokenRepository.insert(publicUser.id, refreshToken, refreshTokenExpiry());
  return { accessToken, refreshToken };
}

async function login(username, password) {
  const user = await userRepository.findByUsername(username);
  if (!user) {
    throw new UnauthorizedError('Invalid username or password');
  }

  const valid = await verifyPassword(password, user.password_hash);
  if (!valid) {
    throw new UnauthorizedError('Invalid username or password');
  }

  // Single-device login: a fresh password sign-in is the newest session,
  // so every previously-issued refresh token for this user is revoked here.
  // Any other device stays usable only until its short-lived (1h) access
  // token expires — its next silent refresh then fails and it's logged out.
  await refreshTokenRepository.revokeAllForUser(user.id);

  const publicUser = toPublicUser(user);
  const { accessToken, refreshToken } = await issueTokenPair(publicUser);
  return { accessToken, refreshToken, user: publicUser };
}

/**
 * Exchanges a still-valid refresh token for a new access token — and a new
 * refresh token, rotating out the old one (revoked here, not just left to
 * expire) so a refresh token can only ever be used once. This is what lets
 * the app stay logged in for weeks without the 1h access token forcing a
 * real re-login: the client silently calls this on a 401 instead.
 */
async function refresh(rawRefreshToken) {
  if (!rawRefreshToken) {
    throw new UnauthorizedError('Refresh token required');
  }
  const record = await refreshTokenRepository.findValidByRawToken(rawRefreshToken);
  if (!record) {
    // Covers "never existed", "expired", and "already used/revoked" alike —
    // deliberately the same generic message for all three, so a client
    // (or attacker) replaying an old token learns nothing about which case
    // it hit.
    throw new UnauthorizedError('Refresh token is invalid or expired');
  }

  const user = await userRepository.findById(record.user_id);
  if (!user) {
    throw new UnauthorizedError('Refresh token is invalid or expired');
  }

  await refreshTokenRepository.revokeById(record.id);
  const publicUser = toPublicUser(user);
  const { accessToken, refreshToken } = await issueTokenPair(publicUser);
  return { accessToken, refreshToken, user: publicUser };
}

/** Revokes one refresh token — a real, server-side "log out" (unlike just deleting a JWT client-side, this actually invalidates the session). */
async function logout(rawRefreshToken) {
  if (rawRefreshToken) {
    await refreshTokenRepository.revokeByRawToken(rawRefreshToken);
  }
}

/**
 * Sets the signed-in user's password directly — no current-password check
 * (by design: the caller is already authenticated via their access token,
 * which is proof enough here). Revokes every existing refresh token for the
 * user (so any other device is logged out) and issues a fresh token pair for
 * the caller so their current session stays alive seamlessly.
 */
async function changePassword(userId, newPassword) {
  const user = await userRepository.findById(userId);
  if (!user) {
    throw new UnauthorizedError('Authentication required');
  }

  await userRepository.updatePasswordHash(userId, await hashPassword(newPassword));
  await refreshTokenRepository.revokeAllForUser(userId);

  const publicUser = toPublicUser(user);
  const { accessToken, refreshToken } = await issueTokenPair(publicUser);
  return { accessToken, refreshToken, user: publicUser };
}

module.exports = { login, refresh, logout, changePassword, toPublicUser };
