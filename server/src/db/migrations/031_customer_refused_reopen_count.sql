-- Tracks how many times the automatic "Customer Refused" call-back task
-- has been re-opened with nothing recorded, so the reopen cadence can grow
-- (2, then 3, then 4, then 5 days, capped) instead of a fixed interval —
-- same pattern as customers.no_answer_attempts for the No Answer cycle.
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS refused_reopen_count INT NOT NULL DEFAULT 0;
