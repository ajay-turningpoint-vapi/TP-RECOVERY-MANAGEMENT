import logger from './logger';

/**
 * Retries an async operation with exponential backoff.
 * Used for the initial MSSQL/MariaDB connect step, where a transient
 * network blip shouldn't fail an entire nightly sync run outright.
 */
export async function withRetry<T>(
  label: string,
  fn: () => Promise<T>,
  attempts = 3,
  baseDelayMs = 2000
): Promise<T> {
  let lastErr: any;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (err: any) {
      lastErr = err;
      logger.warn(
        `[retry] ${label} failed (attempt ${attempt}/${attempts}): ${err.message}`
      );
      if (attempt < attempts) {
        const delay = baseDelayMs * attempt;
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
  throw lastErr;
}
