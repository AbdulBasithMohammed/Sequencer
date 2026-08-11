# Sequencr

**Play the classic Sequence board game online with friends.**

A free, browser-native implementation of Jax's Sequence card-and-board game. 2–12 players, head-to-head or in teams, real-time multiplayer, no installs, no ads.

🌐 **Live:** [sequencr.app](https://sequencr.app)

---

## Highlights

- **Play in seconds** — guest mode with no signup, or a permanent account if you want friends and invites
- **Real-time multiplayer** — 2–12 players in head-to-head or team formats, with live moves over Supabase Realtime
- **Server-authoritative rules engine** — Postgres functions enforce every game rule; clients can't cheat by tampering with state
- **Full Sequence ruleset** — two-eyed jacks, one-eyed jacks, dead-card swap, corner wilds, shared-chip sequences, deck refill
- **Friends, invites & notifications** — Discord-style `Name #TAG`, friend requests with ignore lists, room invites that pop up as toasts in real-time
- **Bot opponents** — fill empty seats with Rookie / Medium / Ace bots; pure PL/pgSQL heuristics (offense, defense, jack discipline, 1-ply anticipation) running through the same server-authoritative path as humans
- **Per-turn timer** — server-enforced via `pg_cron`; AFK players auto-discard so games don't stall
- **Event-driven scheduling** — the turn/bot tick jobs are switched on when a game starts and off when the last game ends, so an idle database does zero polling
- **Mobile-first responsive layout** — hamburger nav, landscape-rotated board, tap-friendly hand
- **In-app feedback + admin dashboard** — players send feedback from the sidebar (rate-limited in the database); a gated `/admin` page shows signups, live rooms, completed-game trends and feedback
- **Storage hygiene** — finished games auto-delete after 5 minutes, stale guest accounts after 24 hours, cron run history after 24 hours, feedback after 30 days

---

## Stack

| Layer | Choice |
|---|---|
| **Framework** | [Next.js 16](https://nextjs.org) (App Router, Turbopack, React Server Components, Server Actions) |
| **Styling** | [Tailwind v4](https://tailwindcss.com) |
| **Database** | [Supabase Postgres](https://supabase.com) + Row-Level Security |
| **Auth** | Supabase Auth (email/password + anonymous sign-ins for guests) |
| **Realtime** | Supabase Realtime — Broadcast-from-Database + monotonic versions |
| **Scheduled jobs** | `pg_cron` (turn timer, stale-game cleanup, finished-game GC, guest TTL) |
| **Hosting** | [Vercel](https://vercel.com) |

---

## Architecture

The whole app is built around one principle: **the server owns the truth, the client renders it.**

### Server-authoritative state

Every game state mutation goes through a `SECURITY DEFINER` Postgres RPC — `play_move`, `play_wild`, `play_remove`, `swap_dead_card`, `start_game`, `join_room`, etc. RLS blocks direct INSERT/UPDATE/DELETE on `games`, `room_players`, `game_moves`, so a malicious client can't fake a move, a sequence, a chip removal, or a deal.

### Optimistic concurrency

Every RPC takes a `client_version` parameter. The server checks it against `games.version`, rejects on mismatch (`SQLSTATE 40001 — Stale client version`), and increments on success. Two players acting at the exact same tick won't race; one wins, the other refetches and retries.

### Realtime: broadcast-from-database

Postgres triggers call `realtime.send(channel, event, payload)` on every meaningful mutation. Clients subscribe to typed channels:

| Channel | What it covers |
|---|---|
| `lobby:<room_id>` | Lobby roster + invites for this room |
| `game:<game_id>` | Game state version changes |
| `friends:<user_id>` | Friend request / friendship / ignore changes |
| `invites:<user_id>` | Room invite arrivals |

Lobby and game payloads carry the full **public** projection of the row (board, turn, roster — never hands or the deck), and clients apply them straight to local state: a turn lands in one realtime hop with no server round trip. Snapshot RPCs (`get_game_snapshot` / `get_lobby_snapshot`) self-heal missed events on refocus, version gaps, regained network, and a turn-deadline backstop. Friends/invites channels carry only a ping; those clients refetch via RLS-filtered reads.

### Append-only move log

`game_moves` is keyed on `(game_id, version)` and never updated. Action types: `place`, `remove` (one-eyed jack), `swap_dead`, `auto_discard` (turn-timer boot), `system` (deal, stale cleanup, redetect). The log drives animations on the client and gives us a perfect replay/audit trail.

### Cron-managed lifecycle

The two gameplay ticks are **event-driven**: triggers on `games` call
`ensure_tick_jobs()`, which schedules them when a live game (or a live game
with a bot) exists and unschedules them when the last one disappears. On an
idle board they are absent from `cron.job` — that's normal, not a failure.
Before this gating, the always-on ticks were 82% of all database execution
time; real gameplay was under 2%.

| Job | Schedule | Purpose |
|---|---|---|
| `sequence-tick-turns` | every 5s *while any game is live* | Detect expired `turn_deadline`s and auto-discard for AFK players |
| `sequence-tick-bots` | every 2s *while a live game seats a bot* | Let bots whose think-delay elapsed take their turn |
| `sequence-stale-cleanup` | every 5 min | Mark games inactive 30+ minutes as `finished`; re-assert tick scheduling (watchdog) |
| `sequence-delete-finished` | every 5 min | Delete `finished` games + their move logs after 5 min |
| `sequence-delete-stale-rooms` | every 5 min | Delete rooms with no recent activity |
| `sequence-delete-stale-guests` | hourly | Delete anonymous `auth.users` inactive 24+ hours |
| `sequence-delete-orphan-bots` | hourly | Delete bot profiles with no seat |
| `sequence-prune-cron-history` | hourly | Prune `cron.job_run_details` older than 24h (it once grew to 584 MB) |
| `sequence-delete-old-feedback` | daily | Delete feedback older than 30 days |

Both tick loops isolate each game in its own subtransaction, so one broken
game is skipped with a warning instead of aborting the whole batch (which
previously could freeze every bot on the site until the game was removed).

---

## Repository layout

```
src/
  app/                       # Next.js App Router
    (app)/                   # Authed route group with shared AppShell layout
      play/                  # Lobby home for logged-in users
      me/                    # Profile page
      friends/               # Friends + requests + ignored
    admin/                   # Gated admin dashboard (stats, charts, users, feedback)
    auth/                    # Sign in / sign up / password reset
    guest/                   # Anonymous sign-in flow
    join/[code]/             # Room-code deep link
    lobby/[code]/            # Pre-game room with team picker
    game/[id]/               # The actual game board + hand
    rules/ strategy/ faq/    # Public content pages (rules, tactics, FAQ)
    sitemap.ts robots.ts     # SEO
    page.tsx                 # Marketing landing
  components/                # Shared UI (AppShell, sidebar, board, feedback modal, etc.)
  lib/
    auth/                    # Server-side auth helpers (cache()-deduped)
    supabase/                # Browser + server clients, middleware
    invites/                 # Room-invite server actions
    feedback/                # Feedback server action
    geo/                     # Country capture from the Vercel edge header
    sound/                   # Game audio
    board-layout.ts          # Canonical 10×10 board layout
    board-helpers.ts         # Dead-card / classify-card utilities
supabase/
  migrations/                # SQL migrations (the source of truth)
  config.toml                # Project config + linked ref
tests/                       # SQL test scripts (run via admin API)
scripts/analytics/           # Saved SQL snippets + run.sh (Management API)
docs/                        # Admin SQL playbook + exports
CLAUDE.md                    # AI pair-programmer notes (untracked by design)
```

---

## Local development

### Prerequisites

- **Node 20+** and **npm**
- **Supabase CLI** ([install](https://supabase.com/docs/guides/cli)) — we use v2.98+ locally; the project is linked to a hosted Supabase instance, no local Postgres needed
- A Supabase project of your own if you want to develop against a fresh database

### Setup

```bash
# 1. Install dependencies
npm install

# 2. Populate environment variables
cp .env.example .env.local
# Then fill in .env.local — see the file for the exact keys
```

`.env.local` needs:

| Variable | What |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Your project's REST URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Publishable anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Secret, server-only |
| `SUPABASE_ACCESS_TOKEN` | Personal Access Token (for CLI) |

```bash
# 3. Link the CLI to your project, then push migrations
set -a && source .env.local && set +a
supabase link --project-ref YOUR_PROJECT_REF
supabase db push

# 4. Run the dev server
npm run dev
```

Open <http://localhost:3000>. Sign up with a real email (or play as a guest), and you're in.

---

## Database & migrations

Supabase migrations live in `supabase/migrations/` and are the source of truth for schema. Never edit the dashboard SQL editor directly — those changes won't be in git.

```bash
# Create a new migration
supabase migration new my_change_name

# Edit the generated SQL file, then push
supabase db push
```

The CLI reads credentials from `.env.local`. Source the file or pipe it inline:

```bash
set -a && source .env.local && set +a && supabase db push
```

### Running game-logic tests

Each integration test is a self-contained SQL script in `tests/` that:

1. Provisions an isolated room + game inside a transaction
2. Exercises one or more RPCs with `set_config('request.jwt.claim.sub', ...)` to simulate `auth.uid()`
3. Asserts invariants (state, version, hand contents, log entries)
4. Cleans up via `DELETE FROM rooms` (cascades wipe everything)

Run one against the linked project:

```bash
set -a && source .env.local && set +a && \
  curl -s -X POST \
    "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @<(jq -Rs '{query: .}' tests/swap-dead-card.sql) | jq .
```

Available suites:

| File | Coverage |
|---|---|
| `tests/swap-dead-card.sql` | Dead-card swap: turn check, non-dead rejection, jack rejection, stale version |
| `tests/deck-refill.sql` | Deck-empty reshuffle: drain → refill → multiset of cards preserved |
| `tests/guest-mode.sql` | Anonymous sign-in trigger, friend/invite guards, 1-hour grace, 24-hour TTL |
| `tests/turn-order.sql` | Team-alternating seat order for 2- and 3-team layouts |

`$SUPABASE_PROJECT_REF` isn't in `.env.example` — it's the subdomain of
`NEXT_PUBLIC_SUPABASE_URL` (or derive it the way `scripts/analytics/run.sh` does).

Each suite returns one row per assertion with `PASS`/`OK`/`FAIL` so you can see exactly which step broke.

---

## Game rules

Full ruleset (deck composition, jacks, corners, shared chips, dead cards, win conditions, deck refill) lives at [/rules](https://sequencr.app/rules) on the deployed site, with tactics at [/strategy](https://sequencr.app/strategy).

---

## Performance & scaling notes

- **Realtime channels are per-resource** (`lobby:<id>`, `friends:<id>`, `invites:<id>`). Each client opens only the channels relevant to its active sessions; cost scales with activity, not total users.
- **Router Cache** is on with `staleTimes.dynamic = 30` — repeat navigations within 30s skip the server entirely.
- **AppShell lives in a `(app)/layout.tsx`** so the sidebar stays mounted across child route changes.
- **Request-scoped fetch dedup** via React's `cache()` keeps `getCurrentUser` + `getCurrentProfile` to a single roundtrip per page render.
- **Stored generated column** `games.deck_count` exposes deck size without leaking the actual card order.
- The current architecture comfortably handles hundreds of concurrent users on Supabase Free tier; thousands+ would want Supabase Pro or Team and a per-friend partitioned presence model if presence indicators come back.

---

## License

Source code in this repository is released under the [MIT License](./LICENSE). Use it, learn from it, fork it. **Sequence®** is a registered trademark of Jax Ltd. — not licensed here. This project is an unaffiliated fan implementation.

---

## Acknowledgments

Game design © Jax Ltd. This is a fan implementation built for friends; not affiliated with or endorsed by Jax.
