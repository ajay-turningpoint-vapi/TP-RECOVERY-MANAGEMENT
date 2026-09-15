-- Multi-branch BUSY sync: the customer-ageing job now loops several BUSY
-- company databases in one run (see src/busySync/config/branches.js —
-- "Turning Point" + "Claart"). Every synced row needs to know which
-- branch it came from so the per-run stale sweep can be scoped and not
-- cross-delete the other branch's data.

-- customer_ageing_snapshot: raw BUSY mirror — add branch + a composite
-- index the scoped DELETE sweep uses.
ALTER TABLE customer_ageing_snapshot
  ADD COLUMN IF NOT EXISTS branch VARCHAR(64) NOT NULL DEFAULT 'Turning Point';
ALTER TABLE customer_ageing_snapshot
  ADD INDEX IF NOT EXISTS idx_cas_branch_synced (branch, last_synced_at);

-- sync_runs: one row per branch per run.
ALTER TABLE sync_runs
  ADD COLUMN IF NOT EXISTS branch VARCHAR(64) NULL;
ALTER TABLE sync_runs
  ADD INDEX IF NOT EXISTS idx_sync_runs_branch (branch, job_name, status);

-- customers already has `branch` (migration 011). The BUSY sync now
-- writes it for real; index it for the scoped soft-deactivate sweep and
-- the app's branch filters.
ALTER TABLE customers
  ADD INDEX IF NOT EXISTS idx_customers_branch (branch);

-- Backfill: the salesman accounts already created by the single-branch
-- sync are all Turning Point. Give them the display-name suffix the
-- multi-branch sync maintains from now on (idempotent — skips names that
-- already carry a suffix).
UPDATE users
  SET full_name = CONCAT(full_name, ' -TP')
  WHERE role = 'SALESPERSON'
    AND busy_salesman_code IS NOT NULL
    AND full_name NOT LIKE '% -TP'
    AND full_name NOT LIKE '% -Claart';
