import { Request, Response, NextFunction } from 'express';
import logger from '../utils/logger';

/**
 * Lightweight shared-secret guard for the RE-facing read endpoints
 * (/api/reports/*). The RE mobile app has no admin account, so instead
 * it sends a static key in `x-api-key`, checked against RE_API_KEY.
 *
 * If RE_API_KEY is unset the guard is open (dev convenience) but logs a
 * warning on every request so it can't be missed in a real deployment.
 */
const RE_API_KEY = process.env.RE_API_KEY || '';

export function requireApiKey(req: Request, res: Response, next: NextFunction): void {
  if (!RE_API_KEY) {
    logger.warn('[api-key] RE_API_KEY is not set — /api/reports is unauthenticated.');
    next();
    return;
  }

  const presented = req.headers['x-api-key'];
  if (typeof presented === 'string' && presented === RE_API_KEY) {
    next();
    return;
  }

  res.status(401).json({ message: 'Missing or invalid API key.' });
}
