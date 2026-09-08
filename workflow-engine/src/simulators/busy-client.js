// Stand-in for the real BUSY financial-system API. Configurable so tests
// can force failures/latency deterministically and prove retry/backoff,
// rate-limiting, and sync-health-gating all behave correctly. Replace with
// a real HTTP client once BUSY integration exists — callers only depend on
// the two async methods below, not on how they're implemented.
export class BusyClient {
  constructor({ failureRate = 0, latencyMs = 0, healthy = true } = {}) {
    this.failureRate = failureRate;
    this.latencyMs = latencyMs;
    this.healthy = healthy;
    this.callCount = 0;
  }

  setHealthy(healthy) {
    this.healthy = healthy;
  }

  async reconcilePtp(ptp) {
    this.callCount += 1;
    if (this.latencyMs) await new Promise((r) => setTimeout(r, this.latencyMs));
    if (Math.random() < this.failureRate) {
      const err = new Error(`BUSY reconciliation transiently failed for PTP ${ptp.id}`);
      err.transient = true;
      throw err;
    }
    if (!this.healthy) {
      const err = new Error('BUSY financial sync is currently unhealthy');
      err.busyUnhealthy = true;
      throw err;
    }
    // Deterministic amount-tier simulation, mirroring the Dart BusySimulator:
    // this is a stand-in for genuine reconciliation, not real payment logic.
    if (ptp.amountPromised < 100000) {
      return { outcome: 'kept', amountReceived: ptp.amountPromised };
    }
    if (ptp.amountPromised < 200000) {
      return { outcome: 'partiallyKept', amountReceived: ptp.amountPromised / 2 };
    }
    return { outcome: 'broken', amountReceived: 0, brokenReason: 'Customer did not honor the commitment' };
  }

  async verifyPayment(claim) {
    this.callCount += 1;
    if (this.latencyMs) await new Promise((r) => setTimeout(r, this.latencyMs));
    if (Math.random() < this.failureRate) {
      const err = new Error(`BUSY payment verification transiently failed for claim ${claim.id}`);
      err.transient = true;
      throw err;
    }
    if (!this.healthy) {
      const err = new Error('BUSY financial sync is currently unhealthy');
      err.busyUnhealthy = true;
      throw err;
    }
    return { verified: true };
  }
}

export const defaultBusyClient = new BusyClient();
