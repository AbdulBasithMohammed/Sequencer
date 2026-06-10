// Instant paint while /play, /me, /friends fetch their data. Renders
// inside the AppShell layout, so only the content pane shimmers.
export default function Loading() {
  return (
    <div className="animate-pulse px-8 py-7" aria-hidden>
      <div className="h-4 w-44 rounded-full bg-surface" />
      <div className="mt-3 h-10 w-[min(520px,80%)] rounded-2xl bg-surface" />
      <div className="mt-6 grid gap-4 lg:grid-cols-[1.3fr_1fr]">
        <div className="h-64 rounded-3xl border border-line bg-surface" />
        <div className="h-64 rounded-3xl border border-line bg-surface" />
      </div>
    </div>
  );
}
