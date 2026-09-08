/**
 * Wrap an async route/middleware handler so a rejected promise (a thrown
 * error inside `await`) is forwarded to Express's error pipeline via
 * next(err), instead of becoming an unhandled rejection. Every controller
 * in this app is wrapped with this — it is the one place that decision is
 * made, so no individual route can forget a try/catch.
 */
function asyncHandler(fn) {
  return function wrapped(req, res, next) {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

module.exports = asyncHandler;
