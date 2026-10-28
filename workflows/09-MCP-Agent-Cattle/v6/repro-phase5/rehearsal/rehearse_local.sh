#!/usr/bin/env bash
# rehearse_local.sh — LOCAL rehearsal of docs/REPRO_PRODUCTION_RUNBOOK.md, steps 2 and 3, plus the fixtures dry run and the list_lots diff.
#
# It writes to the database named by REHEARSAL_DB in the LOCAL container (applies migrations 084-090 and the two seeds). It NEVER touches
# the VPS, production or n8n. Use a FRESH database restored from a production dump (README, "Create the rehearsal database"):
# the local hosting3m_db is not a clean base and is refused.
# Usage:   REHEARSAL_DB=hosting3m_rehearsal bash rehearse_local.sh --i-know-this-is-local
# Env:     REHEARSAL_DB       the database to write to (^hosting3m_[a-z0-9_]+$, must exist; hosting3m_db and system databases are refused)
#          CONFIRMED_BY_086   confirmed_by of the 086 seed (default: veterinarios del rancho (interpretacion verbal, nombre pendiente))
#          OWNER_EMAIL        a member of company 5 (default: discovered read-only from the local database; it is never printed)
#          STAMP              suffix of the folder created inside the container (default: date and time)
# Undo:    REHEARSAL_DB=hosting3m_rehearsal bash rehearse_local_rollback.sh --i-know-this-is-local
# Nothing here has been run by its author: the first real run is yours (UNTESTED).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rehearsal_lib.sh"
guard_local "$@"      # MANDATORY FIRST ACTION: nothing below runs unless every layer of the guard passed

for a in "$@"; do
  case "$a" in
    --i-know-this-is-local) ;;
    *) refuse "unknown argument: $a" ;;
  esac
done

trap print_summary EXIT
mkdir -p "$REH_OUT"
echo "outputs go to ${REH_OUT}/NN_step.txt"

# ---------------------------------------------------------------------------------------------------------------------------
# 0. Variables block of the runbook (verbatim), local values, and the need() guard exercised
# ---------------------------------------------------------------------------------------------------------------------------
load_vars
run_step need_selftest bash -c '
set -u
. "$0"
t() { ( OWNER_TEST="$1"; need OWNER_TEST ) >/dev/null 2>&1; }
if t ""; then echo "need() accepted an empty value"; exit 1; fi
lt="$(printf '\074')"      # the angle bracket is built at run time: no literal placeholder text in this file
if t "${lt}FILL: x"; then echo "need() accepted a value that starts with an angle bracket"; exit 1; fi
if t "FILL later"; then echo "need() accepted a value with FILL"; exit 1; fi
if ( unset OWNER_TEST; need OWNER_TEST ) >/dev/null 2>&1; then echo "need() accepted an unset variable"; exit 1; fi
if ! t "a real value"; then echo "need() rejected a real value"; exit 1; fi
echo "need() rejects empty, unset, angle-bracket and FILL values and accepts a real one"
' "$REH_OUT/repro_vars.sh"
run_step vars_used need OWNER_EMAIL CONFIRMED_BY_086 STAMP COMMIT_BEFORE_PHASE5

# ---------------------------------------------------------------------------------------------------------------------------
# (a) md5 of the 084-090 files against the runbook table
# ---------------------------------------------------------------------------------------------------------------------------
run_step md5_table check_md5_table
run_step stage_files stage_files

# ---------------------------------------------------------------------------------------------------------------------------
# (b) step 2: for each migration  state before -> dry run -> apply -> state after -> fingerprints
# ---------------------------------------------------------------------------------------------------------------------------
for i in "${!MIGS[@]}"; do
  mig="${MIGS[$i]}"
  file="${MIG_FILES[$i]}"
  run_step "${mig}_state_before" state_before_any "$mig"
  before_file="$LAST_FILE"
  run_step "${mig}_dry_run" dry_run "${MC}/${file}"
  run_step "${mig}_apply" apply_run "${MC}/${file}" 'COMMITTED'
  run_step "${mig}_state_after" state_after_ok "$mig"
  after_file="$LAST_FILE"
  run_step "${mig}_fingerprints" fingerprints_equal "$before_file" "$after_file"
done

# ---------------------------------------------------------------------------------------------------------------------------
# (c) step 3: the 086 seed and the 090 seed back to back (dry run first, then apply)
# ---------------------------------------------------------------------------------------------------------------------------
run_step seed086_dry_run dry_run "${MC}/086_seed_tenant5_uterine_codes.sql" -v confirmed_by="$CONFIRMED_BY_086"
run_step seed086_apply apply_run "${MC}/086_seed_tenant5_uterine_codes.sql" 'seed COMMITTED' -v confirmed_by="$CONFIRMED_BY_086"
seed90_dry() {
  local out diffs
  out="$($P -v confirmed_by="$SEED90_BY" -f "${MC}/090_seed_tenant5_vet_code_meanings.sql" 2>&1)" || { printf '%s\n' "$out"; return 1; }
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -q 'DRY RUN' || return 1
  # the line after the "differences" header and its rule is the count of other-company rows changed by the file
  diffs="$(printf '%s\n' "$out" | awk '/^ *differences *$/ {getline; getline; gsub(/ /, ""); print; exit}')"
  echo "other-company differences reported by the seed: '${diffs}'"
  [ "$diffs" = 0 ]
}
run_step seed090_dry_run seed90_dry
run_step seed090_apply apply_run "${MC}/090_seed_tenant5_vet_code_meanings.sql" 'seed COMMITTED' -v confirmed_by="$SEED90_BY"

