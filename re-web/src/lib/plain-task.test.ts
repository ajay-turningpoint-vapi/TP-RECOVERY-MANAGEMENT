import { describe, expect, it } from "vitest";
import { plainTask } from "./plain-task";

describe("plainTask (port of the app's task brief)", () => {
  it("broken promise", () => {
    const t = plainTask("Call SURESH SUTHAR.(R) — promise broken, nothing received. Collect ₹1,36,832, record a new outcome.", "SURESH SUTHAR.(R)");
    expect(t.what).toBe("Call SURESH SUTHAR.(R)");
    expect(t.why).toBe("Customer promised to pay, but the payment did not come.");
    expect(t.amount).toBe("₹1,36,832");
    expect(t.then).toBe("Record what the customer says.");
  });
  it("partial payment", () => {
    const t = plainTask("Call ACME — ₹20,000 received of ₹50,000. Collect ₹30,000, record a new outcome.", "ACME");
    expect(t.what).toBe("Call ACME about the rest");
    expect(t.why).toBe("Customer paid ₹20,000 of the ₹50,000 promised.");
  });
  it("unknown wording keeps the text without the Collect tail", () => {
    const t = plainTask("Something new happened. Collect ₹5,000, record a new outcome.", "X");
    expect(t.what).toBe("Something new happened.");
    expect(t.amount).toBe("₹5,000");
  });
});
