const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { v4: uuid } = require('uuid');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const ptpRepository = require('../src/repositories/ptpRepository');
const customerRepository = require('../src/repositories/customerRepository');
const taskRepository = require('../src/repositories/taskRepository');
const { promoteDuePtps, finalizeDuePtps } = require('../src/services/ptpVerificationService');

// No HTTP app needed, but ptpService.js (via escalationService/decisionNotify)
// pulls in the notification queue's Redis connection at require time — reuse
// teardownAll(null) so that gets closed too, not just the MariaDB pool.
// BUSY itself is stubbed via the injectable getReceiptTotals seam (see
// ptpVerificationService.js) — no MSSQL connection is ever made here.

// promoteDuePtps()/finalizeDuePtps() scan the *whole* ptps table — sharing
// seeded rows (P1/P2/P5 have long-past due dates) across tests would let one
// test's run finalize another test's fixture data out from under it, so
// every test gets a fresh reseed.
beforeEach(async () => {
  await resetDb();
  // Neutralize the seed's other still-'scheduled' PTPs (P1/P2/P5, all with
  // long-past due dates) to a terminal state so they never become noise
  // candidates for promoteDuePtps()/finalizeDuePtps() in these tests — every
  // test below wants to reason about only the PTP(s) it explicitly inserts.
  // P3 ('kept') and P4 ('broken', needed by the escalation test) are
  // already terminal and left alone.
  for (const id of ['P1', 'P2', 'P5']) {
    await ptpRepository.update(id, { status: 'kept', amountReceived: 0 });
  }
});

after(async () => {
  await teardownAll(null);
});

