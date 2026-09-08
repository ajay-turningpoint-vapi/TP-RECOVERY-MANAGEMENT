const logger = require('../../config/logger');

/**
 * Retries an async operation with exponential backoff. Used for the
 * initial BUSY MSSQL connect step, where a transient network blip
 * shouldn't fail an entire daily sync run outright.
 */
async function withRetry(label, fn, attempts = 3, baseDelayMs = 2000) {
  let lastErr;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      logger.warn(`[retry] ${label} failed (attempt ${attempt}/${attempts}): ${err.message}`);
      if (attempt < attempts) {
        const delay = baseDelayMs * attempt;
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
  throw lastErr;
}

module.exports = { withRetry };
