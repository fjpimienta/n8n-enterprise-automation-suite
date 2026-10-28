-- 089_state_check.sql — READ-ONLY state assertions for migration 089 (nacimiento gateway model disabled) and its rollback.
-- Runs inside BEGIN READ ONLY ... ROLLBACK: it cannot write anything. Exits non-zero (with ON_ERROR_STOP) when an assertion fails.
--
--   psql ... -v ON_ERROR_STOP=1 -v expect=before      -f 089_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=applied     -f 089_state_check.sql
--   psql ... -v ON_ERROR_STOP=1 -v expect=rolled_back -f 089_state_check.sql
--
-- Re-apply test (LOCAL only): before -> 089 -> applied -> rollback -> rolled_back -> 089 -> applied.
-- FINGERPRINT lines must be identical at every step: crud_models is fingerprinted WITHOUT row 70 (the one row 089 changes; its state is
-- asserted below) and every other table / procedure is untouched. The backup table is NOT in the fingerprints (it is what 089 adds);
-- its row counts are on the BACKUP_ROWS line (they grow by one DISABLE per apply and one RESTORE per rollback, never shrink).

\set ON_ERROR_STOP on
BEGIN READ ONLY;

SELECT set_config('t089.expect', :'expect', false) AS expect;

\echo === FINGERPRINTS (must not change across apply / rollback / re-apply)
SELECT 'crud_models_without_row_70' AS fingerprint, md5(coalesce(string_agg(row_to_json(c)::text, '|' ORDER BY c.id), '')) AS md5 FROM crud_models c WHERE c.id <> 70
UNION ALL
SELECT 'crud_models_row_70_identity', md5(concat_ws('|', c.id::text, c.model_name, c.table_name, c.primary_key::text, c.allowed_fields::text, c.default_filter::text,
                                                    c.created_at::text, c.schema_json::text, c.hooks::text, c.joins::text, c.is_global::text, c.sp_requires_tenant::text))
  FROM crud_models c WHERE c.id = 70
UNION ALL
SELECT 'birth_events_data', md5(string_agg(row_to_json(b)::text, '|' ORDER BY b.id)) FROM birth_events b
UNION ALL
SELECT 'cattle_livestock_data', md5(string_agg(row_to_json(l)::text, '|' ORDER BY l.id)) FROM cattle_livestock l
UNION ALL
SELECT 'user_companies_data', md5(string_agg(concat_ws('|', email, id_company::text, role, is_active::text), '#' ORDER BY email, id_company)) FROM user_companies
UNION ALL
SELECT 'repro_procedures',
       md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text))
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('sp_register_birth_event', 'sp_log_breeding_event', 'sp_void_event', 'sp_log_palpation_event');

\echo === ROW 70 (the only crud_models row 089 changes)
SELECT id, model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete, sp_requires_tenant
  FROM crud_models WHERE id = 70;

\echo === BACKUP_ROWS
DO $$
DECLARE
    n_dis bigint := 0;
    n_res bigint := 0;
BEGIN
    IF to_regclass('public.crud_models_backup_089') IS NULL THEN
        RAISE NOTICE 'BACKUP_ROWS crud_models_backup_089=absent';
    ELSE
        EXECUTE 'SELECT count(*) FILTER (WHERE action = ''DISABLE''), count(*) FILTER (WHERE action = ''RESTORE'') FROM public.crud_models_backup_089' INTO n_dis, n_res;
        RAISE NOTICE 'BACKUP_ROWS disable=% restore=%', n_dis, n_res;
    END IF;
