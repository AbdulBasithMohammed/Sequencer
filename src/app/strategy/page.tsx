import Link from "next/link";
import { getCurrentUser } from "@/lib/auth/me";
import { Wordmark } from "@/components/ui/wordmark";
import { SoftLinkButton } from "@/components/ui/button";
import { AppShell } from "@/components/app-shell";

// Deliberately does NOT restate the rules — /rules already covers those,
// and two pages competing for the same query is worse than one. This
// targets a distinct intent ("how to win", "tips", "strategy") that the
// rules page does not serve, and every point below is grounded in the
// mechanics actually implemented in this app rather than generic advice.

export const metadata = {
  title: "Sequence Strategy — How to Win",
  description:
    "Sequence strategy: why corners are the cheapest sequences on the board, how to use the shared-chip rule, when to spend a one-eyed jack, and how to build two threats at once.",
  alternates: { canonical: "/strategy" },
};

export default async function StrategyPage() {
  const user = await getCurrentUser();
  const isAuthed = !!user;

  const content = (
    <div
      className={
        isAuthed
          ? "page-enter mx-auto flex w-full max-w-[820px] flex-col px-8 py-8"
          : "page-enter mx-auto flex w-full max-w-[820px] flex-1 flex-col px-6 py-8 lg:px-12"
      }
    >
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
        How to win at Sequence
      </h1>
      <p className="mt-4 max-w-[600px] text-[16px] leading-[1.5] text-ink-soft">
        Sequence looks like luck — you play the cards you&apos;re dealt. Most
        games are decided by three things instead: where you build, what you
        do with your jacks, and whether you notice a threat one turn before
        it lands. If you already know the{" "}
        <Link href="/rules" className="underline">
          rules
        </Link>
        , this is what separates a good player from a lucky one.
      </p>

      <Section title="Build near the corners — always">
        The four corners are free chips for everyone, which means a line
        touching a corner needs only <strong>four</strong> of your chips
        instead of five. That is a 20% discount on every sequence you
        build there, and it applies to your opponents equally — so corner
        space is contested from the first turn. If you have a reasonable
        play near a corner and an equally reasonable play in open board,
        take the corner every time.
      </Section>

      <Section title="Cross your first sequence, don't leave it">
        You need two sequences to win, and one chip from the first may be
        reused as part of the second. Players who ignore this build their
        second line somewhere fresh and pay full price for it. Build the
        second line so it <em>crosses</em> the first — an L or a T shape
        through a shared chip. You get a whole sequence for four new chips
        rather than five, and both lines defend the same region of board
        instead of splitting your attention.
      </Section>

      <Section title="Two-eyed jacks are the best card in the deck">
        A two-eyed jack (♦J, ♣J) places a chip anywhere open. That is the
        only card in the game with no positional constraint, so spending
        one on convenience is a real loss. Hold it for a cell you cannot
        otherwise reach: the fifth chip of a sequence, or the one square
        an opponent needs. Its value goes up as the board fills, because
        late in the game most cells are already covered and ordinary cards
        become unplayable.
      </Section>

      <Section title="Spend one-eyed jacks on threats, not annoyances">
        A one-eyed jack (♠J, ♥J) removes an opponent chip — but never one
        inside a <em>completed</em> sequence. That single exception drives
        the timing: once their line finishes, it is permanent and your jack
        is worthless against it. So the moment to remove is when they have
        three in a row with both ends open, or four with one end open. Not
        before, because you cannot yet tell which line matters, and not
        after, because there is no after.
      </Section>

      <Section title="Make two threats at once">
        An opponent can only block one cell per turn. If your position
        threatens to complete in two different places, they cannot stop
        both, and you win the race regardless of what they draw. This is
        why crossing lines beats parallel lines, and why building outward
        from a shared chip is stronger than extending a single row — an
        intersection naturally creates more than one completion square.
      </Section>

      <Section title="Track the second copy of every card">
        Every non-jack card appears on the board <strong>twice</strong>.
        When both copies are covered, that card in your hand is dead. Good
        players notice a card is about to die — one copy covered, the other
        contested — and play it while it still has a home. Waiting costs
        you a turn even with the free swap, because the swap gives you a
        random replacement rather than the card you needed.
      </Section>

      <Section title="Use the dead-card swap every turn you can">
        Discarding a dead card and drawing a replacement is a free action,
        once per turn, and it happens before your normal play. There is no
        reason to hold a dead card even for a moment — it cannot become
        live again. Players lose games holding a hand that is one-third
        unplayable because they never checked.
      </Section>

      <Section title="Adjust to the player count">
        Hand size shrinks as the table grows: seven cards at two players
        down to three at ten or twelve. With seven cards you can plan a
        line several turns ahead. With three you effectively cannot — the
        board changes too much between your turns. In large games, play
        for corners and immediate blocks, take the sequence that is
        available now rather than the better one two turns away, and treat
        every jack as precious.
      </Section>

      <Section title="In team games, build where your partner can reach">
        Seats alternate, so an opponent plays between every one of your
        turns — but your partner&apos;s chips count as yours for a
        sequence. Two players each building a private line are effectively
        playing two slower solo games. Extending a line your partner
        started means the pair of you place chips into the same threat
        twice as fast as any single opponent can block it.
      </Section>

      <Section title="Watch the clock">
        Turns are timed. If the deadline passes, the server discards your
        top card and moves on — you lose both the turn and the card. When
        the position is complicated, take the good move now instead of
        hunting for the perfect one. A merely decent chip on the board
        beats a brilliant plan that timed out.
      </Section>

      <div className="mt-12 mb-8 flex flex-wrap gap-3">
        <SoftLinkButton href="/rules" variant="outline" size="sm">
          Read the full rules
        </SoftLinkButton>
        {!isAuthed && (
          <SoftLinkButton href="/auth?mode=signup" variant="primary" size="sm">
            Play a game
          </SoftLinkButton>
        )}
      </div>
    </div>
  );

  return isAuthed ? <AppShell>{content}</AppShell> : content;
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
