"use client";

import { useState } from "react";
import { SoftButton } from "@/components/ui/button";

export function ShareButton({ code }: { code: string }) {
  const [status, setStatus] = useState<"idle" | "copied">("idle");

  async function handleShare() {
    const url =
      typeof window !== "undefined"
        ? `${window.location.origin}/join/${code}`
        : `https://sequencr.app/join/${code}`;

    // Try the native share sheet (mobile) first. Pass `url` only — many
    // clients (iMessage, WhatsApp) concatenate text + url and would
    // render the link twice.
    if (typeof navigator !== "undefined" && "share" in navigator) {
      try {
        await navigator.share({
          title: `Sequence · Room ${code}`,
          url,
        });
        return;
      } catch {
        // User dismissed, or share unsupported — fall through to clipboard.
      }
    }

    try {
      await navigator.clipboard.writeText(url);
      setStatus("copied");
      window.setTimeout(() => setStatus("idle"), 1800);
    } catch {
      // Clipboard blocked (rare). No fallback — user can copy the code
      // shown next to this button.
    }
  }

  return (
    <SoftButton
      type="button"
      variant="outline"
      size="sm"
      onClick={handleShare}
      trailing={<span aria-hidden>{status === "copied" ? "✓" : "↗"}</span>}
    >
      {status === "copied" ? "Link copied" : "Share link"}
    </SoftButton>
  );
}
