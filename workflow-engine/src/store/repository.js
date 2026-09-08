import { state } from './state.js';
import { withLock } from './mutex.js';

// The single seam between "business logic" and "current world state."
// Swapping the in-memory Map()s in state.js for real DB queries later
// should only require rewriting this file.

export class NotFoundError extends Error {
  constructor(entity, id) {
    super(`${entity} not found: ${id}`);
    this.name = 'NotFoundError';
    this.entity = entity;
    this.id = id;
  }
}

// ---- Customers ----

export function getCustomer(id) {
  const c = state.customers.get(id);
  if (!c) throw new NotFoundError('Customer', id);
  return c;
}

export function tryGetCustomer(id) {
  return state.customers.get(id) || null;
}

export function listCustomers() {
  return [...state.customers.values()];
}

export function listCustomersForSalesman(salesmanId) {
  return listCustomers().filter((c) => c.assignedSalesmanId === salesmanId);
}

/** Read-modify-write a customer under its per-id lock. `mutator` receives the current
 * customer object and returns a patch (or the fully mutated object). */
export async function updateCustomer(id, mutator) {
  return withLock(`customer:${id}`, () => {
    const current = getCustomer(id);
    const patch = mutator(current);
    const updated = { ...current, ...patch };
    state.customers.set(id, updated);
    return updated;
  });
}

// ---- Audit log (append-only, doubles as durable workflow history) ----

export function appendAuditEvent({
  customerId,
  type,
  description,
  actor = 'System',
  previousState,
  newState,
  source = 'Workflow Engine',
  relatedEntityType,
  relatedEntityId,
}) {
  const event = {
    id: state.nextId('AUD'),
    timestamp: new Date().toISOString(),
    customerId,
    type,
    description,
    actor,
    previousState,
    newState,
    source,
    relatedEntityType,
    relatedEntityId,
  };
  state.auditLog.push(event);
  return event;
}

export function auditHistoryForCustomer(customerId) {
  return state.auditLog.filter((e) => e.customerId === customerId);
}

// ---- PTPs ----

export function createPtp({ customerId, amountPromised, promiseDate, paymentMode }) {
  const id = state.nextId('PTP');
  const ptp = {
    id,
    customerId,
    amountPromised,
    promiseDate: new Date(promiseDate).toISOString(),
    paymentMode,
    status: 'scheduled',
    amountReceived: null,
    correctionStatus: 'none',
    brokenReason: null,
  };
  state.ptps.set(id, ptp);
  return ptp;
}

export function getPtp(id) {
  const p = state.ptps.get(id);
  if (!p) throw new NotFoundError('PTP', id);
  return p;
}

export function listPtps() {
  return [...state.ptps.values()];
}

export function listDuePtps(now = new Date()) {
  return listPtps().filter((p) => p.status === 'scheduled' && new Date(p.promiseDate).getTime() <= now.getTime());
}

export async function updatePtp(id, mutator) {
  return withLock(`ptp:${id}`, () => {
    const current = getPtp(id);
    const updated = { ...current, ...mutator(current) };
    state.ptps.set(id, updated);
    return updated;
  });
}

// ---- Tasks ----

export function createTask(task) {
  const id = state.nextId('TASK');
  const record = {
    id,
    status: 'pending',
    approvalStatus: null,
    reviewedByRE: false,
    createdAt: new Date().toISOString(),
    completedAt: null,
    ...task,
  };
  state.tasks.set(id, record);
  return record;
}

export function getTask(id) {
  const t = state.tasks.get(id);
  if (!t) throw new NotFoundError('Task', id);
  return t;
}

export function listTasks() {
  return [...state.tasks.values()];
}

export function listOpenTasksForCustomer(customerId) {
  return listTasks().filter((t) => t.customerId === customerId && t.status !== 'completed' && t.status !== 'closed');
}

export async function updateTask(id, mutator) {
  return withLock(`task:${id}`, () => {
    const current = getTask(id);
    const updated = { ...current, ...mutator(current) };
    state.tasks.set(id, updated);
    return updated;
  });
}

// ---- Disputes ----

export function createDispute(dispute) {
  const id = state.nextId('DSP');
  const record = { id, status: 'Pending Approval', statusDetail: 'Awaiting Review', ...dispute };
  state.disputes.set(id, record);
  return record;
}

export function getDispute(id) {
  const d = state.disputes.get(id);
  if (!d) throw new NotFoundError('Dispute', id);
  return d;
}

export function listDisputes() {
  return [...state.disputes.values()];
}

export async function updateDispute(id, mutator) {
  return withLock(`dispute:${id}`, () => {
    const current = getDispute(id);
    const updated = { ...current, ...mutator(current) };
    state.disputes.set(id, updated);
    return updated;
  });
}

