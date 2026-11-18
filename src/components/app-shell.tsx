import { Suspense } from "react";
import { signOutAction } from "@/lib/auth/actions";
import { getCurrentProfile, getCurrentUser } from "@/lib/auth/me";
import { recordCountryOnce } from "@/lib/geo/record";
import { createClient } from "@/lib/supabase/server";
import { isExistingUser } from "@/lib/onboarding/steps";
import { OnboardingTour } from "@/components/onboarding/tour";
import { AppSidebar } from "./app-sidebar";

// Server-side data fetcher. Hands the sidebar to a client component
// that detects active route via usePathname() — so this whole shell can
// live in a layout file and stay mounted across tab switches instead
// of re-rendering on every navigation.

export async function AppShell({ children }: { children: React.ReactNode }) {
  const user = await getCurrentUser();
  if (!user) return <>{children}</>;
  const [profile, unreadReplies] = await Promise.all([
    getCurrentProfile(),
    getUnreadReplies(),
  ]);

  // One write per account, ever. Skipped entirely once set, which is
  // also what backfills the accounts that existed before this shipped —
  // they pick it up the next time they visit. There is no historical geo
  // to recover, so returning users are the only route.
  if (profile && !profile.country) await recordCountryOnce();

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
        unreadReplies={unreadReplies}
      />
      <main className="overflow-hidden">{children}</main>

      {/* Mounted for every authed page in this group, but gates itself to
          /play — never over a live game or a lobby. Sitting here rather
          than inside AppSidebar keeps it clear of the mobile dropdown,
          which unmounts its children when the menu closes.
          Suspense because it reads searchParams for the ?tour=1 replay. */}
      <Suspense fallback={null}>
        <OnboardingTour
          userId={user.id}
          isGuest={profile?.is_guest ?? false}
          existingUser={isExistingUser(profile?.created_at)}
          alreadySeen={Boolean(profile?.tour_seen_at)}
        />
      </Suspense>
    </div>
  );
}

// Admin replies the player hasn't opened yet. A partial-index probe; a
// failure just means no dot, never a broken shell.
async function getUnreadReplies() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("my_feedback_unread");
  if (error || typeof data !== "number") return 0;
  return data;
}
