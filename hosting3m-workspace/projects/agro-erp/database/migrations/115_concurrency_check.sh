#!/usr/bin/env bash
# 115_concurrency_check.sh: TWO-SESSION race checks for the tag-change functions. THROWAWAY database only (name must contain test or rehearsal).
# 115_tag_change_authorization.sql (and step 1) must already be APPLIED there. The script COMMITS synthetic data (new companies, @example.test users, fake animals)
# because two real sessions are needed, and removes it at the end (also on error). Never run it anywhere else.
#
#   PSQL_CMD='docker exec -i n8n-enterprise-db psql -X -U n8n_user -d hosting3m_test' ./115_concurrency_check.sh
#   (PSQL_CMD must run psql against the throwaway database and read SQL from stdin; the default is plain "psql -X" using the usual PG* variables.)
#
# Manual cleanup (rehearsal database ONLY; removes only rows named 'TEST race company %' and users race-*@example.test): re-run this script (it purges leftovers
# first), or run the same DO block that purge_data() contains, below in this file, with psql against the rehearsal database.
#
# Scenario 1: two requests on ONE animal at once  -> exactly one pending row; the second session waits for the first, then answers pending_exists.
# Scenario 2: the SAME chip to TWO animals at once -> exactly one animal gets it; the second session waits, then answers identifier_unavailable.
set -u
PSQL_CMD="${PSQL_CMD:-psql -X}"
P() { $PSQL_CMD -v ON_ERROR_STOP=1 -At "$@"; }
HOLD="${HOLD_SECONDS:-4}"
WORK="$(mktemp -d)"
fail=0

db="$(P -c 'select current_database()' </dev/null)" || { echo "ABORT: cannot connect"; exit 2; }
case "$db" in *test*|*rehearsal*) ;; *) echo "ABORT: database '$db' is not a throwaway database (name must contain test or rehearsal)."; exit 2;; esac
P -c "select to_regprocedure('public.sp_request_tag_change(text,text,text,text,text,text,text)') is not null" </dev/null | grep -q t || { echo "ABORT: 115_tag_change_authorization.sql is not applied in $db"; exit 2; }

# purge_data removes ONLY the synthetic rows this script creates (company names 'TEST race company %', users race-*@example.test). It never touches $WORK.
purge_data() {
  P <<'SQL' >/dev/null || echo "WARNING: purge_data failed; see 'Manual cleanup' at the top of this script" >&2
DO $$
DECLARE c integer[];
BEGIN
  SELECT array_agg(id_company) INTO c FROM public.companys WHERE company_name LIKE 'TEST race company %';
  IF c IS NULL THEN
    DELETE FROM public.users WHERE email LIKE 'race-%@example.test';
    RETURN;
  END IF;
  ALTER TABLE public.cattle_identifier_history DISABLE TRIGGER USER;   -- append-only guards, throwaway database only (re-enabled below)
  DELETE FROM public.pending_authorizations WHERE id_company = ANY (c);
  DELETE FROM public.tag_change_previews WHERE id_company = ANY (c);
  DELETE FROM public.cattle_identifier_history WHERE id_company = ANY (c);
  DELETE FROM public.historico_movimientos WHERE tenant_id = ANY (c);
  DELETE FROM public.cattle_livestock WHERE tenant_id = ANY (c);
  DELETE FROM public.user_companies WHERE id_company = ANY (c);
  DELETE FROM public.users WHERE email LIKE 'race-%@example.test';
  DELETE FROM public.companys WHERE id_company = ANY (c);
  ALTER TABLE public.cattle_identifier_history ENABLE TRIGGER USER;
END $$;
SQL
}
# cleanup runs on exit: purge the data, THEN remove $WORK. (An earlier version also called it at the start, which deleted $WORK before the sessions wrote to it.)
cleanup() { purge_data; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM
purge_data   # leftovers of an interrupted run (data only; $WORK must survive)

# ---- setup (committed) -------------------------------------------------------------------------------------------------------------------
TENANT="$(P <<'SQL'
WITH c AS (INSERT INTO public.companys (id_company, company_name, industry) SELECT coalesce(max(id_company), 0) + 1, 'TEST race company A', 'ganaderia' FROM public.companys RETURNING id_company),
u AS (INSERT INTO public.users (email, tenant_id, names, password, role, is_active)
        SELECT e, c.id_company, 'race user', 'x', r, true FROM c, (VALUES ('race-adm@example.test', 'ADMIN'), ('race-edt@example.test', 'EDITOR')) v(e, r) RETURNING email),
m AS (INSERT INTO public.user_companies (email, id_company, role, is_active)
        SELECT e, c.id_company, r, true FROM c, (VALUES ('race-adm@example.test', 'ADMIN'), ('race-edt@example.test', 'EDITOR')) v(e, r) RETURNING 1),
a AS (INSERT INTO public.cattle_livestock (tenant_id, business_model, category, current_status, species, rfid_siniiga, electronic_rfid)
        SELECT c.id_company, 'CRIA', 'VACA', 'ACTIVO', 'BOVINO', t, ch FROM c, (VALUES ('9900000401', NULL), ('9900000402', NULL), ('9900000403', '990000000000401')) v(t, ch) RETURNING 1)
SELECT id_company FROM c;
SQL
)" || { echo "ABORT: setup failed"; exit 2; }
echo "setup: company $TENANT in $db"
[ -d "$WORK" ] && [ -w "$WORK" ] || { echo "ABORT: work directory $WORK is missing or not writable after setup"; exit 2; }
session_out_ok() { : > "$WORK/.probe" 2>/dev/null; }
session_out_ok || { echo "ABORT: cannot write inside $WORK"; exit 2; }

