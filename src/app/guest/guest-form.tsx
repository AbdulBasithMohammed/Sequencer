"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { SoftButton } from "@/components/ui/button";

const MAX_NICKNAME = 20;

export function GuestSignInForm() {
  const [nickname, setNickname] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  const trimmed = nickname.trim();
  const valid = trimmed.length >= 3 && trimmed.length <= MAX_NICKNAME;

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!valid) {
      setError("Nickname must be 3–20 characters.");
      return;
    }
    startTransition(async () => {
      const supabase = createClient();
      const { error: signInError } = await supabase.auth.signInAnonymously({
        options: {
          data: { display_name: `${trimmed} (Guest)` },
        },
      });
      if (signInError) {
        setError(signInError.message);
        return;
      }
      router.replace("/play");
      router.refresh();
    });
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-3">
      <label
        htmlFor="guest-nickname"
        className="text-[11px] font-semibold uppercase tracking-[0.18em] text-ink-soft"
      >
        Nickname
      </label>
      <input
        id="guest-nickname"
        type="text"
        autoComplete="off"
        autoFocus
        maxLength={MAX_NICKNAME}
        value={nickname}
        onChange={(e) => setNickname(e.target.value)}
        placeholder="e.g. Alice"
        className="rounded-2xl border border-line bg-canvas px-4 py-3 text-[15px] text-ink outline-none focus:border-ink"
      />
      {trimmed.length >= 3 ? (
        <div className="text-[12px] text-ink-soft">
          Showing as{" "}
          <span className="font-mono font-semibold text-ink">
            {trimmed} (Guest)
          </span>
        </div>
      ) : null}
      {error ? (
        <div className="text-[12px] font-semibold text-pink">{error}</div>
      ) : null}
      <SoftButton
        type="submit"
        variant="primary"
        size="sm"
        disabled={!valid || pending}
        trailing={<span aria-hidden>→</span>}
        className="self-start"
      >
        {pending ? "Starting…" : "Continue as guest"}
      </SoftButton>
    </form>
  );
}
