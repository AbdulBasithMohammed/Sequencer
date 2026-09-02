"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { Wordmark } from "@/components/ui/wordmark";
import { CoffeeButton } from "@/components/ui/coffee-button";
import { FeedbackModal } from "@/components/feedback-widget";

// `tour` marks an item as an onboarding spotlight target. The attribute is
// emitted on both the mobile and desktop copies of the nav; the tour picks
// whichever one is actually laid out at the current width.
type NavItem = {
  href: string;
  label: string;
  registeredOnly?: boolean;
  tour?: string;
};

const BASE_NAV: NavItem[] = [
  { href: "/play", label: "Play" },
  { href: "/rules", label: "How it works", tour: "nav-rules" },
  {
    href: "/friends",
    label: "Friends",
    registeredOnly: true,
    tour: "nav-friends",
  },
  { href: "/me", label: "Profile" },
];

export function AppSidebar({
  handle,
  initial,
  signOut,
  isGuest,
}: {
  handle: string;
  initial: string;
  signOut: () => Promise<void>;
  isGuest: boolean;
}) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [feedbackOpen, setFeedbackOpen] = useState(false);
  const isActive = (href: string) =>
    pathname === href || pathname.startsWith(href + "/");
  const nav = BASE_NAV.filter((item) => !(item.registeredOnly && isGuest));

  // Auto-close the mobile dropdown when a nav link is clicked — handled
  // on the event instead of a pathname effect so navigation doesn't
  // trigger an extra render pass.
  const navLinks = nav.map((item) => (
    <Link
      key={item.href}
      href={item.href}
      prefetch
      data-tour={item.tour}
      onClick={() => setOpen(false)}
      className={`flex items-center justify-between rounded-xl px-3.5 py-2.5 text-[14px] font-semibold ${
        isActive(item.href)
          ? "bg-ink text-canvas"
          : "text-ink hover:bg-surface"
      }`}
    >
      {item.label}
      {isActive(item.href) && <span aria-hidden>·</span>}
    </Link>
  ));

  const coffeeLink = <CoffeeButton className="w-full" />;

  // The modal is rendered once at the bottom of this component, outside
  // both layouts. It cannot live inside the mobile dropdown: that markup
  // unmounts when the menu closes, which is exactly what opening feedback
  // does — so the modal would be destroyed as soon as it appeared.
  const feedbackButton = (
    <button
      type="button"
      onClick={() => {
        setFeedbackOpen(true);
        setOpen(false);
      }}
      className="w-full rounded-xl border border-line bg-canvas px-3 py-2 text-[12px] font-semibold text-ink-soft transition-colors hover:bg-line/60 hover:text-ink"
    >
      Send feedback
    </button>
  );

  const userCard = (
    <div
      data-tour="user-card"
      className="rounded-2xl border border-line bg-surface p-3.5"
    >
      <Link href="/me" className="flex items-center gap-2.5 hover:opacity-80">
        <div
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full font-display font-bold text-canvas"
          style={{ background: "var(--color-blue)" }}
        >
          {initial}
        </div>
        <div className="min-w-0 flex-1">
          <div
            className="truncate text-[13px] font-bold"
            title={`@${handle}`}
          >
            @{handle}
          </div>
          <div className="text-[11px] text-ink-soft">
            {isGuest ? "Guest session" : "Signed in"}
          </div>
        </div>
      </Link>
      <form action={signOut} className="mt-2.5">
        <button
          type="submit"
          className="w-full rounded-xl border border-line bg-canvas px-3 py-2 text-[12px] font-semibold text-ink-soft transition-colors hover:bg-line/60 hover:text-ink"
        >
          {isGuest ? "Leave guest session" : "Sign out"}
        </button>
      </form>
    </div>
  );

  return (
    <>
      {/* ─── Mobile: top bar + dropdown ─────────────────────────── */}
      <div className="md:hidden">
        <header className="flex items-center justify-between border-b border-line px-5 py-4">
          <Link href="/" aria-label="Sequencr home">
            <Wordmark size={20} accent="pink" />
          </Link>
          <button
            type="button"
            onClick={() => setOpen((o) => !o)}
            aria-label={open ? "Close menu" : "Open menu"}
            aria-expanded={open}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-line bg-surface text-ink"
          >
            {open ? <CloseIcon /> : <HamburgerIcon />}
          </button>
        </header>
        {open && (
          <div className="menu-enter stagger-children flex flex-col gap-2 border-b border-line bg-canvas p-5">
            {navLinks}
            {feedbackButton}
            {coffeeLink}
            <div className="mt-2">{userCard}</div>
          </div>
        )}
      </div>

      {/* ─── Desktop: fixed sidebar ─────────────────────────────── */}
      <aside className="hidden md:flex md:flex-col md:gap-2 md:border-r md:border-line md:p-7">
        <Link href="/" className="mb-6" aria-label="Sequencr home">
          <Wordmark size={22} accent="pink" />
        </Link>
        {navLinks}
        <div className="mt-auto">
          <div className="mb-2">{feedbackButton}</div>
          {coffeeLink}
          <div className="mt-2">{userCard}</div>
        </div>
      </aside>

      {/* Outside both layouts so it survives the mobile dropdown
          unmounting when the menu closes. */}
      <FeedbackModal
        open={feedbackOpen}
        onClose={() => setFeedbackOpen(false)}
      />
    </>
  );
}

function HamburgerIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden
    >
      <path
        d="M2 4h12M2 8h12M2 12h12"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden
    >
      <path
        d="M3 3l10 10M13 3L3 13"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  );
}
