-- 072_authorization_expiry_cdmx.sql
-- Business rule: a pending authorization expires at the END of the day it was requested,
-- in Mexico City time (23:59:59 America/Mexico_City), not at the end of the UTC day (18:00 CDMX).
--
-- fecha_solicitud is "timestamp without time zone" holding UTC. Until now both SPs compared
-- fecha_solicitud::date < CURRENT_DATE (UTC dates), so requests made in the morning expired at
-- 18:00 CDMX and requests made between 18:00 and 23:59 CDMX lived for ~30 hours.
--
-- This migration:
--   1. Backs up the current definitions of the affected functions.
--   2. Adds fn_authorization_local_date(timestamp) and fn_authorization_expired(timestamp),
--      the single source of truth for the expiry rule (also used by the v6/Expiración Diaria workflow).
--   3. Rewrites ONLY the expiry check and the expiry message in sp_resolver_autorizacion and
--      sp_cancelar_autorizacion, by exact text replacement of their current definition.
-- Fail-closed: any unexpected function, overload, column type or occurrence count aborts everything.
-- Must run AFTER 071 (works on whatever resolver overload exists, as long as there is exactly one).
--
-- Usage:
--   psql -v ON_ERROR_STOP=1 -v apply=false -d hosting3m_db -f 072_authorization_expiry_cdmx.sql   -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true  -d hosting3m_db -f 072_authorization_expiry_cdmx.sql   -> commit

\set ON_ERROR_STOP on

BEGIN;

-- 0) Preconditions
DO $$
BEGIN
    IF (SELECT data_type FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'pending_authorizations'
           AND column_name = 'fecha_solicitud') IS DISTINCT FROM 'timestamp without time zone' THEN
        RAISE EXCEPTION '072: pending_authorizations.fecha_solicitud is not "timestamp without time zone"';
    END IF;
    IF current_setting('TimeZone') NOT IN ('UTC', 'Etc/UTC') THEN
        RAISE EXCEPTION '072: expected the database TimeZone to be UTC, got %', current_setting('TimeZone');
    END IF;
END $$;

-- 1) Backup of the functions this migration rewrites
CREATE TABLE function_backup_20261010_072 AS
SELECT p.oid::regprocedure::text AS signature,
       pg_get_functiondef(p.oid)  AS definition,
       now()                      AS backed_up_at
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('sp_resolver_autorizacion', 'sp_cancelar_autorizacion');

-- 2) Single source of truth for the expiry rule
CREATE OR REPLACE FUNCTION public.fn_authorization_local_date(p_requested_at timestamp without time zone)
RETURNS date
LANGUAGE sql STABLE
AS $$
    -- p_requested_at is naive UTC; returns the calendar date in Mexico City
    SELECT (p_requested_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date;
$$;

CREATE OR REPLACE FUNCTION public.fn_authorization_expired(p_requested_at timestamp without time zone)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
    -- A request is valid until 23:59:59 (Mexico City) of the day it was made
    SELECT public.fn_authorization_local_date(p_requested_at)
         < (now() AT TIME ZONE 'America/Mexico_City')::date;
$$;

COMMENT ON FUNCTION public.fn_authorization_expired(timestamp without time zone) IS
  'True when a pending authorization requested at p_requested_at (naive UTC) is past 23:59:59 America/Mexico_City of its request day.';

-- 3) Rewrite the expiry check in the two SPs
DO $$
DECLARE
    c_check_old   constant text := 'v_request.fecha_solicitud::date < CURRENT_DATE';
    c_check_new   constant text := 'public.fn_authorization_expired(v_request.fecha_solicitud)';
    c_date_old    constant text := 'v_request.fecha_solicitud::date';
    c_date_new    constant text := 'public.fn_authorization_local_date(v_request.fecha_solicitud)';
    v_unexpected  text;
    v_name        text;
    v_oid         oid;
    v_n           int;
    v_def         text;
BEGIN
    -- No other function may carry the old UTC comparison
    SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_unexpected
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosrc LIKE '%fecha_solicitud::date%'
       AND p.proname NOT IN ('sp_resolver_autorizacion', 'sp_cancelar_autorizacion');
    IF v_unexpected IS NOT NULL THEN
        RAISE EXCEPTION '072: unexpected functions also use fecha_solicitud::date: %', v_unexpected;
    END IF;

    FOREACH v_name IN ARRAY ARRAY['sp_resolver_autorizacion', 'sp_cancelar_autorizacion'] LOOP
        SELECT count(*), min(p.oid) INTO v_n, v_oid
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = v_name;
        IF v_n <> 1 THEN
            RAISE EXCEPTION '072: expected exactly 1 overload of %, found %', v_name, v_n;
        END IF;

        v_def := pg_get_functiondef(v_oid);

        IF (length(v_def) - length(replace(v_def, c_check_old, ''))) / length(c_check_old) <> 1 THEN
            RAISE EXCEPTION '072: % does not contain the expiry check exactly once', v_name;
        END IF;
        IF (length(v_def) - length(replace(v_def, c_date_old, ''))) / length(c_date_old) <> 2 THEN
            RAISE EXCEPTION '072: % does not contain fecha_solicitud::date exactly twice (check + message)', v_name;
        END IF;

        v_def := replace(v_def, c_check_old, c_check_new);
        v_def := replace(v_def, c_date_old,  c_date_new);
        EXECUTE v_def;

        RAISE NOTICE '072: % rewritten (%)', v_name, v_oid::regprocedure;
    END LOOP;

    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.prosrc LIKE '%fecha_solicitud::date%') THEN
        RAISE EXCEPTION '072: fecha_solicitud::date is still present after the rewrite';
    END IF;
END $$;

-- 4) Pure checks (no data is written)
DO $$
BEGIN
    -- 17:45 CDMX on 2026-10-10 is 23:45 UTC the same day
    IF public.fn_authorization_local_date('2026-10-10 23:45') <> DATE '2026-10-10' THEN RAISE EXCEPTION 'C1 failed'; END IF;
    -- 23:59 CDMX on 2026-10-10 is 05:59 UTC on 2026-10-11
    IF public.fn_authorization_local_date('2026-10-11 05:59') <> DATE '2026-10-10' THEN RAISE EXCEPTION 'C2 failed'; END IF;
    -- 00:00 CDMX on 2026-10-11 is 06:00 UTC on 2026-10-11
    IF public.fn_authorization_local_date('2026-10-11 06:00') <> DATE '2026-10-11' THEN RAISE EXCEPTION 'C3 failed'; END IF;
    -- A request made right now is not expired; one made 24 h ago is
    IF public.fn_authorization_expired((now() AT TIME ZONE 'UTC')::timestamp) THEN RAISE EXCEPTION 'C4 failed'; END IF;
    IF NOT public.fn_authorization_expired(((now() - interval '24 hours') AT TIME ZONE 'UTC')::timestamp) THEN RAISE EXCEPTION 'C5 failed'; END IF;
    RAISE NOTICE '072: checks C1-C5 OK';
END $$;

-- 5) What changes for the current pending requests (informational)
SELECT id_company, id, estado,
       to_char(fecha_solicitud AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City', 'YYYY-MM-DD HH24:MI') AS solicitada_cdmx,
       fecha_solicitud::date < CURRENT_DATE              AS vencida_regla_anterior,
       public.fn_authorization_expired(fecha_solicitud)  AS vencida_regla_nueva
FROM pending_authorizations
WHERE estado = 'PENDIENTE'
ORDER BY fecha_solicitud;

\if :apply
COMMIT;
\echo '*** 072 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
