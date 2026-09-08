-- A task can now carry a real note + attachment (not just the 500-char
-- `reason`) — needed so the auto-created "call customer" follow-up after
-- an RE approve/reject decision (Payment Already Made, Dispute, Internal
-- Action) can hand the salesperson the actual decision details and any
-- evidence file, not just a one-line reason.
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS note VARCHAR(1000) NULL,
  ADD COLUMN IF NOT EXISTS attachment_path VARCHAR(255) NULL;

-- The salesperson's original evidence screenshot (already captured as
-- `attachmentPath` when the outcome was recorded) is threaded straight
-- onto the claim/dispute row at creation, so RE's later verify/approve/
-- reject decision can read it directly instead of re-scraping audit
-- history by type/description matching.
ALTER TABLE payment_claims ADD COLUMN IF NOT EXISTS attachment_path VARCHAR(255) NULL;
ALTER TABLE disputes ADD COLUMN IF NOT EXISTS attachment_path VARCHAR(255) NULL;
