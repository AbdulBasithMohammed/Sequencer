import Link from "next/link";
import { Wordmark } from "@/components/ui/wordmark";
import { ForgotForm } from "./forgot-form";

export const metadata = {
  title: "Reset your password",
};

export default function ForgotPage() {
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
        Forgot
        <br />
        <span className="italic text-pink">password?</span>
      </h1>
      <p className="mb-6 text-[15px] leading-[1.5] text-ink-soft">
        Enter your email and we&apos;ll send you a link to set a new one.
      </p>

      <ForgotForm />
    </div>
  );
}
