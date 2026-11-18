import { permanentRedirect } from "next/navigation";

// Permanent (308), not the default 307. These two paths are fixed aliases
// people type or that other sites link to — a temporary redirect tells
// Google to keep indexing /login itself, which is why it shows up under
// "Page with redirect". 308 consolidates the signal onto /auth instead.
export default function LoginRedirect() {
  permanentRedirect("/auth?mode=signin");
}
