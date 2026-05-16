-- Fix: detect_new_sequences was over-counting.
--
-- The original 5.D function evaluated every 5-window passing through the
-- placed chip independently. Two consecutive windows in the same
-- direction (e.g., offsets -4..0 and -3..1) always overlap by 4 chips, so
-- treating them as separate new sequences violates the official "use at
-- most one space from your first sequence as part of your second" rule.
-- A 6-in-a-row line was getting recorded as TWO sequences this way (the
-- 6-chip / 2-sequence false win you saw).
--
-- Correct behaviour: per direction, pick AT MOST one new sequence per
-- placement. Tie-break: prefer the window with the fewest existing-
-- sequence chips (so a fresh 5 beats a 1-chip extension). Across the 4
-- directions, a placement can still legitimately close up to 4 sequences
-- (one per direction) — those only share the placed chip itself, which
-- is within the rule.

create or replace function public.detect_new_sequences(
  p_board jsonb,
  p_team int,
  p_row int,
  p_col int
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_dr int[] := array[0, 1, 1, 1];
  v_dc int[] := array[1, 0, 1, -1];
  v_dir int;
  v_offset int;
  v_i int;
  v_cr int;
  v_cc int;
  v_cell jsonb;
  v_cell_card text;
  v_cell_team int;
  v_cell_seq_count int;
  v_window_valid boolean;
  v_chips_in_existing int;
  v_seq_cells jsonb;
  v_new_sequences jsonb := '[]'::jsonb;
  v_best_cells jsonb;
  v_best_existing int;
begin
  for v_dir in 1..4 loop
    v_best_cells := null;
    v_best_existing := 999;

    for v_offset in -4..0 loop
      v_window_valid := true;
      v_chips_in_existing := 0;
      v_seq_cells := '[]'::jsonb;

      for v_i in 0..4 loop
        v_cr := p_row + (v_offset + v_i) * v_dr[v_dir];
        v_cc := p_col + (v_offset + v_i) * v_dc[v_dir];

        if v_cr < 0 or v_cr > 9 or v_cc < 0 or v_cc > 9 then
          v_window_valid := false;
          exit;
        end if;

        v_cell := p_board -> v_cr -> v_cc;
        v_cell_card := public.card_at(v_cr, v_cc);

        if v_cell_card is null then
          -- corner: free for any team, no chip-level limits
          null;
        else
          v_cell_team := (v_cell ->> 'team')::int;
          if v_cell_team is null or v_cell_team <> p_team then
            v_window_valid := false;
            exit;
          end if;
          v_cell_seq_count := jsonb_array_length(
            coalesce(v_cell -> 'sequence_ids', '[]'::jsonb)
          );
          if v_cell_seq_count >= 2 then
            v_window_valid := false;
            exit;
          end if;
          if v_cell_seq_count > 0 then
            v_chips_in_existing := v_chips_in_existing + 1;
          end if;
        end if;

        v_seq_cells := v_seq_cells || jsonb_build_object('row', v_cr, 'col', v_cc);
      end loop;

      -- Per-direction selection: keep the window with the fewest chips
      -- already in an existing sequence (cap at 1; the shared-chip rule).
      if v_window_valid
         and v_chips_in_existing <= 1
         and v_chips_in_existing < v_best_existing then
        v_best_cells := v_seq_cells;
        v_best_existing := v_chips_in_existing;
      end if;
    end loop;

    if v_best_cells is not null then
      v_new_sequences := v_new_sequences || jsonb_build_object(
        'cells', v_best_cells
      );
    end if;
  end loop;

  return v_new_sequences;
end;
$$;
