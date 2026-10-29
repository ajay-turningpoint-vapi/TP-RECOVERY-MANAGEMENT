"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTheme } from "next-themes";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Bell,
  Building2,
  CheckCheck,
  CircleAlert,
  KeyRound,
  Loader2,
  LogOut,
  Moon,
  RefreshCw,
  Search,
  Sun,
} from "lucide-react";
import { toast } from "sonner";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
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
import { Separator } from "@/components/ui/separator";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { rmsPost } from "@/lib/api";
import { formatINR, initials, timeAgo } from "@/lib/format";
import { useRefreshAll, useRms, useSyncStatus } from "@/lib/queries";
import { cn } from "@/lib/utils";
import { useBranch, useSessionUser } from "./providers";
import { SimpleSelect } from "./simple-select";

export function Topbar() {
  return (
    <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center gap-2 border-b bg-background/85 px-3 backdrop-blur supports-[backdrop-filter]:bg-background/70 md:px-4">
      <SidebarTrigger className="-ml-1" />
      <Separator orientation="vertical" className="mx-1 h-5" />
      <GlobalSearch />
      <div className="ml-auto flex items-center gap-2">
        <BranchFilter />
        <SyncPill />
        <RefreshButton />
        <NotificationBell />
        <UserMenu />
      </div>
    </header>
  );
}

function GlobalSearch() {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const rms = useRms();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setOpen((o) => !o);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const go = (href: string) => {
    setOpen(false);
    router.push(href);
  };

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex h-8 w-full max-w-sm items-center gap-2 rounded-lg border bg-muted/40 px-2.5 text-sm text-muted-foreground transition-colors hover:bg-muted"
      >
        <Search className="size-4" />
        <span className="hidden truncate sm:inline">Search customers, salesmen…</span>
        <span className="sm:hidden">Search</span>
        <kbd className="ml-auto hidden rounded border bg-background px-1.5 font-mono text-[10px] sm:inline">⌘K</kbd>
      </button>
      <CommandDialog open={open} onOpenChange={setOpen} title="Search" description="Find a customer or salesman">
        <CommandInput placeholder="Customer name, code, salesman or branch…" />
        <CommandList>
          <CommandEmpty>No matches.</CommandEmpty>
          <CommandGroup heading="Customers">
            {rms.allCustomers.slice(0, 2000).map((c) => (
              <CommandItem
                key={c.id}
                value={`${c.name} ${c.id} ${c.branch} ${rms.salesmanName(c.assignedSalesmanId)}`}
                onSelect={() => go(`/customers/${encodeURIComponent(c.id)}`)}
              >
                <Building2 />
                <span className="truncate">{c.name}</span>
                <span className="ml-auto shrink-0 text-xs text-muted-foreground tabular">{formatINR(c.totalDue)} due</span>
              </CommandItem>
            ))}
          </CommandGroup>
          <CommandGroup heading="Salesmen">
            {rms.salesmen.map((s) => (
              <CommandItem key={s.id} value={`${s.fullName} ${s.username} ${s.branch}`} onSelect={() => go(`/salesmen/${encodeURIComponent(s.id)}`)}>
                <Avatar className="size-5">
                  <AvatarFallback className="text-[9px]">{initials(s.fullName)}</AvatarFallback>
                </Avatar>
                <span className="truncate">{s.fullName}</span>
                <span className="ml-auto text-xs text-muted-foreground">{s.branch}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        </CommandList>
      </CommandDialog>
    </>
  );
}

function BranchFilter() {
  const { branch, setBranch } = useBranch();
  const { branchOptions } = useRms();
  return (
    <div className="hidden md:block">
      <SimpleSelect value={branch} onChange={setBranch} options={branchOptions} aria-label="Branch filter" className="min-w-40" />
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
  const state = data.syncing
    ? { label: "Syncing BUSY…", tone: "bg-info/10 text-info", dot: "bg-info animate-pulse" }
    : last?.status === "failed" || last?.status === "stalled"
      ? { label: "Sync failed", tone: "bg-destructive/10 text-destructive", dot: "bg-destructive" }
      : stale
        ? { label: "Stale / Preliminary", tone: "bg-warning/14 text-warning", dot: "bg-warning" }
        : { label: "Fresh", tone: "bg-success/12 text-success", dot: "bg-success" };

  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <span className={cn("hidden h-8 items-center gap-1.5 rounded-lg px-2.5 text-xs font-medium lg:inline-flex", state.tone)} />
        }
      >
        <span className={cn("size-1.5 rounded-full", state.dot)} />
        BUSY: {state.label}
      </TooltipTrigger>
      <TooltipContent className="max-w-xs">
        {last?.message ?? (finished ? `Last BUSY sync finished ${timeAgo(finished)}.` : "No completed BUSY sync recorded yet.")}
      </TooltipContent>
    </Tooltip>
  );
}

function RefreshButton() {
  const refresh = useRefreshAll();
  const { isFetching } = useRms();
  return (
    <Tooltip>
      <TooltipTrigger render={<Button variant="ghost" size="icon" onClick={() => refresh()} aria-label="Refresh data" />}>
        <RefreshCw className={cn(isFetching && "animate-spin")} />
      </TooltipTrigger>
      <TooltipContent>Refresh all data</TooltipContent>
    </Tooltip>
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
  const qc = useQueryClient();
  const markAll = useMutation({
    mutationFn: () => rmsPost("/notifications/read-all"),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["notifications"] }),
  });
  const recent = [...rms.notifications].sort((a, b) => +b.timestamp - +a.timestamp).slice(0, 8);

  return (
    <Popover>
      <PopoverTrigger render={<Button variant="ghost" size="icon" className="relative" aria-label="Notifications" />}>
        <Bell />
        {rms.unreadNotificationCount > 0 && (
          <span className="absolute top-1 right-1 flex min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[10px] leading-4 font-semibold text-white tabular">
            {rms.unreadNotificationCount > 9 ? "9+" : rms.unreadNotificationCount}
          </span>
        )}
      </PopoverTrigger>
      <PopoverContent align="end" className="w-96 p-0">
        <div className="flex items-center justify-between border-b px-4 py-3">
          <div className="text-sm font-semibold">Notifications</div>
          <Button variant="ghost" size="xs" onClick={() => markAll.mutate()} disabled={!rms.unreadNotificationCount || markAll.isPending}>
            <CheckCheck />
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
    await fetch("/api/auth/logout", { method: "POST" }).catch(() => {});
    // Full reload on purpose — drops every cached query along with the session.
    // eslint-disable-next-line @next/next/no-location-assign-relative-destination
    window.location.href = "/login";
  };

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger render={<Button variant="ghost" className="h-9 gap-2 px-1.5" />}>
          <Avatar className="size-7">
            <AvatarFallback className="bg-primary text-[11px] font-semibold text-primary-foreground">{initials(user.fullName)}</AvatarFallback>
          </Avatar>
          <span className="hidden max-w-32 truncate text-sm font-medium xl:inline">{user.fullName}</span>
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
    setPw("");
    setConfirm("");
    onOpenChange(false);
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
