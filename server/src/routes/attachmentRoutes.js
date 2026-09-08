const { Router } = require('express');
const multer = require('multer');
const { authenticate } = require('../middleware/auth');
const { upload: multerUpload } = require('../config/uploads');
const controller = require('../controllers/attachmentController');
const { ValidationError } = require('../errors/AppError');

const router = Router();

/**
 * Wraps multer's single-file middleware so its own errors (file too
 * large, wrong type, no field at all) come back as this app's normal
 * {error:{message}} shape via the real error pipeline instead of an
 * unhandled-exception 500 — multer throws MulterError/plain Error
 * objects, not AppError, so the generic handler would otherwise mask a
 * genuinely user-actionable message ("file too large") behind a vague
 * "Internal Server Error" in production.
 */
function uploadSingle(req, res, next) {
  multerUpload.single('file')(req, res, (err) => {
    if (!err) return next();
    if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
      return next(new ValidationError('That file is too large — the limit is 8MB.'));
    }
    next(new ValidationError(err.message || 'Could not process the uploaded file.'));
  });
}

// Any authenticated role can upload/view evidence attachments — same
// trust model as the rest of this app's authenticated-but-not-further-
// scoped GETs (see attachmentController.js's own path-traversal guard for
// what IS strictly enforced: which file, not who can ask for one).
router.post('/', authenticate, uploadSingle, controller.upload);
router.get('/:filename', authenticate, controller.get);

module.exports = router;
