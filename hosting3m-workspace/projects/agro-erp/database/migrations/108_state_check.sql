-- 108_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 108_state_check.sql
--
-- * 108 creates two views and two crud_models rows. The fingerprint of EVERY OTHER crud_models row and the structure of the tables the views read
--   (cattle_health_logs, cattle_livestock, palpation_repro_details, repro_condition_codes, brand_registrations) must be identical in every state.
-- * Save the output of "before", "applied" and "rolled_back" in the runbook record and diff the FINGERPRINT blocks.
-- * Aggregated output only: no animal identifiers, no data of any company.
\set ON_ERROR_STOP on
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t108.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version,
       now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === FINGERPRINTS (the first two blocks must be identical at every step)
SELECT 'other_crud_models' AS fingerprint,
       coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') AS md5
  FROM public.crud_models c
 WHERE c.model_name NOT IN ('vw_palpation_events', 'vw_palpation_herd')
UNION ALL SELECT 'other_crud_models_count', count(*)::text FROM public.crud_models
 WHERE model_name NOT IN ('vw_palpation_events', 'vw_palpation_herd')
UNION ALL SELECT 'source_table_columns', md5(string_agg(table_name || '.' || column_name || ':' || data_type, '|' ORDER BY table_name, ordinal_position))
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name IN ('cattle_health_logs', 'cattle_livestock', 'palpation_repro_details', 'repro_condition_codes', 'brand_registrations')
UNION ALL SELECT 'view vw_palpation_events', coalesce(md5(pg_get_viewdef(to_regclass('public.vw_palpation_events'))), 'absent')
UNION ALL SELECT 'view vw_palpation_herd', coalesce(md5(pg_get_viewdef(to_regclass('public.vw_palpation_herd'))), 'absent')
UNION ALL SELECT 'model_rows', coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'absent')
  FROM (SELECT model_name, table_name, primary_key, allowed_fields, default_filter, schema_json, allowed_ops, hooks, allowed_roles_select,
               allowed_roles_insert, allowed_roles_update, allowed_roles_delete, joins, is_global, sp_requires_tenant
          FROM public.crud_models WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')) c;

\echo === THE TWO ROWS (information)
SELECT model_name, table_name, primary_key, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete,
       is_global, sp_requires_tenant, (allowed_fields ? 'id_company') AS has_id_company, (allowed_fields ? 'created_at') AS has_created_at
  FROM public.crud_models
 WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')
 ORDER BY model_name;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect text := current_setting('t108.expect');
    v_views  integer := (CASE WHEN to_regclass('public.vw_palpation_events') IS NULL THEN 0 ELSE 1 END)
                      + (CASE WHEN to_regclass('public.vw_palpation_herd') IS NULL THEN 0 ELSE 1 END);
    v_rows   integer;
    v_on     integer;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', v_expect;
    END IF;
    IF to_regclass('public.palpation_repro_details') IS NULL OR to_regclass('public.repro_condition_codes') IS NULL
       OR to_regclass('public.brand_registrations') IS NULL THEN
        RAISE EXCEPTION 'FAIL: 086 / 028 objects are missing - 108 needs them in every state';
    END IF;
    SELECT count(*) INTO v_rows FROM public.crud_models
     WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd') OR table_name IN ('vw_palpation_events', 'vw_palpation_herd');

    IF v_expect = 'before' THEN
        IF v_views <> 0 OR v_rows <> 0 THEN
            RAISE EXCEPTION 'FAIL: expected no view and no model before 108, found % view(s) and % row(s). Review them before applying.', v_views, v_rows;
        END IF;
    ELSE
        IF v_views <> 2 THEN RAISE EXCEPTION 'FAIL: expected both views, found %', v_views; END IF;
        IF v_rows <> 2 THEN RAISE EXCEPTION 'FAIL: expected exactly the two model rows, found %', v_rows; END IF;
        -- id_company and created_at must be in allowed_fields in every state: without id_company the gateway does not filter by company.
        IF EXISTS (SELECT 1 FROM public.crud_models WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')
                    AND (NOT (allowed_fields ? 'id_company') OR NOT (allowed_fields ? 'created_at'))) THEN
            RAISE EXCEPTION 'FAIL: id_company or created_at is missing from allowed_fields of a palpation model';
        END IF;
        SELECT count(*) INTO v_on FROM public.crud_models
         WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')
           AND allowed_ops = '{SELECT}' AND allowed_roles_select = 'ADMIN,EDITOR' AND allowed_roles_insert = 'NONE'
           AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE' AND joins = '[]'::jsonb
           AND is_global = false AND sp_requires_tenant = true AND default_filter IS NULL;
        IF v_expect = 'applied' AND v_on <> 2 THEN
            RAISE EXCEPTION 'FAIL: the two models do not have the expected applied configuration (matching: %)', v_on;
        END IF;
        IF v_expect = 'rolled_back' THEN
            SELECT count(*) INTO v_on FROM public.crud_models
             WHERE model_name IN ('vw_palpation_events', 'vw_palpation_herd')
               AND allowed_ops = '{}' AND allowed_roles_select = 'NONE' AND allowed_roles_insert = 'NONE'
               AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE';
            IF v_on <> 2 THEN RAISE EXCEPTION 'FAIL: the two models are not disabled (disabled: %)', v_on; END IF;
        END IF;
    END IF;
    RAISE NOTICE '108 state check OK (expect=%)', v_expect;
END $$;

\if :{?embedded}
\else
ROLLBACK;
\endif
