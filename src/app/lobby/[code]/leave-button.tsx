"use client";

import { leaveRoomAction } from "./actions";
import { SoftButton } from "@/components/ui/button";

/**
 * Wraps the leave form so we can set a sessionStorage flag *before* submit.
 * The Realtime DELETE event from leave_room arrives on this same browser, and
 * the refresher uses the flag to know this was voluntary (skip the kicked
 * redirect — the server action's redirect takes us to /play directly).
 */
export function LeaveButton({ roomId }: { roomId: string }) {
  return (
    <form
      action={leaveRoomAction}
      onSubmit={() => {
        try {
          window.sessionStorage.setItem("voluntary-leave", roomId);
        } catch {
          // ignore — worst case we get a stray "kicked" banner on /play
        }
      }}
    >
      <input type="hidden" name="roomId" value={roomId} />
      <SoftButton type="submit" variant="outline">
        Leave room
      </SoftButton>
    </form>
  );
}
