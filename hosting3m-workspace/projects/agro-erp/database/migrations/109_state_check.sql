-- 109_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK). Prints fingerprints and privilege status; never an RFC value and no table content.
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 109_state_check.sql
-- Save the output of "before", "applied" and "rolled_back" in the runbook record and compare the FINGERPRINTS block.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t109.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version;

\echo === FUNCTION FINGERPRINTS (md5 of pg_get_functiondef; NULL = function absent)
SELECT s.name,
       md5(pg_get_functiondef(to_regprocedure(s.sig))) AS md5
  FROM (VALUES ('fn_classify_cfdi_role_detail', 'public.fn_classify_cfdi_role_detail(integer,text,text)'),
               ('fn_classify_cfdi_role',        'public.fn_classify_cfdi_role(integer,text,text)'),
               ('sp_cfdi_classify',             'public.sp_cfdi_classify(text,text,text,text)')) AS s(name, sig)
 ORDER BY s.name;

\echo === PRIVILEGES (expected: PUBLIC cannot execute any; the workflow role is a superuser)
SELECT s.name,
       CASE WHEN to_regprocedure(s.sig) IS NULL THEN NULL ELSE has_function_privilege('public', to_regprocedure(s.sig), 'EXECUTE') END AS public_can_execute,
       CASE WHEN to_regprocedure(s.sig) IS NULL THEN NULL ELSE has_function_privilege(current_user, to_regprocedure(s.sig), 'EXECUTE') END AS current_user_can_execute,
       CASE WHEN to_regprocedure(s.sig) IS NULL THEN NULL ELSE (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = to_regprocedure(s.sig)) END AS security_definer
  FROM (VALUES ('fn_classify_cfdi_role_detail', 'public.fn_classify_cfdi_role_detail(integer,text,text)'),
               ('fn_classify_cfdi_role',        'public.fn_classify_cfdi_role(integer,text,text)'),
               ('sp_cfdi_classify',             'public.sp_cfdi_classify(text,text,text,text)')) AS s(name, sig)
 ORDER BY s.name;

\echo === GATEWAY (must be 0: not registered in crud_models)
SELECT count(*) AS classifier_models_in_crud_models
  FROM public.crud_models WHERE table_name ~* 'classify|cfdi_role' OR model_name ~* 'classify|cfdi_role';

\echo === VERDICT
DO $$
DECLARE
    v_expect  text := current_setting('t109.expect');
    v_n       integer := (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
                           AND proname IN ('fn_classify_cfdi_role_detail', 'fn_classify_cfdi_role', 'sp_cfdi_classify'));
    v_stub    boolean;
    v_state   text;
BEGIN
    IF v_n = 0 THEN
        v_state := 'before';
    ELSIF v_n <> 3 THEN
        v_state := 'partial';
    ELSE
        v_stub := (SELECT prosrc LIKE '%DISABLED%' FROM pg_proc WHERE oid = 'public.sp_cfdi_classify(text,text,text,text)'::regprocedure);
        v_state := CASE WHEN v_stub THEN 'rolled_back' ELSE 'applied' END;
        IF has_function_privilege('public', 'public.fn_classify_cfdi_role_detail(integer,text,text)', 'EXECUTE')
           OR has_function_privilege('public', 'public.fn_classify_cfdi_role(integer,text,text)', 'EXECUTE')
           OR has_function_privilege('public', 'public.sp_cfdi_classify(text,text,text,text)', 'EXECUTE') THEN
            RAISE EXCEPTION 'STATE CHECK FAILED: PUBLIC can execute a classifier function';
        END IF;
    END IF;
    IF v_state IS DISTINCT FROM v_expect THEN
        RAISE EXCEPTION 'STATE CHECK FAILED: expected %, found %', v_expect, v_state;
    END IF;
    RAISE NOTICE 'STATE OK: %', v_state;
END $$;
ROLLBACK;
