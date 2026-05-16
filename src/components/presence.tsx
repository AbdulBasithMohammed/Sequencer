"use client";

import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { createClient } from "@/lib/supabase/client";

// Global Supabase Realtime Presence. Every logged-in user tracks
// themselves on the same channel; everyone else sees the synced set
// of online user_ids. The browser client runs its heartbeat in a Web
// Worker (see lib/supabase/client.ts) so backgrounded tabs don't
// silently drop the connection.

const PresenceContext = createContext<Set<string>>(new Set());

export function PresenceProvider({
  userId,
  children,
}: {
  userId: string | null;
  children: ReactNode;
}) {
  const [online, setOnline] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!userId) return;
    const supabase = createClient();
    const channel = supabase.channel("presence:online", {
      config: { presence: { key: userId } },
    });

    channel.on("presence", { event: "sync" }, () => {
      const state = channel.presenceState();
      setOnline(new Set(Object.keys(state)));
    });

    channel.subscribe(async (status) => {
      if (status === "SUBSCRIBED") {
        await channel.track({ online_at: new Date().toISOString() });
      }
    });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId]);

  return (
    <PresenceContext.Provider value={online}>
      {children}
    </PresenceContext.Provider>
  );
}

export function usePresence(targetUserId: string): boolean {
  return useContext(PresenceContext).has(targetUserId);
}

export function OnlineDot({
  userId,
  className = "",
}: {
  userId: string;
  className?: string;
}) {
  const isOnline = usePresence(userId);
  return (
    <span
      aria-label={isOnline ? "Online" : "Offline"}
      title={isOnline ? "Online" : "Offline"}
      className={`inline-block size-2 rounded-full ${
        isOnline ? "bg-mint" : "bg-line"
      } ${className}`}
      style={
        isOnline
          ? { boxShadow: "0 0 0 3px rgba(123,216,181,0.25)" }
          : undefined
      }
    />
  );
}
