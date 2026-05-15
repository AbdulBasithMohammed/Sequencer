import Link from "next/link";
import type { ComponentProps, ReactNode } from "react";

type Variant = "primary" | "outline" | "ghost";
type Size = "lg" | "sm";

const baseClasses =
  "inline-flex cursor-pointer items-center gap-2.5 touch-manipulation select-none font-display font-semibold transition-transform duration-200 ease-out active:scale-[0.98] disabled:pointer-events-none disabled:opacity-60 [@media(hover:hover)]:hover:-translate-y-px";

const sizeClasses: Record<Size, string> = {
  lg: "text-[17px] px-[22px] py-[14px] rounded-2xl",
  sm: "text-sm px-4 py-2.5 rounded-xl",
};

const variantClasses: Record<Variant, string> = {
  primary:
    "bg-ink text-canvas shadow-[0_6px_0_var(--color-pink),0_12px_24px_-8px_rgba(255,92,138,0.5)]",
  outline:
    "bg-transparent text-ink border-[1.5px] border-ink",
  ghost: "bg-transparent text-ink hover:bg-surface",
};

type SoftButtonOwnProps = {
  variant?: Variant;
  size?: Size;
  trailing?: ReactNode;
  className?: string;
  children: ReactNode;
};

type SoftButtonProps = SoftButtonOwnProps &
  Omit<ComponentProps<"button">, keyof SoftButtonOwnProps>;

export function SoftButton({
  variant = "outline",
  size = "lg",
  trailing,
  className = "",
  children,
  ...rest
}: SoftButtonProps) {
  return (
    <button
      className={`${baseClasses} ${sizeClasses[size]} ${variantClasses[variant]} ${className}`}
      {...rest}
    >
      {children}
      {trailing}
    </button>
  );
}

type SoftLinkButtonOwnProps = {
  variant?: Variant;
  size?: Size;
  trailing?: ReactNode;
  className?: string;
  children: ReactNode;
  href: string;
};

type SoftLinkButtonProps = SoftLinkButtonOwnProps &
  Omit<ComponentProps<typeof Link>, keyof SoftLinkButtonOwnProps>;

export function SoftLinkButton({
  variant = "outline",
  size = "lg",
  trailing,
  className = "",
  children,
  href,
  ...rest
}: SoftLinkButtonProps) {
  return (
    <Link
      href={href}
      className={`${baseClasses} ${sizeClasses[size]} ${variantClasses[variant]} ${className}`}
      {...rest}
    >
      {children}
      {trailing}
    </Link>
  );
}
