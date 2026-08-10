import type { Metadata, Viewport } from "next";
import { Bricolage_Grotesque, Plus_Jakarta_Sans } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import { InviteNotificationsMount } from "@/components/invite-notifications-mount";
import "./globals.css";

const bricolage = Bricolage_Grotesque({
  subsets: ["latin"],
  variable: "--font-bricolage",
  display: "swap",
});

const jakarta = Plus_Jakarta_Sans({
  subsets: ["latin"],
  variable: "--font-jakarta",
  display: "swap",
});

const SITE_URL = "https://sequencr.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "Play Sequence Online — Sequencr",
    template: "%s · Sequencr",
  },
  description:
    "Play the classic Sequence board game online with friends. Five chips in a row on a 10×10 board — head-to-head, teams, or up to 12 players. Free, no ads, no install.",
  applicationName: "Sequencr",
  keywords: [
    "sequence",
    "sequence board game",
    "play sequence online",
    "sequence online",
    "sequence card game",
    "sequence multiplayer",
    "online board game",
    "five in a row",
    "play sequence with friends",
  ],
  authors: [{ name: "Sequencr" }],
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "Sequencr",
    title: "Play Sequence Online — Sequencr",
    description:
      "Play the classic Sequence board game online with friends. Free, no ads, 2–12 players, browser-native.",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: "Play Sequence Online — Sequencr",
    description:
      "Play the classic Sequence board game online with friends. Free, no ads, 2–12 players.",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  alternates: {
    canonical: "/",
  },
  category: "game",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${bricolage.variable} ${jakarta.variable} h-full`}
    >
      <body className="min-h-full flex flex-col bg-canvas text-ink">
        <InviteNotificationsMount />
        {children}
        <Analytics />
      </body>
    </html>
  );
}
