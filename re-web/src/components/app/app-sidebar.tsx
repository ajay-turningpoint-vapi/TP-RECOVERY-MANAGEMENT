"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  AlarmClock,
  BarChart3,
  Building2,
  CalendarCheck2,
  ClipboardList,
  FileWarning,
  Gauge,
  Inbox,
  ListOrdered,
  Siren,
  Users,
} from "lucide-react";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarRail,
} from "@/components/ui/sidebar";
import { useRms } from "@/lib/queries";

type NavItem = { href: string; label: string; icon: typeof Gauge; badge?: number; tone?: "danger" };

export function AppSidebar() {
  const pathname = usePathname();
  const rms = useRms();

  const groups: { label: string; items: NavItem[] }[] = [
    {
      label: "Control",
      items: [
        { href: "/dashboard", label: "Control Dashboard", icon: Gauge },
        { href: "/control", label: "5 PM Control", icon: AlarmClock },
      ],
    },
    {
      label: "Work",
      items: [
        { href: "/tasks", label: "My Tasks", icon: ClipboardList, badge: rms.totalOpenTaskItemsCount },
        { href: "/approvals", label: "Approval Inbox", icon: Inbox, badge: rms.approvalInboxCount, tone: "danger" },
        { href: "/disputes", label: "Disputes", icon: FileWarning, badge: rms.disputesNeedingAction.length },
        { href: "/escalations", label: "Escalations", icon: Siren, badge: rms.openEscalations.length },
      ],
    },
    {
      label: "Portfolio",
      items: [
        { href: "/queue", label: "Recovery Queue", icon: ListOrdered },
        { href: "/customers", label: "Customers", icon: Building2 },
        { href: "/ptps", label: "Promises to Pay", icon: CalendarCheck2 },
        { href: "/salesmen", label: "Salesmen", icon: Users },
      ],
    },
    {
      label: "Insight",
      items: [{ href: "/reports", label: "Reports", icon: BarChart3 }],
    },
  ];

  return (
    <Sidebar collapsible="icon">
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton size="lg" render={<Link href="/dashboard" />}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/logo.png" alt="" className="size-8 shrink-0 rounded-lg bg-white/10 p-1" />
              <div className="grid flex-1 text-left leading-tight">
                <span className="truncate text-sm font-semibold text-white">TP-RMS</span>
                <span className="truncate text-xs text-sidebar-foreground/60">Recovery Control</span>
              </div>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        {groups.map((g) => (
          <SidebarGroup key={g.label}>
            <SidebarGroupLabel className="text-sidebar-foreground/50">{g.label}</SidebarGroupLabel>
            <SidebarMenu>
              {g.items.map((item) => {
                const active = pathname === item.href || pathname.startsWith(item.href + "/");
                return (
                  <SidebarMenuItem key={item.href}>
                    <SidebarMenuButton isActive={active} tooltip={item.label} render={<Link href={item.href} />}>
                      <item.icon />
                      <span>{item.label}</span>
                    </SidebarMenuButton>
                    {!!item.badge && (
                      <SidebarMenuBadge
                        className={
                          item.tone === "danger"
                            ? "bg-destructive text-white peer-hover/menu-button:text-white"
                            : "bg-sidebar-accent text-sidebar-accent-foreground"
                        }
                      >
                        {item.badge > 99 ? "99+" : item.badge}
                      </SidebarMenuBadge>
                    )}
                  </SidebarMenuItem>
                );
              })}
            </SidebarMenu>
          </SidebarGroup>
        ))}
      </SidebarContent>
      <SidebarFooter className="group-data-[collapsible=icon]:hidden">
        <p className="px-2 pb-1 text-[11px] leading-snug text-sidebar-foreground/45">
          BUSY is the financial source of truth. Figures follow the last sync.
        </p>
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  );
}
