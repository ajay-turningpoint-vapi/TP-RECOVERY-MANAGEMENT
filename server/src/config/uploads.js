const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { v4: uuid } = require('uuid');

// Real, on-disk storage for evidence attachments (call screenshots today —
// see customerService.recordOutcome / attachmentRoutes.js). This is a
// single on-prem LAN server (see the earlier production-readiness pass on
// this app), so local disk is the right call — no S3/object-store
// dependency to stand up for one server that already owns its own storage.
const UPLOADS_DIR = path.resolve(__dirname, '..', '..', 'uploads');
fs.mkdirSync(UPLOADS_DIR, { recursive: true });

const ALLOWED_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);
const MAX_FILE_SIZE_BYTES = 8 * 1024 * 1024; // 8MB — a phone screenshot/photo or a short PDF, not arbitrary uploads.

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, UPLOADS_DIR),
  // Never trust the client-supplied original filename for the on-disk
  // name — a fresh uuid sidesteps path traversal and collisions entirely;
  // the original name is discarded (not needed for evidence photos).
  filename: (req, file, cb) => {
    let ext = path.extname(file.originalname).toLowerCase();
    if (!ext) ext = file.mimetype === 'application/pdf' ? '.pdf' : '.jpg';
    cb(null, `${uuid()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: MAX_FILE_SIZE_BYTES, files: 1 },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_MIME_TYPES.has(file.mimetype)) {
      cb(new Error('Only JPEG, PNG, or WEBP images are accepted.'));
      return;
    }
    cb(null, true);
  },
});

module.exports = { upload, UPLOADS_DIR, MAX_FILE_SIZE_BYTES };
