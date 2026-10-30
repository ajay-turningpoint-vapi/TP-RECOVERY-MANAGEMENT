import type { Metadata } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";
import { ThemeProvider } from "next-themes";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import "./globals.css";

const sans = Inter({ variable: "--font-sans", subsets: ["latin"] });
const mono = JetBrains_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: { default: "TP-RMS Recovery Control", template: "%s · TP-RMS Recovery Control" },
  description: "Recovery Executive control dashboard for Turning Point receivables.",
  icons: { icon: "/logo.png" },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${sans.variable} ${mono.variable} h-full antialiased`} suppressHydrationWarning>
      <body className="min-h-full bg-background">
        <ThemeProvider attribute="class" defaultTheme="light" enableSystem disableTransitionOnChange>
          <TooltipProvider>{children}</TooltipProvider>
          <Toaster richColors closeButton position="top-center" toastOptions={{ classNames: { toast: "!w-[420px] !py-4", title: "!text-[15px] !font-semibold", description: "!text-sm" } }} />
        </ThemeProvider>
      </body>
    </html>
  );
}
