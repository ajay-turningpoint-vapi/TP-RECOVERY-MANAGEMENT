-- Neither BUSY nor this app has ever had real per-user/per-customer branch
-- data (confirmed: NULL for 30/32 users, all 1335/1335 real customers) —
-- the client was papering over this with scattered, inconsistent
-- fallbacks (some screens crashed outright on the null, one stale model
-- default said 'Mumbai' from back before real BUSY data existed). Fixing
-- it once at the source: every user/customer with no real branch is
-- 'Turning Point' (the company itself, since there's no real branch
-- concept yet) — a genuine default the API always returns, not a
-- client-side patch every screen has to remember to apply.
-- UPDATE before ALTER: MariaDB's implicit NULL->'' coercion during the
-- NOT-NULL conversion trips WARN_DATA_TRUNCATED under strict mode if any
-- NULLs remain when the ALTER runs — clearing them first avoids it.
UPDATE users SET branch = 'Turning Point' WHERE branch IS NULL OR branch = '';
ALTER TABLE users MODIFY COLUMN branch VARCHAR(64) NOT NULL DEFAULT 'Turning Point';

UPDATE customers SET branch = 'Turning Point' WHERE branch IS NULL OR branch = '';
ALTER TABLE customers MODIFY COLUMN branch VARCHAR(64) NOT NULL DEFAULT 'Turning Point';
