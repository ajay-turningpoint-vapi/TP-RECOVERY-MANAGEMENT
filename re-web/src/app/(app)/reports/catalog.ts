export const REPORTS = [
  { slug: "daily-recovery", title: "Daily Recovery Summary", description: "Expected vs collected, PTPs and broken promises per day from the 5 PM snapshots." },
  { slug: "salesman-performance", title: "Salesman Performance", description: "Recovery score, collection, PTP discipline and task completion per salesman." },
  { slug: "ptp", title: "PTP Report", description: "Promises given, kept and broken, by salesman." },
  { slug: "broken-ptp", title: "Broken PTP Report", description: "Every broken promise, who owns it and whether it is escalated." },
  { slug: "dispute-status", title: "Dispute Status", description: "Disputes by lifecycle stage, with shielded amounts and owners." },
  { slug: "ageing", title: "Ageing Receivables", description: "Overdue by ageing bucket, per customer." },
  { slug: "expected-vs-actual", title: "Expected vs Actual", description: "Each salesman's expected collection against what has actually been collected." },
  { slug: "recovery-target", title: "Recovery Target", description: "Collection target vs achievement per salesman." },
  { slug: "no-follow-up", title: "No Follow-Up", description: "Overdue customers with no real recovery activity for 4+ days." },
] as const;

export type ReportSlug = (typeof REPORTS)[number]["slug"];
