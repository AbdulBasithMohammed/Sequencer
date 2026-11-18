// Presentational building blocks shared by the admin sections. No hooks
// and no "use client", so server sections and client islands can both
// import them.

import Link from "next/link";

export function SectionHeader({
  title,
  blurb,
  children,
}: {
  title: string;
  blurb: string;
  children?: React.ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1
          className="font-display font-bold leading-none"
          style={{ fontSize: "clamp(26px, 3.4vw, 34px)", letterSpacing: "-0.03em" }}
        >
          {title}
        </h1>
        <p className="mt-2 text-sm text-ink-soft">{blurb}</p>
      </div>
      {children}
    </div>
  );
}

export function Kpi({
  label,
  value,
  sub,
  href,
  accent,
}: {
  label: string;
  value: React.ReactNode;
  sub?: React.ReactNode;
  href?: string;
  accent?: boolean;
}) {
  const body = (
    <>
      <div className="flex items-center gap-1.5 text-xs text-ink-soft">
        {accent ? (
          <span className="inline-block h-2 w-2 rounded-full bg-pink" />
        ) : null}
        {label}
      </div>
      <div
        className="mt-1 font-display font-bold leading-none tabular-nums"
        style={{ fontSize: "30px", letterSpacing: "-0.03em" }}
      >
        {value}
      </div>
      {sub ? <div className="mt-1.5 text-xs text-ink-soft">{sub}</div> : null}
    </>
  );
  const cls =
    "block rounded-2xl border border-line bg-surface px-4 py-3.5 min-w-0";
  return href ? (
    <Link href={href} className={`${cls} transition-colors hover:border-ink-soft`}>
      {body}
    </Link>
  ) : (
    <div className={cls}>{body}</div>
  );
}

export function Card({
  title,
  action,
  children,
  className = "",
}: {
  title: string;
  action?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`min-w-0 rounded-3xl border border-line bg-surface px-4 py-4 sm:px-5 ${className}`}
    >
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold">{title}</h2>
        {action}
      </div>
      <div className="mt-3">{children}</div>
    </section>
  );
}

export function MiniRow({
  label,
  value,
  of,
}: {
  label: React.ReactNode;
  value: number;
  of: number;
}) {
  const pct = of > 0 ? Math.round((value / of) * 100) : 0;
  return (
    <div className="flex items-center gap-3 py-1.5">
      <span className="w-32 shrink-0 truncate text-sm sm:w-44">{label}</span>
      <span className="h-1.5 min-w-0 flex-1 overflow-hidden rounded-full bg-line">
        <span
          className="block h-full rounded-full bg-ink"
          style={{ width: `${pct}%` }}
        />
      </span>
      <span className="w-16 shrink-0 text-right text-sm tabular-nums">
        <span className="font-semibold">{value}</span>
        <span className="ml-1 text-xs text-ink-soft">{pct}%</span>
      </span>
    </div>
  );
}

export function Pill({
  children,
  tone = "plain",
}: {
  children: React.ReactNode;
  tone?: "plain" | "dark" | "mint";
}) {
  const tones = {
    plain: "border-line text-ink-soft",
    dark: "border-ink bg-ink text-canvas",
    mint: "border-mint bg-mint/30 text-ink",
  };
  return (
    <span
      className={`inline-block whitespace-nowrap rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide ${tones[tone]}`}
    >
      {children}
    </span>
  );
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <p className="py-3 text-sm text-ink-soft">{children}</p>;
}
