"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { CoffeeButton } from "@/components/ui/coffee-button";
import { FeedbackModal } from "@/components/feedback-widget";
import { markOnboarding, seenLocally } from "@/lib/onboarding/mark";
import { TOUR_STEPS, closingCopy } from "@/lib/onboarding/steps";

// Phases, not booleans, because the ordering matters:
//
//   steps -> closing -> feedback -> done
//
// "closing" is reachable from any step via Skip. That is the whole point
// of the design: the feedback pointer and the thank-you sit outside the
// step sequence, so dismissing the walkthrough does not dismiss them.
//
// "feedback" keeps this component mounted with the overlay hidden. The
// feedback modal cannot be a child of anything that unmounts when it
// opens — that is exactly the bug that made the mobile feedback button do
// nothing (see feedback-widget.tsx). Unmounting the tour to show the
// modal would reintroduce it.
type Phase = "steps" | "closing" | "feedback" | "done";

const CARD_W = 320;
const GAP = 14;
const PAD = 10;

type Rect = { top: number; left: number; width: number; height: number };

// Several elements can carry the same data-tour value — the sidebar is
// rendered twice, once for the mobile dropdown and once for desktop, and
// only one of the two is laid out at any given width. Pick whichever is
// actually on screen; if neither is, the step falls back to a centred
// card, which is how the Friends step degrades for guests (whose nav
// omits it entirely).
function findAnchor(name: string): HTMLElement | null {
  const els = Array.from(
    document.querySelectorAll<HTMLElement>(`[data-tour="${name}"]`),
  );
  return (
    els.find((el) => {
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    }) ?? null
  );
}

