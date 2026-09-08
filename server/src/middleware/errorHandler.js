const { AppError, NotFoundError, ValidationError } = require('../errors/AppError');
const logger = require('../config/logger');
const env = require('../config/env');

function notFoundHandler(req, res, next) {
  next(new NotFoundError(`Route ${req.method} ${req.originalUrl}`));
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  // express.json() rejects a malformed body by passing a SyntaxError with
  // this shape from body-parser — treat it as the 400 it really is, not
  // an unexpected server bug.
  if (err.type === 'entity.parse.failed' || (err instanceof SyntaxError && 'body' in err)) {
    err = new ValidationError('Malformed JSON body');
  }

  const isAppError = err instanceof AppError;
  const statusCode = isAppError ? err.statusCode : 500;
  const code = isAppError ? err.code : 'INTERNAL_ERROR';

  const logPayload = {
    requestId: req.id,
    method: req.method,
    path: req.originalUrl,
    statusCode,
    code,
    userId: req.user?.id,
  };

  if (isAppError) {
    // Expected errors (bad input, not found, etc.) — log at warn, no stack noise.
    logger.warn(err.message, logPayload);
  } else {
    // Anything else is a real bug — log the full stack.
    logger.error(err.message, { ...logPayload, stack: err.stack });
  }

  res.status(statusCode).json({
    error: {
      code,
      message: isAppError ? err.message : 'An unexpected error occurred. Please try again.',
      details: isAppError ? err.details : undefined,
      // Stack traces never leave the server outside development.
      stack: !env.isProduction && !isAppError ? err.stack : undefined,
    },
    requestId: req.id,
  });
}

module.exports = { notFoundHandler, errorHandler };
