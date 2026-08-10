import Link from "next/link";
import { getCurrentUser } from "@/lib/auth/me";
import { Wordmark } from "@/components/ui/wordmark";
import { SoftLinkButton } from "@/components/ui/button";
import { AppShell } from "@/components/app-shell";

export const metadata = {
  title: "Sequence Online FAQ",
  description:
    "Common questions about playing Sequence online: player counts, playing with friends, bots, whether you need an account, mobile support, and how long a game takes.",
  alternates: { canonical: "/faq" },
};

// Both the visible list and the FAQPage schema render from this single
// array. Structured data that disagrees with what a reader sees is the
// thing Google issues manual actions for, so there is deliberately no
// second copy to drift out of sync.
const FAQS: { q: string; a: string }[] = [
  {
    q: "Can I play Sequence online for free?",
    a: "Yes. Sequencr is free to play in the browser with no ads, no installs and no payment of any kind. Open the site, pick a game and play.",
  },
  {
    q: "How many people can play at once?",
    a: "Between 2 and 12 players, at counts that split into balanced teams: 2, 3, 4, 6, 8, 9, 10 and 12. Games can run as two teams or three, and hand size shrinks as the table grows — seven cards at two players down to three at ten or twelve.",
  },
  {
    q: "Can I play Sequence online with friends?",
    a: "Yes. Create a room and share the six-character room code, or the join link. Anyone with the code can take a seat, and registered players can also invite friends directly from their friends list.",
  },
  {
    q: "Can I play against the computer?",
    a: "Yes. You can add bots to any room and fill empty seats with them, so you can start immediately without waiting for other people. Bots play a full turn on their own, including using jacks and blocking threats, and come in several difficulty levels.",
  },
  {
    q: "Do I need to create an account?",
    a: "No. You can play as a guest with just a nickname. A free account adds a friends list, room invites and a profile that persists — guest sessions are removed automatically after a day of inactivity.",
  },
  {
    q: "Does it work on a phone?",
    a: "Yes. The board, lobby and game views are built for touch and adapt to small screens, so you can play in a mobile browser without installing anything.",
  },
  {
    q: "How long does a game take?",
    a: "Most games run about 10 to 20 minutes. Turns are timed, so a game cannot stall on one player — if the clock runs out their turn passes automatically and play continues.",
  },
  {
    q: "What happens if someone leaves mid-game?",
    a: "Play continues. Turns are on a timer, so an absent player's turn passes automatically rather than freezing the table, and empty seats can be filled with a bot.",
  },
  {
    q: "Is this the official Sequence game?",
    a: "No. Sequencr is an independent, fan-made implementation of the game's public rules, and is not affiliated with, endorsed by or connected to Jax Ltd, who own the Sequence trademark and publish the physical board game.",
  },
];

export default async function FaqPage() {
  const user = await getCurrentUser();
  const isAuthed = !!user;

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: FAQS.map(({ q, a }) => ({
      "@type": "Question",
      name: q,
      acceptedAnswer: { "@type": "Answer", text: a },
    })),
  };

  const content = (
    <div
      className={
        isAuthed
          ? "page-enter mx-auto flex w-full max-w-[820px] flex-col px-8 py-8"
          : "page-enter mx-auto flex w-full max-w-[820px] flex-1 flex-col px-6 py-8 lg:px-12"
      }
    >
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      {!isAuthed && (
        <header className="mb-10 flex items-center justify-between">
          <Link href="/" aria-label="Sequencr home">
            <Wordmark size={22} accent="pink" />
          </Link>
          <Link
            href="/"
            className="text-[13px] font-semibold text-ink-soft hover:text-ink"
          >
            ← Home
          </Link>
        </header>
      )}

      <h1
        className="font-display font-bold leading-[0.95]"
        style={{ fontSize: "clamp(44px, 6vw, 64px)", letterSpacing: "-0.03em" }}
      >
        Questions
      </h1>
      <p className="mt-4 max-w-[560px] text-[16px] leading-[1.5] text-ink-soft">
        Everything people usually ask before their first game. For the
        mechanics themselves see the{" "}
        <Link href="/rules" className="underline">
          rules
        </Link>
        , and for tactics the{" "}
        <Link href="/strategy" className="underline">
          strategy guide
        </Link>
        .
      </p>

      <dl className="mt-10">
        {FAQS.map(({ q, a }) => (
          <div key={q} className="mt-8">
            <dt
              className="font-display text-[22px] font-bold text-ink"
              style={{ letterSpacing: "-0.01em" }}
            >
              {q}
            </dt>
            <dd className="mt-2 text-[15px] leading-[1.55] text-ink">{a}</dd>
          </div>
        ))}
      </dl>

      <div className="mt-12 mb-8 flex flex-wrap gap-3">
        {!isAuthed && (
          <SoftLinkButton href="/guest" variant="primary" size="sm">
            Play as a guest
          </SoftLinkButton>
        )}
        <SoftLinkButton href="/rules" variant="outline" size="sm">
          Read the rules
        </SoftLinkButton>
      </div>
    </div>
  );

  return isAuthed ? <AppShell>{content}</AppShell> : content;
}
