type Cell = string | number | null | undefined;

function escape(v: Cell) {
  if (v == null) return "";
  const s = String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function toCsv(header: string[], rows: Cell[][]) {
  return [header, ...rows].map((r) => r.map(escape).join(",")).join("\r\n");
}

/** Client-side CSV download (UTF-8 BOM so Excel renders ₹ and names correctly). */
export function downloadCsv(name: string, header: string[], rows: Cell[][]) {
  const blob = new Blob(["﻿" + toCsv(header, rows)], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  const stamp = new Date().toISOString().slice(0, 10);
  a.href = url;
  a.download = `${name}-${stamp}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}
