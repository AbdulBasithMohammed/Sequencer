import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Allow the dev server to serve JS/CSS bundles to LAN devices (phones on
  // the same Wi-Fi). Without this, Next 15+ refuses cross-origin asset
  // requests and the page renders SSR but never hydrates.
  allowedDevOrigins: ["192.168.2.86"],
};

export default nextConfig;
