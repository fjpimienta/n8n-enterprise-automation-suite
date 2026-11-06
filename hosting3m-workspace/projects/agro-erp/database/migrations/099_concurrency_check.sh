#!/usr/bin/env bash
# 099_concurrency_check.sh: two concurrent commits of the SAME ear tag, with two psql sessions.
#   Scenario 1: two regularizations of the same tag in the same company. The second waits on the UNIQUE index and,
#               when the first commits, answers status 'duplicate' (no second row, no raw error).
#   Scenario 2: a purchase in company A holds the tag; a regularization of the same tag in company B waits and answers
#               'duplicate_other_company' (company A is never named).
#   Scenario 3: the first session ROLLS BACK; the second waits and then records the animal (no false rejection).
# Species BORREGO is used on purpose: its categories are a fixed list, so the global lifestage catalog is not touched.
# Two sessions can only see each other's rows after COMMIT, so this script COMMITS fixtures (companies 9897 and 9898,
# one fake user, two UPP) and removes them at the end. Therefore it refuses to run unless ALL of these hold:
#   * the database has NO animals at all (a schema-only throw-away copy, never a real database);
#   * migration 099 is applied and committed in that database (not the rollback stubs);
#   * no fixture of a previous run is left over.
# It is NOT part of 099_tests.sql (which never commits). Never point it at production or at the clone with real data.
# Connection: standard libpq settings (PGHOST, PGPORT, PGUSER, PGDATABASE, ~/.pgpass).  CONC_DRY=1 runs only the guards.
set -euo pipefail
cd "$(dirname "$0")"
Q() { psql -X -At -v ON_ERROR_STOP=1 "$@"; }
HOLD=${CONC_HOLD_SECONDS:-5}      # how long the first session keeps its transaction open
LAG=${CONC_LAG_SECONDS:-1.5}      # delay before the second session starts
EMAIL='t099c-admin@example.test'
REG_SIG="public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)"

animals=$(Q -c "select count(*) from public.cattle_livestock")
[ "$animals" = "0" ] || { echo "ABORT: this database has $animals animal(s); the concurrency check only runs on an empty schema-only copy."; exit 2; }
[ "$(Q -c "select to_regprocedure('$REG_SIG') is not null and pg_get_functiondef(to_regprocedure('$REG_SIG')) like '%REGULARIZACION_PADRON%'")" = "t" ] \
  || { echo "ABORT: migration 099 is not applied in this database (apply it first, with -v apply=true, on the throw-away copy)."; exit 2; }
[ "$(Q -c "select count(*) from public.companys where id_company in (9897, 9898)")" = "0" ] \
  || { echo "ABORT: fixture companies 9897/9898 already exist (leftover of a previous run)."; exit 2; }
echo "guards OK on $(Q -c "select current_database() || ' @ ' || current_setting('port')")"
[ "${CONC_DRY:-0}" = "1" ] && { echo "CONC_DRY=1: guards only, nothing written."; exit 0; }

cleanup() {
  Q <<SQL >/dev/null 2>&1 || echo "WARNING: cleanup failed; remove companies 9897/9898, their children and $EMAIL by hand"
DELETE FROM public.cattle_livestock WHERE tenant_id IN (9897, 9898);
DELETE FROM public.production_units WHERE id_company IN (9897, 9898);
DELETE FROM public.user_companies WHERE email = '$EMAIL';
DELETE FROM public.users WHERE email = '$EMAIL';
DELETE FROM public.companys WHERE id_company IN (9897, 9898);
SQL
  rm -rf "${TMP:-/nonexistent}"
}
TMP=$(mktemp -d)
trap cleanup EXIT

Q <<SQL >/dev/null
INSERT INTO public.companys (id_company, company_name, industry, is_active) VALUES (9897, 'T099 conc A', 'ganaderia', true), (9898, 'T099 conc B', 'ganaderia', true);
INSERT INTO public.users (email, names, password, role, is_active) VALUES ('$EMAIL', 'T099 conc', 'x', 'ADMIN', true);
INSERT INTO public.user_companies (email, id_company, role, is_active) VALUES ('$EMAIL', 9897, 'ADMIN', true), ('$EMAIL', 9898, 'ADMIN', true);
INSERT INTO public.production_units (id_company, upp_code, ranch_name) VALUES (9897, '99-897-0001-001', 'T099 conc A'), (9898, '99-898-0001-001', 'T099 conc B');
SQL

# reg <tenant> <tag> <confirmed> <hash>  /  buy <tenant> <tag> <confirmed> <hash>: the SQL call (all parameters are text).
lit() { if [ -n "${1:-}" ]; then echo "'$1'"; else echo "NULL"; fi; }
reg() { echo "public.sp_register_livestock_regularization('$1', '$EMAIL', 'CHAT_WEB', NULL, NULL, 'BORREGO', 'BORREGA', 'CRIA', '6', '$2', NULL, NULL, NULL, '$3', $(lit "${4:-}"), NULL)"; }
buy() { echo "public.sp_register_livestock_purchase_chat('$1', '$EMAIL', 'CHAT_WEB', NULL, NULL, 'BORREGO', 'BORREGA', 'CRIA', '$2', NULL, NULL, '1000', 'Vendedor Ejemplo', NULL, NULL, '$3', $(lit "${4:-}"), NULL)"; }
hash_of() { Q -c "select ($1)->>'preview_hash'"; }

