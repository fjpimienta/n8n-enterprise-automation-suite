#!/usr/bin/env bash
# 112_static_check.sh: static assertions for the 112 file set. Needs no database.
#  1. The migration, the rollback and the state check contain no DROP, TRUNCATE or DELETE word anywhere in their non-comment text: not at the start of a
#     line only, also inside EXECUTE strings, inside DO blocks and in ALTER TABLE ... DROP COLUMN. Comments (from "--" to the end of the line, outside quotes)
#     are ignored. The tests are not scanned (they contain the statements they exercise).
#  2. The migration and the rollback keep the six-parameter signature of sp_agri_register_sale (one definition, no overload) and never change crud_models.
#  3. The text of the new procedure never contains the word the 104 rollback stub is recognised by (the 104 state check looks for it).
#  4. The migration carries the drift guard (md5 of the 104 text) and the md5 of the 112 text; no placeholder is left; the same constants are used in the
#     rollback and in the state check.
# Usage: bash 112_static_check.sh [directory]   (default: the directory of this script). Exit 0 = clean, 1 = a problem was found.
#        bash 112_static_check.sh --self-test   (checks the scanner itself on synthetic text)
set -euo pipefail

# Prints "line: text" for every line of stdin whose code (comments removed, quotes respected) holds one of the three words.
scan() {
  awk 'BEGIN { q = 0 }
       { out = ""; n = length($0)
         for (i = 1; i <= n; i++) {
           c = substr($0, i, 1)
           if (!q && substr($0, i, 2) == "--") break
           if (c == "\047") q = !q
           out = out c
         }
         print FNR ": " out }' | grep -Eiw '(DROP|TRUNCATE|DELETE)' || true
}

if [ "${1:-}" = "--self-test" ]; then
  bad=0
  expect_hit()  { if [ -z "$(printf '%s\n' "$1" | scan)" ]; then echo "SELF-TEST FAIL (no hit): $1"; bad=1; fi; }
  expect_none() { if [ -n "$(printf '%s\n' "$1" | scan)" ]; then echo "SELF-TEST FAIL (false hit): $1"; bad=1; fi; }
  expect_hit  "DROP TABLE x;"
  expect_hit  "    delete from t;"
  expect_hit  "SELECT 1; TRUNCATE t;"
  expect_hit  "ALTER TABLE t DROP COLUMN c;"
  expect_hit  "EXECUTE 'DROP TABLE ' || quote_ident(n);"
  expect_hit  "EXECUTE format('delete from %I', n);"
  expect_hit  "x := 1; -- fine
DO \$\$ BEGIN DROP INDEX i; END \$\$;"
  expect_none "-- DROP TABLE x;"
  expect_none "SELECT 1; -- delete everything"
  expect_none "SELECT 'a--b' AS t;"
  expect_none "RAISE EXCEPTION 'rows are not deletable';"
  expect_none "COMMENT ON TABLE t IS 'nothing is dropped';"
  [ "$bad" = 0 ] && echo "SELF-TEST OK: the scanner finds DROP / TRUNCATE / DELETE in code and ignores comments"
  exit "$bad"
fi

dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
m="$dir/112_agri_sale_multi_concept.sql"; r="$dir/112_rollback.sql"; sc="$dir/112_state_check.sql"
files=("$m" "$r" "$sc")
sig='sp_agri_register_sale\([[:space:]]*p_tenant_id integer,[[:space:]]*p_actor_email text,[[:space:]]*p_parsed jsonb,[[:space:]]*p_sat_status text,[[:space:]]*p_original_path text,[[:space:]]*p_source_sha256 text[[:space:]]*\)'
c104='425229fb6036884d5c5dcd7527d7c674'; c112='83a5d0a7bad97dcfe1372aa4db961d49'
status=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then echo "MISSING $f"; status=1; continue; fi
  hits=$(scan < "$f")
  if [ -n "$hits" ]; then echo "FAIL $(basename "$f"): DROP / TRUNCATE / DELETE in code:"; echo "$hits"; status=1; else echo "OK   $(basename "$f"): no DROP / TRUNCATE / DELETE in code"; fi
  code=$(awk '{ line=$0; sub(/^[[:space:]]+/, "", line); if (line ~ /^--/) next; print }' "$f")
  if grep -Eiq '(insert[[:space:]]+into|update|delete[[:space:]]+from|alter[[:space:]]+table)[[:space:]]+(public\.)?crud_models' <<<"$code"; then echo "FAIL $(basename "$f"): changes crud_models"; status=1; fi
done
for f in "$m" "$r"; do
  n=$(grep -Ec 'CREATE OR REPLACE FUNCTION public\.sp_agri_register_sale\(' "$f" || true)
  if [ "$n" != "1" ]; then echo "FAIL $(basename "$f"): expected exactly one sp_agri_register_sale definition, found $n"; status=1; else echo "OK   $(basename "$f"): one sp_agri_register_sale definition"; fi
  if ! tr '\n' ' ' < "$f" | grep -Eq "COMMENT ON FUNCTION public\.sp_agri_register_sale\(integer, text, jsonb, text, text, text\)"; then echo "FAIL $(basename "$f"): the six-parameter signature is not the one commented"; status=1; fi
  if ! tr '\n' ' ' < "$f" | grep -Eq "$sig"; then echo "FAIL $(basename "$f"): the parameter list changed"; status=1; fi
done
# the word of the 104 rollback stub must not appear in the text of the new procedure (comments of the file are not part of the function text)
proc=$(awk '/CREATE OR REPLACE FUNCTION public\.sp_agri_register_sale\(/{p=1} p{print} /^END \$\$;/{if(p){exit}}' "$m")
if grep -q 'disabled' <<<"$proc"; then echo "FAIL $(basename "$m"): the procedure text contains the stub word"; status=1; else echo "OK   $(basename "$m"): the procedure text does not contain the stub word"; fi
# constants: drift guard, post-check, rollback guard, state check
for f in "$m" "$r"; do
  if grep -q "$c104" "$f"; then echo "OK   $(basename "$f"): 104 md5 constant present"; else echo "FAIL $(basename "$f"): 104 md5 constant missing"; status=1; fi
  if grep -q "$c112" "$f"; then echo "OK   $(basename "$f"): 112 md5 constant present"; else echo "FAIL $(basename "$f"): 112 md5 constant missing"; status=1; fi
done
for c in "$c104" "$c112"; do
  if grep -q "$c" "$sc"; then echo "OK   $(basename "$sc"): md5 $(echo "$c" | cut -c1-8) present"; else echo "FAIL $(basename "$sc"): md5 $(echo "$c" | cut -c1-8) missing"; status=1; fi
done
if grep -q 'LIKE .%TNE%.' "$r"; then echo "FAIL $(basename "$r"): the rollback guard must compare md5 constants, not look for a word"; status=1; fi
if grep -q '@@' "$m" "$r" "$sc"; then echo "FAIL: a placeholder is still in the files"; status=1; fi
exit "$status"
