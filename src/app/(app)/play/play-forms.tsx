"use client";

import { useActionState, useState } from "react";
import {
  createRoomAction,
  joinRoomAction,
  type FormState,
} from "./actions";
import { SoftButton } from "@/components/ui/button";

const PLAYER_COUNTS = [2, 3, 4, 6, 8, 10, 12] as const;
const initial: FormState = { error: null };

export function CreateRoomCard() {
  const [state, formAction, pending] = useActionState(createRoomAction, initial);
  const [count, setCount] = useState(4);

  return (
    <div
      className="relative overflow-hidden rounded-3xl p-7"
      style={{
        background:
          "linear-gradient(120deg, var(--color-pink), var(--color-butter) 90%)",
      }}
    >
      <h2
        className="font-display font-bold leading-none text-ink"
        style={{ fontSize: 32, letterSpacing: "-0.03em" }}
      >
        Create a room
      </h2>
      <p className="mt-2 max-w-[420px] text-[14px] text-ink/75">
        Pick a player count and share the code with friends.
      </p>

      {/* Chips live OUTSIDE the form. Inside a React-19 server-action form,
          iOS Safari sometimes swallows taps on non-submit buttons. */}
      <div className="mt-5 flex flex-wrap gap-1.5">
        {PLAYER_COUNTS.map((n) => (
          <button
            key={n}
            type="button"
            onClick={() => setCount(n)}
            className={`cursor-pointer touch-manipulation select-none rounded-full px-4 py-2 text-[13px] font-bold transition-colors ${
              count === n
                ? "bg-ink text-canvas"
                : "bg-canvas/40 text-ink [@media(hover:hover)]:hover:bg-canvas/60"
            }`}
          >
            {n}
          </button>
        ))}
      </div>

      <p className="mt-3 text-[12px] text-ink/60">
        {count === 2 || count === 3
          ? `${count} players · free-for-all`
          : `${count} players · ${count / 2}v${count / 2} or teams`}
      </p>

      {state.error && (
        <div className="mt-3 rounded-xl bg-ink/10 px-3 py-2 text-[13px] font-medium text-ink">
          {state.error}
        </div>
      )}

      <form action={formAction} className="mt-5">
        <input type="hidden" name="targetPlayers" value={count} />
        <SoftButton
          type="submit"
          variant="primary"
          disabled={pending}
          trailing={!pending && <span aria-hidden>→</span>}
        >
          {pending ? "Creating…" : "Create room"}
        </SoftButton>
      </form>
    </div>
  );
}

export function JoinRoomCard() {
  const [state, formAction, pending] = useActionState(joinRoomAction, initial);
  const [code, setCode] = useState("");

  return (
    <form
      action={formAction}
      className="rounded-3xl border border-line bg-surface p-7"
    >
      <h2
        className="font-display font-bold leading-none text-ink"
        style={{ fontSize: 28, letterSpacing: "-0.03em" }}
      >
        Join a room
      </h2>
      <p className="mt-2 text-[14px] text-ink-soft">
        Got a code from a friend? Drop it here.
      </p>

      <div className="mt-5 flex flex-col gap-3 sm:flex-row">
        <input
          name="code"
          value={code}
          onChange={(e) =>
            setCode(
              e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 6),
            )
          }
          placeholder="ABC123"
          maxLength={6}
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="characters"
          spellCheck={false}
          inputMode="text"
          className="flex-1 rounded-2xl border-[1.5px] border-line bg-canvas px-4 py-3.5 text-center font-mono text-xl font-bold uppercase tracking-[0.3em] text-ink outline-none placeholder:text-ink-soft/40 focus:border-ink"
        />
        <SoftButton
          type="submit"
          variant="primary"
          disabled={pending || code.length !== 6}
          trailing={!pending && code.length === 6 && <span aria-hidden>→</span>}
        >
          {pending ? "Joining…" : "Join"}
        </SoftButton>
      </div>

      {state.error && (
        <div className="mt-3 flex items-start gap-2 rounded-xl border border-pink/40 bg-pink/10 px-3 py-2.5 text-[13px] font-medium text-ink">
          <span
            aria-hidden
            className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-pink text-canvas"
            style={{ fontSize: 13, fontWeight: 700, lineHeight: 1 }}
          >
            !
          </span>
          <span>{state.error}</span>
        </div>
      )}
    </form>
  );
}
