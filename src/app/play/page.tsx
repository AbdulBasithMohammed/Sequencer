import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "@/lib/auth/actions";
import { Wordmark } from "@/components/ui/wordmark";
import { CreateRoomCard, JoinRoomCard } from "./play-forms";
import { KickBanToast } from "./kick-ban-toast";

export const metadata = {
  title: "Lobby — Sequencer",
};

export default async function PlayPage({
  searchParams,
}: {
  searchParams: Promise<{ kicked?: string; banned?: string }>;
}) {
  const { kicked, banned } = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", user.id)
    .maybeSingle();

  const handle = profile?.display_name ?? user.email?.split("@")[0] ?? "you";
  const greetingName = profile?.display_name ?? "there";
  const initial = (profile?.display_name ?? user.email ?? "?")[0]?.toUpperCase();

  return (
    <div className="grid flex-1 grid-cols-1 md:grid-cols-[300px_1fr]">
      {/* Sidebar */}
      <aside className="flex flex-col gap-2 border-r border-line p-7">
        <Link href="/" className="mb-6" aria-label="Sequencer home">
          <Wordmark size={22} accent="pink" />
        </Link>

        <SidebarLink href="/" label="Home" />
        <SidebarLink href="/play" label="Play" active />
        <SidebarLink href="/me" label="Profile" />

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

      {/* Main */}
      <main className="overflow-hidden px-8 py-7">
        {(banned || kicked) && (
          <KickBanToast banned={banned} kicked={kicked} />
        )}

        <div className="mb-6">
          <div className="text-[13px] font-semibold text-ink-soft">
            Welcome back, {greetingName}.
          </div>
          <h1
            className="mt-1 font-display font-bold leading-none"
            style={{ fontSize: "clamp(32px, 4vw, 44px)", letterSpacing: "-0.03em" }}
          >
            Pick a table.{" "}
            <span className="italic text-pink">Or start your own.</span>
          </h1>
        </div>

        <div className="grid gap-4 lg:grid-cols-[1.3fr_1fr]">
          <CreateRoomCard />
          <JoinRoomCard />
        </div>
      </main>
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
  active?: boolean;
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
