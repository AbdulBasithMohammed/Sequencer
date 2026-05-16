"use client";

import { useEffect, useState, useTransition } from "react";
import { createClient } from "@/lib/supabase/client";
import { OnlineDot } from "@/components/presence";
import {
  fetchInvitableFriends,
  inviteToRoom,
  type InvitableFriend,
} from "@/lib/invites/actions";

export function InviteFriendsPanel({ roomId }: { roomId: string }) {
  const [friends, setFriends] = useState<InvitableFriend[]>([]);
  const [loaded, setLoaded] = useState(false);

  // Initial fetch + re-fetch when the lobby broadcast fires (which it
  // does on room_invites changes via the rooms.version cascade).
  useEffect(() => {
    let alive = true;
    async function reload() {
      const data = await fetchInvitableFriends(roomId);
      if (alive) {
        setFriends(data);
        setLoaded(true);
      }
    }
    reload();

    const supabase = createClient();
    const channel = supabase
      .channel(`lobby:${roomId}`, { config: { private: false } })
      .on("broadcast", { event: "update" }, () => reload())
      .subscribe();
    return () => {
      alive = false;
      supabase.removeChannel(channel);
    };
  }, [roomId]);

  if (!loaded) return null;
  if (friends.length === 0) {
    return (
      <section className="mt-6">
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-ink-soft">
          Invite friends
        </h2>
        <div className="mt-2 rounded-2xl border border-line bg-surface px-4 py-3 text-[13px] text-ink-soft">
          You don&apos;t have any friends yet — add some from the Friends tab.
        </div>
      </section>
    );
  }

  return (
    <section className="mt-6">
      <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-ink-soft">
        Invite friends
        <span className="ml-1.5 text-ink">{friends.length}</span>
      </h2>
      <div className="mt-2 overflow-hidden rounded-2xl border border-line bg-surface">
        {friends.map((f, i) => (
          <FriendRow
            key={f.user_id}
            friend={f}
            roomId={roomId}
            isLast={i === friends.length - 1}
          />
        ))}
      </div>
    </section>
  );
}

function FriendRow({
  friend,
  roomId,
  isLast,
}: {
  friend: InvitableFriend;
  roomId: string;
  isLast: boolean;
}) {
  const [pending, startTransition] = useTransition();

  const action =
    friend.state === "in_room" ? (
      <Pill>In room</Pill>
    ) : friend.state === "invited" ? (
      <Pill>Invited</Pill>
    ) : (
      <button
        type="button"
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            await inviteToRoom(roomId, friend.user_id);
          })
        }
        className="rounded-full bg-ink px-3 py-1.5 text-[12px] font-semibold text-canvas transition-opacity hover:opacity-90 disabled:opacity-50"
      >
        {pending ? "…" : "Invite"}
      </button>
    );

  return (
    <div
      className={`flex items-center justify-between gap-3 px-4 py-3 ${
        isLast ? "" : "border-b border-line"
      }`}
    >
      <div className="flex min-w-0 flex-1 items-center gap-2.5">
        <OnlineDot userId={friend.user_id} />
        <div className="truncate text-[14px] font-semibold text-ink">
          {friend.display_name}{" "}
          <span className="font-mono font-normal text-ink-soft">
            #{friend.tag}
          </span>
        </div>
      </div>
      {action}
    </div>
  );
}

function Pill({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full border border-line px-3 py-1 text-[11px] font-semibold text-ink-soft">
      {children}
    </span>
  );
}
