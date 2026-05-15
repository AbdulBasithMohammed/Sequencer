# Sequencer

Online multiplayer implementation of the Jax **Sequence** board game. Two standard decks, jacks-are-wild, five-in-a-row, teams of 2–12.

Server-authoritative game state via Postgres RPCs — clients never mutate `games`, `room_players`, or `game_moves` directly. Realtime broadcasts row changes; clients refetch and animate.

## Stack

- **Next.js 16** (App Router, Turbopack, React 19 server actions)
- **Supabase** — Postgres + Auth (email/password) + Realtime + RLS
- **Tailwind v4** for styling

## Getting started

```bash
# 1. Install deps
npm install

# 2. Copy env template and fill in your Supabase project values
cp .env.example .env.local
# edit .env.local — see comments in the file

# 3. Push migrations to your linked Supabase project (one-time)
set -a && source .env.local && set +a
supabase link --project-ref YOUR_PROJECT_REF
supabase db push

# 4. Run the dev server
npm run dev
```

Open <http://localhost:3000>.

## Architectural invariants

- All `games` / `room_players` / `game_moves` mutations go through `SECURITY DEFINER` Postgres functions; RLS blocks direct writes.
- Optimistic concurrency via `games.version` — RPCs reject stale `client_version`.
- `game_moves` is append-only; the resulting `version` is the primary key.
- Hands are private via RLS — `games.hands` is a `jsonb` map keyed by `user_id`; the SELECT projection filters to `auth.uid()`.
- Realtime broadcasts the `games` row; clients refetch on update and animate from the move log.
- Per-turn timer enforced server-side by `pg_cron` against `games.turn_deadline`.