# ---------------------------------------------------------------------------------------------------------------------------
# (d) the step 3 verify SELECTs (the runbook's, then an assertion of the expected values)
# ---------------------------------------------------------------------------------------------------------------------------
verify_nine_rows() {
  $P -X -f - <<'SQL'
SELECT code, repro_condition, meaning, source, confirmed_by
  FROM public.repro_condition_codes
 WHERE id_company = 5
   AND code IN ('UNE', 'UTCL1', 'UTCL2', 'UTCL3', 'NR', 'RP', 'NO APTO', 'UTC2', 'MATRIZ OCUPADA')
 ORDER BY code;
SQL
  local ok
  ok="$($P -X -At -v cb="$CONFIRMED_BY_086" -f - <<'SQL'
WITH exp (code, cond, meaning, src, cby) AS (VALUES
  ('MATRIZ OCUPADA', NULL, NULL, 'pending veterinarian confirmation', NULL),
  ('NO APTO', NULL, 'UNFIT', 'SEED_090_FOREMAN_CONFIRMED', 'capataz (sin confirmacion veterinaria)'),
  ('NR', NULL, 'NOT_EXAMINED', 'SEED_090_FOREMAN_CONFIRMED', 'capataz (sin confirmacion veterinaria)'),
  ('RP', NULL, 'POSTPARTUM', 'SEED_090_FOREMAN_CONFIRMED', 'capataz (sin confirmacion veterinaria)'),
  ('UNE', 'ESTATICA', NULL, 'SEED_086_VET_CONFIRMED', lower(btrim(:'cb'))),
  ('UTC2', NULL, NULL, 'pending veterinarian confirmation', NULL),
  ('UTCL1', 'CICLANDO', NULL, 'SEED_086_VET_CONFIRMED', lower(btrim(:'cb'))),
  ('UTCL2', 'CICLANDO', NULL, 'SEED_086_VET_CONFIRMED', lower(btrim(:'cb'))),
  ('UTCL3', 'CICLANDO', NULL, 'SEED_086_VET_CONFIRMED', lower(btrim(:'cb'))))
SELECT count(*) FROM exp e JOIN public.repro_condition_codes c ON c.id_company = 5 AND c.code = e.code
 WHERE c.repro_condition IS NOT DISTINCT FROM e.cond AND c.meaning IS NOT DISTINCT FROM e.meaning
   AND c.source = e.src AND c.confirmed_by IS NOT DISTINCT FROM e.cby;
SQL
)"
  echo "rows matching the expected values of the runbook table: ${ok} of 9"
  [ "$ok" = 9 ]
}
run_step verify_nine_rows verify_nine_rows
verify_tool() {
  local ok
  ok="$($P -X -At -v owner="$OWNER_EMAIL" -f - <<'SQL'
SELECT jsonb_array_length(sp_repro_list_unmapped_uterine_codes('5', :'owner')->'meanings_configured') = 3
   AND EXISTS (SELECT 1 FROM jsonb_array_elements(sp_repro_list_unmapped_uterine_codes('5', :'owner')->'unmapped') e
                WHERE e->>'code' = 'UTC2' AND e->>'known_pending' = 'true');
SQL
)"
  echo "meanings_configured has 3 rows and UTC2 is listed as known_pending: ${ok}"
  [ "$ok" = t ]
}
run_step verify_tool verify_tool

# ---------------------------------------------------------------------------------------------------------------------------
# (e) the QA fixtures: DRY RUN ONLY (this script never applies them)
# ---------------------------------------------------------------------------------------------------------------------------
run_step qa_fixtures_dry_run dry_run "${CDIR}/qa_fixtures.sql" -v run=2

# ---------------------------------------------------------------------------------------------------------------------------
# (f) list_lots_diff.py against tenant 5 (read-only): old = the MCP export of the commit before phase 5, new = the repo file
# ---------------------------------------------------------------------------------------------------------------------------
list_lots_diff() {
  local v="workflows/09-MCP-Agent-Cattle/v6" res a b c d e
  git -C "$REPO" show "${COMMIT_BEFORE_PHASE5}:${v}/v6_MCP_Server_Cattle.json" > "$REH_OUT/repo_before_mcp.json"
  python3 "$REPO/${v}/repro-phase5/list_lots_diff.py" --tenant 5 --email "$OWNER_EMAIL" --old-file "$REH_OUT/repo_before_mcp.json" > "$REH_OUT/list_lots_diff.sql"
  res="$($P -X -At -F '|' -f - < "$REH_OUT/list_lots_diff.sql")"
  printf '%s\n' "$res"
  a="$(printf '%s\n' "$res" | awk -F'|' '$1 == "rows_old" {print $2}')"
  b="$(printf '%s\n' "$res" | awk -F'|' '$1 == "rows_new" {print $2}')"
  c="$(printf '%s\n' "$res" | awk -F'|' '$1 ~ /^only_in_old/ {print $2}')"
  d="$(printf '%s\n' "$res" | awk -F'|' '$1 ~ /^only_in_new/ {print $2}')"
  e="$(printf '%s\n' "$res" | awk -F'|' '$1 ~ /NULL production_unit_id/ {print $2}')"
  echo "REPORT rows_old=${a} rows_new=${b} only_in_old=${c} only_in_new=${d} null_production_unit_id=${e}"
  [ -n "$a" ] && [ "$a" = "$b" ] && [ "$c" = 0 ] && [ "$d" = 0 ] && [ "$e" = 0 ]
}
run_step list_lots_diff list_lots_diff

echo
echo "All steps passed. Database ${REHEARSAL_DB} now has migrations 084-090 and both seeds applied."
echo "To undo:  REHEARSAL_DB=${REHEARSAL_DB} bash rehearse_local_rollback.sh --i-know-this-is-local"
# (g) the summary table is printed by the EXIT trap
