-- Multi-branch support: each branch is a separate BUSY company DB, so a
-- customer's BUSY CODE (customer_id) is only unique *within* a branch.
-- Tag every mirrored row with its branch and make (branch_id, customer_id)
-- the identity, so syncing one branch never collides with or sweeps
-- another branch's rows.
--
-- Idempotent: MariaDB supports ADD COLUMN / DROP PRIMARY KEY / ADD PRIMARY
-- KEY guarded by information_schema checks below is overkill — instead we
-- rely on ADD COLUMN IF NOT EXISTS and a conditional key rebuild.

ALTER TABLE customer_ageing_snapshot
  ADD COLUMN IF NOT EXISTS branch_id VARCHAR(32) NOT NULL DEFAULT 'default' AFTER customer_id;

-- Rebuild the primary key as (branch_id, customer_id) only if it isn't already.
SET @pk_cols := (
  SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'customer_ageing_snapshot'
    AND INDEX_NAME = 'PRIMARY'
);

SET @sql := IF(
  @pk_cols = 'branch_id,customer_id',
  'SELECT "PK already (branch_id, customer_id)"',
  'ALTER TABLE customer_ageing_snapshot DROP PRIMARY KEY, ADD PRIMARY KEY (branch_id, customer_id)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Helpful for "?branch=<id>" reads.
CREATE INDEX IF NOT EXISTS idx_branch_id ON customer_ageing_snapshot (branch_id);
