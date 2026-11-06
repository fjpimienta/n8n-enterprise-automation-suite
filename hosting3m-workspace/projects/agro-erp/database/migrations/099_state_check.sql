-- 099_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back [-v expect_md5_palm=<md5>] -f 099_state_check.sql
--
-- * 099 adds functions only. DATA FINGERPRINTS must be identical before and right after the apply and after a rollback,
--   UNLESS someone registered or edited an animal in between (production is live: if a fingerprint changes, compare the
--   counts by source and the list of rows with metadata->>'migration' = '099' before concluding anything).
-- * UNCHANGED FUNCTIONS: fn_reject_palm_company must keep md5 expect_md5_palm in every state (default: the production
--   value recorded on 2026-11-05, ccf38f121f647bedcb152dd02552f669; the local PG16 copy gives the same value). The other
--   md5 values are printed to be compared between the steps of the SAME environment (PG 15.4 and PG 16 may format
--   pg_get_functiondef differently: never compare them across environments).
-- * Run it in production before the apply (expect=before), after the apply (expect=applied) and after a rollback
--   (expect=rolled_back). Save the outputs in the runbook record.
\set ON_ERROR_STOP on
\if :{?expect_md5_palm}
\else
\set expect_md5_palm 'ccf38f121f647bedcb152dd02552f669'
\endif
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t099.expect', :'expect', false) AS expect,
       set_config('t099.md5_palm', :'expect_md5_palm', false) AS expect_md5_palm;

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
UNION ALL SELECT 'production_unit_lots_data',
       coalesce(md5(string_agg(concat_ws('|', id::text, id_company::text, production_unit_id::text, lot_name, is_active::text), '#' ORDER BY id)), 'empty')
  FROM production_unit_lots
UNION ALL SELECT 'cattle_lifestage_catalog_data',
       coalesce(md5(string_agg(concat_ws('|', especie, categoria_origen, categoria_destino), '#'
                               ORDER BY especie, categoria_origen, categoria_destino)), 'empty')
  FROM cattle_lifestage_catalog
UNION ALL SELECT 'crud_models', md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c;

\echo === ANIMALS BY metadata.source (information)
SELECT coalesce(metadata->>'source', '(null)') AS source, count(*) AS animals,
       count(*) FILTER (WHERE metadata->>'migration' = '099') AS created_by_099
  FROM cattle_livestock GROUP BY 1 ORDER BY 1;

\echo === UNCHANGED FUNCTIONS (099 never touches them)
SELECT 'fn_reject_palm_company' AS function, md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)) AS md5
UNION ALL SELECT 'fn_company_business_domain', md5(pg_get_functiondef('public.fn_company_business_domain(integer)'::regprocedure))
UNION ALL SELECT 'fn_species_requires_bovine_compliance', md5(pg_get_functiondef('public.fn_species_requires_bovine_compliance(character varying)'::regprocedure))
UNION ALL SELECT 'fn_has_official_ear_tag', md5(pg_get_functiondef('public.fn_has_official_ear_tag(character varying)'::regprocedure))
UNION ALL SELECT 'fn_guard_livestock_lot', md5(pg_get_functiondef('public.fn_guard_livestock_lot()'::regprocedure))
UNION ALL SELECT 'fn_guard_livestock_production_unit', md5(pg_get_functiondef('public.fn_guard_livestock_production_unit()'::regprocedure));

\echo === CONSTRAINTS 099 RELIES ON
SELECT conname, contype FROM pg_constraint
 WHERE conrelid = 'public.cattle_livestock'::regclass
   AND conname IN ('cattle_livestock_rfid_siniiga_key', 'cattle_livestock_electronic_rfid_key', 'cattle_livestock_category_check')
 ORDER BY conname;

\echo === 099 OBJECTS
SELECT p.oid::regprocedure::text AS function, md5(pg_get_functiondef(p.oid)) AS md5,
       CASE WHEN p.proname LIKE 'sp\_%' THEN
            NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0)
       END AS public_revoked
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND (p.proname LIKE 'fn\_livestock\_chat\_%' OR p.proname IN ('sp_register_livestock_regularization', 'sp_register_livestock_purchase_chat'))
 ORDER BY 1;

DO $$
DECLARE
    e          text := current_setting('t099.expect');
    v_palm     text := current_setting('t099.md5_palm');
    c_reg      constant text := 'public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)';
    c_buy      constant text := 'public.sp_register_livestock_purchase_chat(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)';
    v_helpers  integer;
    v_tools    integer;
    v_reg_def  text;
    v_buy_def  text;
    v_public   boolean;
BEGIN
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back';
    END IF;

    IF md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)) IS DISTINCT FROM v_palm THEN
        RAISE EXCEPTION 'STATE FAIL (%): fn_reject_palm_company md5 is %, expected %', e,
            md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)), v_palm;
    END IF;
    IF (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.cattle_livestock'::regclass AND contype = 'u'
          AND conname IN ('cattle_livestock_rfid_siniiga_key', 'cattle_livestock_electronic_rfid_key')) <> 2 THEN
        RAISE EXCEPTION 'STATE FAIL (%): the UNIQUE constraints on rfid_siniiga / electronic_rfid are missing', e;
    END IF;

    SELECT count(*) INTO v_helpers FROM pg_proc
     WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'fn\_livestock\_chat\_%';
    v_tools := (to_regprocedure(c_reg) IS NOT NULL)::int + (to_regprocedure(c_buy) IS NOT NULL)::int;

    IF e = 'before' THEN
        IF v_helpers <> 0 OR v_tools <> 0 THEN
            RAISE EXCEPTION 'STATE FAIL (before): 099 objects already exist (helpers=%, tools=%)', v_helpers, v_tools;
        END IF;
        RAISE NOTICE 'STATE OK: before';
        RETURN;
    END IF;

    IF v_helpers <> 17 OR v_tools <> 2 THEN
        RAISE EXCEPTION 'STATE FAIL (%): expected 17 helpers and 2 tools, found % and %', e, v_helpers, v_tools;
    END IF;
    v_reg_def := pg_get_functiondef(c_reg::regprocedure);
    v_buy_def := pg_get_functiondef(c_buy::regprocedure);
    SELECT bool_and(NOT EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a WHERE a.grantee = 0))
      INTO v_public FROM pg_proc p WHERE p.oid IN (c_reg::regprocedure, c_buy::regprocedure);
    IF NOT v_public THEN
        RAISE EXCEPTION 'STATE FAIL (%): PUBLIC can execute a 099 tool function', e;
    END IF;

    IF e = 'applied' THEN
        IF v_reg_def NOT LIKE '%REGULARIZACION_PADRON%' OR v_reg_def LIKE '%''disabled''%'
           OR v_buy_def NOT LIKE '%P0117%' OR v_buy_def LIKE '%''disabled''%' THEN
            RAISE EXCEPTION 'STATE FAIL (applied): a tool function is the rollback stub or incomplete';
        END IF;
    ELSE -- rolled_back
        IF v_reg_def NOT LIKE '%''disabled''%' OR v_buy_def NOT LIKE '%''disabled''%'
           OR v_reg_def LIKE '%REGULARIZACION_PADRON%' OR v_buy_def LIKE '%P0117%' THEN
            RAISE EXCEPTION 'STATE FAIL (rolled_back): the tool functions are not the disabled stubs';
        END IF;
    END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
