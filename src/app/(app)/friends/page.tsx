import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/me";

export const metadata = {
  title: "Friends — Sequencr",
};

export default async function FriendsPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/auth?mode=signin");

  return (
    <div className="mx-auto flex w-full max-w-[760px] flex-col px-8 py-8">
      <div className="text-[13px] font-semibold text-ink-soft">Friends</div>
      <h1
        className="mt-1 font-display font-bold leading-none"
        style={{
          fontSize: "clamp(40px, 5vw, 56px)",
          letterSpacing: "-0.03em",
        }}
      >
        Coming soon.
      </h1>
      <p className="mt-5 max-w-[520px] text-[15px] leading-[1.55] text-ink-soft">
        Friend lists, invites, and rematch shortcuts are on the way. For now,
        drop the 6-character room code into any chat and your people can
        join in seconds.
      </p>

      <div className="mt-10 rounded-3xl border border-line bg-surface px-6 py-6">
        <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-ink-soft">
          On the roadmap
        </div>
        <ul className="mt-3 ml-5 list-disc space-y-1.5 text-[14px] leading-[1.5] text-ink">
          <li>Add friends by display name</li>
          <li>See who&apos;s online and in a room</li>
          <li>One-click rematch invites</li>
          <li>Win-rate head-to-head against each friend</li>
        </ul>
      </div>
    </div>
  );
}
