import { signOutAction } from "@/lib/auth/actions";
import { getCurrentProfile, getCurrentUser } from "@/lib/auth/me";
import { AppSidebar } from "./app-sidebar";
import { FeedbackWidget } from "./feedback-widget";

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
    <div className="flex flex-1 flex-col md:grid md:grid-cols-[300px_1fr]">
      <AppSidebar
        handle={handle}
        initial={initial}
        signOut={signOutAction}
        isGuest={profile?.is_guest ?? false}
      />
      <main className="overflow-hidden">{children}</main>
      {/* Inside the authed branch only — submit_feedback requires a
          session, so showing this to signed-out visitors would just
          produce an error they can do nothing about. */}
      <FeedbackWidget />
    </div>
  );
}
