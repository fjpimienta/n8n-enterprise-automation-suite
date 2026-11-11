-- 101_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -f 101_state_check.sql                                   -> report only
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 101_state_check.sql   -> also assert
--
-- 101 is "applied" when public.vw_cattle_event_log has the 'REGULARIZACION' branch.
-- 101 is "before" / "rolled_back" when it has no such branch AND its whitespace-normalized definition is the 067 one
-- (md5 726fdf2e20ca6848deb0b1d7cfef66b9, PostgreSQL 15.4 deparse). Anything else (view missing, no branch but another
-- definition) is reported as PARTIAL.
-- The COLUMNS FINGERPRINT (names + types of the 18 columns) must be IDENTICAL in every state: 101 changes no column.
-- md5 values are meant to be compared between steps of the SAME environment.
\set ON_ERROR_STOP on
\if :{?expect}
\else
\set expect none
\endif
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t101.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version,
       now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === VIEW COLUMNS FINGERPRINT (identical before and after)
SELECT count(*) AS columns,
       md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)) AS columns_md5
  FROM pg_attribute a
 WHERE a.attrelid = to_regclass('public.vw_cattle_event_log') AND a.attnum > 0 AND NOT a.attisdropped;

\echo === VIEW DEFINITION
SELECT to_regclass('public.vw_cattle_event_log') IS NOT NULL AS view_exists,
       md5(regexp_replace(pg_get_viewdef(to_regclass('public.vw_cattle_event_log'), true), '\s+', ' ', 'g')) AS normalized_viewdef_md5,
       coalesce(pg_get_viewdef(to_regclass('public.vw_cattle_event_log'), true) LIKE '%''REGULARIZACION''::text AS event_type%', false) AS has_branch;

\echo === REGULARIZATION ANIMALS (counts only)
SELECT (SELECT count(*) FROM public.cattle_livestock WHERE metadata->>'source' = 'REGULARIZACION_PADRON') AS animals_regularizacion_padron,
       (SELECT count(*) FROM public.vw_cattle_event_log WHERE event_type = 'REGULARIZACION') AS rows_in_view;

DO $$
DECLARE
    e       text := current_setting('t101.expect');
    v_def   text;
    v_state text;
BEGIN
    IF e NOT IN ('none', 'before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back';
    END IF;
    IF to_regclass('public.vw_cattle_event_log') IS NULL THEN
        v_state := 'PARTIAL';
    ELSE
        v_def := pg_get_viewdef('public.vw_cattle_event_log'::regclass, true);
        v_state := CASE
            WHEN v_def LIKE '%''REGULARIZACION''::text AS event_type%' THEN 'APPLIED'
            WHEN md5(regexp_replace(v_def, '\s+', ' ', 'g')) = '726fdf2e20ca6848deb0b1d7cfef66b9' THEN 'BEFORE'
            ELSE 'PARTIAL' END;
    END IF;
    RAISE NOTICE '101 STATE: %', v_state;
    IF e = 'none' THEN RETURN; END IF;
    IF v_state = 'PARTIAL' THEN
        RAISE EXCEPTION 'STATE FAIL (%): state is PARTIAL', e;
    END IF;
    IF e = 'applied' AND v_state <> 'APPLIED' THEN
        RAISE EXCEPTION 'STATE FAIL (applied): 101 is not applied';
    END IF;
    IF e IN ('before', 'rolled_back') AND v_state <> 'BEFORE' THEN
        RAISE EXCEPTION 'STATE FAIL (%): 101 is applied', e;
    END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
