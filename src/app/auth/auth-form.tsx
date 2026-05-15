"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { signInAction, signUpAction, type AuthState } from "./actions";
import { SoftField } from "@/components/ui/field";
import { SoftButton } from "@/components/ui/button";

const initialAuthState: AuthState = { status: "idle" };

type Mode = "signup" | "signin";

export function AuthForm({
  initialMode,
  next,
  urlError,
  urlNotice,
}: {
  initialMode: Mode;
  next: string;
  urlError?: string | null;
  urlNotice?: string | null;
}) {
  const [mode, setMode] = useState<Mode>(initialMode);

  return (
    <div className="w-full max-w-[440px]">
      {/* Mode toggle pill */}
      <div className="mb-7 inline-flex gap-1 rounded-2xl border border-line bg-surface p-1">
        {(["signup", "signin"] as const).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => setMode(m)}
            className={`rounded-xl px-4 py-2 text-[13px] font-semibold transition-colors ${
              mode === m
                ? "bg-ink text-canvas"
                : "bg-transparent text-ink-soft hover:text-ink"
            }`}
          >
            {m === "signup" ? "Create account" : "Sign in"}
          </button>
        ))}
      </div>

      {/* Headline */}
      <h1
        className="mb-2 font-display font-bold leading-none"
        style={{ fontSize: "clamp(38px, 5vw, 48px)", letterSpacing: "-0.03em" }}
      >
        {mode === "signup" ? (
          <>
            Pick your
            <br />
            <span className="italic text-pink">handle.</span>
          </>
        ) : (
          <>
            Welcome
            <br />
            <span className="italic text-pink">back.</span>
          </>
        )}
      </h1>
      <p className="mb-6 max-w-[380px] text-[15px] leading-[1.5] text-ink-soft">
        {mode === "signup"
          ? "It only takes a moment. You can change everything later."
          : "Your rooms and your rank are waiting."}
      </p>

      {/* URL-driven banners — verification failures, reset completion, etc. */}
      {urlError && (
        <div className="mb-4 flex items-start gap-2 rounded-xl border border-pink/40 bg-pink/10 px-3 py-2.5 text-[13px] font-medium text-ink">
          <span
            aria-hidden
            className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-pink text-canvas"
            style={{ fontSize: 13, fontWeight: 700, lineHeight: 1 }}
          >
            !
          </span>
          <span>{urlError}</span>
        </div>
      )}
      {urlNotice && (
        <div className="mb-4 flex items-start gap-2 rounded-xl border border-mint/40 bg-mint/15 px-3 py-2.5 text-[13px] font-medium text-ink">
          <span
            aria-hidden
            className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-mint text-canvas"
            style={{ fontSize: 13, fontWeight: 700, lineHeight: 1 }}
          >
            ✓
          </span>
          <span>{urlNotice}</span>
        </div>
      )}

      {/* The form — keyed on mode so React remounts (resets state) when toggling */}
      <FormBody key={mode} mode={mode} next={next} />
    </div>
  );
}

