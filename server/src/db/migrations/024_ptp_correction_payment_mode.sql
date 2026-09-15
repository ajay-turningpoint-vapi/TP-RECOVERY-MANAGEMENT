-- PTP correction requests can now change every editable PTP field —
-- amount + promise date/time were already carried; add payment mode.
ALTER TABLE ptps ADD COLUMN IF NOT EXISTS correction_requested_payment_mode VARCHAR(32) NULL;
