import { Router } from 'express';
import { requireApiKey } from '../auth/apiKeyAuth';
import { getBranches, getBranch } from '../config/branches';
import { getCustomersFromSnapshot } from '../repositories/customerAgeingRepository';
import logger from '../utils/logger';

const router = Router();

router.use(requireApiKey);

/** Branch list for the RE dropdown. */
router.get('/branches', (_req, res) => {
  res.json({ branches: getBranches().map((b) => ({ id: b.id, label: b.label })) });
});

/**
 * Customer ageing report from the MariaDB mirror.
 *   ?branch=<id>   → that branch only
 *   ?branch=all    → every branch (default when omitted)
 */
router.get('/customers', async (req, res) => {
  const branchParam = typeof req.query.branch === 'string' ? req.query.branch : 'all';

  if (branchParam !== 'all' && !getBranch(branchParam)) {
    res.status(400).json({
      message: `Unknown branch "${branchParam}".`,
      branches: getBranches().map((b) => b.id),
    });
    return;
  }

  try {
    const rows = await getCustomersFromSnapshot({ branchId: branchParam });
    const labels = new Map(getBranches().map((b) => [b.id, b.label]));
    res.json({
      branch: branchParam,
      count: rows.length,
      customers: rows.map((r) => ({ ...r, branchLabel: labels.get(r.branchId) ?? r.branchId })),
    });
  } catch (err: any) {
    logger.error(`[reports] /customers failed: ${err.message}`);
    res.status(500).json({ message: 'Failed to load customers.', error: err.message });
  }
});

export default router;
