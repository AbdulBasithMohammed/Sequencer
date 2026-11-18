import { permanentRedirect } from "next/navigation";

// 308 rather than the default 307 — see the note in ../login/page.tsx.

export default async function SignupRedirect({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const params = await searchParams;
  const next = params.next;
  const safe =
    next && next.startsWith("/") && !next.startsWith("//") ? next : null;
  permanentRedirect(
    safe ? `/auth?mode=signup&next=${encodeURIComponent(safe)}` : "/auth?mode=signup",
  );
}
