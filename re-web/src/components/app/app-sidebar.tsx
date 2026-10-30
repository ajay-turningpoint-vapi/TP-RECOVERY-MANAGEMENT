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
  Home,
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
import { cn } from "@/lib/utils";
import { useSessionUser } from "./providers";
import { ColorAvatar } from "./visual";

type NavItem = { href: string; label: string; icon: typeof Home; badge?: number; urgent?: boolean };

/** Plain, everyday names for every page (same pages as before). */
export const NAV_GROUPS = (rms: ReturnType<typeof useRms>): { label: string; items: NavItem[] }[] => [
  {
    label: "Today",
    items: [
      { href: "/dashboard", label: "Home", icon: Home },
      { href: "/tasks", label: "My Tasks", icon: ClipboardList, badge: rms.workOpenCount },
      { href: "/approvals", label: "Approvals", icon: Inbox, badge: rms.approvalInboxCount, urgent: true },
      { href: "/control", label: "End-of-Day Check", icon: AlarmClock },
    ],
  },
  {
    label: "Problems",
    items: [
      { href: "/disputes", label: "Disputes", icon: FileWarning, badge: rms.disputesNeedingAction.length, urgent: true },
      { href: "/escalations", label: "Escalations", icon: Siren, badge: rms.openEscalations.length },
    ],
  },
  {
    label: "Customers & Money",
    items: [
      { href: "/queue", label: "Follow-up List", icon: ListOrdered },
      { href: "/customers", label: "All Customers", icon: Building2 },
      { href: "/ptps", label: "Payment Promises", icon: CalendarCheck2 },
      { href: "/salesmen", label: "Salesmen", icon: Users },
    ],
  },
  {
    label: "Reports",
    items: [{ href: "/reports", label: "Reports", icon: BarChart3 }],
  },
];

export function AppSidebar() {
  const pathname = usePathname();
  const rms = useRms();
  const user = useSessionUser();

  return (
    <Sidebar collapsible="icon">
      <SidebarHeader className="border-b border-white/10 pb-3">
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton size="lg" render={<Link href="/dashboard" />} className="hover:bg-white/10">
              <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-white">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src="/logo.png" alt="" className="size-6" />
              </span>
              <div className="grid flex-1 text-left leading-tight">
                <span className="truncate text-[15px] font-bold text-white">TP-RMS</span>
                <span className="truncate text-sm text-white/80">Recovery</span>
              </div>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent className="gap-1 py-2">
        {NAV_GROUPS(rms).map((g) => (
          <SidebarGroup key={g.label} className="py-1">
            <SidebarGroupLabel className="h-7 text-xs font-bold tracking-wide text-white/70 uppercase">{g.label}</SidebarGroupLabel>
            <SidebarMenu className="gap-1">
              {g.items.map((item) => {
                const active = pathname === item.href || pathname.startsWith(item.href + "/");
                return (
                  <SidebarMenuItem key={item.href}>
                    <SidebarMenuButton
                      isActive={active}
                      tooltip={item.label}
                      render={<Link href={item.href} />}
                      className={cn(
                        "h-10 rounded-lg text-[15px] text-white transition-colors hover:bg-white/15 hover:text-white [&_svg]:size-[18px]!",
                        active && "bg-white! font-bold text-slate-900! hover:bg-white!",
                      )}
                    >
                      <item.icon />
                      <span>{item.label}</span>
                    </SidebarMenuButton>
                    {!!item.badge && (
                      <SidebarMenuBadge
                        className={cn(
                          "top-2! h-6 min-w-6 rounded-full px-1.5 text-xs font-bold",
                          item.urgent ? "bg-red-600 text-white" : "bg-white/20 text-white",
                          active && !item.urgent && "bg-slate-900 text-white",
                        )}
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
      <SidebarFooter className="border-t border-white/10">
        <div className="flex items-center gap-3 p-1">
          <ColorAvatar name={user.fullName} />
          <div className="min-w-0 group-data-[collapsible=icon]:hidden">
            <div className="truncate text-sm font-semibold text-white">{user.fullName}</div>
            <div className="truncate text-sm text-white/75">Recovery Executive</div>
          </div>
        </div>
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  );
}
