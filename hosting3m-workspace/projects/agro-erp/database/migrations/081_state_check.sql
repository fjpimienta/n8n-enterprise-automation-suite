-- 081_state_check.sql — READ-ONLY state assertions for migration 081 and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with
-- ON_ERROR_STOP) when any assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 081_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 081_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 081_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 081 -> applied -> rollback -> rolled_back -> 081 -> applied.
-- The FINGERPRINT lines must be identical at every step: they cover what 081 and its rollback must never
-- touch (every other crud_models row, companies and memberships, the palm structure of 080 and the
-- livestock expenses).

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t081.expect', :'expect', false) AS expect;

\echo === FINGERPRINTS (must not change across apply / rollback / re-apply)
SELECT 'other_crud_models' AS fingerprint,
       md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) AS md5
  FROM crud_models c
 WHERE c.model_name NOT IN ('agri_unit_catalog', 'agri_expense_categories', 'agri_expenses', 'agri_expense_summary',
                            'agri_record_expense', 'agri_void_expense', 'agri_expense_balance')
UNION ALL
SELECT 'companys_data',
       md5(string_agg(concat_ws('|', id_company::text, company_name, industry, is_active::text, metadata::text),
                      '#' ORDER BY id_company))
  FROM companys
UNION ALL
SELECT 'user_companies_data',
       md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company))
  FROM user_companies
UNION ALL
SELECT 'agri_structure_data',
       md5(concat_ws('#',
           (SELECT string_agg(row_to_json(p)::text, '|' ORDER BY p.id) FROM agri_plantations p),
           (SELECT string_agg(row_to_json(l)::text, '|' ORDER BY l.id) FROM agri_lots l),
           (SELECT string_agg(row_to_json(r)::text, '|' ORDER BY r.id) FROM agri_rows r)))
