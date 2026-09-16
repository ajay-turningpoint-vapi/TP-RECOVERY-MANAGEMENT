-- Single-device login was only enforced at refresh-token rotation (login
-- revokes every other refresh token), which left a gap: an old device's
-- still-valid access token (up to JWT_EXPIRES_IN, e.g. 12h) kept working
-- right alongside a newly-logged-in device until it happened to expire or
-- try to silently refresh. `session_version` closes that gap — bumped on
-- every login/password-change and embedded in the access token; the
-- `authenticate` middleware rejects any token whose embedded version
-- doesn't match the user's current one, logging out every older device's
-- very next request instead of waiting out its remaining TTL.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS session_version INT NOT NULL DEFAULT 1;
