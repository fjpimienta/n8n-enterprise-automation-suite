#!/usr/bin/env bash
# 098_concurrency_check.sh: sale vs. new loan on the SAME animal, with two concurrent psql sessions, in both orders.
#   Order 1: a sale (UPDATE ... 'VENDIDO') holds the animal row; a concurrent loan INSERT must wait, then fail with P0100.
#   Order 2: a loan INSERT (OPEN) is in flight; a concurrent sale UPDATE must wait, then fail with P0098.
# Two sessions can only see each other's rows after COMMIT, so this script COMMITS fixtures (company 9891 and children) and
# removes them at the end. Therefore it refuses to run unless ALL of these hold:
#   * the database has NO animals at all (a schema-only throw-away copy, never a real database);
#   * migration 098 is already applied (and committed) in that database;
#   * no fixture of a previous run is left over.
# It is NOT part of 098_tests.sql (which never commits). Never point it at production or at the clone with real data.
# Connection: standard libpq settings (PGHOST, PGPORT, PGUSER, PGDATABASE, ~/.pgpass).  CONC_DRY=1 runs only the guards.
set -euo pipefail
cd "$(dirname "$0")"
Q() { psql -X -At -v ON_ERROR_STOP=1 "$@"; }
HOLD=${CONC_HOLD_SECONDS:-5}      # how long the first session keeps its lock
LAG=${CONC_LAG_SECONDS:-1.5}      # delay before the second session starts

animals=$(Q -c "select count(*) from public.cattle_livestock")
[ "$animals" = "0" ] || { echo "ABORT: this database has $animals animal(s); the concurrency check only runs on an empty schema-only copy."; exit 2; }
[ "$(Q -c "select to_regclass('public.uq_movement_animal_one_open') is not null and to_regprocedure('public.sp_return_movement(uuid,uuid[],date,character varying)') is not null")" = "t" ] \
  || { echo "ABORT: migration 098 is not applied in this database (apply it first, with -v apply=true, on the throw-away copy)."; exit 2; }
[ "$(Q -c "select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O' and tgname in ('trg_block_out_on_loan_status','trg_close_loan_on_death','trg_guard_movement_animal_open')")" = "3" ] \
  || { echo "ABORT: the three 098 triggers are not all enabled (098 rolled back?); re-apply 098 first."; exit 2; }
[ "$(Q -c "select count(*) from public.companys where id_company = 9891")" = "0" ] \
  || { echo "ABORT: fixture company 9891 already exists (leftover of a previous run)."; exit 2; }
echo "guards OK on $(Q -c "select current_database() || ' @ ' || current_setting('port')")"
[ "${CONC_DRY:-0}" = "1" ] && { echo "CONC_DRY=1: guards only, nothing written."; exit 0; }

cleanup() {
  Q <<'SQL' >/dev/null 2>&1 || echo "WARNING: cleanup failed; remove company 9891 and its children by hand"
DELETE FROM public.cattle_movement_event_animals WHERE event_id IN (SELECT id FROM public.cattle_movement_events WHERE id_company = 9891);
DELETE FROM public.cattle_movement_events WHERE id_company = 9891;
DELETE FROM public.cattle_livestock WHERE tenant_id = 9891;
DELETE FROM public.external_destinations WHERE id_company = 9891;
DELETE FROM public.production_units WHERE id_company = 9891;
DELETE FROM public.companys WHERE id_company = 9891;
SQL
  rm -rf "${TMP:-/nonexistent}"
}
TMP=$(mktemp -d)
trap cleanup EXIT

Q <<'SQL' >/dev/null
INSERT INTO public.companys (id_company, company_name) VALUES (9891, 'T098 concurrency');
INSERT INTO public.production_units (id_company, upp_code, ranch_name) VALUES (9891, '99-997-0001-001', 'T098 conc unit');
INSERT INTO public.external_destinations (id_company, name, destination_type, normative_type) VALUES (9891, 'T098 conc third party', 'THIRD_PARTY_RANCH', 'UPP');
INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, species, rfid_siniiga, production_unit_id)
SELECT 9891, 'CRIA', 'BECERRA', 'ACTIVO', 'BOVINO', t.tag, (SELECT id FROM public.production_units WHERE id_company = 9891)
  FROM (VALUES ('9891000001'), ('9891000002')) t(tag);
INSERT INTO public.cattle_movement_events (id_company, production_unit_origin_id, external_destination_id, reemo_folio, movement_date, purpose, expected_return_date)
SELECT 9891, pu.id, ed.id, 'CONC-T098', CURRENT_DATE - 5, 'REPASTO', CURRENT_DATE + 30
  FROM public.production_units pu, public.external_destinations ed WHERE pu.id_company = 9891 AND ed.id_company = 9891;