UNION ALL
SELECT 'cattle_expenses_data',
       md5(string_agg(row_to_json(e)::text, '|' ORDER BY e.id))
  FROM cattle_expenses e;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect    text := current_setting('t081.expect');
    v_failures  integer := 0;
    v_models    text[] := ARRAY['agri_unit_catalog', 'agri_expense_categories', 'agri_expenses', 'agri_expense_summary',
                                'agri_record_expense', 'agri_void_expense', 'agri_expense_balance'];
    v_triggers  text[] := ARRAY['trg_agri_plantations_seed_expense_categories', 'trg_agri_expense_categories_guard',
                                'trg_agri_expense_categories_updated_at', 'trg_agri_expenses_guard',
                                'trg_agri_expenses_no_truncate'];
    v_objects   integer;
    v_n         integer;
    v_seed      text;
    v_companies text;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', v_expect;
    END IF;

    SELECT count(*) INTO v_objects FROM pg_class
     WHERE relnamespace = 'public'::regnamespace
       AND relname IN ('agri_unit_catalog', 'agri_expense_categories', 'agri_expenses',
                       'vw_agri_expense_list', 'vw_agri_expense_summary');
    SELECT string_agg(id_company::text, ',' ORDER BY id_company) INTO v_companies
      FROM (SELECT DISTINCT id_company FROM agri_plantations) p;
    RAISE NOTICE 'companies with a plantation: %', coalesce(v_companies, '(none)');

    IF v_expect = 'before' THEN
        IF v_objects <> 0 THEN
            RAISE WARNING 'FAIL: % 081 tables/views already exist', v_objects; v_failures := v_failures + 1;
        END IF;
        IF EXISTS (SELECT 1 FROM crud_models WHERE model_name = ANY (v_models)) THEN
            RAISE WARNING 'FAIL: 081 models already registered'; v_failures := v_failures + 1;
        END IF;
        IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'agri_lots_id_plantation_company_key') THEN
            RAISE WARNING 'FAIL: agri_lots_id_plantation_company_key already exists'; v_failures := v_failures + 1;
        END IF;
    END IF;

    IF v_expect IN ('applied', 'rolled_back') THEN
        -- The structure always survives a rollback (no DROP).
        IF v_objects <> 5 THEN
            RAISE WARNING 'FAIL: expected 3 tables + 2 views, found %', v_objects; v_failures := v_failures + 1;
        END IF;
        SELECT count(*) INTO v_n FROM pg_trigger WHERE tgname = ANY (v_triggers) AND NOT tgisinternal;
        IF v_n <> 5 THEN RAISE WARNING 'FAIL: expected 5 triggers, found %', v_n; v_failures := v_failures + 1; END IF;
        SELECT count(*) INTO v_n FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace
           AND proname IN ('sp_agri_record_expense', 'sp_agri_void_expense', 'sp_agri_expense_balance',
                           'fn_agri_seed_expense_categories', 'fn_company_business_domain');
        IF v_n <> 5 THEN RAISE WARNING 'FAIL: expected 5 functions, found %', v_n; v_failures := v_failures + 1; END IF;
        SELECT count(*) INTO v_n FROM agri_unit_catalog
         WHERE unit_code IN ('KG', 'TON', 'L', 'PZA', 'BULTO', 'JORNAL', 'HA', 'VIAJE', 'SERVICIO');
        IF v_n <> 9 THEN RAISE WARNING 'FAIL: unit seed incomplete (%)', v_n; v_failures := v_failures + 1; END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'agri_lots_id_plantation_company_key') THEN
            RAISE WARNING 'FAIL: agri_lots_id_plantation_company_key missing'; v_failures := v_failures + 1;
        END IF;
        -- Every company with a plantation has its categories (13 seeded unless an ADMIN changed them).
        SELECT string_agg(format('%s=%s', p.id_company,
                                 (SELECT count(*) FROM agri_expense_categories c WHERE c.id_company = p.id_company)),
                          ', ' ORDER BY p.id_company)
          INTO v_seed FROM (SELECT DISTINCT id_company FROM agri_plantations) p;
        RAISE NOTICE 'categories per company with a plantation: %', coalesce(v_seed, '(none)');
        IF EXISTS (SELECT 1 FROM (SELECT DISTINCT id_company FROM agri_plantations) p
                    WHERE NOT EXISTS (SELECT 1 FROM agri_expense_categories c WHERE c.id_company = p.id_company)) THEN
            RAISE WARNING 'FAIL: a company with a plantation has no categories'; v_failures := v_failures + 1;
        END IF;
        IF EXISTS (SELECT 1 FROM agri_expense_categories c
                    WHERE NOT EXISTS (SELECT 1 FROM agri_plantations p WHERE p.id_company = c.id_company)) THEN
            RAISE WARNING 'FAIL: categories exist for a company without a plantation'; v_failures := v_failures + 1;
        END IF;
        IF to_regclass('public.crud_models_backup_20261020_081') IS NULL THEN
            RAISE WARNING 'FAIL: crud_models_backup_20261020_081 missing'; v_failures := v_failures + 1;
        END IF;
        IF EXISTS (SELECT 1 FROM crud_models WHERE model_name = ANY (v_models) AND allowed_fields ? 'id') THEN
            RAISE WARNING 'FAIL: a 081 model exposes id in allowed_fields'; v_failures := v_failures + 1;
        END IF;
    END IF;

    IF v_expect = 'applied' THEN
        SELECT count(*) INTO v_n FROM crud_models WHERE model_name = ANY (v_models) AND cardinality(allowed_ops) > 0;
        IF v_n <> 7 THEN RAISE WARNING 'FAIL: expected 7 enabled models, found %', v_n; v_failures := v_failures + 1; END IF;
        IF EXISTS (SELECT 1 FROM crud_models WHERE model_name = ANY (v_models) AND 'DELETE' = ANY (allowed_ops)) THEN
            RAISE WARNING 'FAIL: a 081 model allows DELETE'; v_failures := v_failures + 1;
        END IF;
        IF EXISTS (SELECT 1 FROM crud_models WHERE model_name IN ('agri_expenses', 'agri_expense_summary')
                    AND (allowed_roles_select <> 'ADMIN,OWNER' OR allowed_ops <> '{SELECT,GETONE,GETALL}')) THEN
            RAISE WARNING 'FAIL: expense amounts must be read-only and ADMIN/OWNER only'; v_failures := v_failures + 1;
        END IF;
        IF EXISTS (SELECT 1 FROM crud_models WHERE model_name = 'agri_unit_catalog'
                    AND (allowed_ops <> '{SELECT,GETONE,GETALL}' OR allowed_roles_insert <> 'NONE' OR allowed_roles_update <> 'NONE')) THEN
            RAISE WARNING 'FAIL: agri_unit_catalog must be read-only'; v_failures := v_failures + 1;
        END IF;
        IF (SELECT tgenabled FROM pg_trigger WHERE tgname = 'trg_agri_plantations_seed_expense_categories') = 'D' THEN
            RAISE WARNING 'FAIL: the seeding trigger is disabled'; v_failures := v_failures + 1;
        END IF;
    END IF;

    IF v_expect = 'rolled_back' THEN
        SELECT count(*) INTO v_n FROM crud_models
         WHERE model_name = ANY (v_models)
           AND (cardinality(allowed_ops) > 0 OR allowed_roles_select <> 'NONE' OR allowed_roles_insert <> 'NONE'
                OR allowed_roles_update <> 'NONE' OR allowed_roles_delete <> 'NONE');
        IF v_n <> 0 THEN RAISE WARNING 'FAIL: % 081 model(s) still enabled', v_n; v_failures := v_failures + 1; END IF;
        IF (SELECT tgenabled FROM pg_trigger WHERE tgname = 'trg_agri_plantations_seed_expense_categories') <> 'D' THEN
            RAISE WARNING 'FAIL: the seeding trigger is still enabled'; v_failures := v_failures + 1;
        END IF;
    END IF;

    IF v_failures > 0 THEN
        RAISE EXCEPTION '081 state check (%): % failure(s)', v_expect, v_failures;
    END IF;
    RAISE NOTICE '081 state check (%): OK', v_expect;
END $$;

ROLLBACK;