# A session that reports the status of one call and how long it waited.
caller() { # <call> [hold-then: commit|rollback]
  cat <<SQL
BEGIN;
DO \$\$ DECLARE t0 timestamptz := clock_timestamp(); r jsonb; BEGIN
  r := $1;
  RAISE NOTICE 'RESULT % waited=%', r->>'status', extract(epoch FROM clock_timestamp() - t0);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RESULT ERROR:% waited=%', SQLSTATE, extract(epoch FROM clock_timestamp() - t0);
END \$\$;
SQL
  if [ -n "${2:-}" ]; then echo "SELECT pg_sleep($HOLD);"; echo "${2^^};"; else echo "COMMIT;"; fi
}

fail=0
check() { # label, outfile, expected status, must_wait (1|0)
  local line state waited
  line=$(grep -o 'RESULT .*' "$2" | head -1 || true)
  state=$(awk '{print $2}' <<<"$line"); waited=$(sed -E 's/.*waited=([0-9.]+).*/\1/' <<<"$line")
  if [ "$state" = "$3" ] && { [ "$4" = "0" ] || awk -v w="$waited" -v h="$HOLD" 'BEGIN{exit !(w >= h - 2.5)}'; }; then
    echo "PASS  $1: $state (waited ${waited}s)"
  else
    echo "FAIL  $1: expected $3$([ "$4" = "1" ] && echo " after waiting ~${HOLD}s"), got '${line:-no result}'"; fail=1
  fi
}
run_pair() { # first.sql second.sql (second starts LAG seconds later)
  psql -X -q -v ON_ERROR_STOP=1 -f "$1" >"${1%.sql}.out" 2>&1 &  local p1=$!
  sleep "$LAG"
  psql -X -q -v ON_ERROR_STOP=1 -f "$2" >"${2%.sql}.out" 2>&1 &  local p2=$!
  wait $p1 $p2
}
rows() { Q -c "select coalesce(string_agg(tenant_id::text, ',' order by tenant_id), '-') from public.cattle_livestock where rfid_siniiga = '$1'"; }

echo "--- Scenario 1: two regularizations of the same tag in the same company (expect duplicate after the wait)"
H1=$(hash_of "$(reg 9897 9897000001 false)")
caller "$(reg 9897 9897000001 true "$H1")" commit >"$TMP/a1.sql"
caller "$(reg 9897 9897000001 true "$H1")" >"$TMP/b1.sql"
run_pair "$TMP/a1.sql" "$TMP/b1.sql"
check "first session" "$TMP/a1.out" recorded 0
check "second session" "$TMP/b1.out" duplicate 1
[ "$(rows 9897000001)" = "9897" ] && echo "PASS  scenario 1 end state: exactly one animal with the tag" || { echo "FAIL  scenario 1 end state: $(rows 9897000001)"; fail=1; }

echo "--- Scenario 2: purchase in company A holds the tag, regularization in company B (expect duplicate_other_company)"
H2a=$(hash_of "$(buy 9897 9897000002 false)")
H2b=$(hash_of "$(reg 9898 9897000002 false)")
caller "$(buy 9897 9897000002 true "$H2a")" commit >"$TMP/a2.sql"
caller "$(reg 9898 9897000002 true "$H2b")" >"$TMP/b2.sql"
run_pair "$TMP/a2.sql" "$TMP/b2.sql"
check "first session (purchase, company A)" "$TMP/a2.out" recorded 0
check "second session (regularization, company B)" "$TMP/b2.out" duplicate_other_company 1
grep -q 'T099 conc A' "$TMP/b2.out" && { echo "FAIL  scenario 2: company A named to company B"; fail=1; } || echo "PASS  scenario 2: company A is never named"
[ "$(rows 9897000002)" = "9897" ] && echo "PASS  scenario 2 end state: one animal, in company A" || { echo "FAIL  scenario 2 end state: $(rows 9897000002)"; fail=1; }

echo "--- Scenario 3: the first session rolls back (expect the second to record after the wait)"
H3=$(hash_of "$(reg 9897 9897000003 false)")
caller "$(reg 9897 9897000003 true "$H3")" rollback >"$TMP/a3.sql"
caller "$(reg 9897 9897000003 true "$H3")" >"$TMP/b3.sql"
run_pair "$TMP/a3.sql" "$TMP/b3.sql"
check "first session (rolled back)" "$TMP/a3.out" recorded 0
check "second session" "$TMP/b3.out" recorded 1
[ "$(rows 9897000003)" = "9897" ] && echo "PASS  scenario 3 end state: exactly one animal with the tag" || { echo "FAIL  scenario 3 end state: $(rows 9897000003)"; fail=1; }

[ $fail -eq 0 ] && echo "CONCURRENCY CHECK: OK (no duplicate tag, no raw error, no deadlock)" || echo "CONCURRENCY CHECK: FAILED"
exit $fail
