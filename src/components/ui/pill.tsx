import type { ReactNode } from "react";

export function SoftPill({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border border-line bg-surface px-3 py-1.5 text-[13px] font-semibold tracking-tight text-ink ${className}`}
    >
      {children}
    </span>
  );
}
