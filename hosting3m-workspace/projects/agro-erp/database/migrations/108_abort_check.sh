#!/usr/bin/env bash
# 108_abort_check.sh: proves that the guards of 108 FAIL CLOSED and that the tests catch regressions (mutation checks).
# LOCAL / throwaway database ONLY: the database name must contain "test" or "rehearsal". Everything runs in transactions that are rolled back;
# nothing is committed. Synthetic data only.
# Usage: CONTAINER=n8n-enterprise-db bash 108_abort_check.sh <database>
#   e.g. bash 108_abort_check.sh rehearsal_108
set -uo pipefail
db="${1:?usage: 108_abort_check.sh <throwaway database>}"
container="${CONTAINER:-n8n-enterprise-db}"
case "$db" in *test*|*rehearsal*) ;; *) echo "ABORT: database name must contain test or rehearsal"; exit 2;; esac
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="/tmp/m108_abort"
fails=0

docker exec "$container" mkdir -p "$work" >/dev/null
put() { docker cp "$1" "$container:$work/$2" >/dev/null; }
for f in 108_palpation_views.sql 108_rollback.sql 108_state_check.sql 108_tests.sql; do put "$dir/$f" "$f"; done

run() { docker exec -i -w "$work" "$container" psql -X -A -q -U n8n_user -d "$db" -v ON_ERROR_STOP=1 "$@" 2>&1; }

# expect_fail <name> <pattern> <sql-from-stdin>: the script must exit non-zero AND print the pattern.
expect_fail() {
  local name="$1" pattern="$2" out rc
  out=$(run -f - ); rc=$?
  if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q -E -- "$pattern"; then echo "PASS  $name"; else echo "FAIL  $name (rc=$rc)"; printf '%s\n' "$out" | tail -5; fails=$((fails+1)); fi
}

# 1) Views already exist -> ABORT (the second include runs inside the same transaction as the first)
expect_fail "second run aborts because the views already exist" "already exists" <<'SQL'
BEGIN;
\set embedded true
\ir 108_palpation_views.sql
\ir 108_palpation_views.sql
ROLLBACK;
SQL

# 2) Only a model row exists -> ABORT
expect_fail "aborts when a crud_models row already exists" "crud_models row for vw_palpation_events" <<'SQL'
BEGIN;
INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields) VALUES ('vw_palpation_herd', 'some_other_table', 'id', '["id"]');
\set embedded true
\ir 108_palpation_views.sql
ROLLBACK;
SQL

# 3) Mutations of the migration (a copy with one guard-relevant line changed) ------------------------------------------------------------------
mutate_and_expect() {   # <name> <sed-expression> <pattern>
  local name="$1" expr="$2" pattern="$3"
  sed -E "$expr" "$dir/108_palpation_views.sql" > "/tmp/108_mut_$$.sql"
  if cmp -s "/tmp/108_mut_$$.sql" "$dir/108_palpation_views.sql"; then echo "FAIL  $name (the mutation changed nothing)"; fails=$((fails+1)); return; fi
  put "/tmp/108_mut_$$.sql" "108_mut.sql"
  expect_fail "$name" "$pattern" <<'SQL'
BEGIN;
\set embedded true
\ir 108_mut.sql
ROLLBACK;
SQL
  rm -f "/tmp/108_mut_$$.sql"
}
mutate_and_expect "migration aborts if id_company is removed from the events model" \
  '0,/"id_company","health_log_id"/s/"id_company","health_log_id"/"health_log_id"/' "id_company is missing from allowed_fields"
mutate_and_expect "migration aborts if created_at is removed from the herd model" \
  '/"palpation_count","created_at"\]/s/,"created_at"\]/]/' "created_at is missing from allowed_fields"
mutate_and_expect "migration aborts if a forbidden field is added to a model" \
  's/"technician","mapping_status"/"technician","notes","mapping_status"/' "forbidden field|differ from the columns"
mutate_and_expect "migration aborts if the roles are widened" \
  "s/'ADMIN,EDITOR', 'NONE', 'NONE', 'NONE', '\[\]', false, true\),/'ADMIN,EDITOR,CUSTOMER', 'NONE', 'NONE', 'NONE', '[]', false, true),/" "does not have the expected configuration"

# 4) Mutations of the VIEW: the tests must FAIL (they would catch a regression) ----------------------------------------------------------------
mutate_tests_expect_fail() {   # <name> <sed-expression> <pattern>
  local name="$1" expr="$2" pattern="$3"
  sed -E "$expr" "$dir/108_palpation_views.sql" > "/tmp/108_mut_$$.sql"
  if cmp -s "/tmp/108_mut_$$.sql" "$dir/108_palpation_views.sql"; then echo "FAIL  $name (the mutation changed nothing)"; fails=$((fails+1)); return; fi
  put "/tmp/108_mut_$$.sql" "108_palpation_views.sql"     # the tests \ir this name
  local out rc
  out=$(run -f 108_tests.sql); rc=$?
  if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q -E -- "$pattern"; then echo "PASS  $name"; else echo "FAIL  $name (rc=$rc)"; printf '%s\n' "$out" | tail -4; fails=$((fails+1)); fi
  put "$dir/108_palpation_views.sql" "108_palpation_views.sql"
  rm -f "/tmp/108_mut_$$.sql"
}
mutate_tests_expect_fail "tests catch code_meaning no longer forced to NULL for UNMAPPED" \
  "s/CASE WHEN d.mapping_status = 'UNMAPPED' THEN NULL ELSE c.meaning END AS code_meaning/c.meaning AS code_meaning/" "FAIL A UNMAPPED forces code_meaning"
mutate_tests_expect_fail "tests catch a historical flag that ignores the result key" \
  "s/\(jj.j \? 'resultado' AND NOT \(jj.j \? 'result'\)\)/(jj.j ? 'resultado')/" "FAIL"
mutate_tests_expect_fail "tests catch NR counted as a palpation" \
  "s/\(r.ranch_term IS DISTINCT FROM 'NR'\)/true/" "FAIL A NR does not count"
mutate_tests_expect_fail "tests catch the company filter missing from the details join (cross-company meaning)" \
  "s/c.id_company = l.tenant_id AND c.code/c.code/" "FAIL|ERROR"

# 5) The static check itself rejects a forbidden column --------------------------------------------------------------------------------------
tmp="$(mktemp -d)"; cp "$dir"/108_palpation_views.sql "$dir"/108_rollback.sql "$dir"/108_state_check.sql "$tmp/"
sed -E -i 's/NULLIF\(btrim\(jj\.j ->> .technician_name.\), ..\) +AS technician/h.description AS technician/' "$tmp/108_palpation_views.sql"
if cmp -s "$tmp/108_palpation_views.sql" "$dir/108_palpation_views.sql"; then echo "FAIL  static-check mutation changed nothing"; fails=$((fails+1)); fi
if bash "$dir/108_static_check.sh" "$tmp" >/dev/null 2>&1; then echo "FAIL  static check accepted a view that selects description"; fails=$((fails+1)); else echo "PASS  static check rejects a view that selects description"; fi
rm -rf "$tmp"

docker exec "$container" sh -c "rm -rf $work" >/dev/null
if [ "$fails" -eq 0 ]; then echo "ALL ABORT / MUTATION CHECKS PASSED"; else echo "$fails CHECK(S) FAILED"; fi
exit "$fails"
