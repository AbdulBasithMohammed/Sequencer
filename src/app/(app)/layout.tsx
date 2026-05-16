import { AppShell } from "@/components/app-shell";

// Shared layout for authed nav pages (/play, /me, /friends). The
// AppShell sidebar stays mounted across these routes — only the page
// content swaps, which is what makes tab switching feel instant.

export default function AppGroupLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <AppShell>{children}</AppShell>;
}
