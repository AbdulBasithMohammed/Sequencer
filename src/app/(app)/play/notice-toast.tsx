"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

const VISIBLE_MS = 4500;
const FADE_MS = 500;

const NOTICES: Record<string, { title: string; body: string }> = {
  verified: {
    title: "Email verified",
    body: "You're all set — create a room or join one to get started.",
  },
};

export function NoticeToast({ notice }: { notice: string }) {
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

  const content = NOTICES[notice];
  if (!content) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 top-5 z-50 flex justify-center px-5"
    >
      <div
        className="menu-enter pointer-events-auto flex w-full max-w-md items-start gap-3 rounded-2xl border border-mint/50 bg-surface px-4 py-3 shadow-xl transition-all duration-500"
        style={{
          opacity: visible ? 1 : 0,
          transform: visible ? "translateY(0)" : "translateY(-12px)",
        }}
      >
        <span
          aria-hidden
          className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-mint text-canvas"
          style={{ fontSize: 14, fontWeight: 700, lineHeight: 1 }}
        >
          ✓
        </span>
        <div className="flex-1">
          <div className="font-display text-[14px] font-bold tracking-tight">
            {content.title}
          </div>
          <div className="text-[12px] text-ink-soft">{content.body}</div>
        </div>
      </div>
    </div>
  );
}
