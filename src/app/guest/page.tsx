import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";
import { GuestSignInForm } from "./guest-form";

export const metadata = {
  title: "Play as guest",
};

export default async function GuestPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const params = await searchParams;
  const next = params.next ?? "/play";
  const safeNext =
    next.startsWith("/") && !next.startsWith("//") ? next : "/play";

  // Already logged in (registered or guest) → go straight to next.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) redirect(safeNext);

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

      <h1
        className="font-display font-bold leading-[0.95]"
        style={{ fontSize: "clamp(40px, 5vw, 56px)", letterSpacing: "-0.03em" }}
      >
        Pick a nickname.
      </h1>
      <p className="mt-4 max-w-[440px] text-[15px] leading-[1.55] text-ink-soft">
        Guests can host or join rooms and play games. We&apos;ll tag your
        name with{" "}
        <span className="font-mono font-semibold text-ink">(Guest)</span> so
        people know. Sessions get tidied up after a day of inactivity.
      </p>

      <div className="mt-8 rounded-3xl border border-line bg-surface p-6">
        <GuestSignInForm next={safeNext} />
      </div>

      <p className="mt-6 text-[12px] text-ink-soft">
        Want friends, invites, and a permanent profile?{" "}
        <Link
          href={`/auth?mode=signup&next=${encodeURIComponent(safeNext)}`}
          className="font-semibold text-ink underline-offset-4 hover:underline"
        >
          Create an account instead
        </Link>
        .
      </p>
    </div>
  );
}
