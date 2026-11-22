-- 109_cfdi_role_classifier.sql
-- Classify a CFDI voucher as a SALE or an EXPENSE of a company by the RFC role (issuer / receptor). Pure, read-only, no logging.
-- Database layer only: no n8n change, no frontend, no cfdi-service change, no crud_models row. Nothing existing is altered or dropped
-- (091 / 092 / 093 / 104 procedures are untouched). Later pull requests consume it (the expense gate and the n8n router).
-- REQUIRES 080 (fn_agri_actor_role, fn_company_business_domain), 091 (company_tax_ids) and 104 (company_issuer_rfcs). Aborts if missing.
--
-- "Own RFC set" of a company = ACTIVE rows of company_tax_ids UNION ACTIVE rows of company_issuer_rfcs of THAT company, applied to
-- BOTH sides (issuer and receptor). Deactivated RFCs are not part of the set and are never reactivated here. companys.metadata is not read.
-- company_flags.is_test does not change the classification.
--
--   issuer own, receptor not          -> SALE
--   receptor own, issuer not          -> EXPENSE
--   both own                          -> AMBIGUOUS (SELF_INVOICE when both RFCs are equal, otherwise BOTH_ROLES)
--   neither                           -> UNKNOWN   (NEITHER)
--   null company, missing / inactive company, RFC null or not matching ^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$ after upper(btrim())
--                                     -> UNKNOWN   (INVALID_INPUT)
--   sp_cfdi_classify only: not an active member of an active company, or ambiguous tenant -> UNKNOWN (FORBIDDEN)
--
-- Objects
--   fn_classify_cfdi_role_detail(integer, text, text) -> jsonb  role, reason, emisor_inactive_match, receptor_inactive_match,
--                                                                own_set_empty, company_domain. Booleans and codes only: never an RFC.
--   fn_classify_cfdi_role(integer, text, text)        -> text   the role only.
--   sp_cfdi_classify(text, text, text, text)          -> jsonb  tenant + user e-mail + RFCs. The ONLY entry point for n8n.
--
-- SECURITY: the two fn_* functions take a free company id. Exposed, they would answer which RFCs belong to which company, so they are
-- revoked from PUBLIC and are NOT in crud_models (the CRUD gateway cannot reach them). sp_cfdi_classify validates the active membership of
-- the user first (fail-closed), then calls them; it is SECURITY DEFINER with a fixed search_path so it keeps working even if the workflow
-- role loses its superuser status.
-- DEPENDENCY: relies on n8n_user being a PostgreSQL superuser, like 099 / 102: the functions are revoked from PUBLIC and no GRANT is
-- issued (see the suite CLAUDE.md). If that role ever stops being a superuser, add an explicit
-- GRANT EXECUTE ON FUNCTION public.sp_cfdi_classify(text, text, text, text) TO <workflow role> (only that function).
--
-- Rollback: 109_rollback.sql replaces the three functions with a fail-closed stub (UNKNOWN / DISABLED); nothing is dropped.
-- State:    109_state_check.sql. Tests: 109_tests.sql (LOCAL / throw-away database only).
-- Usage:    psql -X -v ON_ERROR_STOP=1 -f 109_cfdi_role_classifier.sql                (dry run: ROLLBACK)
--           psql -X -v ON_ERROR_STOP=1 -v apply=true -f 109_cfdi_role_classifier.sql  (COMMIT)

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
    IF to_regprocedure('public.fn_agri_actor_role(integer,text)') IS NULL
       OR to_regprocedure('public.fn_company_business_domain(integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 080 is not applied here (fn_agri_actor_role / fn_company_business_domain missing).';
    END IF;
    IF to_regclass('public.companys') IS NULL OR to_regclass('public.company_tax_ids') IS NULL
       OR to_regclass('public.company_issuer_rfcs') IS NULL THEN
        RAISE EXCEPTION 'ABORT: companys / company_tax_ids (091) / company_issuer_rfcs (104) are missing.';
    END IF;
END $$;

-- 1) Detail (the single implementation of the truth table) -----------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role_detail(p_co integer, p_emisor text, p_receptor text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_e         text := upper(btrim(p_emisor));
    v_r         text := upper(btrim(p_receptor));
    v_re        constant text := '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$';
    v_domain    text;
    v_e_own     boolean;
    v_r_own     boolean;
    v_e_inact   boolean;
    v_r_inact   boolean;
    v_empty     boolean;
    v_role      text;
    v_reason    text;
BEGIN
    IF p_co IS NULL OR NOT EXISTS (SELECT 1 FROM public.companys c WHERE c.id_company = p_co AND c.is_active IS NOT FALSE) THEN
        RETURN jsonb_build_object('role', 'UNKNOWN', 'reason', 'INVALID_INPUT', 'emisor_inactive_match', false,
                                  'receptor_inactive_match', false, 'own_set_empty', NULL, 'company_domain', NULL);
    END IF;
    v_domain := public.fn_company_business_domain(p_co);
    IF v_e IS NULL OR v_r IS NULL OR v_e !~ v_re OR v_r !~ v_re THEN
        RETURN jsonb_build_object('role', 'UNKNOWN', 'reason', 'INVALID_INPUT', 'emisor_inactive_match', false,
                                  'receptor_inactive_match', false, 'own_set_empty', NULL, 'company_domain', v_domain);
    END IF;

    -- Active RFCs of this company only (both tables), and the RFCs that exist only as deactivated rows.
    WITH own AS (
        SELECT t.rfc FROM public.company_tax_ids t WHERE t.id_company = p_co AND t.is_active
        UNION
        SELECT i.rfc FROM public.company_issuer_rfcs i WHERE i.id_company = p_co AND i.is_active
    ), off AS (
        SELECT t.rfc FROM public.company_tax_ids t WHERE t.id_company = p_co AND NOT t.is_active
        UNION
        SELECT i.rfc FROM public.company_issuer_rfcs i WHERE i.id_company = p_co AND NOT i.is_active
    )
    SELECT EXISTS (SELECT 1 FROM own WHERE rfc = v_e),
           EXISTS (SELECT 1 FROM own WHERE rfc = v_r),
           EXISTS (SELECT 1 FROM off WHERE rfc = v_e) AND NOT EXISTS (SELECT 1 FROM own WHERE rfc = v_e),
           EXISTS (SELECT 1 FROM off WHERE rfc = v_r) AND NOT EXISTS (SELECT 1 FROM own WHERE rfc = v_r),
           NOT EXISTS (SELECT 1 FROM own)
      INTO v_e_own, v_r_own, v_e_inact, v_r_inact, v_empty;

    IF v_e_own AND NOT v_r_own THEN
        v_role := 'SALE';      v_reason := 'ISSUER_OWN';
    ELSIF v_r_own AND NOT v_e_own THEN
        v_role := 'EXPENSE';   v_reason := 'RECEPTOR_OWN';
    ELSIF v_e_own AND v_r_own THEN
        v_role := 'AMBIGUOUS'; v_reason := CASE WHEN v_e = v_r THEN 'SELF_INVOICE' ELSE 'BOTH_ROLES' END;
    ELSE
        v_role := 'UNKNOWN';   v_reason := 'NEITHER';
    END IF;

    RETURN jsonb_build_object('role', v_role, 'reason', v_reason, 'emisor_inactive_match', v_e_inact,
                              'receptor_inactive_match', v_r_inact, 'own_set_empty', v_empty, 'company_domain', v_domain);
END;
$$;

-- 2) Role only ----------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_classify_cfdi_role(p_co integer, p_emisor text, p_receptor text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $$ SELECT public.fn_classify_cfdi_role_detail(p_co, p_emisor, p_receptor) ->> 'role' $$;

-- 3) The only entry point for n8n ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_cfdi_classify(p_tenant_id text, p_user_email text, p_emisor text, p_receptor text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_co integer;
BEGIN
    -- Fail-closed: a tenant that is not one plain integer is ambiguous; anything but an active member of an active company is refused.
    IF p_tenant_id IS NULL OR btrim(p_tenant_id) !~ '^[0-9]{1,9}$' THEN
        RETURN jsonb_build_object('role', 'UNKNOWN', 'reason', 'FORBIDDEN');
    END IF;
    v_co := btrim(p_tenant_id)::integer;
    IF NOT EXISTS (SELECT 1 FROM public.companys c WHERE c.id_company = v_co AND c.is_active IS NOT FALSE)
       OR public.fn_agri_actor_role(v_co, p_user_email) IS NULL THEN
        RETURN jsonb_build_object('role', 'UNKNOWN', 'reason', 'FORBIDDEN');
    END IF;
    RETURN public.fn_classify_cfdi_role_detail(v_co, p_emisor, p_receptor);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_classify_cfdi_role_detail(integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_classify_cfdi_role(integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sp_cfdi_classify(text, text, text, text) FROM PUBLIC;

COMMENT ON FUNCTION public.fn_classify_cfdi_role_detail(integer, text, text) IS
  '109: SALE / EXPENSE / AMBIGUOUS / UNKNOWN of a voucher by RFC role for ONE company. Read-only, returns codes and booleans, never an RFC. Not callable from the gateway; use sp_cfdi_classify.';
COMMENT ON FUNCTION public.fn_classify_cfdi_role(integer, text, text) IS
  '109: role only of fn_classify_cfdi_role_detail. Internal; not callable from the gateway.';
COMMENT ON FUNCTION public.sp_cfdi_classify(text, text, text, text) IS
  '109: membership-checked entry point of the RFC role classifier (the only one for n8n). Fail-closed: FORBIDDEN unless the user is an active member of the active company.';

-- 4) Self-check --------------------------------------------------------------------------------------------------

DO $$
BEGIN
    IF to_regprocedure('public.fn_classify_cfdi_role_detail(integer,text,text)') IS NULL
       OR to_regprocedure('public.fn_classify_cfdi_role(integer,text,text)') IS NULL
       OR to_regprocedure('public.sp_cfdi_classify(text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION '109: a function is missing after the change';
    END IF;
    IF has_function_privilege('public', 'public.fn_classify_cfdi_role_detail(integer,text,text)', 'EXECUTE')
       OR has_function_privilege('public', 'public.fn_classify_cfdi_role(integer,text,text)', 'EXECUTE')
       OR has_function_privilege('public', 'public.sp_cfdi_classify(text,text,text,text)', 'EXECUTE') THEN
        RAISE EXCEPTION '109: PUBLIC can still execute a classifier function';
    END IF;
    IF (SELECT count(*) FROM public.crud_models WHERE table_name ~ 'cfdi_classify|classify_cfdi' OR model_name ~ 'cfdi_classify|classify_cfdi') <> 0 THEN
        RAISE EXCEPTION '109: a classifier function is registered in crud_models';
    END IF;
    RAISE NOTICE '109: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 109 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 109 rolled back ***'
\endif
\endif