function FormBody({ mode, next }: { mode: Mode; next: string }) {
  const action = mode === "signup" ? signUpAction : signInAction;
  const [state, formAction, pending] = useActionState<AuthState, FormData>(
    action,
    initialAuthState,
  );
  const [showPassword, setShowPassword] = useState(false);
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");

  // Mirror the server-side regex so client + server agree on what counts.
  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  const emailValid = EMAIL_RE.test(email);
  const showEmailHint = email.length > 0 && !emailValid;

  if (state.status === "success") {
    return (
      <div className="rounded-2xl border border-line bg-surface px-6 py-8">
        <div className="font-display text-2xl font-bold tracking-tight">
          Check your email
        </div>
        <p className="mt-2 text-[14px] leading-[1.5] text-ink-soft">
          We sent a verification link to{" "}
          <span className="font-mono text-ink">{state.email}</span>. Click it to
          activate your account.
        </p>
      </div>
    );
  }

  return (
    <form action={formAction} noValidate>
      {mode === "signin" && <input type="hidden" name="next" value={next} />}

      {mode === "signup" && (
        <div>
          <SoftField
            label="Display name"
            name="displayName"
            placeholder="e.g. Hex-Wizard"
            required
            minLength={3}
            maxLength={20}
            autoComplete="username"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            trailing={
              <span
                className={`text-[12px] font-semibold tabular-nums ${
                  displayName.length >= 3 && displayName.length <= 20
                    ? "text-mint"
                    : "text-ink-soft"
                }`}
              >
                {displayName.length}/20
              </span>
            }
          />
          {displayName.length > 0 && displayName.length < 3 && (
            <p className="mb-3.5 -mt-2 text-[12px] text-ink-soft">
              Display name must be at least 3 characters.
            </p>
          )}
        </div>
      )}

      <div>
        <SoftField
          label="Email"
          name="email"
          type="email"
          placeholder="you@somewhere.cool"
          required
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          trailing={
            email.length > 0 && (
              <span
                aria-hidden
                className={`flex h-4 w-4 items-center justify-center rounded-full text-[10px] font-bold ${
                  emailValid
                    ? "bg-mint text-canvas"
                    : "bg-ink-soft/30 text-ink-soft"
                }`}
              >
                {emailValid ? "✓" : "?"}
              </span>
            )
          }
        />
        {showEmailHint && (
          <p className="mb-3.5 -mt-2 text-[12px] text-ink-soft">
            That doesn&apos;t look like a valid email.
          </p>
        )}
      </div>

      <SoftField
        label="Password"
        name="password"
        type={showPassword ? "text" : "password"}
        placeholder="••••••••••"
        required
        autoComplete={mode === "signup" ? "new-password" : "current-password"}
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        trailing={
          <button
            type="button"
            onClick={() => setShowPassword((v) => !v)}
            className="text-[12px] font-semibold text-ink-soft hover:text-ink"
          >
            {showPassword ? "hide" : "show"}
          </button>
        }
      />

      {mode === "signup" && (
        <PasswordChecklist password={password} />
      )}

      {mode === "signin" && (
        <div className="mb-4 -mt-1.5 text-right">
          <Link
            href="/auth/forgot"
            className="text-[12.5px] font-semibold text-ink-soft hover:text-ink"
          >
            Forgot password?
          </Link>
        </div>
      )}

      {mode === "signup" && (
        <p className="mt-1 mb-4 text-[12px] text-ink-soft">
          By signing up, you agree to play nice.{" "}
          <span className="underline">Terms</span> ·{" "}
          <span className="underline">Privacy</span>
        </p>
      )}

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
        disabled={pending}
        className="mt-2 w-full justify-center"
        trailing={!pending && <span aria-hidden>→</span>}
      >
        {pending
          ? mode === "signup"
            ? "Creating account…"
            : "Signing in…"
          : mode === "signup"
            ? "Create account"
            : "Sign in"}
      </SoftButton>
    </form>
  );
}

function PasswordChecklist({ password }: { password: string }) {
  const rules: { label: string; pass: boolean }[] = [
    { label: "At least 8 characters", pass: password.length >= 8 },
    { label: "One lowercase letter", pass: /[a-z]/.test(password) },
    { label: "One uppercase letter", pass: /[A-Z]/.test(password) },
    { label: "One number", pass: /\d/.test(password) },
    { label: "One special character", pass: /[^a-zA-Z0-9]/.test(password) },
  ];

  return (
    <ul className="mb-4 mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-[12px]">
      {rules.map((r) => (
        <li
          key={r.label}
          className={`flex items-center gap-1.5 ${
            r.pass ? "text-mint" : "text-ink-soft"
          }`}
        >
          <span
            aria-hidden
            className={`flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full text-[9px] font-bold ${
              r.pass ? "bg-mint text-canvas" : "border border-line bg-canvas"
            }`}
          >
            {r.pass ? "✓" : ""}
          </span>
          <span>{r.label}</span>
        </li>
      ))}
    </ul>
  );
}
