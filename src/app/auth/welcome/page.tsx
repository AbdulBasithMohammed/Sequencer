import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";
import { SoftLinkButton } from "@/components/ui/button";

export const metadata = {
  title: "Welcome",
};

export default async function WelcomePage() {
  // Only reachable after a successful /auth/callback exchange — i.e. the user
  // is signed in AND verified. Anything else bounces back to /auth.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/auth?mode=signin");
  if (!user.email_confirmed_at) redirect("/auth?error=verification_failed");

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", user.id)
    .maybeSingle();
  const handle = profile?.display_name ?? "player";

  return (
    <div className="page-enter mx-auto flex w-full max-w-[520px] flex-1 flex-col px-6 py-10">
      <header className="mb-12">
        <Link href="/" aria-label="Sequencr home">
          <Wordmark size={24} accent="pink" />
        </Link>
      </header>

      <div className="mt-6">
        <div className="mb-3 inline-flex items-center gap-2 rounded-full border border-mint/50 bg-mint/15 px-3 py-1 text-[12px] font-semibold text-ink">
          <span
            aria-hidden
            className="flex h-4 w-4 items-center justify-center rounded-full bg-mint text-canvas"
            style={{ fontSize: 10, fontWeight: 700, lineHeight: 1 }}
          >
            ✓
          </span>
          Email verified
        </div>

        <h1
          className="mb-3 font-display font-bold leading-none"
          style={{
            fontSize: "clamp(38px, 5vw, 52px)",
            letterSpacing: "-0.03em",
          }}
        >
          Welcome,
          <br />
          <span className="italic text-pink">@{handle}.</span>
        </h1>
        <p className="mb-8 max-w-[440px] text-[15px] leading-[1.5] text-ink-soft">
          Your account is live. Create a room, share the code with friends, and
          start playing.
        </p>

        <SoftLinkButton
          variant="primary"
          href="/play?notice=verified"
          trailing={<span aria-hidden>→</span>}
        >
          Start playing
        </SoftLinkButton>
      </div>
    </div>
  );
}
