import { signOutAction } from "@/lib/auth/actions";
import { getCurrentProfile, getCurrentUser } from "@/lib/auth/me";
import { AppSidebar } from "./app-sidebar";

// Server-side data fetcher. Hands the sidebar to a client component
// that detects active route via usePathname() — so this whole shell can
// live in a layout file and stay mounted across tab switches instead
// of re-rendering on every navigation.

export async function AppShell({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!user) return <>{children}</>;
  const profile = await getCurrentProfile();

  const handle =
    profile?.display_name ?? user.email?.split("@")[0] ?? "you";
  const initial = (profile?.display_name ?? user.email ?? "?")[0]?.toUpperCase() ?? "?";

  return (
    <div className="grid flex-1 grid-cols-1 md:grid-cols-[300px_1fr]">
      <AppSidebar handle={handle} initial={initial} signOut={signOutAction} />
      <main className="overflow-hidden">{children}</main>
    </div>
  );
}
