import { redirect } from "next/navigation";

export default async function SignupRedirect({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const params = await searchParams;
  const next = params.next;
  const safe =
    next && next.startsWith("/") && !next.startsWith("//") ? next : null;
  redirect(
    safe ? `/auth?mode=signup&next=${encodeURIComponent(safe)}` : "/auth?mode=signup",
  );
}
