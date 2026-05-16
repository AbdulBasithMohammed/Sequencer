"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

const VISIBLE_MS = 5500;
const FADE_MS = 500;

export function KickBanToast({
  banned,
  kicked,
}: {
  banned?: string;
  kicked?: string;
}) {
  const router = useRouter();
  const [visible, setVisible] = useState(true);

  useEffect(() => {
    const fade = window.setTimeout(() => setVisible(false), VISIBLE_MS);
    const clear = window.setTimeout(
      () => router.replace("/play"),
      VISIBLE_MS + FADE_MS,
    );
    return () => {
      window.clearTimeout(fade);
      window.clearTimeout(clear);
    };
  }, [router]);

  return (
    <div
      role="status"
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 top-5 z-50 flex justify-center px-5"
    >
      <div
        className="pointer-events-auto flex w-full max-w-md items-start gap-3 rounded-2xl border border-pink/40 bg-surface px-4 py-3 shadow-xl transition-all duration-500"
        style={{
          opacity: visible ? 1 : 0,
          transform: visible ? "translateY(0)" : "translateY(-12px)",
        }}
      >
        <span
          aria-hidden
          className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-pink text-canvas"
          style={{ fontSize: 14, fontWeight: 700, lineHeight: 1 }}
        >
          !
        </span>
        <div className="flex-1">
          <div className="font-display text-[14px] font-bold tracking-tight">
            {banned
              ? `You were banned from room ${banned}.`
              : `You were removed from room ${kicked}.`}
          </div>
          <div className="text-[12px] text-ink-soft">
            {banned
              ? "The host banned you. You can't rejoin this room unless they unban you."
              : "The host kicked you. You can join a different room or create your own below."}
          </div>
        </div>
        <Link
          href="/play"
          aria-label="Dismiss"
          className="text-[13px] font-semibold text-ink-soft hover:text-ink"
        >
          Dismiss
        </Link>
      </div>
    </div>
  );
}
