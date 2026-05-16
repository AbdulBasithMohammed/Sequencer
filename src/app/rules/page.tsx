import Link from "next/link";
import { Wordmark } from "@/components/ui/wordmark";
import { SoftLinkButton } from "@/components/ui/button";

export const metadata = {
  title: "How to play — Sequencr",
};

export default function RulesPage() {
  return (
    <div className="mx-auto flex w-full max-w-[820px] flex-1 flex-col px-6 py-8 lg:px-12">
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

      <h1
        className="font-display font-bold leading-[0.95]"
        style={{ fontSize: "clamp(44px, 6vw, 64px)", letterSpacing: "-0.03em" }}
      >
        How to play
      </h1>
      <p className="mt-4 max-w-[560px] text-[16px] leading-[1.5] text-ink-soft">
        Five chips in a row, on a 10×10 grid of playing cards. Place your
        chips on cells matching the cards in your hand. First team to two
        sequences wins.
      </p>

      <Section title="The goal">
        Be the first team to claim <strong>2 sequences</strong> on the board.
        A sequence is 5 of your team&apos;s chips in a connected line —
        horizontal, vertical, or diagonal. In 3-team games you only need{" "}
        <strong>1</strong>.
      </Section>

      <Section title="The deck">
        104 cards (two standard 52-card decks, no jokers). Every non-jack
        card appears twice on the board. Jacks are never on the board —
        they&apos;re wild plays.
      </Section>

      <Section title="Players & teams">
        2 to 12 players, in counts that divide evenly into balanced teams:{" "}
        <span className="font-mono">2, 3, 4, 6, 8, 9, 10, 12</span>.
        <ul className="mt-3 ml-5 list-disc space-y-1">
          <li>
            <strong>2 teams</strong>: seats alternate around the table
            (A, B, A, B…).
          </li>
          <li>
            <strong>3 teams</strong>: seats go every-third (A, B, C, A,
            B, C…).
          </li>
          <li>Max 3 teams.</li>
        </ul>
      </Section>

      <Section title="Hand sizes">
        <div className="mt-1 overflow-hidden rounded-2xl border border-line">
          <Row left="2 players" right="7 cards" />
          <Row left="3 – 4 players" right="6 cards" />
          <Row left="6 players" right="5 cards" />
          <Row left="8 – 9 players" right="4 cards" />
          <Row left="10 – 12 players" right="3 cards" last />
        </div>
      </Section>

      <Section title="A turn">
        <ol className="ml-5 list-decimal space-y-1">
          <li>Pick one card from your hand.</li>
          <li>Place a chip on a matching open tile on the board.</li>
          <li>Auto-draw a replacement card.</li>
        </ol>
        <p className="mt-3 text-[14px] text-ink-soft">
          Turns are timed. If you don&apos;t move before the deadline, the
          server discards your top card and the turn advances.
        </p>
      </Section>

      <Section title="Jacks">
        <ul className="ml-5 list-disc space-y-1.5">
          <li>
            <strong>Two-eyed jacks (♦J, ♣J)</strong> are wild. Place your
            chip on any open cell.
          </li>
          <li>
            <strong>One-eyed jacks (♠J, ♥J)</strong> remove one of an
            opponent&apos;s chips — but not a chip already inside a
            completed sequence.
          </li>
          <li>Jacks never appear on the board itself.</li>
        </ul>
      </Section>

      <Section title="Corners">
        The four corners are printed SEQUENCE icons — free chips for every
        team. With a corner in your line, only <strong>4</strong> of your
        own chips are needed to complete a sequence. Multiple sequences
        can share a corner.
      </Section>

      <Section title="Shared chips">
        If your team needs two sequences to win, <strong>one</strong> chip
        from your first sequence may be reused as the joining chip of your
        second. No more than one shared chip across the pair.
      </Section>

      <Section title="Dead cards">
        If both board copies of a card you&apos;re holding are already
        covered, that card is <em>dead</em>. Discard it as a free action
        and draw a replacement, then play normally. One swap per turn.
      </Section>

      <Section title="Running out of cards">
        When the draw deck empties, the discard pile reshuffles back into
        it and play continues. Games don&apos;t end in a draw on empty
        decks.
      </Section>

      <Section title="Sequences are permanent">
        Once a chip is part of a completed sequence, it can&apos;t be
        removed by a one-eyed jack. The line is locked in.
      </Section>

      <div className="mt-12 mb-8 flex flex-wrap gap-3">
        <SoftLinkButton href="/auth?mode=signup" variant="primary" size="sm">
          Create your account
        </SoftLinkButton>
        <SoftLinkButton href="/auth?mode=signin" variant="outline" size="sm">
          I already play
        </SoftLinkButton>
      </div>
    </div>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mt-8">
      <h2
        className="font-display text-[22px] font-bold text-ink"
        style={{ letterSpacing: "-0.01em" }}
      >
        {title}
      </h2>
      <div className="mt-2 text-[15px] leading-[1.55] text-ink">{children}</div>
    </section>
  );
}

function Row({
  left,
  right,
  last,
}: {
  left: string;
  right: string;
  last?: boolean;
}) {
  return (
    <div
      className={`flex items-center justify-between bg-surface px-4 py-3 ${last ? "" : "border-b border-line"}`}
    >
      <span className="text-[14px] font-semibold text-ink">{left}</span>
      <span className="font-mono text-[14px] text-ink-soft">{right}</span>
    </div>
  );
}
