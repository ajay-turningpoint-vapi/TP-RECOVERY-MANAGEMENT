-- Dispute clarification / resolution thread messages can carry an
-- attachment (evidence exchanged back-and-forth between the RE and the
-- resolution-owner salesman while working a dispute).
ALTER TABLE dispute_messages ADD COLUMN IF NOT EXISTS attachment_path VARCHAR(255) NULL;
