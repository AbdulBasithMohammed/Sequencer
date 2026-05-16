import { getCurrentUser } from "@/lib/auth/me";
import { fetchMyInvites } from "@/lib/invites/actions";
import { InviteNotifications } from "./invite-notifications";

// Server-side gate: only mount the client notifications stack for
// signed-in users. Sits in the root layout so it appears across every
// authed route — /play, /lobby, /game, /friends, etc.

export async function InviteNotificationsMount() {
  const user = await getCurrentUser();
  if (!user) return null;
  const invites = await fetchMyInvites();
  return <InviteNotifications userId={user.id} initialInvites={invites} />;
}
