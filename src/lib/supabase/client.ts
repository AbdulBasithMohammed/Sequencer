import { createBrowserClient } from "@supabase/ssr";

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      realtime: {
        // Run the realtime heartbeat in a Web Worker so backgrounded tabs
        // don't get throttled by the browser's setTimeout/setInterval
        // suspension — that throttle kills the WebSocket heartbeat silently,
        // causing the channel to "disconnect" with no error and miss every
        // event until the next manual page refresh. Workers are exempt from
        // that throttling. See:
        // https://supabase.com/docs/guides/realtime/troubleshooting
        params: { worker: true },
      },
    },
  );
}
