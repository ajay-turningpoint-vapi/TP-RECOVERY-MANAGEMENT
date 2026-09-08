const { ValidationError } = require('../errors/AppError');

/**
 * Validates req.body (default) or another request part against a Zod
 * schema, replacing it with the parsed/coerced value on success. Every
 * write endpoint uses this — validation logic lives once, in the route's
 * schema, not duplicated across controllers.
 */
function validate(schema, part = 'body') {
  return function (req, res, next) {
    const result = schema.safeParse(req[part]);
    if (!result.success) {
      throw new ValidationError('Invalid request', result.error.flatten());
    }
    req[part] = result.data;
    next();
  };
}

module.exports = validate;
