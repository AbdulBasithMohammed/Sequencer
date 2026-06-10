#!/usr/bin/env bash
# Run a saved analytics query against the linked Supabase project
# (whichever project NEXT_PUBLIC_SUPABASE_URL in .env.local points at).
#
#   scripts/analytics/run.sh friend-count-per-profile
#   scripts/analytics/run.sh scripts/analytics/stale-rooms-diagnostics.sql
#
# Goes through the Management API with the PAT, so it works for
# cross-schema queries (auth.users, cron.job) that the anon key can't see.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; source .env.local; set +a

REF=$(printf '%s' "$NEXT_PUBLIC_SUPABASE_URL" | sed -E 's#https://([^.]+).*#\1#')
FILE="${1:?usage: run.sh <snippet-name|path.sql>}"
[ -f "$FILE" ] || FILE="scripts/analytics/$FILE.sql"
[ -f "$FILE" ] || { echo "no such snippet: $1" >&2; ls scripts/analytics/*.sql | sed 's#.*/##; s#\.sql$##' >&2; exit 1; }

python3 - "$FILE" <<'PY' | curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" --data @- | python3 -m json.tool
import json, sys
print(json.dumps({"query": open(sys.argv[1]).read()}))
PY
