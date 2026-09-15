const { Router } = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const { authenticate, authorize } = require('../middleware/auth');
const controller = require('../controllers/customerController');

const router = Router();
router.use(authenticate);

const recordOutcomeSchema = z.object({
  nextAction: z.string().min(1),
  reason: z.string().min(1),
  details: z.string().min(1),
  followUpAt: z.coerce.date().optional(),
  ptpAmountValue: z.coerce.number().positive().optional(),
  ptpDate: z.coerce.date().optional(),
  ptpMode: z.string().optional(),
  // The on-disk filename an earlier POST /api/attachments call returned —
  // never a client-supplied path/URL, so there's no path-injection surface
  // here; attachmentRoutes.js's own GET validates it against what's
  // actually on disk before ever touching the filesystem again.
  attachmentPath: z.string().min(1).optional(),
  // Set only by "Edit Recorded Outcome" (Today's Recovery Tasks) replacing
  // a prior No Answer — see customerService.recordOutcome's
  // `replacingNoAnswer` branch.
  replacingNoAnswer: z.boolean().optional(),
});

const reassignSchema = z.object({
  toSalesmanId: z.string().min(1),
  reason: z.string().min(1),
});

const instructionSchema = z.object({
  salesmanId: z.string().min(1),
  desc: z.string().min(1),
  deadline: z.coerce.date(),
  priority: z.enum(['Low', 'Normal', 'High', 'Critical']).optional(),
  // Defaults to a Management Instruction (overrides the salesperson's own
  // judgment). RE can instead assign a plain 'customerCall' or
  // 'physicalVisit' task — same endpoint, just a different task type/label.
  taskType: z.enum(['managementInstruction', 'customerCall', 'physicalVisit']).optional(),
  // Optional evidence the RE attaches when creating a call/visit task.
  note: z.string().optional(),
  attachmentPath: z.string().optional(),
});

router.get('/', controller.list);
router.get('/next', controller.getNext);
router.get('/:id', controller.getOne);
router.post('/:id/record-outcome', validate(recordOutcomeSchema), controller.recordOutcome);
router.post('/:id/take-control', authorize('RECOVERY_EXECUTIVE'), controller.takeControl);
router.post('/:id/release-control', authorize('RECOVERY_EXECUTIVE'), controller.releaseControl);
router.post('/:id/reassign', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(reassignSchema), controller.reassign);
router.post('/:id/management-instruction', authorize('RECOVERY_EXECUTIVE', 'MANAGEMENT'), validate(instructionSchema), controller.assignInstruction);

module.exports = router;
