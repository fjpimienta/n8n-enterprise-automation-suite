#!/usr/bin/env bash
# rehearsal_lib.sh — shared guard and helpers of the LOCAL rehearsal of docs/REPRO_PRODUCTION_RUNBOOK.md
# (sourced by rehearse_local.sh and rehearse_local_rollback.sh). It only DEFINES functions and constants: sourcing it runs nothing
# else. Never run it on its own.
#
# Why the guard has several layers: the runbook's P string (container n8n-enterprise-db, database hosting3m_db) is IDENTICAL on the
# VPS and on a developer machine, so checking the container and database names alone cannot tell the two apart. The guard therefore
# also requires: an explicit flag, a non-root user (the runbook runs as root on the VPS), a LOCAL docker socket, and a database that
# exists only in the LOCAL cluster (n8n_db_prod_clone: the local n8n points at it; see agro-erp/CLAUDE.md, "El n8n de LOCAL no se
# restaura desde producción"). If the marker is not there the script aborts instead of guessing.
#
# The database the run WRITES to is REHEARSAL_DB (default hosting3m_db). The default is REFUSED on purpose: the local hosting3m_db is
# NOT a clean base (objects of 084-090 survive the daily local refresh, so the state checks find no known state). Create a fresh
# database restored from a production dump and point REHEARSAL_DB at it (README, "Create the rehearsal database").

REH_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$REH_HERE" rev-parse --show-toplevel)"
RUNBOOK="$REPO/hosting3m-workspace/projects/agro-erp/docs/REPRO_PRODUCTION_RUNBOOK.md"
MIG_DIR="$REPO/hosting3m-workspace/projects/agro-erp/database/migrations"
V6="$REPO/workflows/09-MCP-Agent-Cattle/v6"
REH_OUT="${REHEARSAL_OUT:-/tmp/rehearsal}"
LOCAL_CONTAINER="n8n-enterprise-db"
REHEARSAL_DB="${REHEARSAL_DB:-hosting3m_db}"
# the P string of the runbook (production): used only to detect that the runbook's variables block changed
PRODUCTION_P='docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -v ON_ERROR_STOP=1'
# the P of the rehearsal: built by guard_local AFTER REHEARSAL_DB was validated (empty until then, so nothing can use it by mistake)
LOCAL_P=""
MARKER_DB="${REHEARSAL_MARKER_DB:-n8n_db_prod_clone}"

# the migrations of step 2, in order, with the file each one applies (the same table as the runbook)
MIGS=(084 085 086 087 088 090)
MIG_FILES=(084_repro_births_age.sql 085_repro_empadre.sql 086_repro_palpation.sql 087_repro_births.sql 088_repro_services.sql 090_repro_vet_code_semantics.sql)
SEED90_BY='capataz (sin confirmacion veterinaria)'          # exactly the value the runbook uses for the 090 seed

refuse() {
  echo "REFUSING TO RUN: $*" >&2
  exit 2
}

# ---------------------------------------------------------------------------------------------------------------------------
# The name of the database the run writes to. Pure (no docker): returns 0 if it is acceptable, 1 with a message otherwise.
#   * must match ^hosting3m_[a-z0-9_]+$   (so no space, no semicolon, no quote, nothing that could be read as SQL or as a shell word)
#   * postgres, template0, template1 and hosting3m_db are rejected by name: hosting3m_db is the local copy, which is NOT a clean base
# ---------------------------------------------------------------------------------------------------------------------------
validate_rehearsal_db() {
  local n="$1"
  case "$n" in
    postgres|template0|template1)
      echo "REHEARSAL_DB='${n}' is a system database" >&2
      return 1 ;;
    hosting3m_db)
      echo "REHEARSAL_DB='hosting3m_db' is the local copy: it is NOT a clean base (objects of 084-090 survive the daily local refresh and the state checks find no known state). Use a fresh database restored from a production dump: see README, 'Create the rehearsal database', and set REHEARSAL_DB (for example hosting3m_rehearsal)" >&2
      return 1 ;;
  esac
  if [[ ! "$n" =~ ^hosting3m_[a-z0-9_]+$ ]]; then
    echo "REHEARSAL_DB='${n}' does not match ^hosting3m_[a-z0-9_]+\$" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------------
