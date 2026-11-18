// Shared by the server page and the client tables. No "use client" and no
// server-only imports, so both sides can pull from it.
//
// /admin renders on the server and Vercel runs UTC, so an unqualified
// toLocaleString() formats in UTC rather than the viewer's zone. Every
// timestamp is pinned to Toronto explicitly. America/Toronto handles
// EST/EDT, so there is no DST maintenance.
export const TZ = "America/Toronto";

export function fmtDateTime(iso: string | null) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-CA", {
    timeZone: TZ,
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
}

export function fmtTime(iso: string) {
  return new Date(iso).toLocaleTimeString("en-CA", {
    timeZone: TZ,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
}

export function duration(secs: number | null) {
  if (!secs || secs < 0) return "—";
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return m ? `${m}m ${s}s` : `${s}s`;
}

// Two-letter code -> regional indicator pair, which renders as a flag.
export function flag(cc: string | null) {
  if (!cc || !/^[A-Z]{2}$/.test(cc)) return "";
  return String.fromCodePoint(
    ...[...cc].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65),
  );
}

const regionNames = new Intl.DisplayNames(["en"], { type: "region" });

export function countryLabel(cc: string | null) {
  if (!cc || !/^[A-Z]{2}$/.test(cc)) return "Unknown";
  try {
    return regionNames.of(cc) ?? cc;
  } catch {
    return cc;
  }
}

export function fmtDate(iso: string | null) {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-CA", {
    timeZone: TZ,
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

// "3h ago". `now` is passed in (from the server render) rather than read
// here, so a client component hydrates with the same text the server sent.
export function fmtAgo(iso: string | null, now: number) {
  if (!iso) return "never";
  const secs = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000));
  if (secs < 60) return "just now";
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  return fmtDate(iso);
}
