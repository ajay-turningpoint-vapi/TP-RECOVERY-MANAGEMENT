/**
 * Port of the app's plainTask() (lib/v3/screens/task_details_screen_v3.dart):
 * the server's task reason turned into plain words — WHAT TO DO / WHY /
 * AMOUNT TO COLLECT / THEN (+ NOTE). Unknown wording falls back to the
 * original text, same as the app.
 */
export type PlainTask = { what: string; why: string; amount: string | null; then: string | null; note: string | null };

export function plainTask(raw: string, customerName: string): PlainTask {
  const text = raw.trim();
  const name = customerName.trim() || "the customer";
  const grab = (p: string) => new RegExp(p, "is").exec(text)?.[1]?.trim() ?? null;
  const collect = grab(String.raw`Collect\s+(₹\s?\d(?:[\d,]*\d)?)`);
  const then = collect != null ? "Record what the customer says." : null;
  const low = text.toLowerCase();
  const r = (what: string, why: string, extra: Partial<PlainTask> = {}): PlainTask => ({ what, why, amount: collect, then, note: null, ...extra });

  if (low.startsWith("overdue still open")) return r(`Call ${name}`, "Payment is still overdue.");
  if (low.includes("promise broken")) return r(`Call ${name}`, "Customer promised to pay, but the payment did not come.");
  if (low.includes("confirm time has passed"))
    return r(`Call ${name}`, "Customer said they would confirm. That time has passed.", { note: grab(String.raw`Note:\s*"?(.+?)"?\.?\s*(?:Collect|$)`) });

  const paid = /—\s*(₹\s?[\d,]+)\s+received(?:\s+of\s+(₹\s?[\d,]+))?/i.exec(text);
  if (paid) {
    const why = paid[2] ? `Customer paid ${paid[1]} of the ${paid[2]} promised.` : `Customer paid ${paid[1]}.`;
    return r(`Call ${name} about the rest`, why);
  }
  if (low.startsWith("keep calling")) return r(`Call ${name}`, "Nothing has been recorded for this customer yet.");
  if (low.startsWith("previous task closed")) return r(`Call ${name}`, "The last task was closed without recording what happened.");
  if (low.includes("non-response threshold") || low.includes("no answer on 3 attempts"))
    return r(`Visit ${name}`, "Customer did not answer 3 calls.", { then: "The salesman asks the RE for the visit." });
  if (low.includes("no answer on the last attempt"))
    return r(`Call ${name} again`, "Customer did not answer last time.", { then: "Record what happened on the call." });
  if (low.startsWith("dispute clarification needed"))
    return r("Answer the RE's question", `RE asks: ${grab(String.raw`:\s*(.+)$`) ?? ""}`, { amount: null, then: "Reply in the dispute thread." });
  if (low.startsWith("dispute resolution"))
    return r("Sort out this dispute", grab(String.raw`:\s*(.+)$`) ?? "", { amount: null, then: "Mark it resolved when done." });
  if (low.startsWith("customer refused")) {
    const reason = grab(String.raw`Reason:\s*(.+?)\s*(?:Notes?:|$)`);
    return r(`Call ${name} again`, reason ? `Customer refused to pay. Reason: ${reason}.` : "Customer refused to pay.", {
      then: then ?? "Record what the customer says.",
      note: grab(String.raw`Notes?:\s*(.+)$`),
    });
  }
  const dispute = /Dispute of\s+(₹\s?[\d,]+)\s+(raised|approved|rejected)/i.exec(text);
  if (dispute) {
    const amt = dispute[1];
    const rejectReason = grab(String.raw`Reason:\s*"?(.+?)"?\.?\s*(?:Collect|$)`);
    const kind = dispute[2].toLowerCase();
    const why =
      kind === "raised"
        ? `A ${amt} dispute was raised. The RE is checking it. Collect the rest.`
        : kind === "approved"
          ? `The RE accepted the ${amt} dispute. Collect the rest.`
          : `The RE rejected the ${amt} dispute${rejectReason ? ` (${rejectReason})` : ""}. The full amount is due.`;
    return r(`Call ${name}`, why);
  }
  if (low.startsWith("internal action")) return r(`Call ${name}`, "The RE has finished the internal check. Continue collecting.");
  if (low.startsWith("physical visit completed")) return r(`Call ${name}`, "The RE visited the customer. See the notes in History.");
  if (low.startsWith("physical visit could not")) return r(`Call ${name}`, "The RE could not do the visit. See the notes in History.");
  if (/^L\d escalation resolved/i.test(text)) return r(`Call ${name}`, "The escalation is closed. Start collecting again.");
  const ptp = /the PTP for\s+(₹\s?[\d.,]+)/i.exec(text);
  if (ptp) return r(`Call ${name}`, `Customer promised ${ptp[1].replace(/\.0+$/, "")} but did not pay.`, { then: "Get a new promise to pay." });

  // Unknown wording — keep the original, minus the "Collect ₹X, …" tail.
  const body = text.replace(/\s*Collect\s+₹[\s\S]*$/, "").trim();
  return r(body || `Call ${name}`, "");
}