# MANDATORY FIRST ACTION of both scripts. Nothing may run unless every layer passes. Prints the database host and the database it
# will write to.
# ---------------------------------------------------------------------------------------------------------------------------
guard_local() {
  local flag=0 a endpoint dbname dockerhost exists marker_count why
  for a in "$@"; do
    if [ "$a" = "--i-know-this-is-local" ]; then flag=1; fi
  done
  echo "== LOCAL GUARD: this script writes to the database it points at (migrations, seeds); it must be a database of the LOCAL container =="
  if [ "$flag" != 1 ]; then refuse "pass --i-know-this-is-local (and only on the developer machine)"; fi
  if [ "$(id -u)" = 0 ]; then refuse "running as root: the production runbook runs as root on the VPS; this rehearsal is for the developer machine"; fi
  if ! why="$(validate_rehearsal_db "$REHEARSAL_DB" 2>&1)"; then refuse "$why"; fi
  case "${DOCKER_HOST-}" in
    ''|unix://*) ;;
    *) refuse "DOCKER_HOST points at a remote docker daemon: ${DOCKER_HOST}" ;;
  esac
  endpoint="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  case "$endpoint" in
    unix://*) ;;
    *) refuse "the docker context endpoint is not a local socket: '${endpoint}'" ;;
  esac
  if ! docker inspect -f '{{.State.Running}}' "$LOCAL_CONTAINER" 2>/dev/null | grep -qx true; then
    refuse "container ${LOCAL_CONTAINER} is not running on this docker daemon"
  fi
  dockerhost="$(docker info --format '{{.Name}}' 2>/dev/null || echo unknown)"
  # the name was validated above, so it is safe inside this literal; the check runs on the 'postgres' database of the cluster
  exists="$(docker exec -i "$LOCAL_CONTAINER" psql -U n8n_user -d postgres -X -Atc "SELECT count(*) FROM pg_database WHERE datname = '${REHEARSAL_DB}'" 2>/dev/null || true)"
  if [ "$exists" != 1 ]; then
    refuse "database '${REHEARSAL_DB}' does not exist in container ${LOCAL_CONTAINER}: create it first (README, 'Create the rehearsal database')"
  fi
  dbname="$(docker exec -i "$LOCAL_CONTAINER" psql -U n8n_user -d "$REHEARSAL_DB" -X -Atc 'SELECT current_database()' 2>/dev/null || true)"
  echo "database host : container '${LOCAL_CONTAINER}' on docker daemon '${dockerhost}' (${endpoint}); this machine is '$(hostname)'"
  echo "database name : '${dbname}'"
  if [ "$dbname" != "$REHEARSAL_DB" ]; then refuse "connected to '${dbname}' instead of '${REHEARSAL_DB}'"; fi
  marker_count="$(docker exec -i "$LOCAL_CONTAINER" psql -U n8n_user -d postgres -X -Atc "SELECT count(*) FROM pg_database WHERE datname = '${MARKER_DB}'" 2>/dev/null || true)"
  if [ "$marker_count" != 1 ]; then
    refuse "the local-only marker database '${MARKER_DB}' does not exist in this cluster, so this may NOT be the local container (set REHEARSAL_MARKER_DB to another database that exists only locally if you know better)"
  fi
  LOCAL_P="docker exec -i ${LOCAL_CONTAINER} psql -U n8n_user -d ${REHEARSAL_DB} -v ON_ERROR_STOP=1"
  echo "THIS RUN WRITES TO DATABASE '${REHEARSAL_DB}' in container '${LOCAL_CONTAINER}'"
  echo "guard passed: flag given, non-root, local docker socket, container ${LOCAL_CONTAINER}, database ${REHEARSAL_DB} (valid name, exists, not hosting3m_db), local-only marker '${MARKER_DB}' present"
}

# ---------------------------------------------------------------------------------------------------------------------------
# The runbook's variables block, extracted VERBATIM from the runbook and sourced, so the block (and need()) is what gets exercised.
# ---------------------------------------------------------------------------------------------------------------------------
extract_vars_block() {
  mkdir -p "$REH_OUT"
  awk '/^# repro_vars.sh$/ {f = 1; next} f && /^```/ {exit} f' "$RUNBOOK" > "$REH_OUT/repro_vars.sh"
  grep -q '^need()' "$REH_OUT/repro_vars.sh" || { echo "the variables block of the runbook has no need() function" >&2; return 1; }
  grep -q '^COMMIT_BEFORE_PHASE5=14dd60c' "$REH_OUT/repro_vars.sh" || { echo "the variables block of the runbook changed (COMMIT_BEFORE_PHASE5)" >&2; return 1; }
  bash -n "$REH_OUT/repro_vars.sh"
}

