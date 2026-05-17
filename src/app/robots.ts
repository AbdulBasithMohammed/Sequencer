import type { MetadataRoute } from "next";

const SITE_URL = "https://sequencr.app";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // The authed UI is behind login and not interesting to crawlers.
        disallow: ["/play", "/me", "/friends", "/lobby", "/game", "/auth/callback"],
      },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  };
}
