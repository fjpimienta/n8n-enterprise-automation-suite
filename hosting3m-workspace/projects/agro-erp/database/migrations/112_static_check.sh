#!/usr/bin/env bash
# 112_static_check.sh: static assertions for the 112 file set. Needs no database.
#  1. No 112 SQL file other than the tests may contain a statement that starts a line with DROP, TRUNCATE or DELETE (comment lines are ignored).
#  2. The migration and the rollback keep the signature of sp_agri_register_sale (six parameters, no overload) and never touch crud_models.
#  3. The migration text never contains the word the 104 rollback stub is recognised by (the 104 state check looks for it).
#  4. The migration carries the drift guard with the md5 of the 104 text.
# Usage: bash 112_static_check.sh [directory]   (default: the directory of this script). Exit 0 = clean, 1 = a problem was found.
set -euo pipefail
dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
files=("$dir/112_agri_sale_multi_concept.sql" "$dir/112_rollback.sql" "$dir/112_state_check.sql")
sig='sp_agri_register_sale\([[:space:]]*p_tenant_id integer,[[:space:]]*p_actor_email text,[[:space:]]*p_parsed jsonb,[[:space:]]*p_sat_status text,[[:space:]]*p_original_path text,[[:space:]]*p_source_sha256 text[[:space:]]*\)'
status=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then echo "MISSING $f"; status=1; continue; fi
  hits=$(awk '{ line=$0; sub(/^[[:space:]]+/, "", line); if (line ~ /^--/) next; if (toupper(line) ~ /^(DROP|TRUNCATE|DELETE)([[:space:]]|$)/) print FILENAME ":" FNR ": " $0 }' "$f" || true)
  if [ -n "$hits" ]; then echo "$hits"; status=1; else echo "OK   $(basename "$f"): no DROP / TRUNCATE / DELETE statement"; fi
  code=$(awk '{ line=$0; sub(/^[[:space:]]+/, "", line); if (line ~ /^--/) next; print }' "$f")
  if grep -Eiq '(insert[[:space:]]+into|update|delete[[:space:]]+from|alter[[:space:]]+table)[[:space:]]+(public\.)?crud_models' <<<"$code"; then echo "FAIL $(basename "$f"): changes crud_models"; status=1; fi
done
m="$dir/112_agri_sale_multi_concept.sql"; r="$dir/112_rollback.sql"
for f in "$m" "$r"; do
  n=$(grep -Ec 'CREATE OR REPLACE FUNCTION public\.sp_agri_register_sale\(' "$f" || true)
  if [ "$n" != "1" ]; then echo "FAIL $(basename "$f"): expected exactly one sp_agri_register_sale definition, found $n"; status=1; else echo "OK   $(basename "$f"): one sp_agri_register_sale definition"; fi
  if ! tr '\n' ' ' < "$f" | grep -Eq "COMMENT ON FUNCTION public\.sp_agri_register_sale\(integer, text, jsonb, text, text, text\)"; then echo "FAIL $(basename "$f"): the six-parameter signature is not the one commented"; status=1; fi
  if ! tr '\n' ' ' < "$f" | grep -Eq "$sig"; then echo "FAIL $(basename "$f"): the parameter list changed"; status=1; fi
done
# the word of the 104 rollback stub must not appear in the executable text of the new procedure (comments of the file are not part of the function text)
proc=$(awk '/CREATE OR REPLACE FUNCTION public\.sp_agri_register_sale\(/{p=1} p{print} /^END \$\$;/{if(p){exit}}' "$m")
if grep -q 'disabled' <<<"$proc"; then echo "FAIL $(basename "$m"): the procedure text contains the stub word"; status=1; else echo "OK   $(basename "$m"): the procedure text does not contain the stub word"; fi
if ! grep -q '425229fb6036884d5c5dcd7527d7c674' "$m"; then echo "FAIL $(basename "$m"): drift guard constant missing"; status=1; else echo "OK   $(basename "$m"): drift guard present"; fi
if grep -q '@@MD5_112@@' "$m" "$dir/112_state_check.sql"; then echo "FAIL: the md5 placeholder is still in the files"; status=1; fi
exit "$status"