// ---- Payment claims ----

export function createPaymentClaim(claim) {
  const id = state.nextId('PC');
  const record = { id, status: 'Awaiting Verification', ...claim };
  state.paymentClaims.set(id, record);
  return record;
}

export function getPaymentClaim(id) {
  const c = state.paymentClaims.get(id);
  if (!c) throw new NotFoundError('PaymentClaim', id);
  return c;
}

export async function updatePaymentClaim(id, mutator) {
  return withLock(`claim:${id}`, () => {
    const current = getPaymentClaim(id);
    const updated = { ...current, ...mutator(current) };
    state.paymentClaims.set(id, updated);
    return updated;
  });
}

// ---- Escalation cases ----

export function openEscalationCaseForCustomer(customerId) {
  return [...state.escalationCases.values()].find((c) => c.customerId === customerId && c.resolvedAt == null) || null;
}

export function getEscalationCase(id) {
  const c = state.escalationCases.get(id);
  if (!c) throw new NotFoundError('EscalationCase', id);
  return c;
}

export async function upsertEscalationCase(customerId, patch) {
  return withLock(`escalation:${customerId}`, () => {
    const existing = openEscalationCaseForCustomer(customerId);
    if (existing) {
      const updated = { ...existing, ...patch, history: [...existing.history, ...(patch.historyEntry ? [patch.historyEntry] : [])] };
      delete updated.historyEntry;
      state.escalationCases.set(existing.id, updated);
      return { case: updated, created: false };
    }
    const id = state.nextId('ESC');
    const record = {
      id,
      customerId,
      history: patch.historyEntry ? [patch.historyEntry] : [],
      resolvedAt: null,
      ...patch,
    };
    delete record.historyEntry;
    state.escalationCases.set(id, record);
    return { case: record, created: true };
  });
}

export async function resolveEscalationCase(id, resolutionNote) {
  return withLock(`escalation-case:${id}`, () => {
    const current = getEscalationCase(id);
    const updated = { ...current, resolvedAt: new Date().toISOString(), history: [...current.history, `Resolved: ${resolutionNote}`] };
    state.escalationCases.set(id, updated);
    return updated;
  });
}

// ---- Notifications ----

export function pushNotification(notification) {
  const record = { id: state.nextId('NOTIF'), read: false, timestamp: new Date().toISOString(), ...notification };
  state.notifications.push(record);
  return record;
}

// ---- No-answer attempt counter ----

export function nextNoAnswerAttempt(customerId) {
  const attempts = (state.noAnswerAttempts.get(customerId) || 0) + 1;
  return attempts;
}

export function recordNoAnswerAttempt(customerId, attempts) {
  state.noAnswerAttempts.set(customerId, attempts);
}

export function resetNoAnswerAttempts(customerId) {
  state.noAnswerAttempts.set(customerId, 0);
}

// ---- 5 PM Control (append-only) ----

export function appendFivePmControlSnapshot(snapshot) {
  const record = { id: state.nextId('5PM'), timestamp: new Date().toISOString(), ...snapshot };
  state.fivePmControlSnapshots.push(record);
  return record;
}

export function listFivePmControlSnapshots() {
  return [...state.fivePmControlSnapshots];
}

// ---- Correction requests (generic: PTP amount/date, or recorded outcome) ----

export function createCorrectionRequest(request) {
  const id = state.nextId('CORR');
  const record = { id, status: 'Pending', ...request };
  state.correctionRequests.set(id, record);
  return record;
}

export function getCorrectionRequest(id) {
  const r = state.correctionRequests.get(id);
  if (!r) throw new NotFoundError('CorrectionRequest', id);
  return r;
}

export async function updateCorrectionRequest(id, mutator) {
  return withLock(`correction:${id}`, () => {
    const current = getCorrectionRequest(id);
    const updated = { ...current, ...mutator(current) };
    state.correctionRequests.set(id, updated);
    return updated;
  });
}

// ---- BUSY sync health ----

export function getBusySyncHealth() {
  return state.isBusySyncHealthy;
}

export function setBusySyncHealth(healthy) {
  state.isBusySyncHealthy = healthy;
  return state.isBusySyncHealthy;
}

export function recordBusySyncRun() {
  state.lastBusySync = new Date().toISOString();
  return state.lastBusySync;
}

// ---- Salesmen ----

export function listSalesmen() {
  return [...state.salesmen.values()];
}

export function getSalesman(id) {
  const s = state.salesmen.get(id);
  if (!s) throw new NotFoundError('Salesman', id);
  return s;
}
