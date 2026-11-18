import { AppShell } from "@/components/app-shell";

// Shared layout for the nav pages (/play, /me, /friends, and the public
// /rules, /faq, /strategy). The AppShell sidebar stays mounted across all
// of them — only the page content swaps, which is what makes tab
// switching feel instant. The content pages used to wrap themselves in
// AppShell outside this group, so Play → How it works tore down and
// rebuilt the whole shell. AppShell renders bare for signed-out readers,
// so those pages look the same to them as before.

export default function AppGroupLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <AppShell>{children}</AppShell>;
}
