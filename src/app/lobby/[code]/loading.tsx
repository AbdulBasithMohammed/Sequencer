// Instant paint while the lobby snapshot loads.
export default function Loading() {
  return (
    <div
      className="mx-auto flex w-full max-w-[820px] flex-1 animate-pulse flex-col px-6 py-7 lg:px-10"
      aria-hidden
    >
      <div className="mb-10 flex items-center justify-between">
        <div className="h-6 w-32 rounded-full bg-surface" />
        <div className="h-4 w-24 rounded-full bg-surface" />
      </div>
      <div className="flex flex-col items-center">
        <div className="h-6 w-56 rounded-full bg-surface" />
        <div className="mt-6 h-3 w-24 rounded-full bg-surface" />
        <div className="mt-3 h-14 w-64 rounded-2xl bg-surface" />
      </div>
      <div className="mt-10 grid gap-4 sm:grid-cols-2">
        <div className="h-56 rounded-3xl border border-line bg-surface" />
        <div className="h-56 rounded-3xl border border-line bg-surface" />
      </div>
    </div>
  );
}
