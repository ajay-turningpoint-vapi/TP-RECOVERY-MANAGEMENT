const { v4: uuid } = require('uuid');
const crypto = require('crypto');
const { query } = require('../config/db');

/** SHA-256 of the raw token — same "never store the usable credential" reasoning as password hashing. */
function hashToken(rawToken) {
  return crypto.createHash('sha256').update(rawToken).digest('hex');
}

/** Cryptographically random, URL-safe, 256 bits of entropy — plenty for a bearer credential. */
function generateRawToken() {
  return crypto.randomBytes(32).toString('base64url');
}

async function insert(userId, rawToken, expiresAt, channel = 'mobile') {
  const id = uuid();
  await query(
    'INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, channel) VALUES (:id, :userId, :tokenHash, :expiresAt, :channel)',
    { id, userId, tokenHash: hashToken(rawToken), expiresAt, channel }
  );
  return id;
}

/** Only a live (unrevoked, unexpired) token counts as valid — everything else is treated as "no such token". */
async function findValidByRawToken(rawToken) {
  const rows = await query(
    'SELECT * FROM refresh_tokens WHERE token_hash = :tokenHash AND revoked_at IS NULL AND expires_at > NOW() LIMIT 1',
    { tokenHash: hashToken(rawToken) }
  );
  return rows[0] || null;
}

async function revokeById(id) {
  await query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = :id', { id });
}

async function revokeByRawToken(rawToken) {
  await query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = :tokenHash', { tokenHash: hashToken(rawToken) });
}

/** "Log out everywhere" — e.g. on a password change. Pass `channel` to revoke only that channel's tokens (a fresh login on one channel leaves the other alone). */
async function revokeAllForUser(userId, channel = null) {
  if (channel) {
    await query(
      'UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = :userId AND channel = :channel AND revoked_at IS NULL',
      { userId, channel }
    );
    return;
  }
  await query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = :userId AND revoked_at IS NULL', { userId });
}

module.exports = { generateRawToken, insert, findValidByRawToken, revokeById, revokeByRawToken, revokeAllForUser };
