import type { Metadata, Viewport } from "next";
import { Bricolage_Grotesque, Plus_Jakarta_Sans } from "next/font/google";
import { InviteNotificationsMount } from "@/components/invite-notifications-mount";
import { PresenceProvider } from "@/components/presence";
import { getCurrentUser } from "@/lib/auth/me";
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

export const metadata: Metadata = {
  title: "Sequencr",
  description: "Five in a row, forever. The bubbly take on the classic board game.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const user = await getCurrentUser();

  return (
    <html
      lang="en"
      className={`${bricolage.variable} ${jakarta.variable} h-full`}
    >
      <body className="min-h-full flex flex-col bg-canvas text-ink">
        <PresenceProvider userId={user?.id ?? null}>
          <InviteNotificationsMount />
          {children}
        </PresenceProvider>
      </body>
    </html>
  );
}
