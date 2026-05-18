import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";
import { SoftLinkButton } from "@/components/ui/button";

export const dynamic = "force-dynamic";

type RoomLookup = {
  status: string;
  team_layout: string;
  target_players: number;
  is_full: boolean;
  is_banned: boolean;
} | null;

async function lookupRoom(code: string): Promise<RoomLookup> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: room } = await supabase
    .from("rooms")
    .select("id, status, team_layout, target_players")
    .eq("code", code)
    .maybeSingle();
  if (!room) return null;

  const { count } = await supabase
    .from("room_players")
    .select("user_id", { head: true, count: "exact" })
    .eq("room_id", room.id);

  let isBanned = false;
  if (user) {
    const { data: ban } = await supabase
      .from("room_bans")
      .select("user_id")
      .eq("room_id", room.id)
      .eq("user_id", user.id)
      .maybeSingle();
    isBanned = !!ban;
  }

  return {
    status: room.status,
    team_layout: room.team_layout,
    target_players: room.target_players,
    is_full: (count ?? 0) >= room.target_players,
    is_banned: isBanned,
  };
}

export default async function JoinPage({
  params,
}: {
  params: Promise<{ code: string }>;
}) {
  const { code: rawCode } = await params;
  const code = String(rawCode).trim().toUpperCase();
  if (!/^[A-Z0-9]{4,8}$/.test(code)) redirect("/play?error=invalid-code");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const room = await lookupRoom(code);

  // Auto-join if already authenticated and the room is joinable.
  if (user && room && !room.is_banned && room.status === "waiting" && !room.is_full) {
    const { error } = await supabase.rpc("join_room", { p_code: code });
    if (!error) redirect(`/lobby/${code}`);
    // Fall through to render the landing card with an error if join failed.
  }

  // Already in the room (or game already started) → just go to the lobby; it
  // handles routing into the active game.
  if (user && room && room.status !== "waiting") redirect(`/lobby/${code}`);
  if (user && room && !room.is_banned) {
    // Could be a join-race; just send to lobby.
    redirect(`/lobby/${code}`);
  }

  // ── Render landing card ───────────────────────────────────────────────
  const next = `/join/${code}`;
  const notFound = !room;
  const banned = !!room?.is_banned;
  const full = !!room?.is_full;
  const inGame = room?.status && room.status !== "waiting";

  return (
    <div className="mx-auto flex w-full max-w-[560px] flex-1 flex-col px-6 py-8 lg:px-10">
      <header className="mb-12 flex items-center justify-between">
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

      {notFound ? (
        <NotFoundCard code={code} />
      ) : banned ? (
        <NoticeCard
          code={code}
          title="You can't rejoin this room."
          body="The host has banned this user. Ask the host for a fresh room code."
        />
      ) : full ? (
        <NoticeCard
          code={code}
          title="This room is full."
          body="Ask the host to make space or share a new room code."
        />
      ) : inGame ? (
        <NoticeCard
          code={code}
          title="That game is already underway."
          body="Wait for the round to finish, then ask the host to invite you again."
        />
      ) : (
        <JoinCard code={code} next={next} />
      )}
    </div>
  );
}

function JoinCard({ code, next }: { code: string; next: string }) {
  return (
    <>
      <div className="text-[12px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
        You&apos;ve been invited to
      </div>
      <h1
        className="mt-1 font-display font-bold leading-[0.95]"
        style={{ fontSize: "clamp(36px, 5vw, 56px)", letterSpacing: "-0.03em" }}
      >
        Room{" "}
        <span
          className="font-mono"
          style={{ letterSpacing: "0.08em" }}
        >
          {code}
        </span>
      </h1>
      <p className="mt-4 max-w-[440px] text-[15px] leading-[1.55] text-ink-soft">
        Sign in, create an account, or hop in as a guest. We&apos;ll drop you
        straight into the lobby once you&apos;re ready.
      </p>

      <div className="mt-8 flex flex-col gap-3 rounded-3xl border border-line bg-surface p-6">
        <SoftLinkButton
          href={`/auth?mode=signin&next=${encodeURIComponent(next)}`}
          variant="primary"
          size="sm"
          trailing={<span aria-hidden>→</span>}
        >
          Sign in
        </SoftLinkButton>
        <SoftLinkButton
          href={`/auth?mode=signup&next=${encodeURIComponent(next)}`}
          variant="ghost"
          size="sm"
        >
          Create an account
        </SoftLinkButton>
        <div className="my-1 flex items-center gap-3 text-[11px] uppercase tracking-[0.18em] text-ink-soft">
          <div className="h-px flex-1 bg-line" />
          or
          <div className="h-px flex-1 bg-line" />
        </div>
        <SoftLinkButton
          href={`/guest?next=${encodeURIComponent(next)}`}
          variant="ghost"
          size="sm"
        >
          Continue as guest
        </SoftLinkButton>
      </div>

      <p className="mt-6 text-[12px] text-ink-soft">
        New here?{" "}
        <Link
          href="/rules"
          className="font-semibold text-ink underline-offset-4 hover:underline"
        >
          How to play
        </Link>
        .
      </p>
    </>
  );
}

function NotFoundCard({ code }: { code: string }) {
  return (
    <>
      <h1
        className="font-display font-bold leading-[0.95]"
        style={{ fontSize: "clamp(36px, 5vw, 56px)", letterSpacing: "-0.03em" }}
      >
        Room{" "}
        <span className="font-mono" style={{ letterSpacing: "0.08em" }}>
          {code}
        </span>{" "}
        wasn&apos;t found.
      </h1>
      <p className="mt-4 max-w-[440px] text-[15px] leading-[1.55] text-ink-soft">
        The room may have closed, or the code might be off by a character.
        Ask the host to resend the link.
      </p>
      <div className="mt-8">
        <SoftLinkButton href="/play" variant="primary" size="sm">
          Back to play
        </SoftLinkButton>
      </div>
    </>
  );
}

function NoticeCard({
  code,
  title,
  body,
}: {
  code: string;
  title: string;
  body: string;
}) {
  return (
    <>
      <div className="text-[12px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
        Room{" "}
        <span className="font-mono" style={{ letterSpacing: "0.08em" }}>
          {code}
        </span>
      </div>
      <h1
        className="mt-1 font-display font-bold leading-[0.95]"
        style={{ fontSize: "clamp(32px, 4.5vw, 48px)", letterSpacing: "-0.03em" }}
      >
        {title}
      </h1>
      <p className="mt-4 max-w-[440px] text-[15px] leading-[1.55] text-ink-soft">
        {body}
      </p>
      <div className="mt-8">
        <SoftLinkButton href="/play" variant="primary" size="sm">
          Back to play
        </SoftLinkButton>
      </div>
    </>
  );
}
