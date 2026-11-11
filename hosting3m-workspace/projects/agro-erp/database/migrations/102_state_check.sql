-- 102_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied [-v expect_md5_palm=<md5>] -f 102_state_check.sql
--
-- * 102 adds ONE function. DATA FINGERPRINTS must be identical before and right after the apply and after a rollback,
--   UNLESS someone registered or edited an animal in between (production is live: if a fingerprint changes, list the rows
--   with metadata->>'migration' = '102' and compare the counts by source before concluding anything).
-- * UNCHANGED FUNCTIONS: the 099/100 functions and the palm guard must have the same md5 in every state of the SAME
--   environment (never compare md5 values across environments: PG 15 and PG 16 may format pg_get_functiondef differently).
--   fn_reject_palm_company must keep md5 expect_md5_palm (default: the production value recorded on 2026-11-05).
-- * The columns 102 needs to accept NULL (weight, production unit, tags, dates) are printed and checked here.
-- * Run it in production before the apply (expect=before) and after it (expect=applied). Save the outputs in the runbook record.
\set ON_ERROR_STOP on
\if :{?expect_md5_palm}
\else
\set expect_md5_palm 'ccf38f121f647bedcb152dd02552f669'
\endif
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t102.expect', :'expect', false) AS expect,
       set_config('t102.md5_palm', :'expect_md5_palm', false) AS expect_md5_palm;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version,
       now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === DATA FINGERPRINTS (identical at every step unless the data changed in between)
SELECT 'cattle_livestock_data' AS fingerprint,
       coalesce(md5(string_agg(concat_ws('|', id::text, tenant_id::text, current_status, category, coalesce(species, '~'),
                                         coalesce(rfid_siniiga, '~'), coalesce(electronic_rfid, '~'), coalesce(numero_fuego, '~'),
                                         coalesce(production_unit_id::text, '~'), coalesce(lot_id::text, '~'),
                                         md5(coalesce(metadata::text, '~'))), '#' ORDER BY id)), 'empty') AS md5
  FROM cattle_livestock
UNION ALL SELECT 'cattle_livestock_count', count(*)::text FROM cattle_livestock
UNION ALL SELECT 'production_units_data',
       coalesce(md5(string_agg(concat_ws('|', id::text, id_company::text, upp_code, ranch_name, is_active::text), '#' ORDER BY id)), 'empty')
  FROM production_units
UNION ALL SELECT 'crud_models', md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c;

\echo === ANIMALS BY metadata.source (information)
SELECT coalesce(metadata->>'source', '(null)') AS source, count(*) AS animals,
       count(*) FILTER (WHERE metadata->>'migration' = '102') AS created_by_102
  FROM cattle_livestock GROUP BY 1 ORDER BY 1;

\echo === COLUMNS 102 NEEDS TO ACCEPT NULL (is_nullable must be YES)
SELECT column_name, data_type, character_maximum_length, is_nullable
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'cattle_livestock'
   AND column_name IN ('rfid_siniiga', 'electronic_rfid', 'numero_fuego', 'current_weight_kg', 'production_unit_id', 'lot_id',
                       'upp_origen', 'tb_test_date', 'br_test_date')
 ORDER BY column_name;

\echo === CONSTRAINTS 102 RELIES ON
SELECT conname, contype FROM pg_constraint
 WHERE conrelid = 'public.cattle_livestock'::regclass
   AND conname IN ('cattle_livestock_rfid_siniiga_key', 'cattle_livestock_electronic_rfid_key', 'cattle_livestock_category_check')
 ORDER BY conname;

\echo === UNCHANGED FUNCTIONS (102 never touches them)
SELECT p.oid::regprocedure::text AS function, md5(pg_get_functiondef(p.oid)) AS md5
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND (p.proname LIKE 'fn\_livestock\_chat\_%'
        OR p.proname IN ('sp_register_livestock_regularization', 'sp_register_livestock_purchase_chat', 'fn_reject_palm_company',
                         'fn_species_requires_bovine_compliance', 'fn_has_official_ear_tag', 'fn_is_herd_free',
                         'sp_procesar_salida_ganado'))
 ORDER BY 1;

\echo === 102 OBJECTS
SELECT p.oid::regprocedure::text AS function, md5(pg_get_functiondef(p.oid)) AS md5,
       NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0) AS public_revoked
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'sp_register_livestock_panel';

DO $$
DECLARE
    e         text := current_setting('t102.expect');
    v_palm    text := current_setting('t102.md5_palm');
    c_panel   constant text := 'public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)';
    v_n       integer;
    v_def     text;
    v_public  boolean;
    v_bad     text;
BEGIN
    IF e NOT IN ('before', 'applied') THEN
        RAISE EXCEPTION 'expect must be before or applied';
    END IF;
    IF md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)) IS DISTINCT FROM v_palm THEN
        RAISE EXCEPTION 'STATE FAIL (%): fn_reject_palm_company md5 is %, expected %', e,
            md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)), v_palm;
    END IF;
    IF (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.cattle_livestock'::regclass AND contype = 'u'
          AND conname IN ('cattle_livestock_rfid_siniiga_key', 'cattle_livestock_electronic_rfid_key')) <> 2 THEN
        RAISE EXCEPTION 'STATE FAIL (%): the UNIQUE constraints on rfid_siniiga / electronic_rfid are missing', e;
    END IF;
    SELECT string_agg(ic.column_name, ', ') INTO v_bad
      FROM information_schema.columns ic
     WHERE ic.table_schema = 'public' AND ic.table_name = 'cattle_livestock' AND ic.is_nullable = 'NO'
       AND ic.column_name IN ('rfid_siniiga', 'electronic_rfid', 'numero_fuego', 'current_weight_kg', 'production_unit_id',
                              'lot_id', 'upp_origen', 'tb_test_date', 'br_test_date');
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'STATE FAIL (%): columns that must accept NULL are NOT NULL: %', e, v_bad;
    END IF;
    IF (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'fn\_livestock\_chat\_%') < 17 THEN
        RAISE EXCEPTION 'STATE FAIL (%): the 099 helpers are missing', e;
    END IF;

    SELECT count(*) INTO v_n FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'sp_register_livestock_panel';
    IF e = 'before' THEN
        IF v_n <> 0 THEN
            RAISE EXCEPTION 'STATE FAIL (before): sp_register_livestock_panel already exists';
        END IF;
        RAISE NOTICE 'STATE OK: before';
        RETURN;
    END IF;

    IF v_n <> 1 OR to_regprocedure(c_panel) IS NULL THEN
        RAISE EXCEPTION 'STATE FAIL (applied): expected exactly one sp_register_livestock_panel with the 19-parameter signature, found %', v_n;
    END IF;
    v_def := pg_get_functiondef(c_panel::regprocedure);
    IF v_def NOT LIKE '%PANEL_ALTA%' OR v_def NOT LIKE '%''102''%' THEN
        RAISE EXCEPTION 'STATE FAIL (applied): the function body is not the 102 one';
    END IF;
    SELECT NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0)
      INTO v_public FROM pg_proc p WHERE p.oid = c_panel::regprocedure;
    IF NOT v_public THEN
        RAISE EXCEPTION 'STATE FAIL (applied): PUBLIC can execute sp_register_livestock_panel';
    END IF;
    RAISE NOTICE 'STATE OK: applied';
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
