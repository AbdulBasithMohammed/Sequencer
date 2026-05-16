import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Allow the dev server to serve JS/CSS bundles to LAN devices (phones on
  // the same Wi-Fi). Without this, Next 15+ refuses cross-origin asset
  // requests and the page renders SSR but never hydrates.
  allowedDevOrigins: ["192.168.2.86"],

  // Next 15 set staleTimes.dynamic to 0 by default — every navigation to
  // a page that reads cookies/auth hits the server. Restore client-side
  // Router Cache so /play ↔ /me ↔ /friends ↔ /rules feel instant after
  // the first visit. Cache window short enough that profile edits and
  // sign-out propagate within ~half a minute.
  experimental: {
    staleTimes: {
      dynamic: 30,
      static: 180,
    },
  },
};

export default nextConfig;
