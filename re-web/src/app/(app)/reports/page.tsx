import Link from "next/link";
import { ArrowUpRight, BarChart3 } from "lucide-react";
import { PageHeader } from "@/components/app/page-header";
import { REPORTS } from "./catalog";

export const metadata = { title: "Reports" };

export default function ReportsPage() {
  return (
    <div className="mx-auto max-w-[1400px]">
      <PageHeader title="Reports" description="Drill from company to branch to salesman to customer. Every report respects the branch filter and exports to CSV." />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {REPORTS.map((r) => (
          <Link key={r.slug} href={`/reports/${r.slug}`} className="group rounded-xl border bg-card p-5 shadow-xs transition-colors hover:border-primary/40">
            <div className="flex items-start justify-between">
              <span className="flex size-9 items-center justify-center rounded-lg bg-accent text-accent-foreground">
                <BarChart3 className="size-4" />
              </span>
              <ArrowUpRight className="size-4 text-muted-foreground transition-colors group-hover:text-primary" />
            </div>
            <h2 className="mt-4 font-semibold">{r.title}</h2>
            <p className="mt-1 text-sm text-muted-foreground">{r.description}</p>
          </Link>
        ))}
      </div>
    </div>
  );
}
