"use client";

import { useEffect, useState, useTransition } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  acceptInvite,
  declineInvite,
  fetchMyInvites,
  type RoomInvite,
} from "@/lib/invites/actions";

export function InviteNotifications({
  userId,
  initialInvites,
}: {
  userId: string;
  initialInvites: RoomInvite[];
}) {
  const [invites, setInvites] = useState<RoomInvite[]>(initialInvites);

  useEffect(() => {
    const supabase = createClient();
    const channel = supabase
      .channel(`invites:${userId}`, { config: { private: false } })
      .on("broadcast", { event: "update" }, async () => {
        const fresh = await fetchMyInvites();
        setInvites(fresh);
      })
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId]);

  if (invites.length === 0) return null;

  return (
    <div className="pointer-events-none fixed right-4 top-4 z-50 flex w-[320px] max-w-[calc(100vw-2rem)] flex-col gap-2">
      {invites.map((inv) => (
        <InviteCard key={inv.room_id} invite={inv} />
      ))}
    </div>
  );
}

function InviteCard({ invite }: { invite: RoomInvite }) {
  const [acting, startTransition] = useTransition();

  return (
    <div
      className="card-enter pointer-events-auto rounded-2xl border border-line bg-surface px-4 py-3 shadow-[0_8px_30px_-12px_rgba(0,0,0,0.25)]"
      style={{ borderTopWidth: 3, borderTopColor: "var(--color-pink)" }}
    >
      <div className="text-[10px] font-semibold uppercase tracking-[0.18em] text-ink-soft">
        Room invite
      </div>
      <div className="mt-1 text-[14px] font-semibold text-ink">
        {invite.from_display_name}{" "}
        <span className="font-mono font-normal text-ink-soft">
          #{invite.from_tag}
        </span>
      </div>
      <div className="mt-0.5 text-[12px] text-ink-soft">
        Room{" "}
        <span className="font-mono font-bold text-ink">
          {invite.room_code}
        </span>{" "}
        · {invite.target_players} players
      </div>
      <div className="mt-3 flex gap-2">
        <button
          type="button"
          disabled={acting}
          onClick={() =>
            startTransition(async () => {
              await acceptInvite(invite.room_id, invite.room_code);
            })
          }
          className="flex-1 rounded-full bg-ink px-3 py-1.5 text-[12px] font-semibold text-canvas transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {acting ? "…" : "Accept"}
        </button>
        <button
          type="button"
          disabled={acting}
          onClick={() =>
            startTransition(async () => {
              await declineInvite(invite.room_id);
            })
          }
          className="flex-1 rounded-full border border-line px-3 py-1.5 text-[12px] font-semibold text-ink transition-opacity hover:bg-canvas disabled:opacity-50"
        >
          Decline
        </button>
      </div>
    </div>
  );
}
