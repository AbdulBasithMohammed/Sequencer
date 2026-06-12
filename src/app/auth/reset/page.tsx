import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";
import { ResetForm } from "./reset-form";

export const metadata = {
  title: "Set a new password",
};

export default async function ResetPage() {
  // The user lands here AFTER /auth/callback exchanges the recovery code
  // for a session. Without that session there's no one to update — bounce
  // them back to /auth with a clear message.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/auth?error=reset_link_expired");

  return (
    <div className="page-enter mx-auto flex w-full max-w-[440px] flex-1 flex-col px-6 py-10">
      <header className="mb-12">
        <Link href="/" aria-label="Sequencr home">
          <Wordmark size={24} accent="pink" />
        </Link>
      </header>

      <h1
        className="mb-2 font-display font-bold leading-none"
        style={{ fontSize: "clamp(34px, 5vw, 44px)", letterSpacing: "-0.03em" }}
      >
        Set a new
        <br />
        <span className="italic text-pink">password.</span>
      </h1>
      <p className="mb-6 text-[15px] leading-[1.5] text-ink-soft">
        For{" "}
        <span className="font-mono text-ink">{user.email}</span>. Pick something
        strong this time.
      </p>

      <ResetForm />
    </div>
  );
}
