"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { CheckCheck } from "lucide-react";
import { PageHeader } from "@/components/app/page-header";
import { Pill } from "@/components/app/status";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useRmsAction } from "@/lib/actions";
import { formatDateTime } from "@/lib/format";
import type { NotificationSeverity } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { cn } from "@/lib/utils";

const SEVERITY: Record<NotificationSeverity, { label: string; tone: "danger" | "warning" | "info" | "neutral" }> = {
  critical: { label: "Critical", tone: "danger" },
  warning: { label: "Warning", tone: "warning" },
  actionRequired: { label: "Action required", tone: "info" },
  info: { label: "Info", tone: "neutral" },
};

export function NotificationsView() {
  const rms = useRms();
  const router = useRouter();
  const action = useRmsAction();
  const [filter, setFilter] = useState("all");

  const list = [...rms.notifications]
    .filter((n) => (filter === "all" ? true : filter === "unread" ? !n.read : n.severity === filter))
    .sort((a, b) => +b.timestamp - +a.timestamp);

  return (
    <div className="mx-auto max-w-4xl">
      <PageHeader
        title="Notifications"
        description="Reading a notification does not complete the work behind it."
        actions={
          <Button variant="outline" disabled={!rms.unreadNotificationCount || action.isPending} onClick={() => action.mutate({ path: "/notifications/read-all" })}>
            <CheckCheck /> Mark all read
          </Button>
        }
      />
      <Tabs value={filter} onValueChange={(v) => setFilter(String(v))} className="mb-4">
        <TabsList>
          <TabsTrigger value="all">All</TabsTrigger>
          <TabsTrigger value="unread">Unread ({rms.unreadNotificationCount})</TabsTrigger>
          <TabsTrigger value="critical">Critical</TabsTrigger>
          <TabsTrigger value="warning">Warning</TabsTrigger>
          <TabsTrigger value="actionRequired">Action required</TabsTrigger>
        </TabsList>
      </Tabs>
      <div className="overflow-hidden rounded-xl border bg-card">
        {list.length === 0 ? (
          <p className="p-10 text-center text-sm text-muted-foreground">Nothing here.</p>
        ) : (
          list.map((n) => (
            <button
              key={n.id}
              type="button"
              onClick={() => {
                if (!n.read) action.mutate({ path: `/notifications/${n.id}/read` });
                if (n.customerId) router.push(`/customers/${encodeURIComponent(n.customerId)}`);
              }}
              className={cn("flex w-full gap-4 border-b px-5 py-4 text-left last:border-0 hover:bg-muted/50", !n.read && "bg-accent/30")}
            >
              <div className="w-28 shrink-0">
                <Pill tone={SEVERITY[n.severity]?.tone ?? "neutral"}>{SEVERITY[n.severity]?.label ?? n.severity}</Pill>
              </div>
              <div className="min-w-0 flex-1">
                <div className={cn("text-sm", !n.read && "font-semibold")}>{n.title}</div>
                <div className="mt-0.5 text-sm text-muted-foreground">{n.body}</div>
              </div>
              <div className="shrink-0 text-xs text-muted-foreground">{formatDateTime(n.timestamp)}</div>
            </button>
          ))
        )}
      </div>
    </div>
  );
}