END $$;

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect text := current_setting('t089.expect');
    r        record;
    bk       record;
    v_dis    boolean;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before | applied | rolled_back';
    END IF;
    SELECT * INTO r FROM crud_models WHERE id = 70;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'FAIL: crud_models id 70 does not exist here (nothing for 089 to disable; this is not an error for the migration, but this check expects it)';
    END IF;
    IF r.model_name <> 'nacimiento' OR r.table_name <> 'sp_register_birth_event' THEN
        RAISE EXCEPTION 'FAIL: crud_models id 70 is % / % (expected nacimiento / sp_register_birth_event)', r.model_name, r.table_name;
    END IF;
    IF (SELECT count(*) FROM crud_models WHERE model_name = 'nacimiento') <> 1 THEN
        RAISE EXCEPTION 'FAIL: the nacimiento model must exist exactly once (a missing row would reopen the auto-register path, a second one is a mess)';
    END IF;
    v_dis := cardinality(coalesce(r.allowed_ops, ARRAY[]::text[])) = 0 AND r.allowed_roles_select = 'NONE' AND r.allowed_roles_insert = 'NONE'
             AND r.allowed_roles_update = 'NONE' AND r.allowed_roles_delete = 'NONE';

    IF v_expect = 'applied' THEN
        IF NOT v_dis THEN RAISE EXCEPTION 'FAIL: crud_models id 70 is not disabled (allowed_ops %, insert roles %)', r.allowed_ops, r.allowed_roles_insert; END IF;
        IF to_regclass('public.crud_models_backup_089') IS NULL
           OR NOT EXISTS (SELECT 1 FROM public.crud_models_backup_089 WHERE crud_model_id = 70 AND action = 'DISABLE') THEN
            RAISE EXCEPTION 'FAIL: there is no DISABLE backup of the original row';
        END IF;
        SELECT * INTO bk FROM public.crud_models_backup_089 WHERE crud_model_id = 70 AND action = 'DISABLE' ORDER BY done_at DESC, id LIMIT 1;
        IF (bk.row_data - 'allowed_ops' - 'allowed_roles_select' - 'allowed_roles_insert' - 'allowed_roles_update' - 'allowed_roles_delete')
           IS DISTINCT FROM (to_jsonb(r) - 'allowed_ops' - 'allowed_roles_select' - 'allowed_roles_insert' - 'allowed_roles_update' - 'allowed_roles_delete') THEN
            RAISE EXCEPTION 'FAIL: a column other than the five disabled ones differs from the backup';
        END IF;
        IF bk.row_data->>'allowed_roles_insert' = 'NONE' THEN
            RAISE EXCEPTION 'FAIL: the backup holds an already disabled row, not the original';
        END IF;
    ELSE
        -- before / rolled_back: the row is as in production on 2026-10-28
        IF v_dis THEN RAISE EXCEPTION 'FAIL: crud_models id 70 is still disabled (expected the original row)'; END IF;
        IF r.allowed_roles_insert <> 'ADMIN,EDITOR' OR r.allowed_roles_select <> 'ADMIN' OR r.allowed_roles_update <> 'ADMIN' OR r.allowed_roles_delete <> 'ADMIN'
           OR r.sp_requires_tenant IS NOT TRUE OR cardinality(r.allowed_ops) <> 1 OR lower(r.allowed_ops[1]) <> 'insert' THEN
            RAISE EXCEPTION 'FAIL: crud_models id 70 is not the production original (insert roles %, ops %)', r.allowed_roles_insert, r.allowed_ops;
        END IF;
        IF v_expect = 'rolled_back' THEN
            SELECT * INTO bk FROM public.crud_models_backup_089 WHERE crud_model_id = 70 AND action = 'DISABLE' ORDER BY done_at DESC, id LIMIT 1;
            IF bk.id IS NULL THEN RAISE EXCEPTION 'FAIL: there is no backup in the rolled_back state'; END IF;
            IF to_jsonb(r) IS DISTINCT FROM bk.row_data THEN
                RAISE EXCEPTION 'FAIL: the restored row is not identical to the backed-up original';
            END IF;
        END IF;
    END IF;
    RAISE NOTICE '089 state check (%): OK', v_expect;
END $$;

ROLLBACK;
