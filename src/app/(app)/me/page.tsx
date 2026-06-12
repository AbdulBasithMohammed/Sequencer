import { signOutAction } from "@/lib/auth/actions";
import { getCurrentProfile, getCurrentUser } from "@/lib/auth/me";
import { SoftButton } from "@/components/ui/button";

export const metadata = {
  title: "Profile",
};

export default async function MePage() {
  const user = await getCurrentUser();
  if (!user) return null;
  const profile = await getCurrentProfile();

  const displayName = profile?.display_name ?? user.email ?? "";
  const tag = profile?.tag ?? "";

  return (
    <div className="stagger-children mx-auto flex w-full max-w-[760px] flex-col px-8 py-8">
      <h1
        className="font-display font-bold leading-none"
        style={{
          fontSize: "clamp(40px, 5vw, 56px)",
          letterSpacing: "-0.03em",
        }}
      >
        {displayName}
        {tag ? (
          <span className="ml-2 font-mono text-ink-soft" style={{ letterSpacing: "0" }}>
            #{tag}
          </span>
        ) : null}
      </h1>

      <dl className="mt-8 overflow-hidden rounded-3xl border border-line bg-surface">
        <Row label="Email" value={user.email ?? "—"} mono />
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