# ---- scenario 1: two requests on ONE animal ------------------------------------------------------------------------------------------------
tok() { P -c "select (public.sp_request_tag_change('$TENANT','$1','$2','$3','$4','$5'))->>'preview_token'" </dev/null; }
T1="$(tok race-adm@example.test 9900000403 SINIIGA 9900000411 'race one')"
T2="$(tok race-edt@example.test 9900000403 SINIIGA 9900000412 'race two')"
( P <<SQL > "$WORK/s1.out" 2>&1
BEGIN;
SELECT (public.sp_request_tag_change('$TENANT','race-adm@example.test','9900000403','SINIIGA','9900000411','race one','$T1'))->>'status';
SELECT pg_sleep($HOLD);
COMMIT;
SQL
) &
sleep 1
start=$(date +%s)
P -c "select (public.sp_request_tag_change('$TENANT','race-edt@example.test','9900000403','SINIIGA','9900000412','race two','$T2'))->>'status'" </dev/null > "$WORK/s2.out" 2>&1
waited=$(( $(date +%s) - start ))
wait
s1="$(grep -E '^(requested|pending_exists|[a-z_]+)$' "$WORK/s1.out" | head -1)"; s2="$(head -1 "$WORK/s2.out")"
pend="$(P -c "select count(*) from public.pending_authorizations where id_company=$TENANT and tipo_evento='CAMBIO_ARETE' and estado='PENDIENTE'" </dev/null)"
echo "scenario 1: session1=$s1 session2=$s2 pending_rows=$pend session2_waited=${waited}s (expect ~$((HOLD-1))s)"
[ "$s1" = "requested" ] && [ "$s2" = "pending_exists" ] && [ "$pend" = "1" ] && [ "$waited" -ge 2 ] || { echo "scenario 1 FAILED"; fail=1; }

# ---- scenario 2: the same chip to two animals ------------------------------------------------------------------------------------------------
CHIP=990000000000450
atok() { P -c "select (public.sp_assign_livestock_identifier('$TENANT','$1','$2','CHIP','$CHIP'))->>'preview_token'" </dev/null; }
A1="$(atok race-adm@example.test 9900000401)"
A2="$(atok race-edt@example.test 9900000402)"
( P <<SQL > "$WORK/c1.out" 2>&1
BEGIN;
SELECT (public.sp_assign_livestock_identifier('$TENANT','race-adm@example.test','9900000401','CHIP','$CHIP','$A1'))->>'status';
SELECT pg_sleep($HOLD);
COMMIT;
SQL
) &
sleep 1
start=$(date +%s)
P -c "select (public.sp_assign_livestock_identifier('$TENANT','race-edt@example.test','9900000402','CHIP','$CHIP','$A2'))->>'status'" </dev/null > "$WORK/c2.out" 2>&1
waited=$(( $(date +%s) - start ))
wait
c1="$(grep -E '^[a-z_]+$' "$WORK/c1.out" | head -1)"; c2="$(head -1 "$WORK/c2.out")"
holders="$(P -c "select count(*) from public.cattle_livestock where tenant_id=$TENANT and electronic_rfid='$CHIP'" </dev/null)"
echo "scenario 2: session1=$c1 session2=$c2 animals_with_chip=$holders session2_waited=${waited}s"
[ "$c1" = "applied" ] && [ "$c2" = "identifier_unavailable" ] && [ "$holders" = "1" ] && [ "$waited" -ge 2 ] || { echo "scenario 2 FAILED"; fail=1; }

purge_data
left="$(P -c "select (select count(*) from public.companys where company_name like 'TEST race company %') + (select count(*) from public.users where email like 'race-%@example.test')" </dev/null)"
echo "cleanup: synthetic rows left = $left (expect 0)"
[ "$left" = "0" ] || { echo "cleanup FAILED"; fail=1; }
[ "$fail" = 0 ] && echo "ALL CONCURRENCY CHECKS PASSED" || echo "CONCURRENCY CHECKS FAILED"
exit "$fail"
