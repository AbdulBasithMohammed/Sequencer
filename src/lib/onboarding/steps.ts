// Tour content, shared by both renderers. The desktop spotlight and the
// mobile card stack read this same array — the difference is presentation
// only, so copy never drifts between the two.

// Accounts created before onboarding shipped. They get the same tour, but
// the closing card thanks them for being here first. A constant beats a
// backfill migration: nothing to run, and it stays correct forever without
// anyone maintaining a flag.
export const EXISTING_USER_CUTOFF = "2026-09-01T00:00:00Z";

export function isExistingUser(createdAt: string | null | undefined): boolean {
  if (!createdAt) return false;
  return new Date(createdAt) < new Date(EXISTING_USER_CUTOFF);
}

export type TourStep = {
  id: string;
  // Value of the data-tour attribute to spotlight. If no visible element
  // carries it, the step falls back to a centred card — which is how the
  // Friends step degrades gracefully for guests, whose nav omits it.
  anchor: string;
  title: string;
  body: string;
  // Swapped in for guests, who see a different thing at that spot.
  guestBody?: string;
};

export const TOUR_STEPS: TourStep[] = [
  {
    id: "play",
    anchor: "play-create",
    title: "Start a table",
    body: "Create a room and share the code, or drop a friend's code into Join to sit down at theirs. Empty seats can be filled with bots.",
  },
  {
    id: "rules",
    anchor: "nav-rules",
    title: "How it works",
    body: "The full ruleset lives here — jacks, dead cards, corner wilds — plus a strategy guide for when you want to start winning more.",
  },
  {
    id: "friends",
    anchor: "nav-friends",
    title: "Friends & invites",
    body: "Add people by their handle and tag. Invites arrive as live pop-ups wherever you are on the site.",
    guestBody:
      "Guest play works forever, no account needed. Signing up is what adds a friends list and invites that follow you between devices.",
  },
  {
    id: "you",
    anchor: "user-card",
    title: "That's you",
    body: "Your handle and tag — friends need both to add you. Change your display name any time from Profile.",
    guestBody:
      "Your guest session lives in this browser and clears itself after a day of being idle. Nothing to sign up for unless you want to.",
  },
];

// The closing card is not a step. It shows whether the tour was finished
// or skipped on the first slide, because the feedback pointer is the one
// thing worth guaranteeing gets seen.
export function closingCopy(existing: boolean): {
  title: string;
  body: string;
} {
  return existing
    ? {
        title: "Thanks for being here",
        body: "Sequencr is a passion project built in spare time, and you were playing it before this tour existed. That genuinely means a lot.",
      }
    : {
        title: "That's the tour",
        body: "Sequencr is free, has no ads, and gets built in whatever spare time there is. Hope you enjoy it.",
      };
}
