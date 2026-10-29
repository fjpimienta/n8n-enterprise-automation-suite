#!/usr/bin/env bash
# rehearse_local_rollback.sh — the reverse sequence of rehearse_local.sh, to leave the LOCAL database as it was:
#   seed undos (090 first, then 086), then the rollbacks 090, 088, 087, 086, 085, 084, each checked with expect=rolled_back.
#
# Same guard as rehearse_local.sh (it refuses to run unless --i-know-this-is-local is given and REHEARSAL_DB names an existing,
# valid rehearsal database of the local container; hosting3m_db itself is refused).
# A migration that is not applied (for example because the rehearsal stopped half way) is SKIPPED, not forced: the point is to end in
# a consistent state wherever the rehearsal stopped. Nothing is dropped or deleted: the rollbacks of 084-090 keep their tables,
# columns and helpers BY DESIGN (see each NNN_rollback.sql), so "as it was" means "functionally as before", not "schema identical".
# The local copy (hosting3m_db) is NOT a clean base and the daily local refresh does not wipe everything, so a full reset means a
# FRESH database restored from a production dump (README, "Create the rehearsal database").
# Usage:   REHEARSAL_DB=hosting3m_rehearsal bash rehearse_local_rollback.sh --i-know-this-is-local
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

load_vars
run_step vars_used need STAMP COMMIT_BEFORE_PHASE5
run_step stage_files stage_files

has_meaning_column() {
  [ "$($P -X -At -c "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'repro_condition_codes' AND column_name = 'meaning'")" = 1 ]
}
has_codes_table() {
  [ "$($P -X -At -c "SELECT to_regclass('public.repro_condition_codes') IS NOT NULL")" = t ]
}

# ---------------------------------------------------------------------------------------------------------------------------
# 1. the seed undos (the 090 seed first: it returns its rows to pending; then the 086 seed deletes the rows it inserted)
# ---------------------------------------------------------------------------------------------------------------------------
undo_seed090() {
  if ! has_meaning_column; then
    echo "REHEARSAL_SKIP: migration 090 is not applied here, so there is no 090 seed to undo"
    return 0
  fi
  dry_run "${MC}/090_seed_tenant5_vet_code_meanings.sql" -v confirmed_by=x -v undo=true
  apply_run "${MC}/090_seed_tenant5_vet_code_meanings.sql" 'seed COMMITTED' -v confirmed_by=x -v undo=true
}
undo_seed086() {
  if ! has_codes_table; then
    echo "REHEARSAL_SKIP: migration 086 is not applied here, so there is no 086 seed to undo"
    return 0
  fi
  dry_run "${MC}/086_seed_tenant5_uterine_codes.sql" -v confirmed_by=x -v undo=true
  apply_run "${MC}/086_seed_tenant5_uterine_codes.sql" 'seed COMMITTED' -v confirmed_by=x -v undo=true
}
run_step seed090_undo undo_seed090
run_step seed086_undo undo_seed086

# ---------------------------------------------------------------------------------------------------------------------------
# 2. the rollbacks, in reverse order, each followed by state_check expect=rolled_back
# ---------------------------------------------------------------------------------------------------------------------------
rollback_one() {
  local mig="$1" out o2
  if out="$(state_check "$mig" applied 2>&1)"; then
    echo "${mig} is applied: rolling it back"
  elif state_check "$mig" before >/dev/null 2>&1 || state_check "$mig" rolled_back >/dev/null 2>&1; then
    echo "REHEARSAL_SKIP: ${mig} is not applied (it is in the 'before' or 'rolled_back' state)"
    return 0
  else
    printf '%s\n' "$out"
    echo "STOP: ${mig} is in no known state (not before, applied or rolled_back): look at the output above"
    return 1
  fi
  dry_run "${MC}/${mig}_rollback.sql"
  apply_run "${MC}/${mig}_rollback.sql" 'ROLLBACK COMMITTED'
  o2="$(state_check "$mig" rolled_back 2>&1)" || { printf '%s\n' "$o2"; return 1; }
  printf '%s\n' "$o2"
  printf '%s\n' "$o2" | grep -q '(rolled_back): OK'
}
for mig in 090 088 087 086 085 084; do
  run_step "${mig}_rollback" rollback_one "$mig"
done

echo
echo "Rollback finished on database ${REHEARSAL_DB}: back to the pre-rehearsal behaviour (objects are kept by design)."
echo "You can run rehearse_local.sh again on it: it accepts the 'rolled_back' state as its starting point; for a clean start create a new database from a production dump."
# the summary table is printed by the EXIT trap
