const userRepository = require('../repositories/userRepository');
const refreshTokenRepository = require('../repositories/refreshTokenRepository');
const { hashPassword } = require('../utils/password');
const { NotFoundError, ForbiddenError } = require('../errors/AppError');

/**
 * ADMIN-only: resets a salesperson's password directly, no current-password
 * check (same trust model as the self-service authService.changePassword,
 * which this mirrors) — but for an arbitrary target user instead of the
 * caller, and deliberately restricted to SALESPERSON accounts only. An
 * admin can never reset another admin/RE/manager's password this way —
 * closes off a privilege-escalation path (reset their password, log in as
 * them). Every existing session for that salesperson is revoked and
 * session_version bumped, so they're forced to sign back in with the new
 * password — no token pair is returned here, since the admin isn't
 * assuming that session (unlike the self-service flow's own return value).
 */
async function resetSalesmanPassword(targetUserId, newPassword) {
  const user = await userRepository.findById(targetUserId);
  if (!user) {
    throw new NotFoundError('Salesperson');
  }
  if (user.role !== 'SALESPERSON') {
    throw new ForbiddenError('Can only reset a salesperson\'s password.');
  }

  await userRepository.updatePasswordHash(targetUserId, await hashPassword(newPassword));
  await refreshTokenRepository.revokeAllForUser(targetUserId);
  await userRepository.bumpSessionVersion(targetUserId);
}

module.exports = { resetSalesmanPassword };