# Sourcing the block overwrites the variables with '': keep what the caller passed in the environment first.
load_vars() {
  local env_owner="${OWNER_EMAIL-}" env_cb="${CONFIRMED_BY_086-}" env_stamp="${STAMP-}"
  extract_vars_block
  # shellcheck disable=SC1091
  . "$REH_OUT/repro_vars.sh"
  if [ -z "$LOCAL_P" ]; then refuse "guard_local has not run (LOCAL_P is empty)"; fi
  if [ "$P" != "$PRODUCTION_P" ]; then echo "note: the runbook's P is no longer the production string expected by the rehearsal; check the variables block" >&2; fi
  P="$LOCAL_P"          # the runbook's P names hosting3m_db; the rehearsal writes to REHEARSAL_DB instead
  CONFIRMED_BY_086="${env_cb:-veterinarios del rancho (interpretacion verbal, nombre pendiente)}"
  STAMP="${env_stamp:-$(date +%F_%H%M%S)}"
  if [ -n "$env_owner" ]; then
    OWNER_EMAIL="$env_owner"
  else
    # a real active member of company 5 (read-only); the e-mail is never printed
    OWNER_EMAIL="$($P -X -At -f - <<'SQL'
SELECT u.email FROM users u JOIN user_companies uc ON uc.email = u.email
 WHERE uc.id_company = 5 AND uc.is_active AND u.is_active
 ORDER BY (uc.role = 'ADMIN') DESC, u.email LIMIT 1;
SQL
)"
  fi
  # the folder of this run inside the container (plain assignments here: a step body runs in a subshell and could not set them)
  CDIR="/tmp/reh_${STAMP}"
  MC="${CDIR}/migrations"
  export P CONFIRMED_BY_086 STAMP OWNER_EMAIL COMMIT_BEFORE_PHASE5 CDIR MC
}

# ---------------------------------------------------------------------------------------------------------------------------
# Step runner: the body runs in a subshell WITH set -e (so a failing command inside a function really stops it), its output goes to
# NN_label.txt, and the first failure stops the whole script (the EXIT trap prints the summary).
# ---------------------------------------------------------------------------------------------------------------------------
STEP_N=0
STEP_LABELS=()
STEP_RESULTS=()
STEP_FILES=()
LAST_FILE=""

run_step() {
  local label="$1" f rc res
  shift
  STEP_N=$((STEP_N + 1))
  mkdir -p "$REH_OUT"
  f="$(printf '%s/%02d_%s.txt' "$REH_OUT" "$STEP_N" "$label")"
  LAST_FILE="$f"
  echo "-> $(basename "$f")"
  set +e
  ( set -e; "$@" ) > "$f" 2>&1
  rc=$?
  set -e
  if [ "$rc" = 0 ]; then
    res=OK
    if grep -q '^REHEARSAL_SKIP' "$f"; then res=SKIP; fi
  else
    res=FAIL
  fi
  STEP_LABELS+=("$label")
  STEP_RESULTS+=("$res")
  STEP_FILES+=("$f")
  if [ "$res" = FAIL ]; then
    echo "FAIL: $label (exit $rc); last lines of $f:"
    tail -20 "$f"
    exit 1
  fi
}

print_summary() {
  local i fails=0
  echo
  echo "== SUMMARY (database ${REHEARSAL_DB}; output files in ${REH_OUT}) =="
  printf '%-3s %-42s %-6s\n' NN STEP RESULT
  for i in "${!STEP_LABELS[@]}"; do
    printf '%02d  %-42s %-6s\n' "$((i + 1))" "${STEP_LABELS[$i]}" "${STEP_RESULTS[$i]}"
    if [ "${STEP_RESULTS[$i]}" = FAIL ]; then fails=$((fails + 1)); fi
  done
  echo "${#STEP_LABELS[@]} steps run, ${fails} failed (a failed step stops the rehearsal: later steps did not run)"
}

