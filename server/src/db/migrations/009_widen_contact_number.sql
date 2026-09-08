-- BUSY's MOBILE field sometimes holds multiple numbers in one string
-- (e.g. '9925015086 (a/c Mithun.bhai),9638867777,9723712982' — confirmed
-- real data, up to 50 chars) rather than one phone number — the
-- pre-existing VARCHAR(32) (sized for a single RMS-entered phone number)
-- is too narrow and the sync failed inserting real BUSY customers with
-- "Data too long for column 'contact_number'". Widened generously rather
-- than just barely fitting today's longest value.
ALTER TABLE customers MODIFY COLUMN contact_number VARCHAR(255) NULL;
