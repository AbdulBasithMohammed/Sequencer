import { redirect } from "next/navigation";
import { getCurrentProfile, getCurrentUser } from "@/lib/auth/me";
import { CreateRoomCard, JoinRoomCard } from "./play-forms";
import { KickBanToast } from "./kick-ban-toast";
import { NoticeToast } from "./notice-toast";

export const metadata = {
  title: "Lobby",
};

export default async function PlayPage({
  searchParams,
}: {
  searchParams: Promise<{ kicked?: string; banned?: string; notice?: string }>;
}) {
  const { kicked, banned, notice } = await searchParams;
  const user = await getCurrentUser();
  if (!user) redirect("/auth?mode=signin");

  const profile = await getCurrentProfile();
  const greetingName = profile?.display_name ?? "there";

  return (
    <div className="stagger-children px-8 py-7">
      {(banned || kicked) && (
        <KickBanToast banned={banned} kicked={kicked} />
      )}
      {notice && !banned && !kicked && <NoticeToast notice={notice} />}

      <div className="mb-6">
        <div className="text-[13px] font-semibold text-ink-soft">
          Welcome back, {greetingName}.
        </div>
        <h1
          className="mt-1 font-display font-bold leading-none"
          style={{
            fontSize: "clamp(32px, 4vw, 44px)",
            letterSpacing: "-0.03em",
          }}
        >
          Pick a table.{" "}
          <span className="italic text-pink">Or start your own.</span>
        </h1>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1.3fr_1fr]">
        <CreateRoomCard />
        <JoinRoomCard />
      </div>
    </div>
  );
}
