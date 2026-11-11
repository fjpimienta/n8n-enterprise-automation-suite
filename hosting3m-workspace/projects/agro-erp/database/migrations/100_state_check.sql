-- 100_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -f 100_state_check.sql                          -> report only
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 100_state_check.sql   -> also assert
--
-- 100 is "applied" when the helper public.fn_livestock_chat_folio(text) exists AND the regularization tool uses it.
-- 100 is "before" / "rolled_back" when the helper does not exist and the tool is the 099 version (it uses
-- fn_livestock_chat_txt(p_guide_folio)). Any mix (helper without the tool using it, or the reverse) is reported as PARTIAL.
-- 100 changes no data: the DATA FINGERPRINT must be identical in every state unless someone edited animals in between.
-- md5 values are meant to be compared between steps of the SAME environment (never across PostgreSQL versions).
\set ON_ERROR_STOP on
\if :{?expect}
\else
\set expect none
\endif
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t100.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version,
       now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === DATA FINGERPRINT (identical at every step unless animals changed in between)
SELECT 'cattle_livestock_count' AS fingerprint, count(*)::text AS value FROM cattle_livestock
UNION ALL SELECT 'cattle_livestock_data',
       coalesce(md5(string_agg(concat_ws('|', id::text, tenant_id::text, current_status, category,
                                         coalesce(rfid_siniiga, '~'), md5(coalesce(metadata::text, '~'))), '#' ORDER BY id)), 'empty')
  FROM cattle_livestock;

\echo === 100 OBJECTS
SELECT p.oid::regprocedure::text AS function, md5(pg_get_functiondef(p.oid)) AS md5
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('fn_livestock_chat_folio', 'sp_register_livestock_regularization')
 ORDER BY 1;

\echo === STATE
SELECT to_regprocedure('public.fn_livestock_chat_folio(text)') IS NOT NULL AS helper_exists,
       coalesce(pg_get_functiondef(to_regprocedure('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)')) LIKE '%fn_livestock_chat_folio(p_guide_folio)%', false) AS tool_uses_helper,
       to_regprocedure('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NOT NULL AS tool_exists;

DO $$
DECLARE
    e         text := current_setting('t100.expect');
    c_reg     constant text := 'public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)';
    v_helper  boolean := to_regprocedure('public.fn_livestock_chat_folio(text)') IS NOT NULL;
    v_uses    boolean := false;
    v_099     boolean := false;
    v_state   text;
BEGIN
    IF e NOT IN ('none', 'before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back';
    END IF;
    IF to_regprocedure(c_reg) IS NULL THEN
        v_state := 'NO_099';
    ELSE
        v_uses := pg_get_functiondef(c_reg::regprocedure) LIKE '%fn_livestock_chat_folio(p_guide_folio)%';
        v_099  := pg_get_functiondef(c_reg::regprocedure) LIKE '%fn_livestock_chat_txt(p_guide_folio)%';
        v_state := CASE WHEN v_helper AND v_uses THEN 'APPLIED'
                        WHEN NOT v_helper AND v_099 THEN 'NOT_APPLIED'
                        ELSE 'PARTIAL' END;
    END IF;
    RAISE NOTICE '100 STATE: % (helper_exists=%, tool_uses_helper=%)', v_state, v_helper, v_uses;
    IF e = 'none' THEN
        RETURN;
    END IF;
    IF v_state IN ('NO_099', 'PARTIAL') THEN
        RAISE EXCEPTION 'STATE FAIL (%): state is %', e, v_state;
    END IF;
    IF e = 'applied' AND v_state <> 'APPLIED' THEN
        RAISE EXCEPTION 'STATE FAIL (applied): 100 is not applied';
    END IF;
    IF e IN ('before', 'rolled_back') AND v_state <> 'NOT_APPLIED' THEN
        RAISE EXCEPTION 'STATE FAIL (%): 100 is applied', e;
    END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
