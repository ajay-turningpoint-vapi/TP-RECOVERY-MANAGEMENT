import type { Metadata } from "next";
import { Suspense } from "react";
import { BarChart3, ShieldCheck, Workflow } from "lucide-react";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Sign in" };

const POINTS = [
  { icon: BarChart3, title: "Company-wide control", body: "Outstanding, overdue, PTPs and collections across every branch — live." },
  { icon: Workflow, title: "One decision inbox", body: "Disputes, PTP corrections, payment claims and task requests in one place." },
  { icon: ShieldCheck, title: "Audited by design", body: "Every approval, escalation and reassignment is recorded with who, when and why." },
];

export default function LoginPage() {
  return (
    <div className="grid min-h-svh lg:grid-cols-[1.1fr_1fr]">
      <aside className="relative hidden overflow-hidden bg-sidebar text-sidebar-foreground lg:flex lg:flex-col lg:justify-between lg:p-12">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 opacity-40"
          style={{
            background:
              "radial-gradient(60% 50% at 20% 10%, oklch(0.546 0.215 262.88 / 0.45), transparent 70%), radial-gradient(50% 40% at 90% 90%, oklch(0.596 0.145 163.23 / 0.3), transparent 70%)",
          }}
        />
        <div className="relative flex items-center gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="" className="size-10 rounded-xl bg-white/10 p-1.5" />
          <div>
            <div className="text-base font-semibold text-white">Turning Point</div>
            <div className="text-xs text-sidebar-foreground/70">Recovery Management System</div>
          </div>
        </div>

        <div className="relative max-w-md space-y-8">
          <div className="space-y-3">
            <h1 className="text-4xl font-semibold tracking-tight text-white">Recovery Control Center</h1>
            <p className="text-base text-sidebar-foreground/80">
              The operational cockpit for Recovery Executives — supervise salesmen, decide approvals and keep every rupee
              of exposure owned.
            </p>
          </div>
          <ul className="space-y-5">
            {POINTS.map(({ icon: Icon, title, body }) => (
              <li key={title} className="flex gap-4">
                <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-white/10 text-white">
                  <Icon className="size-4.5" />
                </span>
                <div>
                  <div className="text-sm font-medium text-white">{title}</div>
                  <div className="text-sm text-sidebar-foreground/70">{body}</div>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <p className="relative text-xs text-sidebar-foreground/50">BUSY is the financial source of truth. TP-RMS owns recovery.</p>
      </aside>

      <main className="flex items-center justify-center px-4 py-12 sm:px-8">
        <div className="w-full max-w-sm space-y-8">
          <div className="space-y-2">
            <div className="flex items-center gap-2 lg:hidden">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/logo.png" alt="" className="size-8" />
              <span className="font-semibold">TP-RMS</span>
            </div>
            <h2 className="text-2xl font-semibold tracking-tight">Sign in</h2>
            <p className="text-sm text-muted-foreground">Use your Recovery Executive account.</p>
          </div>
          <Suspense>
            <LoginForm />
          </Suspense>
          <p className="text-xs text-muted-foreground">
            One device at a time: signing in here signs you out of the TP-RMS mobile app, and signing in on the app signs you out here.
          </p>
        </div>
      </main>
    </div>
  );
}
