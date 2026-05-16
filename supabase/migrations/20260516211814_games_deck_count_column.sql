-- Expose deck size to clients without leaking the deck contents (which
-- would let a player predict their next draws). Stored generated
-- column derives from games.deck and is granted alongside the other
-- public game columns.

alter table public.games
  add column deck_count int generated always as (jsonb_array_length(deck)) stored;

grant select (deck_count) on public.games to authenticated;
