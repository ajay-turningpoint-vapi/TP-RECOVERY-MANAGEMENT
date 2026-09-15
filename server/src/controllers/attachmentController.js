const path = require('path');
const fs = require('fs');
const asyncHandler = require('../middleware/asyncHandler');
const { UPLOADS_DIR } = require('../config/uploads');
const { ValidationError, NotFoundError } = require('../errors/AppError');

/** Stores the uploaded file (multer already wrote it to disk under a fresh uuid name) and hands back that name for the client to reference later — e.g. as record-outcome's `attachmentPath`. */
const upload = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw new ValidationError('No file uploaded — expected a multipart field named "file".');
  }
  res.status(201).json({ path: req.file.filename });
});

/**
 * Streams a previously-uploaded attachment back. `path.basename` strips
 * any directory components the URL param might contain before it ever
 * touches the filesystem, so this can only ever resolve to a file
 * directly inside UPLOADS_DIR — no path traversal via `../../etc/passwd`
 * or similar, regardless of what's in req.params.filename.
 */
const get = asyncHandler(async (req, res) => {
  const safeName = path.basename(req.params.filename);
  const filePath = path.join(UPLOADS_DIR, safeName);
  if (!fs.existsSync(filePath)) {
    throw new NotFoundError('Attachment');
  }
  // A PDF should download rather than try to render inline in whatever
  // opened it — images still stream normally for in-app previews.
  if (safeName.toLowerCase().endsWith('.pdf')) {
    res.setHeader('Content-Disposition', `attachment; filename="${safeName}"`);
  }
  res.sendFile(filePath);
});

module.exports = { upload, get };
