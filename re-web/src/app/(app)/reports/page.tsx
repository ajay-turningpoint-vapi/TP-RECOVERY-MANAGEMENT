import Link from "next/link";
import { ChartColumn as ChartColumnIcon } from "lucide-react";
import {
  ArrowUpRight,
  BellRing,
  CalendarCheck,
  ChartPie,
  ClipboardList,
  FileWarning,
  Scale,
  Target,
  Unlink,
  Users,
} from "lucide-react";
import { IconTile, HUE, type Hue } from "@/components/app/visual";
import { cn } from "@/lib/utils";

const LOOK: Record<string, [React.ElementType, Hue]> = {
  "daily-recovery": [ClipboardList, "indigo"],
  "salesman-performance": [Users, "violet"],
  ptp: [CalendarCheck, "emerald"],
  "broken-ptp": [Unlink, "rose"],
  "dispute-status": [FileWarning, "violet"],
  ageing: [ChartPie, "sky"],
  "expected-vs-actual": [Scale, "emerald"],
  "recovery-target": [Target, "amber"],
  "no-follow-up": [BellRing, "amber"],
};
import { PageHeader } from "@/components/app/page-header";
import { REPORTS } from "./catalog";

export const metadata = { title: "Reports" };

export default function ReportsPage() {
  return (
    <div className="mx-auto max-w-[1400px]">
      <PageHeader icon={<ChartColumnIcon />} hue="indigo" title="Reports" description="Ready-made reports. Click one to open it. Every report can be downloaded." />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {REPORTS.map((r) => {
          const [Icon, hue] = LOOK[r.slug];
          return (
            <Link
              key={r.slug}
              href={`/reports/${r.slug}`}
              className="group relative overflow-hidden rounded-2xl border border-border/60 bg-card p-5 shadow-soft transition-all duration-300 hover:-translate-y-1 hover:shadow-xl"
            >
              <div aria-hidden className={cn("pointer-events-none absolute inset-0 bg-linear-to-br to-transparent to-60%", HUE[hue].wash)} />
              <div className="relative flex items-start justify-between">
                <IconTile hue={hue} size="lg">
                  <Icon />
                </IconTile>
                <span className="flex size-8 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-all group-hover:bg-primary group-hover:text-white">
                  <ArrowUpRight className="size-4" />
                </span>
              </div>
              <h2 className="relative mt-5 text-base font-bold tracking-tight">{r.title}</h2>
              <p className="relative mt-1 text-sm text-muted-foreground">{r.description}</p>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
