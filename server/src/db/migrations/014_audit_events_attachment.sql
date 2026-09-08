-- Real backing for the "call screenshot" evidence capture that already
-- existed client-side (outcome_forms.dart's NoAnswerForm) but was
-- entirely theatrical — the picked image was required by validation, then
-- silently discarded, never uploaded or stored anywhere. This column is
-- where the uploaded file's on-disk name (see server/uploads/,
-- attachmentRoutes.js) is recorded against the audit event it's evidence
-- for, so Customer History can display it.
ALTER TABLE audit_events
  ADD COLUMN IF NOT EXISTS attachment_path VARCHAR(255) NULL;
