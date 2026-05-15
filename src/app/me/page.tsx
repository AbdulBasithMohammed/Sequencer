import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "@/lib/auth/actions";
import { Wordmark } from "@/components/ui/wordmark";
import { SoftButton } from "@/components/ui/button";

export const metadata = {
  title: "Profile — Sequencer",
};

export default async function MePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name, created_at")
    .eq("id", user.id)
    .maybeSingle();

  const verifiedAt = user.email_confirmed_at;

  return (
    <div className="mx-auto flex w-full max-w-[820px] flex-1 flex-col px-6 py-8 lg:px-12">
      <header className="mb-10 flex items-center justify-between">
        <Link href="/" aria-label="Sequencer home">
          <Wordmark size={22} accent="pink" />
        </Link>
        <Link
          href="/play"
          className="text-[13px] font-semibold text-ink-soft hover:text-ink"
        >
          ← Back to lobby
        </Link>
      </header>

      <h1
        className="font-display font-bold leading-none"
        style={{ fontSize: "clamp(40px, 5vw, 56px)", letterSpacing: "-0.03em" }}
      >
        {profile?.display_name ?? user.email}
      </h1>

      <dl className="mt-8 overflow-hidden rounded-3xl border border-line bg-surface">
        <Row label="Display name" value={profile?.display_name ?? "—"} />
        <Row label="Email" value={user.email ?? "—"} mono />
        <Row
          label="Verified"
          value={
            verifiedAt
              ? new Date(verifiedAt).toLocaleString()
              : "Not yet verified"
          }
        />
        <Row
          label="Account created"
          value={
            profile?.created_at
              ? new Date(profile.created_at).toLocaleString()
              : "—"
          }
        />
      </dl>

      <form action={signOutAction} className="mt-8">
        <SoftButton variant="outline" type="submit">
          Sign out
        </SoftButton>
      </form>
    </div>
  );
}

function Row({
  label,
  value,
  mono,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-line px-5 py-4 last:border-b-0">
      <dt className="text-[13px] font-semibold text-ink-soft">{label}</dt>
      <dd
        className={`text-[14px] text-ink ${mono ? "font-mono" : "font-medium"}`}
      >
        {value}
      </dd>
    </div>
  );
}