// Mirrors ptpVerificationService.js's istDateStr()/addDaysStr() exactly, so
// "today"/"N days ago" here always agrees with what the service computes —
// a plain UTC offset would drift by a day around the IST/UTC boundary.
function istToday() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());
}
function dateStr(offsetDays) {
  const d = new Date(`${istToday()}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + offsetDays);
  return d.toISOString().slice(0, 10);
}

/** Inserts a fresh PTP row on an existing seed customer, with a controlled promise_date/status. */
async function insertPtp({ customerId, amount, promiseDateOffsetDays, status = 'scheduled', promiseTime = '12:00:00' }) {
  const id = uuid();
  await ptpRepository.insert({
    id,
    customerId,
    amountPromised: amount,
    promiseDate: `${dateStr(promiseDateOffsetDays)} ${promiseTime}`,
    paymentMode: 'Bank Transfer',
    status,
  });
  return id;
}

/** A getReceiptTotals stub that also records every window it was called with. */
function stubReceipts(rowsByWindow) {
  const calls = [];
  const fn = async ({ startDate, endDate }) => {
    calls.push({ startDate, endDate });
    return rowsByWindow[`${startDate}|${endDate}`] || [];
  };
  fn.calls = calls;
  return fn;
}

test('a PTP whose promise time has passed is promoted to pendingVerification', async () => {
  // Promotion is now exact-time (00:00:01 today is always already past when
  // the test runs), not a whole-calendar-day cutoff.
  const id = await insertPtp({ customerId: 'C1', amount: 5000, promiseDateOffsetDays: 0, promiseTime: '00:00:01' });
  await promoteDuePtps();
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'pendingVerification');
});

test('a PTP whose promise time is still in the future stays scheduled', async () => {
  const id = await insertPtp({ customerId: 'C1', amount: 5000, promiseDateOffsetDays: 0, promiseTime: '23:59:59' });
  await promoteDuePtps();
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'scheduled');
});

test('a PTP due in the future stays scheduled', async () => {
  const id = await insertPtp({ customerId: 'C1', amount: 5000, promiseDateOffsetDays: 3 });
  await promoteDuePtps();
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'scheduled');
});

test('inside the 1-day grace period, a pendingVerification PTP is left untouched', async () => {
  const id = await insertPtp({ customerId: 'C2', amount: 5000, promiseDateOffsetDays: 0, status: 'pendingVerification' });
  const getReceiptTotals = stubReceipts({});
  await finalizeDuePtps(getReceiptTotals);
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'pendingVerification', 'must not finalize before the grace period elapses');
  assert.equal(getReceiptTotals.calls.length, 0, 'must not even query BUSY for a PTP still inside its grace period');
});

test('exact payment (BUSY TOTAL_AMOUNT == PTP amount) → kept', async () => {
  const id = await insertPtp({ customerId: 'C2', amount: 10000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals = stubReceipts({ [window]: [{ customerId: 'C2', customerName: 'XYZ Enterprises', totalEntries: 1, totalAmount: 10000 }] });
  const result = await finalizeDuePtps(getReceiptTotals);
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'kept');
  assert.equal(ptp.amountReceived, 10000);
  assert.equal(result.kept >= 1, true);
});

test('overpayment (BUSY TOTAL_AMOUNT > PTP amount) → kept, amountReceived clamped to the promised amount', async () => {
  const id = await insertPtp({ customerId: 'C1', amount: 6000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals = stubReceipts({ [window]: [{ customerId: 'C1', customerName: 'ABC Traders', totalEntries: 1, totalAmount: 6800 }] });
  await finalizeDuePtps(getReceiptTotals);
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'kept');
  assert.equal(ptp.amountReceived, 6000, 'amountReceived must clamp at the promised amount, not the raw BUSY total');
});

test('partial payment (0 < BUSY TOTAL_AMOUNT < PTP amount) → partiallyKept with the real received amount', async () => {
  const id = await insertPtp({ customerId: 'C3', amount: 10000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals = stubReceipts({ [window]: [{ customerId: 'C3', customerName: 'PQR Stores', totalEntries: 1, totalAmount: 6800 }] });
  await finalizeDuePtps(getReceiptTotals);
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'partiallyKept');
  assert.equal(ptp.amountReceived, 6800);
});

test('TOTAL_ENTRIES is never used for the decision — many small entries below the promise still resolve to partiallyKept, not kept', async () => {
  const id = await insertPtp({ customerId: 'C5', amount: 10000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals = stubReceipts({ [window]: [{ customerId: 'C5', customerName: 'Om Sai Enterprises', totalEntries: 7, totalAmount: 2000 }] });
  await finalizeDuePtps(getReceiptTotals);
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'partiallyKept', 'TOTAL_ENTRIES=7 must not be mistaken for "fulfilled" — only TOTAL_AMOUNT counts');
});

test('no matching BUSY row for the customer, after the grace period → broken', async () => {
  const id = await insertPtp({ customerId: 'C1', amount: 10000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const getReceiptTotals = stubReceipts({}); // no rows at all
  await finalizeDuePtps(getReceiptTotals);
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'broken');
  assert.equal(ptp.amountReceived, null);
  assert.ok(ptp.brokenReason);
});

test('matching is by CUSTOMER_ID, not CUSTOMER_NAME — a row with the right id but a mismatched/garbled name still counts', async () => {
  const id = await insertPtp({ customerId: 'C2', amount: 5000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals = stubReceipts({
    [window]: [{ customerId: 'C2', customerName: 'TOTALLY DIFFERENT NAME (R)', totalEntries: 1, totalAmount: 5000 }],
  });
  await finalizeDuePtps(getReceiptTotals);
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'kept', 'the id matched — the name mismatch must not matter');
});

test('the BUSY query window used is [promise_date, promise_date + 1 day] — the eligible receipt window', async () => {
  await insertPtp({ customerId: 'C3', amount: 5000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const getReceiptTotals = stubReceipts({});
  await finalizeDuePtps(getReceiptTotals);
  assert.ok(getReceiptTotals.calls.some((c) => c.startDate === dateStr(-2) && c.endDate === dateStr(-1)));
});

test('idempotent: running finalizeDuePtps again does not re-examine or change an already-finalized PTP', async () => {
  const id = await insertPtp({ customerId: 'C5', amount: 4000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals1 = stubReceipts({ [window]: [{ customerId: 'C5', customerName: 'Om Sai Enterprises', totalEntries: 1, totalAmount: 4000 }] });
  await finalizeDuePtps(getReceiptTotals1);
  const first = await ptpRepository.findById(id);
  assert.equal(first.status, 'kept');

  const getReceiptTotals2 = stubReceipts({ [window]: [{ customerId: 'C5', customerName: 'Om Sai Enterprises', totalEntries: 1, totalAmount: 0 }] });
  const result2 = await finalizeDuePtps(getReceiptTotals2);
  const second = await ptpRepository.findById(id);
  assert.equal(second.status, 'kept', 'a finalized PTP must never be re-decided by a later run');
  assert.equal(getReceiptTotals2.calls.length, 0, 'an already-finalized PTP must not be a candidate at all on the next run');
  assert.equal(result2.examined, 0);
});

test('idempotent: running promoteDuePtps again does not touch an already-pendingVerification PTP', async () => {
  const id = await insertPtp({ customerId: 'C1', amount: 3000, promiseDateOffsetDays: 0, status: 'pendingVerification' });
  const promoted = await promoteDuePtps();
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'pendingVerification', 'still pendingVerification — promotion only ever touches status=scheduled rows');
  assert.equal(promoted, 0, 'nothing new to promote on this run');
});

test('a fully broken PTP still drives the existing broken-PTP escalation ladder', async () => {
  // C4 already has one broken seed PTP (P4) — a 2nd broken PTP here reaches L2.
  const id = await insertPtp({ customerId: 'C4', amount: 20000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const getReceiptTotals = stubReceipts({});
  await finalizeDuePtps(getReceiptTotals);
  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'broken');

  const c4 = await customerRepository.findById('C4');
  assert.equal(c4.escalationLevel, 'L2', '2 broken PTPs (seed P4 + this one) must reach L2 via the shared escalation path');
});

test('a broken PTP reopens recovery and creates an urgent follow-up task for the salesperson', async () => {
  // C3 has no other open task and no other active PTP (P3 is already
  // 'kept', terminal) — the clean case where the reopen guard must fire.
  await customerRepository.update('C3', { currentRecoveryState: 'Waiting / Monitoring', primaryNextAction: '' });
  const id = await insertPtp({ customerId: 'C3', amount: 5000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const getReceiptTotals = stubReceipts({});
  await finalizeDuePtps(getReceiptTotals);

  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'broken');

  const c3 = await customerRepository.findById('C3');
  assert.equal(c3.currentRecoveryState, 'Action Required', 'customer must reappear in the salesperson\'s active queue');
  assert.equal(c3.primaryNextAction, 'CALL CUSTOMER');

  const tasks = await taskRepository.findByCustomer('C3');
  const newTask = tasks.find((t) => t.source === 'Recovery');
  assert.ok(newTask, 'a new follow-up task must be created for the salesperson');
  assert.equal(newTask.type, 'customerCall');
  assert.equal(newTask.priority, 'High');
  assert.equal(newTask.ownerId, 'rahul');
  assert.match(newTask.reason, /Collect ₹/, 'the task says exactly what to collect');

  const c3Detail = await customerRepository.findById('C3');
  assert.ok(c3Detail, 'sanity: customer still exists');
});

test('a broken PTP does NOT create a call task when a physical visit has taken over', async () => {
  // C1 already has an open seed physicalVisit task (T1) — the visit is the
  // next step, so reopenRecoveryAfterPtpOutcome must not stack a call task,
  // and must not touch currentRecoveryState.
  await customerRepository.update('C1', { currentRecoveryState: 'Waiting / Monitoring', primaryNextAction: '' });
  const id = await insertPtp({ customerId: 'C1', amount: 5000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const getReceiptTotals = stubReceipts({});
  await finalizeDuePtps(getReceiptTotals);

  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'broken');

  const tasksBefore = await taskRepository.findByCustomer('C1');
  const recoveryTasks = tasksBefore.filter((t) => t.source === 'Recovery');
  assert.equal(recoveryTasks.length, 0, 'must not create a call task while a physical visit is open');

  const c1 = await customerRepository.findById('C1');
  assert.equal(c1.currentRecoveryState, 'Waiting / Monitoring', 'must not touch recovery state when the visit holds the account');
});

test('a kept PTP that still leaves a balance due creates a normal-priority follow-up — the chase continues, not just on broken', async () => {
  // C3 has no other open task and no other active PTP (P3 is already
  // 'kept', terminal). The PTP amount (10000) is far less than C3's
  // seeded total_due, so real money remains even though this PTP itself
  // was fully kept.
  await customerRepository.update('C3', { currentRecoveryState: 'Waiting / Monitoring', primaryNextAction: '' });
  const id = await insertPtp({ customerId: 'C3', amount: 10000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals = stubReceipts({ [window]: [{ customerId: 'C3', customerName: 'PQR Stores', totalEntries: 1, totalAmount: 10000 }] });
  await finalizeDuePtps(getReceiptTotals);

  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'kept');

  const c3 = await customerRepository.findById('C3');
  assert.ok(c3.totalDue > 0, 'sanity: balance genuinely remains after this PTP');
  assert.equal(c3.currentRecoveryState, 'Action Required', 'a kept PTP with balance remaining must still reopen recovery');
  assert.equal(c3.primaryNextAction, 'CALL CUSTOMER');

  const tasks = await taskRepository.findByCustomer('C3');
  const newTask = tasks.find((t) => t.source === 'Recovery');
  assert.ok(newTask, 'a follow-up task must be created even though the PTP itself was kept, not broken');
  assert.equal(newTask.type, 'customerCall');
  assert.equal(newTask.priority, 'Normal', 'kept/partiallyKept follow-ups are normal urgency, unlike broken');
});

test('a kept PTP that fully clears the balance does NOT create a follow-up task — the chase stops exactly at ₹0', async () => {
  await customerRepository.update('C3', { currentRecoveryState: 'Waiting / Monitoring', primaryNextAction: '', totalDue: 0 });
  const id = await insertPtp({ customerId: 'C3', amount: 10000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals = stubReceipts({ [window]: [{ customerId: 'C3', customerName: 'PQR Stores', totalEntries: 1, totalAmount: 10000 }] });
  await finalizeDuePtps(getReceiptTotals);

  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'kept');

  const tasks = await taskRepository.findByCustomer('C3');
  const newTask = tasks.find((t) => t.source === 'Recovery');
  assert.equal(newTask, undefined, 'no follow-up task once the customer genuinely owes nothing');

  const c3 = await customerRepository.findById('C3');
  assert.equal(c3.currentRecoveryState, 'Waiting / Monitoring', 'recovery state must not be reopened when nothing is due');
});

test('a partially kept PTP (balance necessarily remains) creates a normal-priority follow-up', async () => {
  await customerRepository.update('C3', { currentRecoveryState: 'Waiting / Monitoring', primaryNextAction: '' });
  const id = await insertPtp({ customerId: 'C3', amount: 10000, promiseDateOffsetDays: -2, status: 'pendingVerification' });
  const window = `${dateStr(-2)}|${dateStr(-1)}`;
  const getReceiptTotals = stubReceipts({ [window]: [{ customerId: 'C3', customerName: 'PQR Stores', totalEntries: 1, totalAmount: 6800 }] });
  await finalizeDuePtps(getReceiptTotals);

  const ptp = await ptpRepository.findById(id);
  assert.equal(ptp.status, 'partiallyKept');

  const c3 = await customerRepository.findById('C3');
  assert.equal(c3.currentRecoveryState, 'Action Required');
  assert.equal(c3.primaryNextAction, 'CALL CUSTOMER');

  const tasks = await taskRepository.findByCustomer('C3');
  const newTask = tasks.find((t) => t.source === 'Recovery');
  assert.ok(newTask, 'a follow-up task must be created for the remaining balance');
  assert.equal(newTask.priority, 'Normal');
});
