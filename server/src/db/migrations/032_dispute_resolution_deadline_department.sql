-- The RE picks a resolution deadline and an internal department when
-- approving a dispute (dispute_assign_view.dart) — both were captured
-- client-side but never persisted anywhere: the deadline only ever made
-- it onto the resolution TASK, never the dispute row itself, and
-- department was dropped before it even left the client. The dispute
-- detail screen reads d['deadline']/d['department'] and always showed
-- "Not Set"/"Not assigned" as a result.
ALTER TABLE disputes
  ADD COLUMN IF NOT EXISTS resolution_deadline DATETIME NULL,
  ADD COLUMN IF NOT EXISTS department VARCHAR(64) NULL;
