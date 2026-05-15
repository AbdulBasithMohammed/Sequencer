"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AuthState =
  | { status: "idle" }
  | { status: "error"; message: string }
  | { status: "success"; email: string };

// Practical email regex — catches obvious typos without trying to implement
// full RFC 5322. Real validation is the verification email round-trip.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function validateEmail(email: string): string | null {
  if (!email) return "Email is required.";
  if (!EMAIL_RE.test(email)) return "Please enter a valid email address.";
  return null;
}

function validatePassword(password: string): string | null {
  if (password.length < 8) return "Password must be at least 8 characters.";
  if (!/[a-z]/.test(password))
    return "Password must include a lowercase letter.";
  if (!/[A-Z]/.test(password))
    return "Password must include an uppercase letter.";
  if (!/\d/.test(password)) return "Password must include a number.";
  if (!/[^a-zA-Z0-9]/.test(password))
    return "Password must include a special character.";
  return null;
}

export async function signUpAction(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const displayName = String(formData.get("displayName") ?? "").trim();

  if (!email || !password || !displayName) {
    return { status: "error", message: "All fields are required." };
  }
  if (displayName.length < 3 || displayName.length > 20) {
    return {
      status: "error",
      message: "Display name must be 3–20 characters.",
    };
  }
  const emailError = validateEmail(email);
  if (emailError) return { status: "error", message: emailError };
  const passwordError = validatePassword(password);
  if (passwordError) return { status: "error", message: passwordError };

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { display_name: displayName },
      emailRedirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/auth/callback?next=/auth/welcome`,
    },
  });

  if (error) {
    const msg = error.message.toLowerCase();
    if (
      msg.includes("profiles_display_name_lower_idx") ||
      msg.includes("duplicate key") ||
      msg.includes("database error saving new user")
    ) {
      return { status: "error", message: "That display name is taken." };
    }
    if (
      msg.includes("already registered") ||
      msg.includes("already been registered")
    ) {
      return {
        status: "error",
        message: "An account with that email already exists.",
      };
    }
    return { status: "error", message: error.message };
  }

  // Supabase returns a fake user with empty `identities` when the email is
  // already registered AND verified — security feature to prevent email
  // enumeration. Surface it as a clear error in our UI.
  if (data.user && data.user.identities && data.user.identities.length === 0) {
    return {
      status: "error",
      message: "An account with that email already exists.",
    };
  }

  return { status: "success", email };
}

export async function signInAction(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const next = String(formData.get("next") ?? "/play");

  if (!email || !password) {
    return { status: "error", message: "Email and password are required." };
  }
  const emailError = validateEmail(email);
  if (emailError) return { status: "error", message: emailError };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    const msg = error.message.toLowerCase();
    if (msg.includes("invalid login credentials")) {
      return { status: "error", message: "Invalid email or password." };
    }
    if (msg.includes("email not confirmed")) {
      return {
        status: "error",
        message: "Please verify your email before signing in.",
      };
    }
    return { status: "error", message: error.message };
  }

  const safeNext = next.startsWith("/") && !next.startsWith("//") ? next : "/play";
  redirect(safeNext);
}

// ─── Password reset ────────────────────────────────────────────────────────

// Always return success so we don't leak which emails are registered.
export async function requestPasswordResetAction(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const email = String(formData.get("email") ?? "").trim();
  if (!email) return { status: "error", message: "Email is required." };
  const emailError = validateEmail(email);
  if (emailError) return { status: "error", message: emailError };

  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/auth/callback?next=/auth/reset`,
  });

  return { status: "success", email };
}

export async function resetPasswordAction(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const password = String(formData.get("password") ?? "");
  if (!password) return { status: "error", message: "Password is required." };
  const passwordError = validatePassword(password);
  if (passwordError) return { status: "error", message: passwordError };

  const supabase = await createClient();
  // Caller must already have a recovery session from the callback exchange.
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    redirect("/auth?error=reset_link_expired");
  }

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    return { status: "error", message: error.message };
  }

  // Sign out the recovery session — user must sign in fresh with new password.
  await supabase.auth.signOut();
  redirect("/auth?mode=signin&notice=reset_complete");
}
