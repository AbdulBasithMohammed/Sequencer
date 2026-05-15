"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { requestPasswordResetAction } from "../actions";
import type { AuthState } from "../actions";
import { SoftField } from "@/components/ui/field";
import { SoftButton } from "@/components/ui/button";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const initial: AuthState = { status: "idle" };

export function ForgotForm() {
  const [state, formAction, pending] = useActionState<AuthState, FormData>(
    requestPasswordResetAction,
    initial,
  );
  const [email, setEmail] = useState("");
  const emailValid = EMAIL_RE.test(email);

  if (state.status === "success") {
    return (
      <div className="rounded-2xl border border-line bg-surface px-6 py-8">
        <div className="font-display text-2xl font-bold tracking-tight">
          Check your email
        </div>
        <p className="mt-2 text-[14px] leading-[1.5] text-ink-soft">
          If an account exists for{" "}
          <span className="font-mono text-ink">{state.email}</span>, we sent a
          link to reset its password. The link expires in 1 hour.
        </p>
        <p className="mt-4 text-[13px] text-ink-soft">
          <Link
            href="/auth?mode=signin"
            className="font-semibold text-ink hover:underline"
          >
            ← Back to sign in
          </Link>
        </p>
      </div>
    );
  }

  return (
    <form action={formAction} noValidate>
      <SoftField
        label="Email"
        name="email"
        type="email"
        placeholder="you@somewhere.cool"
        required
        autoComplete="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
      />

      {state.status === "error" && (
        <div className="mb-3 flex items-start gap-2 rounded-xl border border-pink/40 bg-pink/10 px-3 py-2.5 text-[13px] font-medium text-ink">
          <span
            aria-hidden
            className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-pink text-canvas"
            style={{ fontSize: 13, fontWeight: 700, lineHeight: 1 }}
          >
            !
          </span>
          <span>{state.message}</span>
        </div>
      )}

      <SoftButton
        variant="primary"
        type="submit"
        disabled={pending || !emailValid}
        className="mt-2 w-full justify-center"
        trailing={!pending && emailValid && <span aria-hidden>→</span>}
      >
        {pending ? "Sending…" : "Send reset link"}
      </SoftButton>

      <p className="mt-4 text-center text-[13px] text-ink-soft">
        <Link
          href="/auth?mode=signin"
          className="font-semibold text-ink hover:underline"
        >
          ← Back to sign in
        </Link>
      </p>
    </form>
  );
}
