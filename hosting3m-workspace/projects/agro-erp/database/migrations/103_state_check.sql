-- 103_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied -f 103_state_check.sql
--
-- * 103 adds ONE crud_models row. The fingerprint of every OTHER crud_models row must be identical in every state.
-- * Prints the current allowed_roles_insert of the direct cattle_livestock model for comparison (103 grants ADMIN,EDITOR only).
-- * Save the outputs of "before" and "applied" in the runbook record and diff them: only the model row and the check time change.
\set ON_ERROR_STOP on
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t103.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version,
       now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === FINGERPRINTS (identical at every step)
SELECT 'other_crud_models' AS fingerprint,
       coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') AS md5
  FROM crud_models c WHERE c.model_name <> 'register_livestock_panel'
UNION ALL SELECT 'other_crud_models_count', count(*)::text FROM crud_models WHERE model_name <> 'register_livestock_panel'
UNION ALL SELECT 'sp_register_livestock_panel_md5',
       coalesce((SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p
                  WHERE p.oid = to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)')), 'missing');

\echo === THE MODEL ROW (information)
SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_roles_insert, allowed_roles_update,
       allowed_roles_delete, is_global, sp_requires_tenant, jsonb_array_length(allowed_fields) AS n_fields
  FROM crud_models WHERE model_name = 'register_livestock_panel';

\echo === DIRECT cattle_livestock MODEL, FOR COMPARISON (information)
SELECT model_name, allowed_ops, allowed_roles_insert FROM crud_models WHERE model_name = 'cattle_livestock';

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect text := current_setting('t103.expect');
    v_fn     boolean := to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NOT NULL;
    v_rows   integer;
BEGIN
    IF v_expect NOT IN ('before', 'applied') THEN
        RAISE EXCEPTION 'expect must be before or applied (got %)', v_expect;
    END IF;
    IF NOT v_fn THEN
        RAISE EXCEPTION 'FAIL: sp_register_livestock_panel (migration 102) is missing - 103 needs it in every state';
    END IF;
    SELECT count(*) INTO v_rows FROM crud_models WHERE model_name = 'register_livestock_panel';
    IF v_expect = 'before' THEN
        IF v_rows <> 0 THEN RAISE EXCEPTION 'FAIL: expected no register_livestock_panel model, found %', v_rows; END IF;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM crud_models
                        WHERE model_name = 'register_livestock_panel' AND table_name = 'sp_register_livestock_panel'
                          AND allowed_ops = '{INSERT}' AND allowed_roles_insert = 'ADMIN,EDITOR'
                          AND allowed_roles_select = 'NONE' AND allowed_roles_update = 'NONE' AND allowed_roles_delete = 'NONE'
                          AND is_global = false AND sp_requires_tenant = true AND jsonb_array_length(allowed_fields) = 18
                          AND NOT (allowed_fields ? 'id') AND NOT (allowed_fields ? 'tenant_id') AND NOT (allowed_fields ? 'id_company')) THEN
            RAISE EXCEPTION 'FAIL: the register_livestock_panel row is missing or has other values';
        END IF;
    END IF;
    RAISE NOTICE 'STATE OK: %', v_expect;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
