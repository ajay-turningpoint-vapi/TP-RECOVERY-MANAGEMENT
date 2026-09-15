-- The BUSY customer-invoice sync now loops the same branches as the
-- ageing sync (src/busySync/config/branches.js). Each invoice row needs
-- its branch so the per-run stale sweep is scoped and doesn't wipe the
-- other branch's invoices.
ALTER TABLE customer_invoice_snapshot
  ADD COLUMN IF NOT EXISTS branch VARCHAR(64) NOT NULL DEFAULT 'Turning Point';
ALTER TABLE customer_invoice_snapshot
  ADD INDEX IF NOT EXISTS idx_cis_branch_synced (branch, last_synced_at);