SQL
A=$(Q -c "select id from public.cattle_livestock where rfid_siniiga='9891000001'")
B=$(Q -c "select id from public.cattle_livestock where rfid_siniiga='9891000002'")
EV=$(Q -c "select id from public.cattle_movement_events where id_company=9891")

# Waiter snippets: report the SQLSTATE and how long the statement waited.
loan_waiter() { cat <<SQL
DO \$\$ DECLARE t0 timestamptz := clock_timestamp(); BEGIN
  INSERT INTO public.cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES ('$EV', '$1', 'OPEN');
  RAISE NOTICE 'RESULT ok waited=%', extract(epoch FROM clock_timestamp() - t0);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RESULT % waited=%', SQLSTATE, extract(epoch FROM clock_timestamp() - t0);
END \$\$;
SQL
}
sale_waiter() { cat <<SQL
DO \$\$ DECLARE t0 timestamptz := clock_timestamp(); BEGIN
  UPDATE public.cattle_livestock SET current_status = 'VENDIDO' WHERE id = '$1';
  RAISE NOTICE 'RESULT ok waited=%', extract(epoch FROM clock_timestamp() - t0);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'RESULT % waited=%', SQLSTATE, extract(epoch FROM clock_timestamp() - t0);
END \$\$;
SQL
}

fail=0
check() { # label, outfile, expected sqlstate
  local line state waited
  line=$(grep -o 'RESULT .*' "$2" | head -1 || true)
  state=$(awk '{print $2}' <<<"$line"); waited=$(sed -E 's/.*waited=([0-9.]+).*/\1/' <<<"$line")
  if [ "$state" = "$3" ] && awk -v w="$waited" -v h="$HOLD" 'BEGIN{exit !(w >= h - 2.5)}'; then
    echo "PASS  $1: $state after waiting ${waited}s"
  else
    echo "FAIL  $1: expected $3 after waiting ~${HOLD}s, got '${line:-no result}'"; fail=1
  fi
}

echo "--- Order 1: sale holds the animal, loan arrives second (expect P0100 after the wait)"
{ echo "BEGIN;"; echo "UPDATE public.cattle_livestock SET current_status = 'VENDIDO' WHERE id = '$A';"; echo "SELECT pg_sleep($HOLD);"; echo "COMMIT;"; } >"$TMP/s1.sql"
loan_waiter "$A" >"$TMP/l1.sql"
psql -X -q -v ON_ERROR_STOP=1 -f "$TMP/s1.sql" >"$TMP/s1.out" 2>&1 &  p1=$!
sleep "$LAG"
psql -X -q -v ON_ERROR_STOP=1 -f "$TMP/l1.sql" >"$TMP/l1.out" 2>&1 &  p2=$!
wait $p1 $p2
check "loan INSERT vs. sale" "$TMP/l1.out" P0100
[ "$(Q -c "select count(*) from public.cattle_movement_event_animals where cattle_livestock_id='$A' and return_status='OPEN'")" = "0" ] \
  && [ "$(Q -c "select current_status from public.cattle_livestock where id='$A'")" = "VENDIDO" ] \
  && echo "PASS  order 1 end state: sold animal, no OPEN loan row" || { echo "FAIL  order 1 end state"; fail=1; }

echo "--- Order 2: loan INSERT in flight, sale arrives second (expect P0098 after the wait)"
{ echo "BEGIN;"; echo "INSERT INTO public.cattle_movement_event_animals (event_id, cattle_livestock_id, return_status) VALUES ('$EV', '$B', 'OPEN');"; echo "SELECT pg_sleep($HOLD);"; echo "COMMIT;"; } >"$TMP/l2.sql"
sale_waiter "$B" >"$TMP/s2.sql"
psql -X -q -v ON_ERROR_STOP=1 -f "$TMP/l2.sql" >"$TMP/l2.out" 2>&1 &  p1=$!
sleep "$LAG"
psql -X -q -v ON_ERROR_STOP=1 -f "$TMP/s2.sql" >"$TMP/s2.out" 2>&1 &  p2=$!
wait $p1 $p2
check "sale UPDATE vs. loan" "$TMP/s2.out" P0098
[ "$(Q -c "select count(*) from public.cattle_movement_event_animals where cattle_livestock_id='$B' and return_status='OPEN'")" = "1" ] \
  && [ "$(Q -c "select current_status from public.cattle_livestock where id='$B'")" = "ACTIVO" ] \
  && echo "PASS  order 2 end state: animal still ACTIVO with its OPEN loan row" || { echo "FAIL  order 2 end state"; fail=1; }

[ $fail -eq 0 ] && echo "CONCURRENCY CHECK: OK (no lost protection, no deadlock)" || echo "CONCURRENCY CHECK: FAILED"
exit $fail
