const { verifyToken } = require('../utils/jwt');
const { UnauthorizedError, ForbiddenError } = require('../errors/AppError');
const userRepository = require('../repositories/userRepository');
const asyncHandler = require('./asyncHandler');

/**
 * Requires a valid `Authorization: Bearer <token>` header. On success,
 * attaches the decoded payload as `req.user` ({ id, username, role,
 * fullName }) for downstream handlers and the request logger.
 *
 * Also enforces single-device login: every access token embeds the
 * `session_version` that was current when it was issued (authService.js).
 * A fresh login/password-change bumps that version in the `users` row —
 * so an older device's token, still cryptographically valid and unexpired,
 * gets rejected here on its very next request the moment a newer login
 * happens elsewhere, rather than staying usable until it expires.
 */
const authenticate = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    throw new UnauthorizedError('Missing or malformed Authorization header');
  }

  let payload;
  try {
    payload = verifyToken(token);
  } catch {
    throw new UnauthorizedError('Invalid or expired token');
  }

  const currentVersion = await userRepository.getSessionVersion(payload.id);
  if (currentVersion == null || payload.sessionVersion !== currentVersion) {
    throw new UnauthorizedError('Signed in on another device — please log in again');
  }

  req.user = payload;
  next();
});

/**
 * Restrict a route to one or more roles, e.g. authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT').
 * Must run after `authenticate`.
 */
function authorize(...allowedRoles) {
  return function (req, res, next) {
    if (!req.user) {
      throw new UnauthorizedError();
    }
    if (!allowedRoles.includes(req.user.role)) {
      throw new ForbiddenError(`This action requires one of: ${allowedRoles.join(', ')}`);
    }
    next();
  };
}

module.exports = { authenticate, authorize };
