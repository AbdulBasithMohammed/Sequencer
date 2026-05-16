import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";
import { SoftButton, SoftLinkButton } from "@/components/ui/button";
import { SoftPill } from "@/components/ui/pill";

const FEATURES = [
  ["Cozy rooms", "Invite friends with a 6-character code."],
  ["Your own color", "Pick a chip color and keep it all game."],
  ["Up to 12 players", "Solo, head-to-head, or two big teams."],
  ["Cross-device", "Phone or laptop — refresh anytime, your seat stays."],
] as const;

export default async function Home() {
  // Verified users land on the lobby — the marketing landing is for visitors.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user && user.email_confirmed_at) {
    redirect("/play");
  }

  return (
    <div className="relative flex flex-1 flex-col overflow-hidden">
      <div className="mx-auto flex w-full max-w-[1280px] flex-1 flex-col px-6 lg:px-12">
        {/* Top nav */}
        <header className="flex items-center justify-between py-6">
          <Link href="/" aria-label="Sequencr home">
            <Wordmark size={26} accent="pink" />
          </Link>
          <nav className="flex items-center gap-2">
            <NavLink href="/rules">How it works</NavLink>
            <SoftLinkButton
              href="/auth?mode=signin"
              size="sm"
              variant="outline"
            >
              Sign in
            </SoftLinkButton>
            <SoftLinkButton
              href="/auth?mode=signup"
              size="sm"
              variant="primary"
            >
              Create account
            </SoftLinkButton>
          </nav>
        </header>

        {/* Hero */}
        <main className="grid flex-1 grid-cols-1 items-center gap-10 py-6 lg:grid-cols-[1.1fr_1fr]">
          {/* Left column */}
          <div>
            <SoftPill>
              <span
                aria-hidden
                className="inline-block h-2 w-2 rounded-full bg-mint"
                style={{ boxShadow: "0 0 0 4px rgba(123,216,181,0.2)" }}
              />
              <span>Two players to twelve · 5 in a row to win</span>
            </SoftPill>

            <h1
              className="mt-5 font-display font-bold leading-[0.95]"
              style={{
                fontSize: "clamp(56px, 8vw, 92px)",
                letterSpacing: "-0.04em",
              }}
            >
              Five
              <br />
              <span className="font-display italic text-pink">in a row,</span>
              <br />
              forever.
            </h1>

            <p className="mt-5 max-w-[460px] text-[18px] leading-[1.5] text-ink-soft">
              A modern take on the board game you grew up with. Place tokens,
              claim lines, outwit friends — across cozy rooms with people you
              actually like.
            </p>

            <div className="mt-8 flex flex-wrap gap-3">
              <SoftLinkButton
                href="/auth?mode=signup"
                variant="primary"
                trailing={<span aria-hidden>→</span>}
              >
                Create your account
              </SoftLinkButton>
              <SoftLinkButton href="/auth?mode=signin" variant="outline">
                I already play
              </SoftLinkButton>
            </div>

            <div className="mt-8 flex flex-wrap gap-x-6 gap-y-1 text-[13px] font-medium text-ink-soft">
              <span>Friendly competitive</span>
              <span>· Free to play</span>
              <span>· No ads, ever</span>
            </div>
          </div>

          {/* Right column — four card suits dancing */}
          <div className="flex items-center justify-center lg:justify-end">
            <div className="relative" style={{ width: 460, height: 460 }}>
              {/* Soft radial glow behind the suits */}
              <div
                aria-hidden
                className="absolute inset-0"
                style={{
                  background:
                    "radial-gradient(circle at 50% 50%, rgba(255,210,63,0.45), rgba(255,92,138,0.18) 50%, transparent 70%)",
                  filter: "blur(30px)",
                }}
              />

              <Suit
                char="♥"
                color="var(--color-pink)"
                size={150}
                top={40}
                right={20}
                animation="suit-dance-2 8s ease-in-out infinite"
              />
              <Suit
                char="♠"
                color="var(--color-ink)"
                size={140}
                top={70}
                left={40}
                animation="suit-dance-1 7s 0.4s ease-in-out infinite"
              />
              <Suit
                char="♦"
                color="var(--color-blue)"
                size={130}
                bottom={50}
                right={70}
                animation="suit-dance-3 9s 0.8s ease-in-out infinite"
              />
              <Suit
                char="♣"
                color="var(--color-mint)"
                size={155}
                bottom={30}
                left={50}
                animation="suit-dance-4 10s 0.2s ease-in-out infinite"
              />
            </div>
          </div>
        </main>

        {/* Feature row */}
        <section
          id="how"
          className="grid grid-cols-2 gap-4 pb-7 lg:grid-cols-4"
        >
          {FEATURES.map(([title, body]) => (
            <div
              key={title}
              className="rounded-2xl border border-line bg-surface px-[18px] py-[14px]"
            >
              <div className="font-display text-base font-bold tracking-tight">
                {title}
              </div>
              <div className="mt-0.5 text-[12.5px] leading-[1.45] text-ink-soft">
                {body}
              </div>
            </div>
          ))}
        </section>
      </div>
    </div>
  );
}

function NavLink({ href, children }: { href: string; children: string }) {
  return (
    <Link
      href={href}
      className="rounded-full px-3 py-1.5 text-[13px] font-semibold text-ink hover:bg-surface"
    >
      {children}
    </Link>
  );
}

function Suit({
  char,
  color,
  size,
  top,
  left,
  right,
  bottom,
  animation,
}: {
  char: string;
  color: string;
  size: number;
  top?: number;
  left?: number;
  right?: number;
  bottom?: number;
  animation: string;
}) {
  return (
    <span
      aria-hidden
      style={{
        position: "absolute",
        top,
        left,
        right,
        bottom,
        fontSize: size,
        lineHeight: 1,
        color,
        fontFamily: "ui-serif, Georgia, 'Times New Roman', serif",
        filter: "drop-shadow(0 6px 0 rgba(27,21,48,0.16))",
        animation,
        display: "inline-block",
        willChange: "transform",
      }}
    >
      {char}
    </span>
  );
}
