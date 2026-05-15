"use client";

import { useActionState, useState } from "react";
import { resetPasswordAction, type AuthState } from "../actions";
import { SoftField } from "@/components/ui/field";
import { SoftButton } from "@/components/ui/button";

const initial: AuthState = { status: "idle" };

export function ResetForm() {
  const [state, formAction, pending] = useActionState<AuthState, FormData>(
    resetPasswordAction,
    initial,
  );
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);

  return (
    <form action={formAction} noValidate>
      <SoftField
        label="New password"
        name="password"
        type={showPassword ? "text" : "password"}
        placeholder="••••••••••"
        required
        autoComplete="new-password"
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

      <PasswordChecklist password={password} />

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
        {pending ? "Saving…" : "Set new password"}
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
