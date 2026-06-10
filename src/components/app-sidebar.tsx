"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { Wordmark } from "@/components/ui/wordmark";

const BASE_NAV = [
  { href: "/play", label: "Play" },
  { href: "/rules", label: "How it works" },
  { href: "/friends", label: "Friends", registeredOnly: true },
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
  const isActive = (href: string) =>
    pathname === href || pathname.startsWith(href + "/");
  const nav = BASE_NAV.filter(
    (item) => !("registeredOnly" in item && item.registeredOnly && isGuest),
  );

  // Auto-close the mobile dropdown when a nav link is clicked — handled
  // on the event instead of a pathname effect so navigation doesn't
  // trigger an extra render pass.
  const navLinks = nav.map((item) => (
    <Link
      key={item.href}
      href={item.href}
      prefetch
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

  const coffeeLink = (
    <a
      href="https://buymeacoffee.com/abmd"
      target="_blank"
      rel="noopener noreferrer"
      className="flex items-center gap-1.5 rounded-xl px-3.5 py-2 text-[12px] font-semibold text-ink-soft hover:bg-surface hover:text-ink"
    >
      <span aria-hidden>☕</span> Buy me a coffee
    </a>
  );

  const userCard = (
    <div className="rounded-2xl border border-line bg-surface p-3.5">
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
      <form action={signOut} className="mt-2">
        <button
          type="submit"
          className="text-[11px] font-semibold text-ink-soft hover:text-ink"
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
          <div className="flex flex-col gap-2 border-b border-line bg-canvas p-5">
            {navLinks}
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
          {coffeeLink}
          <div className="mt-2">{userCard}</div>
        </div>
      </aside>
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
