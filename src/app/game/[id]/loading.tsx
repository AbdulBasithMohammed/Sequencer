// Instant paint while the game snapshot loads — a board-shaped shimmer in
// the same footprint as the real layout, so the swap-in doesn't jump.
export default function Loading() {
  return (
    <div
      className="mx-auto flex w-full max-w-[1240px] flex-1 animate-pulse flex-col px-6 py-6 lg:px-10"
      aria-hidden
    >
      <div className="mb-6 flex items-center justify-between">
        <div className="h-6 w-32 rounded-full bg-surface" />
        <div className="h-4 w-28 rounded-full bg-surface" />
      </div>
      <div className="mb-4 flex items-center justify-between">
        <div>
          <div className="h-3 w-12 rounded-full bg-surface" />
          <div className="mt-2 h-7 w-28 rounded-xl bg-surface" />
        </div>
        <div className="h-4 w-10 rounded-full bg-surface" />
      </div>
      <div className="mx-auto mb-3 h-5 w-64 rounded-full bg-surface" />
      <div
        className="relative mx-auto rounded-2xl border border-line bg-surface"
        style={{
          aspectRatio: "70 / 50",
          width: "min(96vw, calc((100dvh - 280px) * 70 / 50), 1100px)",
        }}
      />
      <div className="mx-auto mt-4 flex gap-2">
        {Array.from({ length: 6 }).map((_, i) => (
          <div
            key={i}
            className="h-20 w-14 rounded-xl border border-line bg-surface"
          />
        ))}
      </div>
    </div>
  );
}
