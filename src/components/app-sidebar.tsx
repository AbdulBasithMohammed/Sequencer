"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Wordmark } from "@/components/ui/wordmark";

const NAV = [
  { href: "/play", label: "Play" },
  { href: "/rules", label: "How it works" },
  { href: "/friends", label: "Friends" },
  { href: "/me", label: "Profile" },
];

export function AppSidebar({
  handle,
  initial,
  signOut,
}: {
  handle: string;
  initial: string;
  signOut: () => Promise<void>;
}) {
  const pathname = usePathname();
  const isActive = (href: string) =>
    pathname === href || pathname.startsWith(href + "/");

  return (
    <aside className="flex flex-col gap-2 border-r border-line p-7">
      <Link href="/" className="mb-6" aria-label="Sequencr home">
        <Wordmark size={22} accent="pink" />
      </Link>

      {NAV.map((item) => (
        <Link
          key={item.href}
          href={item.href}
          prefetch
          className={`flex items-center justify-between rounded-xl px-3.5 py-2.5 text-[14px] font-semibold ${
            isActive(item.href)
              ? "bg-ink text-canvas"
              : "text-ink hover:bg-surface"
          }`}
        >
          {item.label}
          {isActive(item.href) && <span aria-hidden>·</span>}
        </Link>
      ))}

      <div className="mt-auto rounded-2xl border border-line bg-surface p-3.5">
        <Link
          href="/me"
          className="flex items-center gap-2.5 hover:opacity-80"
        >
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
            <div className="text-[11px] text-ink-soft">Signed in</div>
          </div>
        </Link>
        <form action={signOut} className="mt-2">
          <button
            type="submit"
            className="text-[11px] font-semibold text-ink-soft hover:text-ink"
          >
            Sign out
          </button>
        </form>
      </div>
    </aside>
  );
}
