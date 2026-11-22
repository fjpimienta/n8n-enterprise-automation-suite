-- 109 ROLLBACK. No DROP, no DELETE, no TRUNCATE: the three functions are REPLACED by a fail-closed stub with the same signatures, so any
-- later object that already calls them keeps working and always receives role UNKNOWN, reason DISABLED. Tables and data are untouched.
-- Re-applying 109_cfdi_role_classifier.sql restores the classifier.
--
-- Usage (dry run is the default):
--   psql -X -v ON_ERROR_STOP=1 -f 109_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 109_rollback.sql  -> commit
-- Then: 109_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

DO $$
BEGIN
    IF to_regprocedure('public.sp_cfdi_classify(text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_cfdi_classify not found - 109 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
BEGIN
    RETURN jsonb_build_object('role', 'UNKNOWN', 'reason', 'DISABLED', 'emisor_inactive_match', false,
                              'receptor_inactive_match', false, 'own_set_empty', NULL, 'company_domain', NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role(p_co integer, p_emisor text, p_receptor text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $$ SELECT public.fn_classify_cfdi_role_detail(p_co, p_emisor, p_receptor) ->> 'role' $$;

CREATE OR REPLACE FUNCTION public.sp_cfdi_classify(p_tenant_id text, p_user_email text, p_emisor text, p_receptor text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    RETURN jsonb_build_object('role', 'UNKNOWN', 'reason', 'DISABLED');
END;
$$;

REVOKE ALL ON FUNCTION public.fn_classify_cfdi_role_detail(integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_classify_cfdi_role(integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sp_cfdi_classify(text, text, text, text) FROM PUBLIC;

DO $$
BEGIN
    IF public.sp_cfdi_classify('0', 'x', 'x', 'x') ->> 'reason' IS DISTINCT FROM 'DISABLED' THEN
        RAISE EXCEPTION '109 rollback: the stub is not in place';
    END IF;
    RAISE NOTICE '109 rollback: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 109 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 109 rollback rolled back ***'
\endif
\endif
