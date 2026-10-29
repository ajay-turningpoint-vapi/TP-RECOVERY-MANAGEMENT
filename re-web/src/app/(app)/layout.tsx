import { Suspense } from "react";
import { redirect } from "next/navigation";
import { Loader2 } from "lucide-react";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { AppProviders } from "@/components/app/providers";
import { AppSidebar } from "@/components/app/app-sidebar";
import { Topbar } from "@/components/app/topbar";
import { readSessionUser } from "@/lib/server/session";

export default function AppLayout({ children }: LayoutProps<"/">) {
  // Everything below depends on the signed-in user (cookies), so it streams
  // behind a lightweight placeholder instead of blocking the prerender.
  return (
    <Suspense fallback={<ShellFallback />}>
      <AuthedShell>{children}</AuthedShell>
    </Suspense>
  );
}

async function AuthedShell({ children }: { children: React.ReactNode }) {
  const user = await readSessionUser();
  if (!user) redirect("/login");
  if (user.role !== "RECOVERY_EXECUTIVE") redirect("/login?reason=role");

  return (
    <AppProviders user={user}>
      <SidebarProvider>
        <AppSidebar />
        <SidebarInset className="min-w-0">
          <Topbar />
          <div className="flex-1 px-4 py-6 md:px-6 lg:px-8">{children}</div>
        </SidebarInset>
      </SidebarProvider>
    </AppProviders>
  );
}

function ShellFallback() {
  return (
    <div className="flex min-h-svh">
      <div className="hidden w-64 shrink-0 bg-sidebar md:block" />
      <div className="flex flex-1 items-center justify-center text-muted-foreground">
        <Loader2 className="size-5 animate-spin" />
      </div>
    </div>
  );
}
