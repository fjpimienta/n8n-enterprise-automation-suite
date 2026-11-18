#!/usr/bin/env bash
# 108_static_check.sh: static assertions for the 108 file set. Needs no database.
#   1. No SQL file other than the tests may contain a statement that starts a line with DROP, TRUNCATE or DELETE (comment lines are ignored).
#   2. The migration must not select description, notes, metadata or any owner_* column in the views (comment lines are ignored).
#   3. The migration must contain the id_company / created_at abort guards.
# Usage: bash 108_static_check.sh [directory]   (default: the directory of this script). Exit 0 = clean, 1 = a rule was broken.
set -euo pipefail
dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
files=("$dir/108_palpation_views.sql" "$dir/108_rollback.sql" "$dir/108_state_check.sql")
status=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then echo "MISSING $f"; status=1; continue; fi
  hits=$(awk '{ line=$0; sub(/^[[:space:]]+/, "", line); if (line ~ /^--/) next; if (toupper(line) ~ /^(DROP|TRUNCATE|DELETE)([[:space:]]|$)/) print FILENAME ":" FNR ": " $0 }' "$f" || true)
  if [ -n "$hits" ]; then echo "$hits"; status=1; else echo "OK   $(basename "$f"): no DROP / TRUNCATE / DELETE statement"; fi
done

mig="$dir/108_palpation_views.sql"
if [ -f "$mig" ]; then
  # Only the CREATE VIEW section (between the first CREATE VIEW and the INSERT INTO crud_models) is inspected for forbidden columns.
  views=$(awk '/^CREATE VIEW/{on=1} /^INSERT INTO public.crud_models/{on=0} on{ line=$0; sub(/^[[:space:]]+/, "", line); if (line !~ /^--/) print }' "$mig")
  bad=$(printf '%s\n' "$views" | grep -n -i -E '(\.|[[:space:]])(description|notes|metadata|owner_[a-z_]+)([[:space:],]|$)|medicines_json[[:space:]]+AS|SELECT[[:space:]]+\*|\.\*' | grep -v -i "COMMENT ON" || true)
  if [ -n "$bad" ]; then echo "FAIL the views select a forbidden column or use *:"; echo "$bad"; status=1; else echo "OK   108_palpation_views.sql: views select no description / notes / metadata / owner_* and no *"; fi
  grep -q "l\.category," "$mig" && grep -q "l\.species," "$mig" && echo "OK   vw_palpation_herd selects category and species" || { echo "FAIL vw_palpation_herd must select l.category and l.species"; status=1; }
  grep -q '"category","species"' "$mig" && echo "OK   vw_palpation_herd model lists category and species" || { echo "FAIL the herd model must list category and species"; status=1; }
  for needle in "category and species must be in allowed_fields" "id_company is missing from allowed_fields" "created_at is missing from allowed_fields" "already exists. Not touching it"; do
    if grep -q "$needle" "$mig"; then echo "OK   guard present: $needle"; else echo "FAIL guard missing: $needle"; status=1; fi
  done
fi
exit "$status"
