import { getCurrentProfile, getCurrentUser } from "@/lib/auth/me";
import { fetchMyInvites } from "@/lib/invites/actions";
import { InviteNotifications } from "./invite-notifications";

// Server-side gate: only mount the client notifications stack for
// signed-in registered users. Guests never receive invites (the
// invite_to_room RPC rejects guest targets) so don't open the
// realtime channel for them.

export async function InviteNotificationsMount() {
  const user = await getCurrentUser();
  if (!user) return null;
  const profile = await getCurrentProfile();
  if (profile?.is_guest) return null;
  const invites = await fetchMyInvites();
  return <InviteNotifications userId={user.id} initialInvites={invites} />;
}
