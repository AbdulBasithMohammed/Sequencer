-- Top 20 Largest User Tables
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 8e. Database table sizes (largest first)
select
  schemaname,
  relname as table_name,
  pg_size_pretty(pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass))
    as total_size,
  n_live_tup as approx_rows
from pg_stat_user_tables
where schemaname in ('public', 'auth')
order by pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass) desc
limit 20;