export function OnboardingTour({
  userId,
  isGuest,
  existingUser,
  alreadySeen,
}: {
  userId: string;
  isGuest: boolean;
  existingUser: boolean;
  alreadySeen: boolean;
}) {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const replay = searchParams.get("tour") === "1";

  const [armed, setArmed] = useState(false);
  const [phase, setPhase] = useState<Phase>("steps");
  const [idx, setIdx] = useState(0);
  const [rect, setRect] = useState<Rect | null>(null);
  const [desktop, setDesktop] = useState(false);

  const cardRef = useRef<HTMLDivElement | null>(null);
  const [cardH, setCardH] = useState(190);

  const step = TOUR_STEPS[idx];
  const last = idx === TOUR_STEPS.length - 1;

  // Only ever on /play. Never over a live game or a lobby, where an
  // overlay would sit on top of a turn timer that is still counting down.
  //
  // AppShell stays mounted across this route group, so the check has to
  // hold for the whole life of the tour, not just at launch — otherwise
  // navigating away mid-tour carries the overlay onto the next page.
  const onPlay = pathname === "/play";
  const eligible =
    onPlay && (replay || (!alreadySeen && !seenLocally(userId, "tour")));

  // Matches Tailwind's md breakpoint, which is where the sidebar stops
  // being a dropdown and becomes a real column worth pointing at.
  useEffect(() => {
    const mq = window.matchMedia("(min-width: 768px)");
    const sync = () => setDesktop(mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);

  // Wait a beat before arming: the page-enter stagger is still animating
  // on first paint, and an overlay that lands mid-animation reads as a
  // glitch. The dialog check keeps the tour off the top of a kick/ban
  // toast or a room invite that got there first.
  useEffect(() => {
    if (!eligible) return;
    const t = window.setTimeout(() => {
      if (document.querySelector('[role="dialog"][aria-modal="true"]')) return;
      setArmed(true);
    }, 650);
    return () => window.clearTimeout(t);
  }, [eligible]);

  const showing = armed && onPlay && (phase === "steps" || phase === "closing");
  const anchorName = step?.anchor;

  // Track the anchor through scroll, resize and layout shift. The hole is
  // painted from a live rect rather than a snapshot, so it cannot drift
  // off the thing it is meant to be pointing at.
  //
  // Every write goes through requestAnimationFrame or a listener rather
  // than the effect body: measuring is a read of an external system, and
  // the first read has to wait for the smooth scroll below to start
  // anyway.
  const spotlightable = showing && phase === "steps" && desktop && !!anchorName;

  useLayoutEffect(() => {
    const el = spotlightable ? findAnchor(anchorName) : null;

    const measure = () => {
      if (!el) {
        setRect(null);
        return;
      }
      const r = el.getBoundingClientRect();
      setRect(
        r.width === 0 && r.height === 0
          ? null
          : { top: r.top, left: r.left, width: r.width, height: r.height },
      );
    };

    const raf = requestAnimationFrame(measure);
    if (!el) return () => cancelAnimationFrame(raf);

    el.scrollIntoView({ block: "nearest", behavior: "smooth" });
    window.addEventListener("scroll", measure, true);
    window.addEventListener("resize", measure);
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    ro.observe(document.body);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("scroll", measure, true);
      window.removeEventListener("resize", measure);
      ro.disconnect();
    };
  }, [spotlightable, anchorName]);

  // The tooltip is placed from its own measured height, so a long step
  // never gets clamped off the bottom of the viewport.
  const anchored = rect !== null;

  useLayoutEffect(() => {
    const el = cardRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setCardH(el.offsetHeight));
    ro.observe(el);
    return () => ro.disconnect();
  }, [showing, phase, idx, desktop, anchored]);

  const finish = useCallback(
    (skipped: boolean) => {
      void markOnboarding(userId, skipped ? "tour_skipped" : "tour_done");
      setPhase("closing");
    },
    [userId],
  );

  // Esc from a step goes to the closing card, not out of the tour. From
  // the closing card it dismisses for real — one extra keypress at worst,
  // which honours "the feedback and coffee don't get skipped" without
  // building a modal nobody can escape.
  useEffect(() => {
    if (!showing) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      if (phase === "steps") finish(true);
      else setPhase("done");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [showing, phase, finish]);

  // Still rendered while the feedback modal is open — see the Phase note.
  if (phase === "feedback") {
    return <FeedbackModal open onClose={() => setPhase("done")} />;
  }
  if (!showing || !step) return null;

  const body = isGuest && step.guestBody ? step.guestBody : step.body;

  /* ---------------------------------------------- closing card --- */

  if (phase === "closing") {
    const copy = closingCopy(existingUser);
    return (
      <div
        className="fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-ink/40 p-4 backdrop-blur-[2px] sm:items-center"
        role="dialog"
        aria-modal="true"
        aria-label="Welcome to Sequencr"
        onClick={() => setPhase("done")}
      >
        <div
          className="win-enter w-full max-w-[400px] rounded-3xl border border-line bg-surface p-6 shadow-xl"
          onClick={(e) => e.stopPropagation()}
        >
          <h2 className="font-display text-[20px] font-bold leading-tight">
            {copy.title}
          </h2>
          <p className="mt-2 text-[13px] leading-[1.55] text-ink-soft">
            {copy.body}
          </p>

          <div className="mt-4 rounded-2xl border border-line bg-canvas p-3.5">
            <p className="text-[12.5px] leading-[1.5] text-ink-soft">
              Found a bug, or did something feel off? The feedback box in the
              sidebar comes straight to me, and I read all of it.
            </p>
            <button
              type="button"
              onClick={() => setPhase("feedback")}
              className="mt-2.5 w-full rounded-xl bg-ink px-4 py-2 text-[13px] font-semibold text-canvas transition-opacity hover:opacity-90"
            >
              Send feedback
            </button>
          </div>

          <div className="mt-4 flex flex-col items-center gap-2">
            <p className="text-center text-[11.5px] leading-[1.5] text-ink-soft">
              The game stays free either way. There is a tip jar if you ever
              feel like it — entirely optional.
            </p>
            <CoffeeButton />
          </div>

          <button
            type="button"
            onClick={() => setPhase("done")}
            className="mt-4 w-full rounded-xl border border-line bg-canvas px-4 py-2 text-[13px] font-semibold text-ink-soft transition-colors hover:bg-line/60 hover:text-ink"
          >
            Let me play
          </button>
        </div>
      </div>
    );
  }

  /* ---------------------------------------------- shared card ---- */

  const cardInner = (
    <>
      <div className="text-[10.5px] font-semibold uppercase tracking-[0.18em] text-ink-soft">
        {idx + 1} of {TOUR_STEPS.length}
      </div>
      <h2 className="mt-1.5 font-display text-[17px] font-bold leading-tight">
        {step.title}
      </h2>
      <p className="mt-1.5 text-[13px] leading-[1.5] text-ink-soft">{body}</p>

      <div className="mt-4 flex items-center justify-between gap-3">
        <div className="flex items-center gap-1.5" aria-hidden>
          {TOUR_STEPS.map((s, n) => (
            <span
              key={s.id}
              className="block h-1.5 rounded-full transition-all"
              style={{
                width: n === idx ? 16 : 6,
                background: n === idx ? "var(--color-ink)" : "var(--color-line)",
              }}
            />
          ))}
        </div>
        <div className="flex items-center gap-2">
          {idx > 0 && (
            <button
              type="button"
              onClick={() => setIdx((n) => n - 1)}
              className="rounded-xl px-3 py-1.5 text-[12.5px] font-semibold text-ink-soft hover:text-ink"
            >
              Back
            </button>
          )}
          <button
            type="button"
            onClick={() => (last ? finish(false) : setIdx((n) => n + 1))}
            className="rounded-xl bg-ink px-4 py-1.5 text-[12.5px] font-semibold text-canvas transition-opacity hover:opacity-90"
          >
            {last ? "Finish" : "Next"}
          </button>
        </div>
      </div>

      {/* On every step, never buried behind a first slide. */}
      <button
        type="button"
        onClick={() => finish(true)}
        className="mt-2.5 w-full text-center text-[11.5px] font-semibold text-ink-soft underline-offset-4 hover:text-ink hover:underline"
      >
        Skip the tour
      </button>
    </>
  );

  /* ------------------------ mobile, or anchor missing: card ------ */

  if (!desktop || !rect) {
    return (
      <div
        className="fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-ink/40 p-4 backdrop-blur-[2px] sm:items-center"
        role="dialog"
        aria-modal="true"
        aria-label={step.title}
        onClick={() => finish(true)}
      >
        <div
          ref={cardRef}
          className="menu-enter w-full max-w-[380px] rounded-3xl border border-line bg-surface p-5 shadow-xl"
          onClick={(e) => e.stopPropagation()}
        >
          {cardInner}
        </div>
      </div>
    );
  }

  /* ------------------------ desktop: spotlight + tooltip --------- */

  // One element with an enormous spread shadow, rather than four dimming
  // rectangles or an SVG mask. The hole is genuinely transparent, it
  // animates as a single box between steps, and there is no seam where
  // the pieces would otherwise meet.
  const hole = {
    top: rect.top - PAD,
    left: rect.left - PAD,
    width: rect.width + PAD * 2,
    height: rect.height + PAD * 2,
  };

  const vw = window.innerWidth;
  const vh = window.innerHeight;

  // Four candidate sides, first that genuinely fits wins. Order matters:
  // sidebar items are tall and narrow, so beside beats below (a tooltip
  // under one would cover the next item down), while the play grid is wide
  // and short, where only below or above can fit at all.
  //
  // If none fit — a short viewport against a tall anchor — the card pins to
  // the bottom of the screen instead of being clamped into overlapping the
  // thing it is pointing at. The spotlight still marks the target, so the
  // pairing stays readable even when the card is not beside it.
  const fits = {
    right: vw - (hole.left + hole.width) - GAP * 2 >= CARD_W,
    left: hole.left - GAP * 2 >= CARD_W,
    below: hole.top + hole.height + GAP + cardH + GAP <= vh,
    above: hole.top - GAP - cardH - GAP >= 0,
  };

  let cardTop: number;
  let cardLeft: number;
  if (fits.right) {
    cardLeft = hole.left + hole.width + GAP;
    cardTop = hole.top;
  } else if (fits.left) {
    cardLeft = hole.left - CARD_W - GAP;
    cardTop = hole.top;
  } else if (fits.below) {
    cardLeft = hole.left;
    cardTop = hole.top + hole.height + GAP;
  } else if (fits.above) {
    cardLeft = hole.left;
    cardTop = hole.top - cardH - GAP;
  } else {
    cardLeft = (vw - CARD_W) / 2;
    cardTop = vh - cardH - GAP * 2;
  }
  cardLeft = Math.max(GAP, Math.min(cardLeft, vw - CARD_W - GAP));
  cardTop = Math.max(GAP, Math.min(cardTop, vh - cardH - GAP));

  return (
    <div
      className="fixed inset-0 z-50"
      role="dialog"
      aria-modal="true"
      aria-label={step.title}
    >
      {/* Backdrop click skips — same as Esc, lands on the closing card. */}
      <div className="absolute inset-0" onClick={() => finish(true)} />
      <div
        aria-hidden
        className="pointer-events-none absolute rounded-2xl transition-all duration-300 ease-out"
        style={{
          top: hole.top,
          left: hole.left,
          width: hole.width,
          height: hole.height,
          boxShadow:
            "0 0 0 9999px rgba(23, 23, 23, 0.45), 0 0 0 2px var(--color-pink)",
        }}
      />
      <div
        ref={cardRef}
        className="absolute rounded-3xl border border-line bg-surface p-5 shadow-xl transition-all duration-300 ease-out"
        style={{ top: cardTop, left: cardLeft, width: CARD_W }}
      >
        {cardInner}
      </div>
    </div>
  );
}
