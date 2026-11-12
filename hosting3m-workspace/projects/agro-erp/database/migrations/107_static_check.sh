#!/usr/bin/env bash
# 107_static_check.sh: static assertion for the 107 file set. No 107 SQL file other than the tests may contain a statement that starts a line with
# DROP, TRUNCATE or DELETE (comment lines are ignored). Needs no database.
# Usage: bash 107_static_check.sh [directory]   (default: the directory of this script). Exit 0 = clean, 1 = a statement was found.
set -euo pipefail
dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
files=("$dir/107_agri_sale_gateway_sp.sql" "$dir/107_rollback.sql" "$dir/107_state_check.sql")
status=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then echo "MISSING $f"; status=1; continue; fi
  hits=$(awk '{ line=$0; sub(/^[[:space:]]+/, "", line); if (line ~ /^--/) next; if (toupper(line) ~ /^(DROP|TRUNCATE|DELETE)([[:space:]]|$)/) print FILENAME ":" FNR ": " $0 }' "$f" || true)
  if [ -n "$hits" ]; then echo "$hits"; status=1; else echo "OK   $(basename "$f"): no DROP / TRUNCATE / DELETE statement"; fi
done
exit "$status"
