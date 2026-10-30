"use client";

import { useState } from "react";
import Link from "next/link";
import { useTheme } from "next-themes";
import {
  Bell,
  CheckCheck,
  CircleAlert,
  KeyRound,
  Loader2,
  LogOut,
  Moon,
  RefreshCw,
  Sun,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { expectOwnSessionChange } from "@/lib/api";
import { timeAgo } from "@/lib/format";
import { useRmsAction } from "@/lib/actions";
import { useRefreshAll, useRms, useSyncStatus } from "@/lib/queries";
import { cn } from "@/lib/utils";
import { useBranch, useSessionUser } from "./providers";
import { TopProgress } from "./top-progress";
import { ColorAvatar } from "./visual";
import { SimpleSelect } from "./simple-select";

export function Topbar() {
  const { isFetching } = useRms();
  return (
    <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center gap-3 border-b-2 bg-card px-3 md:px-5">
      <SidebarTrigger className="size-10 [&_svg]:size-5!" />
      <div className="ml-auto flex items-center gap-2">
        <BranchFilter />
        <SyncPill />
        <RefreshButton />
        <NotificationBell />
        <UserMenu />
      </div>
      <TopProgress active={isFetching} />
    </header>
  );
}

function BranchFilter() {
  const { branch, setBranch } = useBranch();
  const { branchOptions } = useRms();
  return (
    <div className="hidden md:block">
      <SimpleSelect value={branch} onChange={setBranch} options={branchOptions} aria-label="Branch" className="min-w-44 font-semibold" />
    </div>
  );
}

function SyncPill() {
  const { data, dataUpdatedAt } = useSyncStatus();
  if (!data) return null;
  const last = data.lastSync;
  const finished = last?.finishedAt ? new Date(last.finishedAt) : null;
  // Measured against when the status was fetched (refetched every 5 min), not the render clock.
  const stale = !finished || dataUpdatedAt - finished.getTime() > 26 * 3600_000;
  const failed = last?.status === "failed" || last?.status === "stalled";
  const state = data.syncing
    ? { label: "Updating data…", cls: "bg-sky-100 text-sky-900", Icon: RefreshCw }
    : failed
      ? { label: "Data update failed", cls: "bg-red-100 text-red-800", Icon: CircleAlert }
      : stale
        ? { label: "Data may be old", cls: "bg-amber-100 text-amber-900", Icon: CircleAlert }
        : { label: finished ? `Data updated ${timeAgo(finished)}` : "Data up to date", cls: "bg-green-100 text-green-800", Icon: CheckCheck };

  return (
    <Tooltip>
      <TooltipTrigger render={<span className={cn("hidden h-10 items-center gap-2 rounded-lg px-3 text-sm font-semibold xl:inline-flex", state.cls)} />}>
        <state.Icon className="size-4" />
        {state.label}
      </TooltipTrigger>
      <TooltipContent className="max-w-xs text-sm">
        {last?.message ?? "Money figures come from BUSY. They update automatically every day."}
      </TooltipContent>
    </Tooltip>
  );
}

function RefreshButton() {
  const refresh = useRefreshAll();
  const { isFetching } = useRms();
  return (
    <Button
      variant="outline"
      disabled={isFetching}
      onClick={() =>
        toast.promise(refresh(), {
          loading: "Getting the latest data…",
          success: "Data is up to date.",
          error: "Could not refresh. Check your internet and try again.",
        })
      }
      aria-label="Refresh data"
    >
      <RefreshCw className={cn(isFetching && "animate-spin")} />
      <span className="hidden lg:inline">{isFetching ? "Refreshing…" : "Refresh"}</span>
    </Button>
  );
}

const SEVERITY_DOT: Record<string, string> = {
  critical: "bg-destructive",
  warning: "bg-warning",
  actionRequired: "bg-info",
  info: "bg-muted-foreground/40",
};

function NotificationBell() {
  const rms = useRms();
  const markAll = useRmsAction();
  const recent = [...rms.notifications].sort((a, b) => +b.timestamp - +a.timestamp).slice(0, 8);

  return (
    <Popover>
      <PopoverTrigger render={<Button variant="outline" size="icon" className="relative" aria-label="Notifications" />}>
        <Bell />
        {rms.unreadNotificationCount > 0 && (
          <span className="absolute top-0.5 right-0.5 flex min-w-5 items-center justify-center rounded-full bg-red-600 px-1 text-xs leading-5 font-bold text-white tabular">
            {rms.unreadNotificationCount > 9 ? "9+" : rms.unreadNotificationCount}
          </span>
        )}
      </PopoverTrigger>
      <PopoverContent align="end" className="w-96 p-0">
        <div className="flex items-center justify-between border-b px-4 py-3">
          <div className="text-sm font-semibold">Notifications</div>
          <Button variant="ghost" size="xs" onClick={() => markAll.mutate({ path: "/notifications/read-all", success: "All messages marked as read." })} disabled={!rms.unreadNotificationCount || markAll.isPending}>
            {markAll.isPending ? <Loader2 className="animate-spin" /> : <CheckCheck />}
            Mark all read
          </Button>
        </div>
        <div className="max-h-96 overflow-y-auto">
          {recent.length === 0 ? (
            <div className="px-4 py-10 text-center text-sm text-muted-foreground">You&apos;re all caught up.</div>
          ) : (
            recent.map((n) => (
              <Link
                key={n.id}
                href={n.customerId ? `/customers/${encodeURIComponent(n.customerId)}` : "/notifications"}
                className={cn("flex gap-3 border-b px-4 py-3 last:border-0 hover:bg-muted/50", !n.read && "bg-accent/30")}
              >
                <span className={cn("mt-1.5 size-2 shrink-0 rounded-full", SEVERITY_DOT[n.severity])} />
                <div className="min-w-0 space-y-0.5">
                  <div className={cn("text-sm", !n.read && "font-medium")}>{n.title}</div>
                  <div className="line-clamp-2 text-xs text-muted-foreground">{n.body}</div>
                  <div className="text-[11px] text-muted-foreground/70">{timeAgo(n.timestamp)}</div>
                </div>
              </Link>
            ))
          )}
        </div>
        <div className="border-t p-2">
          <Button variant="ghost" size="sm" className="w-full" render={<Link href="/notifications" />}>
            View all notifications
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  );
}

function UserMenu() {
  const user = useSessionUser();
  const { resolvedTheme, setTheme } = useTheme();
  const [pwOpen, setPwOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  const signOut = async () => {
    setSigningOut(true);
    toast.loading("Signing you out…");
    await fetch("/api/auth/logout", { method: "POST" }).catch(() => {});
    // Full reload on purpose — drops every cached query along with the session.
    // eslint-disable-next-line @next/next/no-location-assign-relative-destination
    window.location.href = "/login";
  };

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger render={<Button variant="outline" className="gap-2 px-2" aria-label="My account" />}>
          <ColorAvatar name={user.fullName} size="sm" />
          <span className="hidden max-w-36 truncate font-semibold 2xl:inline">{user.fullName}</span>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-60">
          <DropdownMenuGroup>
            <DropdownMenuLabel className="font-normal">
              <div className="text-sm font-medium text-foreground">{user.fullName}</div>
              <div className="text-xs text-muted-foreground">
                Recovery Executive · {user.username}
              </div>
            </DropdownMenuLabel>
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}>
            {resolvedTheme === "dark" ? <Sun /> : <Moon />}
            {resolvedTheme === "dark" ? "Light mode" : "Dark mode"}
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => setPwOpen(true)}>
            <KeyRound />
            Change password
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem variant="destructive" onClick={signOut} disabled={signingOut}>
            <LogOut />
            Sign out
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <ChangePasswordDialog open={pwOpen} onOpenChange={setPwOpen} />
    </>
  );
}

function ChangePasswordDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (o: boolean) => void }) {
  const [pw, setPw] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const submit = async () => {
    setError(null);
    if (pw.length < 8) return setError("Use at least 8 characters.");
    if (pw !== confirm) return setError("Passwords don't match.");
    setPending(true);
    expectOwnSessionChange();
    const res = await fetch("/api/auth/change-password", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ newPassword: pw }),
    }).catch(() => null);
    setPending(false);
    if (!res?.ok) {
      const body = await res?.json().catch(() => ({}));
      return setError(body?.message ?? "Could not change password.");
    }
    toast.success("Password changed. Your mobile app will ask you to sign in again.");
    // The change bumped the server's session version — reload so this page
    // runs with its new version (the echo is ignored meanwhile, see api.ts).
    window.location.reload();
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Change password</DialogTitle>
          <DialogDescription>This signs you out everywhere else, including the mobile app.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="new-pw">New password</Label>
            <Input id="new-pw" type="password" autoComplete="new-password" value={pw} onChange={(e) => setPw(e.target.value)} />
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirm-pw">Confirm new password</Label>
            <Input id="confirm-pw" type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />
          </div>
          {error && (
            <p className="flex items-center gap-1.5 text-sm text-destructive">
              <CircleAlert className="size-4" />
              {error}
            </p>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={pending}>
            {pending && <Loader2 className="animate-spin" />}
            Update password
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
