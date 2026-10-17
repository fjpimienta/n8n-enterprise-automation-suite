-- 080_state_check.sql — READ-ONLY state assertions for migration 080 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with
-- ON_ERROR_STOP) when any assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 080_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 080_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 080_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 080 -> applied -> rollback -> rolled_back -> 080 -> applied.
-- The FINGERPRINT lines must be identical at every step: they cover what 080 and its rollback must never
-- touch (every other crud_models row, the untouched columns of PalmTelemetry, companies and memberships).

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t080.expect', :'expect', false) AS expect;

\echo === FINGERPRINTS (must not change across apply / rollback / re-apply)
SELECT 'other_crud_models' AS fingerprint,
       md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5
  FROM crud_models c
 WHERE c.model_name <> 'PalmTelemetry' AND c.model_name NOT LIKE 'agri\_%'
UNION ALL
SELECT 'palmtelemetry_untouched_columns',
       md5(concat_ws('|', c.model_name, c.table_name, c.primary_key, c.allowed_fields::text, c.default_filter,
                     c.schema_json::text, c.hooks::text, c.allowed_roles_select, c.allowed_roles_insert,
                     c.joins::text, c.is_global::text, c.sp_requires_tenant::text))
  FROM crud_models c
 WHERE c.model_name = 'PalmTelemetry'
UNION ALL
SELECT 'companys_data',
       md5(string_agg(concat_ws('|', id_company::text, company_name, industry, is_active::text, metadata::text),
                      '#' ORDER BY id_company))
  FROM companys
UNION ALL
SELECT 'user_companies_data',
       md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company))
  FROM user_companies;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect    text := current_setting('t080.expect');
    v_failures  integer := 0;
    v_models    text[] := ARRAY['agri_variety_catalog', 'agri_plantations', 'agri_lots', 'agri_rows',
                                'agri_row_census_history', 'agri_lot_summary', 'agri_plantation_summary',
                                'agri_set_default_plantation', 'agri_bulk_create_rows', 'agri_record_row_census'];
    v_objects   integer;
    v_n         integer;
    v_palm      record;
    PROCEDURE_CHECK constant text := 'sp_agri_set_default_plantation,sp_agri_bulk_create_rows,sp_agri_record_row_census';
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', v_expect;
    END IF;

    SELECT count(*) INTO v_objects FROM pg_class
     WHERE relnamespace = 'public'::regnamespace
       AND relname IN ('agri_variety_catalog', 'agri_plantations', 'agri_lots', 'agri_rows',
                       'agri_row_census_history', 'vw_agri_lot_summary', 'vw_agri_plantation_summary');
    SELECT * INTO v_palm FROM crud_models WHERE model_name = 'PalmTelemetry';

    IF v_expect = 'before' THEN
        IF v_objects <> 0 THEN
            RAISE WARNING 'FAIL: % agri_* tables/views already exist', v_objects; v_failures := v_failures + 1;
        END IF;
        IF EXISTS (SELECT 1 FROM crud_models WHERE model_name = ANY (v_models)) THEN
            RAISE WARNING 'FAIL: agri_* models already registered'; v_failures := v_failures + 1;
        END IF;
        RAISE NOTICE 'PalmTelemetry before: ops=% update=% delete=%',
            v_palm.allowed_ops, v_palm.allowed_roles_update, v_palm.allowed_roles_delete;
    END IF;

    IF v_expect IN ('applied', 'rolled_back') THEN
        -- The structure always survives a rollback (no DROP).
        IF v_objects <> 7 THEN
            RAISE WARNING 'FAIL: expected 5 tables + 2 views, found %', v_objects; v_failures := v_failures + 1;
        END IF;
        SELECT count(*) INTO v_n FROM pg_trigger WHERE tgname LIKE 'trg_agri_%' AND NOT tgisinternal;
        IF v_n <> 9 THEN RAISE WARNING 'FAIL: expected 9 triggers, found %', v_n; v_failures := v_failures + 1; END IF;
        SELECT count(*) INTO v_n FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace AND proname = ANY (string_to_array(PROCEDURE_CHECK, ','));
        IF v_n <> 3 THEN RAISE WARNING 'FAIL: expected 3 procedures, found %', v_n; v_failures := v_failures + 1; END IF;
        SELECT count(*) INTO v_n FROM agri_variety_catalog
         WHERE variety_code IN ('TENERA', 'DURA', 'HIBRIDO_OXG', 'OTRA_SIN_ESPECIFICAR');
        IF v_n <> 4 THEN RAISE WARNING 'FAIL: variety seed incomplete (%)', v_n; v_failures := v_failures + 1; END IF;
        IF to_regclass('public.crud_models_backup_20261017_080') IS NULL THEN
            RAISE WARNING 'FAIL: crud_models_backup_20261017_080 missing'; v_failures := v_failures + 1;
        END IF;
        IF EXISTS (SELECT 1 FROM crud_models WHERE model_name = ANY (v_models) AND allowed_fields ? 'id') THEN
            RAISE WARNING 'FAIL: an agri_* model exposes id in allowed_fields'; v_failures := v_failures + 1;
        END IF;
    END IF;

    IF v_expect = 'applied' THEN
        SELECT count(*) INTO v_n FROM crud_models WHERE model_name = ANY (v_models) AND cardinality(allowed_ops) > 0;
        IF v_n <> 10 THEN RAISE WARNING 'FAIL: expected 10 enabled agri_* models, found %', v_n; v_failures := v_failures + 1; END IF;
        IF EXISTS (SELECT 1 FROM crud_models WHERE model_name = ANY (v_models) AND 'DELETE' = ANY (allowed_ops)) THEN
            RAISE WARNING 'FAIL: an agri_* model allows DELETE'; v_failures := v_failures + 1;
        END IF;
        IF 'DELETE' = ANY (v_palm.allowed_ops) OR v_palm.allowed_roles_update <> 'ADMIN' OR v_palm.allowed_roles_delete <> 'NONE' THEN
            RAISE WARNING 'FAIL: PalmTelemetry not restricted (ops=% update=% delete=%)',
                v_palm.allowed_ops, v_palm.allowed_roles_update, v_palm.allowed_roles_delete;
            v_failures := v_failures + 1;
        END IF;
    END IF;

    IF v_expect = 'rolled_back' THEN
        SELECT count(*) INTO v_n FROM crud_models
         WHERE model_name = ANY (v_models)
           AND (cardinality(allowed_ops) > 0 OR allowed_roles_select <> 'NONE' OR allowed_roles_insert <> 'NONE'
                OR allowed_roles_update <> 'NONE' OR allowed_roles_delete <> 'NONE');
        IF v_n <> 0 THEN RAISE WARNING 'FAIL: % agri_* model(s) still enabled', v_n; v_failures := v_failures + 1; END IF;
        IF NOT EXISTS (SELECT 1 FROM crud_models_backup_20261017_080 b
                        WHERE b.model_name = 'PalmTelemetry'
                          AND b.allowed_ops = v_palm.allowed_ops
                          AND b.allowed_roles_update IS NOT DISTINCT FROM v_palm.allowed_roles_update
                          AND b.allowed_roles_delete IS NOT DISTINCT FROM v_palm.allowed_roles_delete) THEN
            RAISE WARNING 'FAIL: PalmTelemetry differs from its pre-080 backup'; v_failures := v_failures + 1;
        END IF;
    END IF;

    IF v_failures > 0 THEN
        RAISE EXCEPTION '080 state check (%): % failure(s)', v_expect, v_failures;
    END IF;
    RAISE NOTICE '080 state check (%): OK', v_expect;
END $$;

ROLLBACK;
