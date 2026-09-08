import { buildSeedCustomers, buildSeedSalesmen } from './seed-data.js';

// The DB stand-in. A single process-wide instance (`state`, exported below)
// holds everything the Dart AppStore/BusySimulator kept in memory. Every
// mutation goes through repository.js, never through this class directly,
// so the eventual DB swap only touches one file.
//
// NOTE: this is intentionally a plain in-process object, not Redis-backed.
// BullMQ job *data* and *results* already persist in Redis independently;
// this class is the "current world state" a real database would own.
class InMemoryState {
  constructor() {
    this.reset();
  }

  reset() {
    this.customers = new Map(buildSeedCustomers().map((c) => [c.id, { ...c }]));
    this.salesmen = new Map(buildSeedSalesmen().map((s) => [s.id, { ...s }]));
    this.ptps = new Map(); // id -> PromiseToPay
    this.tasks = new Map(); // id -> AppTask
    this.disputes = new Map(); // id -> Dispute
    this.paymentClaims = new Map(); // id -> PaymentClaim
    this.escalationCases = new Map(); // id -> EscalationCase (keyed by customerId for "open case" lookup convenience via index below)
    this.notifications = [];
    this.auditLog = []; // append-only, global — each entry also has customerId
    this.fivePmControlSnapshots = []; // append-only, never edited
    this.noAnswerAttempts = new Map(); // customerId -> count
    this.dispatchedPtpEscalationChecks = new Set(); // idempotency guard, see escalation processor
    this.correctionRequests = new Map(); // id -> CorrectionRequest (ptp | outcome)
    this.isBusySyncHealthy = true;
    this.lastBusySync = null;
    this._seq = 0;
  }

  nextId(prefix) {
    this._seq += 1;
    return `${prefix}_${Date.now()}_${this._seq}`;
  }
}

export const state = new InMemoryState();
