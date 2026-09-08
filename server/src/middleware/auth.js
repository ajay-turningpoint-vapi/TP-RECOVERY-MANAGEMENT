const { verifyToken } = require('../utils/jwt');
const { UnauthorizedError, ForbiddenError } = require('../errors/AppError');

/**
 * Requires a valid `Authorization: Bearer <token>` header. On success,
 * attaches the decoded payload as `req.user` ({ id, username, role,
 * fullName }) for downstream handlers and the request logger.
 */
function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    throw new UnauthorizedError('Missing or malformed Authorization header');
  }

  try {
    req.user = verifyToken(token);
  } catch {
    throw new UnauthorizedError('Invalid or expired token');
  }

  next();
}

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
