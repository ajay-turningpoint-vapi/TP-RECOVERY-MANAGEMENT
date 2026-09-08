-- Refresh tokens, stored hashed (never the raw token — same reasoning as
-- password_hash: a DB leak must not directly hand out usable credentials).
-- Rotated on every use (old row revoked, new row issued) so a stolen,
-- already-used refresh token is inert going forward. Real server-side
-- revocation (unlike a stateless JWT) is what makes "log out" and
-- "log out everywhere" actually possible.
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id VARCHAR(36) NOT NULL,
  user_id VARCHAR(36) NOT NULL,
  token_hash CHAR(64) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_refresh_tokens_hash (token_hash),
  KEY idx_refresh_tokens_user (user_id),
  KEY idx_refresh_tokens_expires (expires_at),
  CONSTRAINT fk_refresh_tokens_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci;
