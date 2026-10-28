-- 087_088_smoke_local.sql — SMOKE SCRIPT for the phase 4 tools (migrations 087, 088, 089) on the LOCAL copy, tenant 5.
--
-- ##########################################################################################################################
-- #  LOCAL ONLY. DO NOT RUN THIS AGAINST PRODUCTION.                                                                       #
-- #  Part A only reads. Part B WRITES (births, calves, a service, a historical birth) inside ONE transaction that ENDS IN  #
-- #  ROLLBACK, and the script proves it: it prints the counts before and after and FAILS LOUDLY if any differs. Even so,   #
-- #  never point it at the production database: a rolled-back write still takes locks, burns sequence values and fires     #
-- #  triggers, and a mistake in the connection string would make this a production write test.                              #
-- #  SQL cannot tell the local copy from production; look at the "WHERE AM I" lines it prints first and stop if wrong.      #
-- ##########################################################################################################################
--
-- Needs 084 - 088 applied on this database (089 is not required). Nothing is hardcoded about people: it picks, by itself, a real
-- ADMIN member of tenant 5 and a user who is NOT a member of tenant 5, and it NEVER prints an e-mail: every answer goes through
-- pg_temp.scrub(), which replaces any key containing "email" and any text containing "@" with "(hidden)". (If a statement FAILS,
-- PostgreSQL's own error context may show the statement text, e-mail included: do not paste an error context without reading it.)
-- It creates only session-private (pg_temp) helper functions. It changes no migration, rollback or state-check file.
--
-- The exact command (no --single-transaction: the script manages its own transactions; the output is plain text):
--   docker exec -i n8n-enterprise-db psql -U n8n_user -d hosting3m_db -X -v ON_ERROR_STOP=1 < hosting3m-workspace/projects/agro-erp/database/migrations/087_088_smoke_local.sql > /tmp/smoke_087_088.txt 2>&1
--
-- Reading the output: every call is printed as "=== <label>" followed by the answer as indented JSON (or RAISED sqlstate=...).
-- "EXPECT" lines say OK or MISMATCH for the few things this script can check by itself; a MISMATCH is information, not a crash.
-- The ONLY hard failure is the final count check (and a failed precondition): they raise an error and psql exits non-zero.
--
-- Values the script needs and takes FROM THE DATA (when the local data has none of them, the call is printed as "skipped: ..."
-- and the missing thing is named; nothing is invented):
--   * a PREÑADA dam of tenant 5 whose last palpation is on the company's most common (stale imported) palpation date
--   * a VACÍA dam of tenant 5 (with a palpation)
--   * a numero_fuego of tenant 5 shared by several animals (2012 if it exists, else the most repeated one)
--   * a dam with a REGISTERED birth in tenant 5 (to show possible_duplicate in the preview)
--   * five "fresh" dams: active VACA of tenant 5 with a SINIIGA tag and no birth, historical birth or service on record
--     (Part B builds its own service for the first one; if fewer than five exist, the calls that need the rest are skipped)
--   * a user who is not a member of tenant 5 (else a clearly fake address is used) and a company where the admin is not a member
--     (else the number 999999)
-- The one deliberately invented value is a "no such animal" identifier for the not_found line; the script checks it matches nothing.

\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\pset footer off
\pset null '(null)'

\echo
\echo '################################################################################'
\echo '#  LOCAL SMOKE SCRIPT - tenant 5 - NEVER RUN THIS AGAINST PRODUCTION           #'
\echo '################################################################################'
\echo '=== WHERE AM I (stop here if this is not the local copy)'
SELECT 'database=' || current_database() || '  server_addr=' || coalesce(host(inet_server_addr()), '(unix socket)') || '  version=' || split_part(version(), ' on ', 1)
       || E'\npostmaster_started=' || pg_postmaster_start_time()::text || '  companies=' || (SELECT count(*) FROM companys) || '  animals=' || (SELECT count(*) FROM cattle_livestock);

-- ---------------------------------------------------------------------------------------------------------------------
-- Preconditions and session helpers (outside any transaction; pg_temp only)
-- ---------------------------------------------------------------------------------------------------------------------

DO $$
BEGIN
    IF to_regprocedure('public.sp_repro_register_birth(text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_repro_get_dam_history(text,text,text,text)') IS NULL
       OR to_regprocedure('public.fn_repro_palpations(integer)') IS NULL THEN
        RAISE EXCEPTION 'PRECONDITION: migrations 086, 087 and 088 must be applied on this database first.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM companys WHERE id_company = 5 AND is_active) THEN
        RAISE EXCEPTION 'PRECONDITION: company 5 does not exist or is not active here.';
    END IF;
    IF coalesce(fn_company_business_domain(5), '') = 'PALM' THEN
        RAISE EXCEPTION 'PRECONDITION: company 5 is a palm company.';
    END IF;
    IF (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.sp_register_birth_event(integer,character varying,character varying,uuid,character varying,character varying,date,uuid,uuid,uuid,numeric,text,character varying)')) NOT LIKE '%087:legacy-birth-v1%' THEN
        RAISE EXCEPTION 'PRECONDITION: sp_register_birth_event does not carry the 087 body.';
    END IF;
END $$;

-- hides every e-mail: any key containing "email" and any text containing "@"
CREATE FUNCTION pg_temp.scrub(j jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    r jsonb;
    k text;
    v jsonb;
BEGIN
    IF j IS NULL THEN RETURN NULL; END IF;
    CASE jsonb_typeof(j)
        WHEN 'object' THEN
            r := '{}'::jsonb;
            FOR k, v IN SELECT key, value FROM jsonb_each(j) LOOP
                IF k ILIKE '%email%' THEN
                    r := r || jsonb_build_object(k, CASE WHEN jsonb_typeof(v) = 'null' THEN 'null'::jsonb ELSE to_jsonb('(hidden)'::text) END);
                ELSE
                    r := r || jsonb_build_object(k, pg_temp.scrub(v));
                END IF;
            END LOOP;
            RETURN r;
        WHEN 'array' THEN
            SELECT coalesce(jsonb_agg(pg_temp.scrub(e) ORDER BY o), '[]'::jsonb) INTO r FROM jsonb_array_elements(j) WITH ORDINALITY AS t (e, o);
            RETURN r;
        WHEN 'string' THEN
            IF (j #>> '{}') LIKE '%@%' THEN RETURN to_jsonb('(hidden)'::text); END IF;
            RETURN j;
        ELSE
            RETURN j;
    END CASE;
END $$;

CREATE FUNCTION pg_temp.show(p_label text, p_j jsonb) RETURNS text
LANGUAGE sql AS $$ SELECT E'\n=== ' || p_label || E'\n' || coalesce(jsonb_pretty(pg_temp.scrub(p_j)), '(null)') $$;

CREATE FUNCTION pg_temp.skipped(p_label text, p_missing text) RETURNS text
LANGUAGE sql AS $$ SELECT E'\n=== ' || p_label || E'\nskipped: ' || p_missing $$;

-- runs a statement that is EXPECTED to raise (or answer) and prints which, without ever printing an e-mail
CREATE FUNCTION pg_temp.attempt(p_label text, p_sql text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    v jsonb;
BEGIN
    BEGIN
        EXECUTE p_sql INTO v;
        RETURN E'\n=== ' || p_label || E'\nANSWERED (no error): ' || coalesce(jsonb_pretty(pg_temp.scrub(v)), '(null)');
    EXCEPTION WHEN assert_failure THEN
        RETURN E'\n=== ' || p_label || E'\nRAISED sqlstate=' || SQLSTATE || '  message=' || regexp_replace(SQLERRM, '[^[:space:]]+@[^[:space:]]+', '(hidden)', 'g');
    WHEN OTHERS THEN
        RETURN E'\n=== ' || p_label || E'\nRAISED sqlstate=' || SQLSTATE || '  message=' || regexp_replace(SQLERRM, '[^[:space:]]+@[^[:space:]]+', '(hidden)', 'g');
    END;
END $$;

CREATE FUNCTION pg_temp.expect(p_label text, p_ok boolean) RETURNS text
LANGUAGE sql AS $$ SELECT 'EXPECT ' || CASE WHEN coalesce(p_ok, false) THEN 'OK        ' ELSE 'MISMATCH  ' END || p_label $$;

-- the numbers Part B must leave untouched
CREATE FUNCTION pg_temp.counts() RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'birth_events_all',               (SELECT count(*) FROM birth_events),
        'birth_events_tenant_5',          (SELECT count(*) FROM birth_events WHERE id_company = 5),
        'cattle_livestock_all',           (SELECT count(*) FROM cattle_livestock),
        'calves_with_a_mother_all',       (SELECT count(*) FROM cattle_livestock WHERE mother_id IS NOT NULL),
        'cattle_breeding_events_all',     (SELECT count(*) FROM cattle_breeding_events),
        'cattle_breeding_events_linked',  (SELECT count(*) FROM cattle_breeding_events WHERE birth_event_id IS NOT NULL),
        'repro_historical_births',        (SELECT count(*) FROM repro_historical_births),
        'repro_historical_birth_voids',   (SELECT count(*) FROM repro_historical_birth_voids),
        'event_voids',                    (SELECT count(*) FROM event_voids),
        'cattle_weight_logs',             (SELECT count(*) FROM cattle_weight_logs),
        'tenant_5_status_checksum',       (SELECT md5(coalesce(string_agg(id::text || ':' || current_status, ',' ORDER BY id), '')) FROM cattle_livestock WHERE tenant_id = 5)
    )
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Picks from the data (read-only; every pick is "" when the local data has none)
-- ---------------------------------------------------------------------------------------------------------------------

\echo '=== PICKS (counts only; ids and e-mails are not printed here)'

SELECT uc.email AS admin_email
  FROM user_companies uc JOIN users u ON lower(u.email) = lower(uc.email) JOIN companys c ON c.id_company = uc.id_company AND c.is_active
 WHERE uc.id_company = 5 AND uc.is_active AND upper(uc.role) = 'ADMIN'
 ORDER BY uc.email LIMIT 1
\gset
\if :{?admin_email}
\else
    \echo 'PRECONDITION FAILED: tenant 5 has no active ADMIN member in this database.'
    DO $$ BEGIN RAISE EXCEPTION 'PRECONDITION: no active ADMIN member of tenant 5'; END $$;
\endif

SELECT coalesce((SELECT u.email FROM users u
                  WHERE NOT EXISTS (SELECT 1 FROM user_companies uc WHERE uc.id_company = 5 AND uc.is_active AND lower(uc.email) = lower(u.email))
                  ORDER BY u.email LIMIT 1), 'smoke-no-such-member@invalid.example') AS nonmember_email
\gset

SELECT coalesce((SELECT c.id_company::text FROM companys c
                  WHERE c.is_active AND coalesce(fn_company_business_domain(c.id_company), '') <> 'PALM'
                    AND NOT EXISTS (SELECT 1 FROM user_companies uc WHERE uc.id_company = c.id_company AND uc.is_active AND lower(uc.email) = lower(:'admin_email'))
                  ORDER BY c.id_company LIMIT 1), '999999') AS wrong_tenant
\gset

-- a PREÑADA dam whose last palpation is on the company's most common palpation date (the stale imported one)
SELECT coalesce((SELECT l.id::text FROM cattle_livestock l
                  WHERE l.tenant_id = 5 AND l.current_status = 'PREÑADA'
                    AND EXISTS (SELECT 1 FROM fn_repro_palpations(5) p
                                 WHERE p.livestock_id = l.id
                                   AND p.pdate = (SELECT q.pdate FROM fn_repro_palpations(5) q GROUP BY q.pdate ORDER BY count(*) DESC, q.pdate LIMIT 1))
                  ORDER BY l.id LIMIT 1), '') AS dam_preg_stale
\gset

-- a VACÍA dam that has at least one palpation
SELECT coalesce((SELECT l.id::text FROM cattle_livestock l
                  WHERE l.tenant_id = 5 AND l.current_status IN ('VACÍA', 'VACIA')
                    AND EXISTS (SELECT 1 FROM fn_repro_palpations(5) p WHERE p.livestock_id = l.id)
                  ORDER BY l.id LIMIT 1), '') AS dam_vacia
\gset
SELECT coalesce((SELECT l.rfid_siniiga FROM cattle_livestock l WHERE l.id = NULLIF(:'dam_vacia', '')::uuid), '') AS dam_vacia_rfid
\gset

-- a fire number shared by several animals of tenant 5 (2012 first if it exists)
SELECT coalesce((SELECT l.numero_fuego FROM cattle_livestock l
                  WHERE l.tenant_id = 5 AND l.numero_fuego IS NOT NULL AND btrim(l.numero_fuego) <> ''
                  GROUP BY l.numero_fuego HAVING count(*) > 1
                  ORDER BY (l.numero_fuego = '2012') DESC, count(*) DESC, l.numero_fuego LIMIT 1), '') AS dup_fuego
\gset
SELECT coalesce((SELECT count(*)::text FROM cattle_livestock l WHERE l.tenant_id = 5 AND l.numero_fuego = NULLIF(:'dup_fuego', '')), '0') AS dup_fuego_n
\gset

-- the dam of the latest REGISTERED birth of tenant 5 (to show possible_duplicate)
SELECT coalesce((SELECT be.dam_id::text FROM birth_events be WHERE be.id_company = 5 AND be.dam_id IS NOT NULL ORDER BY be.birth_date DESC, be.created_at DESC LIMIT 1), '') AS dam_pd
\gset
SELECT coalesce((SELECT be.birth_date::text FROM birth_events be WHERE be.id_company = 5 AND be.dam_id IS NOT NULL ORDER BY be.birth_date DESC, be.created_at DESC LIMIT 1), '') AS dam_pd_date
\gset

-- five fresh dams: active VACA, SINIIGA tag, no birth, no historical birth, no service on record
WITH f AS (
    SELECT l.id, l.rfid_siniiga
      FROM cattle_livestock l
     WHERE l.tenant_id = 5 AND l.species = 'BOVINO' AND l.category = 'VACA'
       AND l.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS')
       AND l.rfid_siniiga IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM birth_events be WHERE be.dam_id = l.id)
       AND NOT EXISTS (SELECT 1 FROM repro_historical_births h WHERE h.dam_id = l.id)
       AND NOT EXISTS (SELECT 1 FROM cattle_breeding_events e WHERE e.livestock_id = l.id)
     ORDER BY l.id LIMIT 5)
SELECT coalesce((SELECT id::text FROM f ORDER BY id OFFSET 0 LIMIT 1), '') AS dam_f1,
       coalesce((SELECT rfid_siniiga FROM f ORDER BY id OFFSET 0 LIMIT 1), '') AS dam_f1_rfid,
       coalesce((SELECT id::text FROM f ORDER BY id OFFSET 1 LIMIT 1), '') AS dam_f2,
       coalesce((SELECT id::text FROM f ORDER BY id OFFSET 2 LIMIT 1), '') AS dam_f3,
       coalesce((SELECT id::text FROM f ORDER BY id OFFSET 3 LIMIT 1), '') AS dam_f4,
       coalesce((SELECT id::text FROM f ORDER BY id OFFSET 4 LIMIT 1), '') AS dam_f5
\gset

-- an identifier that must match nothing (deliberately invented; verified absent)
SELECT CASE WHEN EXISTS (SELECT 1 FROM cattle_livestock WHERE tenant_id = 5 AND 'SMOKE-NO-EXISTE-000' IN (rfid_siniiga, electronic_rfid, numero_fuego))
            THEN 'SMOKE-NO-EXISTE-001' ELSE 'SMOKE-NO-EXISTE-000' END AS missing_ident
\gset

SELECT jsonb_pretty(jsonb_build_object(
    'tenant', 5,
    'admin_member_found', true,
    'non_member_user_is_a_real_user', :'nonmember_email' <> 'smoke-no-such-member@invalid.example',
    'wrong_tenant_is_a_real_company', :'wrong_tenant' <> '999999',
    'dam_preg_with_stale_palpation', :'dam_preg_stale' <> '',
    'dam_vacia_with_palpation', :'dam_vacia' <> '',
    'duplicated_fire_number_found', :'dup_fuego' <> '',
    'animals_sharing_that_fire_number', :'dup_fuego_n'::int,
    'dam_with_a_registered_birth', :'dam_pd' <> '',
    'fresh_dams_found', (CASE WHEN :'dam_f1' <> '' THEN 1 ELSE 0 END) + (CASE WHEN :'dam_f2' <> '' THEN 1 ELSE 0 END) + (CASE WHEN :'dam_f3' <> '' THEN 1 ELSE 0 END)
                       + (CASE WHEN :'dam_f4' <> '' THEN 1 ELSE 0 END) + (CASE WHEN :'dam_f5' <> '' THEN 1 ELSE 0 END)));

-- =====================================================================================================================
-- PART A. READ ONLY
-- =====================================================================================================================

\echo
\echo '################################ PART A - READ ONLY ################################'
BEGIN READ ONLY;

SELECT pg_temp.show('A1  births config of tenant 5 (the default window is 240 days unless an ADMIN set one)', sp_repro_births_get_config('5', :'admin_email'));

SELECT CASE WHEN :'dam_preg_stale' = '' THEN pg_temp.skipped('A2a dam history: PREÑADA with a stale imported palpation', 'no PREÑADA dam of tenant 5 has a palpation on the most common palpation date in this database')
            ELSE pg_temp.show('A2a dam history: a PREÑADA dam whose last palpation is on the stale imported date (look at expected_calving.bucket and quality_flags)',
                              sp_repro_get_dam_history('5', :'admin_email', NULL, :'dam_preg_stale')) END;

SELECT CASE WHEN :'dam_vacia' = '' THEN pg_temp.skipped('A2b dam history: VACÍA', 'no VACÍA dam of tenant 5 with a palpation in this database')
            ELSE pg_temp.show('A2b dam history: a VACÍA dam (expected_calving.applies must be false)',
                              sp_repro_get_dam_history('5', :'admin_email', NULL, :'dam_vacia')) END;

SELECT CASE WHEN :'dup_fuego' = '' THEN pg_temp.skipped('A2c dam history: duplicated fire number', 'no numero_fuego of tenant 5 is shared by several animals in this database')
            ELSE pg_temp.show('A2c dam history by a fire number shared by ' || :'dup_fuego_n' || ' animals: must answer ambiguous with candidates and NO history of any of them',
                              sp_repro_get_dam_history('5', :'admin_email', :'dup_fuego')) END;
SELECT CASE WHEN :'dup_fuego' = '' THEN '(A2c check omitted: no duplicated fire number in the data)'
            ELSE pg_temp.expect('A2c answered ambiguous with ' || :'dup_fuego_n' || ' candidates and no history sections',
                                sp_repro_get_dam_history('5', :'admin_email', :'dup_fuego')->>'status' = 'ambiguous'
                                AND jsonb_array_length(sp_repro_get_dam_history('5', :'admin_email', :'dup_fuego')->'candidates') = :'dup_fuego_n'::int
                                AND NOT sp_repro_get_dam_history('5', :'admin_email', :'dup_fuego') ? 'births') END;

-- A3: births_batch_preview with four lines (pure read)
SELECT pg_temp.show('A3  births_batch_preview, 4 lines: valid / ambiguous / not_found / possible_duplicate (nothing is written)',
    sp_repro_births_batch_preview('5', :'admin_email',
        (SELECT jsonb_agg(x ORDER BY o)::text FROM (
            SELECT 1 AS o, jsonb_build_object('dam_id', :'dam_f1', 'calf_sex', 'MACHO', 'birth_weight_kg', '33') AS x WHERE :'dam_f1' <> ''
            UNION ALL
            SELECT 2, jsonb_build_object('dam_identifier', :'dup_fuego', 'calf_sex', 'HEMBRA') WHERE :'dup_fuego' <> ''
            UNION ALL
            SELECT 3, jsonb_build_object('dam_identifier', :'missing_ident', 'calf_sex', 'MACHO')
            UNION ALL
            SELECT 4, jsonb_build_object('dam_id', :'dam_pd', 'calf_sex', 'MACHO', 'birth_date', CASE WHEN :'dam_pd_date' <> '' THEN :'dam_pd_date' END) WHERE :'dam_pd' <> '') q)));
SELECT CASE WHEN :'dam_f1' = '' THEN '(A3 line 1 omitted: no fresh dam in the local data)' ELSE '' END
    || CASE WHEN :'dup_fuego' = '' THEN ' (A3 line 2 omitted: no duplicated fire number)' ELSE '' END
    || CASE WHEN :'dam_pd' = '' THEN ' (A3 line 4 omitted: tenant 5 has no registered birth with a dam, so no possible_duplicate exists in the data)' ELSE '' END;

-- A4: the historical list
SELECT pg_temp.show('A4a historical births of tenant 5 (first 5; usually empty before any historical entry)', sp_repro_list_historical_births('5', :'admin_email', NULL, NULL, '5', '0'));
SELECT CASE WHEN :'dam_vacia_rfid' = '' THEN pg_temp.skipped('A4b historical births of one dam', 'no VACÍA dam with a SINIIGA tag was found')
            ELSE pg_temp.show('A4b historical births of one dam (the VACÍA dam of A2b)', sp_repro_list_historical_births('5', :'admin_email', :'dam_vacia_rfid')) END;

ROLLBACK;

-- =====================================================================================================================
-- PART B. WRITES INSIDE ONE TRANSACTION THAT ENDS IN ROLLBACK
-- =====================================================================================================================

\echo
\echo '############## PART B - WRITES INSIDE ONE TRANSACTION THAT ENDS IN ROLLBACK ##############'

SELECT pg_temp.counts()::text AS counts_before
\gset
SELECT E'\n=== B0  counts BEFORE (taken outside the transaction)\n' || jsonb_pretty(:'counts_before'::jsonb);

BEGIN;

-- B1: a service of dam f1 inside the gestation window of the birth registered in B2 (birth yesterday, service 283 days earlier)
SELECT CASE WHEN :'dam_f1' = '' THEN pg_temp.skipped('B1  build a service for the dam', 'no fresh dam (active VACA with a SINIIGA tag and no birth / service on record) exists in tenant 5')
            ELSE pg_temp.show('B1  a service of the dam 283 days before the birth of B2 (built here with sp_log_breeding_event; rolled back at the end)',
                 sp_log_breeding_event(:'dam_f1_rfid', 5, fn_repro_today() - 1 - 283, 'MONTA_NATURAL', NULL, NULL, :'admin_email', 'SMOKE phase 4 (rolled back)')) END;

-- B2: a single birth
SELECT CASE WHEN :'dam_f1' = '' THEN pg_temp.skipped('B2  single birth', 'needs the fresh dam of B1')
            ELSE pg_temp.show('B2  sp_repro_register_birth: a single birth (expect status recorded, a calf, and service_link = linked)',
                 sp_repro_register_birth('5', :'admin_email', 'MACHO', NULL, :'dam_f1', to_char(fn_repro_today() - 1, 'YYYY-MM-DD'), '33.5', NULL, NULL, NULL, NULL, 'SMOKE phase 4 (rolled back)', NULL)) END;
-- B3: the exact retry
SELECT CASE WHEN :'dam_f1' = '' THEN pg_temp.skipped('B3  exact retry', 'needs the fresh dam of B1')
            ELSE pg_temp.show('B3  the exact same call again (expect status duplicate_skipped, written 0)',
                 sp_repro_register_birth('5', :'admin_email', 'MACHO', NULL, :'dam_f1', to_char(fn_repro_today() - 1, 'YYYY-MM-DD'), '33.5', NULL, NULL, NULL, NULL, 'SMOKE phase 4 (rolled back)', NULL)) END;
-- B4: same dam, other data, inside the window
SELECT CASE WHEN :'dam_f1' = '' THEN pg_temp.skipped('B4  possible duplicate', 'needs the fresh dam of B1')
            ELSE pg_temp.show('B4  the same dam again with other data inside the window (expect possible_duplicate with the existing birth, nothing inserted)',
                 sp_repro_register_birth('5', :'admin_email', 'HEMBRA', NULL, :'dam_f1', to_char(fn_repro_today(), 'YYYY-MM-DD'), '30', NULL, NULL, NULL, NULL, 'SMOKE phase 4 (rolled back)', NULL)) END;
-- B5: the same with force
SELECT CASE WHEN :'dam_f1' = '' THEN pg_temp.skipped('B5  force', 'needs the fresh dam of B1')
            ELSE pg_temp.show('B5  the same call with force = true (expect status recorded, forced true; a twin / a real second birth)',
                 sp_repro_register_birth('5', :'admin_email', 'HEMBRA', NULL, :'dam_f1', to_char(fn_repro_today(), 'YYYY-MM-DD'), '30', NULL, NULL, NULL, NULL, 'SMOKE phase 4 (rolled back)', 'true')) END;

SELECT CASE WHEN :'dam_f1' = '' THEN '(B2-B5 checks omitted)' ELSE
    pg_temp.expect('the dam has 2 registered births after B2 + B5 (B3 and B4 inserted nothing)', (SELECT count(*) FROM birth_events WHERE dam_id = :'dam_f1'::uuid) = 2) || E'\n' ||
    pg_temp.expect('the dam has 2 calves', (SELECT count(*) FROM cattle_livestock WHERE mother_id = :'dam_f1'::uuid) = 2) || E'\n' ||
    pg_temp.expect('the service of B1 is linked to the FIRST birth (exactly one link)',
        (SELECT count(*) FROM cattle_breeding_events WHERE livestock_id = :'dam_f1'::uuid AND birth_event_id IS NOT NULL) = 1) END;

-- B6: the cap
SELECT pg_temp.show('B6a births_batch_preview with 51 lines (expect code TOO_MANY_ITEMS; the cap is 50)',
    sp_repro_births_batch_preview('5', :'admin_email', (SELECT jsonb_agg(jsonb_build_object('dam_identifier', 'SMOKE-' || g, 'calf_sex', 'MACHO'))::text FROM generate_series(1, 51) g)));
SELECT pg_temp.show('B6b births_batch_register with 51 lines (expect code TOO_MANY_ITEMS and nothing written)',
    sp_repro_births_batch_register('5', :'admin_email', (SELECT jsonb_agg(jsonb_build_object('dam_identifier', 'SMOKE-' || g, 'calf_sex', 'MACHO'))::text FROM generate_series(1, 51) g)));

-- B7: a batch of two lines
SELECT CASE WHEN :'dam_f2' = '' OR :'dam_f3' = '' THEN pg_temp.skipped('B7  batch register of two lines', 'needs two more fresh dams (found fewer than three in total)')
            ELSE pg_temp.show('B7a births_batch_register, two lines (expect status recorded, written 2)',
                 sp_repro_births_batch_register('5', :'admin_email',
                    jsonb_build_array(jsonb_build_object('dam_id', :'dam_f2', 'calf_sex', 'MACHO', 'birth_weight_kg', '34'),
                                      jsonb_build_object('dam_id', :'dam_f3', 'calf_sex', 'HEMBRA', 'birth_weight_kg', '31'))::text,
                    to_char(fn_repro_today() - 1, 'YYYY-MM-DD'))) END;
SELECT CASE WHEN :'dam_f2' = '' OR :'dam_f3' = '' THEN pg_temp.skipped('B7b the same batch again', 'needs the dams of B7a')
            ELSE pg_temp.show('B7b the same batch again (expect every line duplicate_skipped, written 0)',
                 sp_repro_births_batch_register('5', :'admin_email',
                    jsonb_build_array(jsonb_build_object('dam_id', :'dam_f2', 'calf_sex', 'MACHO', 'birth_weight_kg', '34'),
                                      jsonb_build_object('dam_id', :'dam_f3', 'calf_sex', 'HEMBRA', 'birth_weight_kg', '31'))::text,
                    to_char(fn_repro_today() - 1, 'YYYY-MM-DD'))) END;
SELECT CASE WHEN :'dam_f4' = '' OR :'dup_fuego' = '' THEN pg_temp.skipped('B7c a batch with an ambiguous line', 'needs a fourth fresh dam and a duplicated fire number')
            ELSE pg_temp.show('B7c a batch whose second line is ambiguous (expect status rejected, written 0: the good line is NOT written either)',
                 sp_repro_births_batch_register('5', :'admin_email',
                    jsonb_build_array(jsonb_build_object('dam_id', :'dam_f4', 'calf_sex', 'MACHO'),
                                      jsonb_build_object('dam_identifier', :'dup_fuego', 'calf_sex', 'MACHO'))::text)) END;
SELECT CASE WHEN :'dam_f4' = '' THEN '(B7c dam f4 missing)' ELSE pg_temp.expect('B7c wrote nothing for the good line (dam f4 has no birth)', (SELECT count(*) FROM birth_events WHERE dam_id = :'dam_f4'::uuid) = 0) END;

-- B8: a historical birth and its void
SELECT CASE WHEN :'dam_f5' = '' THEN pg_temp.skipped('B8a historical birth', 'needs a fifth fresh dam')
            ELSE pg_temp.show('B8a register_historical_birth: a DAY historical birth 800 days ago (no calf, no status change)',
                 sp_repro_register_historical_birth('5', :'admin_email', NULL, :'dam_f5', to_char(fn_repro_today() - 800, 'YYYY-MM-DD'), 'DAY', 'HEMBRA', NULL, NULL, 'SMOKE phase 4 (rolled back)')) END;
-- the id of the historical birth just registered: read from the idempotent second answer (hidden), then that answer is shown
SELECT coalesce(sp_repro_register_historical_birth('5', :'admin_email', NULL, NULLIF(:'dam_f5', ''), to_char(fn_repro_today() - 800, 'YYYY-MM-DD'), 'DAY', 'HEMBRA', NULL, NULL, 'SMOKE phase 4 (rolled back)')->>'historical_birth_id', '') AS hist_id
\gset
SELECT CASE WHEN :'dam_f5' = '' THEN pg_temp.skipped('B8b idempotency', 'needs the dam of B8a')
            ELSE pg_temp.show('B8b the same historical birth again (expect status duplicate_skipped; the id in it is the one B8c voids)',
                 sp_repro_register_historical_birth('5', :'admin_email', NULL, :'dam_f5', to_char(fn_repro_today() - 800, 'YYYY-MM-DD'), 'DAY', 'HEMBRA', NULL, NULL, 'SMOKE phase 4 (rolled back)')) END;
SELECT CASE WHEN :'dam_f5' = '' THEN pg_temp.skipped('B8c void', 'needs the dam of B8a')
            ELSE pg_temp.show('B8c sp_repro_void_historical_birth (expect status voided)', sp_repro_void_historical_birth('5', :'admin_email', :'hist_id', 'SMOKE phase 4 void (rolled back)')) END;
SELECT CASE WHEN :'dam_f5' = '' THEN pg_temp.skipped('B8d list with voided', 'needs the dam of B8a')
            ELSE pg_temp.show('B8d the dam''s historical births including the voided one (expect voided true)',
                 sp_repro_list_historical_births('5', :'admin_email', (SELECT rfid_siniiga FROM cattle_livestock WHERE id = :'dam_f5'::uuid), 'true')) END;
SELECT CASE WHEN :'dam_f5' = '' THEN '' ELSE
    pg_temp.expect('the dam''s status did not change and no calf was created by the historical birth',
        (SELECT count(*) FROM cattle_livestock WHERE mother_id = :'dam_f5'::uuid) = 0) END;

-- B9: a non-member user and a wrong tenant must RAISE (nothing is printed about who they are)
SELECT pg_temp.attempt('B9a a user who is NOT a member of tenant 5 calls the new tool (expect RAISED sqlstate=P0001)',
    format('SELECT sp_repro_register_birth(%L, %L, ''MACHO'', NULL, %L)', '5', :'nonmember_email', :'dam_f1'));
SELECT pg_temp.attempt('B9b the admin of tenant 5 calls it with a tenant where he/she is not a member (expect RAISED sqlstate=P0001)',
    format('SELECT sp_repro_births_get_config(%L, %L)', :'wrong_tenant', :'admin_email'));
SELECT pg_temp.attempt('B9c a tenant that is not a number (expect RAISED sqlstate=P0001)',
    format('SELECT sp_repro_births_get_config(%L, %L)', '5 OR 1=1', :'admin_email'));
SELECT pg_temp.attempt('B9d the LEGACY sp_register_birth_event with a non-member e-mail (expect RAISED sqlstate=P0001, before anything is written)',
    format('SELECT sp_register_birth_event(5, ''MACHO'', ''BOVINO'', %L::uuid, NULL, NULL, CURRENT_DATE, NULL, NULL, NULL, NULL, NULL, %L)', NULLIF(:'dam_f4', ''), :'nonmember_email'));
SELECT pg_temp.attempt('B9e sp_log_breeding_event with a non-member e-mail (expect RAISED sqlstate=P0001)',
    format('SELECT sp_log_breeding_event(%L, 5, CURRENT_DATE, ''MONTA_NATURAL'', NULL, NULL, %L, NULL)', :'dam_f1_rfid', :'nonmember_email'));

SELECT E'\n=== B10  counts INSIDE the transaction, after all the writes (they must differ from B0)\n' || jsonb_pretty(pg_temp.counts());

ROLLBACK;

-- =====================================================================================================================
-- PROOF: nothing remains
-- =====================================================================================================================

SELECT pg_temp.counts()::text AS counts_after
\gset
SELECT E'\n=== B11  counts AFTER the ROLLBACK\n' || jsonb_pretty(:'counts_after'::jsonb);
SELECT (:'counts_before'::jsonb = :'counts_after'::jsonb) AS counts_equal
\gset
\if :counts_equal
    \echo
    \echo '=== PROOF: every count after the ROLLBACK equals the count before (birth_events, calves, linked services, historical births and voids, weights, statuses). OK'
\else
    \echo
    \echo '!!!!!!!! FAILURE: the counts after the ROLLBACK DIFFER from the counts before. Something was NOT rolled back. Do not use this database until it is understood. !!!!!!!!'
    DO $$ BEGIN RAISE EXCEPTION 'SMOKE FAILED: counts after ROLLBACK differ from counts before'; END $$;
\endif
\echo
\echo '=== END OF SMOKE SCRIPT'
