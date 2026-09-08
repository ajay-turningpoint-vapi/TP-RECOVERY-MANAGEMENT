import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { Request, Response, NextFunction } from 'express';
import logger from '../utils/logger';

const JWT_SECRET = process.env.ADMIN_JWT_SECRET || '';
const TOKEN_TTL = '8h';

if (!JWT_SECRET) {
  // Fail loudly at startup rather than silently signing tokens with an
  // empty secret — this guards admin-only sync controls.
  throw new Error('ADMIN_JWT_SECRET is not set in .env — refusing to start with an insecure default.');
}

export interface AdminTokenPayload {
  username: string;
  role: 'admin';
}

/** Verifies username/password against the single configured admin account and issues a JWT. */
export async function loginAdmin(username: string, password: string): Promise<string | null> {
  const expectedUsername = process.env.ADMIN_USERNAME || '';
  const expectedPasswordHash = process.env.ADMIN_PASSWORD_HASH || '';

  if (!expectedUsername || !expectedPasswordHash) {
    logger.error('[admin-auth] ADMIN_USERNAME / ADMIN_PASSWORD_HASH not configured.');
    return null;
  }

  if (username !== expectedUsername) {
    return null;
  }

  const matches = await bcrypt.compare(password, expectedPasswordHash);
  if (!matches) {
    return null;
  }

  const payload: AdminTokenPayload = { username, role: 'admin' };
  return jwt.sign(payload, JWT_SECRET, { expiresIn: TOKEN_TTL });
}

/** Express middleware — blocks any route unless a valid admin JWT is presented. */
export function requireAdmin(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) {
    res.status(401).json({ message: 'Missing admin token.' });
    return;
  }

  try {
    const payload = jwt.verify(token, JWT_SECRET) as AdminTokenPayload;
    if (payload.role !== 'admin') {
      res.status(403).json({ message: 'Not an admin token.' });
      return;
    }
    (req as any).admin = payload;
    next();
  } catch (err: any) {
    res.status(401).json({ message: 'Invalid or expired admin token.' });
  }
}
