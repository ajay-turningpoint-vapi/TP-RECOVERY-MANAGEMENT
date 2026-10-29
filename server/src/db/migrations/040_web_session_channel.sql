-- The RE web dashboard (re-web/) is a second, independent session channel
-- next to the mobile app: single-device login (028) still applies *within*
-- each channel, but a browser login must not log the same user out of their
-- phone (or vice versa). Web access tokens carry `channel: 'web'` and are
-- checked against `web_session_version`; every refresh token records which
-- channel minted it so a login only revokes that channel's tokens.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS web_session_version INT NOT NULL DEFAULT 1;

ALTER TABLE refresh_tokens
  ADD COLUMN IF NOT EXISTS channel VARCHAR(10) NOT NULL DEFAULT 'mobile';
