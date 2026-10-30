const { test } = require('node:test');
const assert = require('node:assert/strict');
const scoringService = require('../src/services/scoringService');

test('computeCreditHealthScore returns null (Insufficient History) for a customer with no due, no overdue days, and no PTP history', () => {
  const customer = { totalDue: 0, oldestOverdueDays: 0, disputedAmount: 0, escalationLevel: 'none' };
  assert.equal(scoringService.computeCreditHealthScore(customer, []), null);
  assert.equal(scoringService.creditHealthBand(null), 'Insufficient History');
});

test('computeCreditHealthScore drops for a customer with severe overdue ageing, an open dispute, and an active escalation', () => {
  // The score also uses BUSY's credit limit (exposure) and last receipt
  // (recent trend), so a genuinely healthy account has room on its limit,
  // paid recently and kept its promises.
  const recent = new Date(Date.now() - 5 * 86400000).toISOString();
  const healthy = { totalDue: 1000, totalOutstanding: 1000, creditLimit: 100000, lastPaymentDate: recent, oldestOverdueDays: 0, disputedAmount: 0, escalationLevel: 'none' };
  const unhealthy = { totalDue: 1000, totalOutstanding: 1000, creditLimit: 0, lastPaymentDate: null, oldestOverdueDays: 120, disputedAmount: 500, escalationLevel: 'L2' };
  const kept = [{ status: 'kept' }, { status: 'kept' }];
  const healthyScore = scoringService.computeCreditHealthScore(healthy, kept);
  const unhealthyScore = scoringService.computeCreditHealthScore(unhealthy, [{ status: 'broken' }]);
  assert.ok(healthyScore > unhealthyScore, `expected a healthy account to score higher (${healthyScore} vs ${unhealthyScore})`);
  assert.equal(scoringService.creditHealthBand(healthyScore), 'Low Risk');
});

test('computeCreditHealthScore rewards a real kept-PTP track record over a broken one', () => {
  const customer = { totalDue: 1000, oldestOverdueDays: 10, disputedAmount: 0, escalationLevel: 'none' };
  const reliablePtps = [
    { status: 'kept' },
    { status: 'kept' },
    { status: 'kept' },
  ];
  const unreliablePtps = [
    { status: 'broken' },
    { status: 'broken' },
    { status: 'kept' },
  ];
  const reliableScore = scoringService.computeCreditHealthScore(customer, reliablePtps);
  const unreliableScore = scoringService.computeCreditHealthScore(customer, unreliablePtps);
  assert.ok(reliableScore > unreliableScore);
});

test('computeRecoveryScoreComponents rewards genuine collection performance against target', () => {
  const ownedCustomers = [{ id: 'X1', totalDue: 100000, oldestOverdueDays: 10, escalationLevel: 'none' }];
  // Tier 1 recovery target: 25% of overdue (same as the app's Recovery Target report).
  const target = 100000 * 0.25;
  const goodPtps = [{ customerId: 'X1', status: 'kept', amountReceived: target }];
  const badPtps = [{ customerId: 'X1', status: 'broken', amountReceived: 0 }];
  const empty = { ownedTasks: [], auditByCustomer: new Map(), taskByCustomer: new Map() };

  const good = scoringService.computeRecoveryScoreComponents({ ownedCustomers, ownedPtps: goodPtps, ...empty });
  const bad = scoringService.computeRecoveryScoreComponents({ ownedCustomers, ownedPtps: badPtps, ...empty });
  assert.equal(good.collectionPerformance, 100);
  assert.equal(bad.collectionPerformance, 0);
  assert.ok(good.total > bad.total);
});

test('compareByRecoveryPriority ranks escalation severity above overdue days above amount due', () => {
  const list = [
    { id: 'FRESH_ESCALATED', escalationLevel: 'L1', oldestOverdueDays: 1, totalDue: 100 },
    { id: 'OLD_UNESCALATED', escalationLevel: 'none', oldestOverdueDays: 500, totalDue: 999999 },
  ];
  list.sort(scoringService.compareByRecoveryPriority);
  assert.equal(list[0].id, 'FRESH_ESCALATED', 'even a bare L1 must outrank a non-escalated customer no matter how overdue or large');

  const equalEscalation = [
    { id: 'NEWER', escalationLevel: 'L2', oldestOverdueDays: 10, totalDue: 1000000 },
    { id: 'OLDER', escalationLevel: 'L2', oldestOverdueDays: 90, totalDue: 1000 },
  ];
  equalEscalation.sort(scoringService.compareByRecoveryPriority);
  assert.equal(equalEscalation[0].id, 'OLDER');
});