# ---------------------------------------------------------------------------------------------------------------------------
# Helpers used by the steps. They are small on purpose; each ends with an explicit check so that set -e is never the only guard.
# ---------------------------------------------------------------------------------------------------------------------------
stage_files() {
  # copies the migrations folder and the fixture file into a NEW folder of the container; nothing is ever deleted
  docker exec "$LOCAL_CONTAINER" mkdir -p "$CDIR"
  docker cp "$MIG_DIR" "${LOCAL_CONTAINER}:${CDIR}/migrations"
  docker cp "$V6/repro-phase5/qa_fixtures.sql" "${LOCAL_CONTAINER}:${CDIR}/qa_fixtures.sql"
  echo "staged in the container: ${CDIR}"
}

check_md5_table() {
  # the 084-090 rows of the runbook's md5 table against the files of the repo
  local n=0 bad=0 label want got
  while IFS='|' read -r _ label want _; do
    label="$(echo "$label" | tr -d ' `')"
    want="$(echo "$want" | tr -d ' `')"
    if [ ! -f "$MIG_DIR/$label" ]; then echo "MISSING $label"; bad=$((bad + 1)); continue; fi
    got="$(md5sum "$MIG_DIR/$label" | cut -d' ' -f1)"
    n=$((n + 1))
    if [ "$got" = "$want" ]; then echo "OK   $label"; else echo "DIFF $label  table=$want  file=$got"; bad=$((bad + 1)); fi
  done < <(grep -E '^\| `(08[4-9]|090)_[^`]+` \| `[0-9a-f]{32}` \|$' "$RUNBOOK")
  echo "${n} files checked against the runbook table, ${bad} problems"
  [ "$n" -eq 23 ] && [ "$bad" -eq 0 ]
}

state_check() {      # state_check MIG EXPECT
  $P -v expect="$2" -f "${MC}/${1}_state_check.sql"
}

fp_section() {       # the rows of the "=== FINGERPRINTS" section of a state-check output
  awk '/^=== FINGERPRINTS/ {f = 1; next} f && /^=== / {exit} f' "$1"
}

fingerprints_equal() {   # fingerprints_equal BEFORE_FILE AFTER_FILE: not empty and identical
  local n
  n="$(fp_section "$1" | grep -c . || true)"
  if [ "$n" -lt 3 ]; then echo "no fingerprint rows found in $1"; return 1; fi
  if diff <(fp_section "$1") <(fp_section "$2"); then
    echo "FINGERPRINTS identical (${n} lines compared)"
  else
    echo "FINGERPRINTS DIFFER"
    return 1
  fi
}

dry_run() {          # dry_run FILE [psql args...]: ends in DRY RUN
  local f="$1" out
  shift
  out="$($P "$@" -f "$f" 2>&1)" || { printf '%s\n' "$out"; return 1; }
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -q 'DRY RUN'
}

apply_run() {        # apply_run FILE WORD [psql args...]: apply=true and the output must contain WORD
  local f="$1" word="$2" out
  shift 2
  out="$($P "$@" -v apply=true -f "$f" 2>&1)" || { printf '%s\n' "$out"; return 1; }
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -q "$word"
}

state_after_ok() {   # MIG: the state check says 'applied'
  local out
  out="$(state_check "$1" applied 2>&1)" || { printf '%s\n' "$out"; return 1; }
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -q '(applied): OK'
}

state_before_any() { # MIG: the state before applying is 'before' (pristine) or 'rolled_back' (after the rollback script)
  local mig="$1" out out2
  if out="$(state_check "$mig" before 2>&1)"; then
    printf '%s\n' "$out"; echo "BASE_STATE=before"; return 0
  fi
  if out2="$(state_check "$mig" rolled_back 2>&1)"; then
    printf '%s\n' "$out2"; echo "BASE_STATE=rolled_back"; return 0
  fi
  printf '%s\n--- and with expect=rolled_back:\n%s\n' "$out" "$out2"
  echo "STOP: ${mig} is neither in the 'before' nor in the 'rolled_back' state (already applied?). Use a fresh database restored from a production dump (README, 'Create the rehearsal database') or, if only this rehearsal applied it, run rehearse_local_rollback.sh first."
  return 1
}
