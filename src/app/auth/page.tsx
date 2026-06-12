import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";
import { Glyph } from "@/components/ui/glyph";
import { BoardPreview } from "@/components/ui/board";
import { makeScattered } from "@/lib/board-helpers";
import { AuthForm } from "./auth-form";
import { QuoteCycler } from "@/components/ui/quote-cycler";

export const metadata = {
  title: "Sign in",
};

const URL_MESSAGES: Record<string, string> = {
  verification_failed:
    "That verification link is invalid or has expired. Sign up again to get a fresh one.",
  link_expired:
    "Your verification link expired. Sign up again to get a fresh one.",
  reset_failed:
    "We couldn't process that password reset link. Request a new one below.",
  reset_link_expired:
    "Your password reset link expired. Request a new one below.",
  reset_complete: "Password reset — sign in with your new password.",
};

export default async function AuthPage({
  searchParams,
}: {
  searchParams: Promise<{
    mode?: string;
    next?: string;
    error?: string;
    notice?: string;
  }>;
}) {
  const params = await searchParams;
  const next = params.next ?? "/play";
  const mode: "signup" | "signin" = params.mode === "signin" ? "signin" : "signup";
  const urlError = params.error ? URL_MESSAGES[params.error] ?? null : null;
  const urlNotice = params.notice ? URL_MESSAGES[params.notice] ?? null : null;

  // Already signed in + verified → bounce to next.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user && user.email_confirmed_at) {
    redirect(next.startsWith("/") && !next.startsWith("//") ? next : "/play");
  }

  return (
    <div className="page-enter grid flex-1 grid-cols-1 lg:grid-cols-2">
      {/* Left: decorative gradient panel */}
      <aside
        className="relative hidden items-center justify-center overflow-hidden lg:flex"
        style={{
          background:
            "linear-gradient(160deg, var(--color-pink) 0%, var(--color-butter) 100%)",
        }}
      >
        {/* Bloom glow */}
        <div
          aria-hidden
          className="absolute inset-0"
          style={{
            background:
              "radial-gradient(circle at 80% 90%, rgba(91,124,250,0.4), transparent 50%)",
          }}
        />

        {/* Wordmark top-left */}
        <Link
          href="/"
          className="absolute left-10 top-10 z-10"
          aria-label="Sequencr home"
        >
          <Wordmark size={26} accent="#FFFBF3" color="var(--color-ink)" />
        </Link>

        {/* Floating decorative board */}
        <div
          className="relative"
          style={{
            transform: "rotate(-8deg)",
            animation: "seq-float 7s ease-in-out infinite",
          }}
        >
          <BoardPreview size={420} cells={makeScattered()} />
        </div>

        {/* Floating ink token with butter hex glyph */}
        <div
          aria-hidden
          className="absolute"
          style={{
            top: 110,
            right: 60,
            animation: "seq-bob 5s ease-in-out infinite",
          }}
        >
          <div
            className="flex items-center justify-center rounded-full bg-ink"
            style={{
              width: 80,
              height: 80,
              boxShadow: "0 8px 0 rgba(0,0,0,0.2)",
            }}
          >
            <Glyph kind="hex" size={36} color="#FFD23F" />
          </div>
        </div>

        {/* Rotating pull-quote bottom-left */}
        <div className="absolute bottom-10 left-10 right-10">
          <QuoteCycler />
        </div>
      </aside>

      {/* Right: form */}
      <main className="flex items-center justify-center px-8 py-12 lg:px-20">
        <AuthForm
          initialMode={mode}
          next={next}
          urlError={urlError}
          urlNotice={urlNotice}
        />
      </main>
    </div>
  );
}
