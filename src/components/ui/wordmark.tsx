import Image from "next/image";

export function Wordmark({
  size = 26,
  color = "var(--color-ink)",
}: {
  size?: number;
  color?: string;
  /** Kept for API compatibility — no longer used now that we render the
   *  raster icon instead of the recolorable dot. */
  accent?: string;
}) {
  const iconSize = size * 3;
  return (
    <span
      className="inline-flex items-center font-display font-bold leading-none"
      style={{
        fontSize: size,
        color,
        gap: size * 0,
        letterSpacing: "-0.02em",
      }}
    >
      <Image
        src="/wordmark-icon.png"
        alt=""
        aria-hidden
        width={iconSize}
        height={iconSize}
        style={{ display: "block", flexShrink: 0 }}
      />
      <span>sequencr</span>
    </span>
  );
}
