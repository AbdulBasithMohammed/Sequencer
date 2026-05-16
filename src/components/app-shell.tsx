import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "@/lib/auth/actions";
import { Wordmark } from "@/components/ui/wordmark";

type NavKey = "play" | "rules" | "friends" | "profile";

const NAV: { key: NavKey; href: string; label: string }[] = [
  { key: "play", href: "/play", label: "Play" },
  { key: "rules", href: "/rules", label: "How it works" },
  { key: "friends", href: "/friends", label: "Friends" },
  { key: "profile", href: "/me", label: "Profile" },
];

export async function AppShell({
  active,
  children,
}: {
  active: NavKey;
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return <>{children}</>;

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", user.id)
    .maybeSingle();

  const handle =
    profile?.display_name ?? user.email?.split("@")[0] ?? "you";
  const initial = (profile?.display_name ?? user.email ?? "?")[0]?.toUpperCase();

  return (
    <div className="grid flex-1 grid-cols-1 md:grid-cols-[300px_1fr]">
      <aside className="flex flex-col gap-2 border-r border-line p-7">
        <Link href="/" className="mb-6" aria-label="Sequencr home">
          <Wordmark size={22} accent="pink" />
        </Link>

        {NAV.map((item) => (
          <SidebarLink
            key={item.key}
            href={item.href}
            label={item.label}
            active={active === item.key}
          />
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
          <form action={signOutAction} className="mt-2">
            <button
              type="submit"
              className="text-[11px] font-semibold text-ink-soft hover:text-ink"
            >
              Sign out
            </button>
          </form>
        </div>
      </aside>

      <main className="overflow-hidden">{children}</main>
    </div>
  );
}

function SidebarLink({
  href,
  label,
  active,
}: {
  href: string;
  label: string;
  active: boolean;
}) {
  return (
    <Link
      href={href}
      className={`flex items-center justify-between rounded-xl px-3.5 py-2.5 text-[14px] font-semibold ${
        active ? "bg-ink text-canvas" : "text-ink hover:bg-surface"
      }`}
    >
      {label}
      {active && <span aria-hidden>·</span>}
    </Link>
  );
}
