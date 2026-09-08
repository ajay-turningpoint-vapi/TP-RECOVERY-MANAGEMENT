-- Maps an RMS `users` account (role SALESPERSON) to the BUSY ERP salesman
-- code (MASTER1.CODE, e.g. 633582) that scopes which
-- BUSY_SOURCE_DATA.customer_ageing_snapshot rows they see. NULL for
-- non-salesperson roles and any salesperson not yet mapped.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS busy_salesman_code INT NULL,
  ADD INDEX IF NOT EXISTS idx_users_busy_salesman_code (busy_salesman_code);
