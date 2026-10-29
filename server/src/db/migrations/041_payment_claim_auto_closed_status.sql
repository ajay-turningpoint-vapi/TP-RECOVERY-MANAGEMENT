-- A payment claim whose customer no longer appears in BUSY has nothing left
-- to verify against — closed by customerRepository.closeOutRemovedCustomers,
-- the same way that customer's tasks and disputes already are (039).
ALTER TABLE payment_claims MODIFY COLUMN status ENUM('Awaiting Verification','Verified','Failed','Sync Pending','Auto-Closed') NOT NULL DEFAULT 'Awaiting Verification';
