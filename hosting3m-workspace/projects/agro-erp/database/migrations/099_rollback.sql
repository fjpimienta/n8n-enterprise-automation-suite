-- 099 ROLLBACK. No DROP / DELETE / UPDATE of data.
-- The two chat tool functions keep their names and signatures (the n8n livestock agents still call them) but their bodies
-- become a constant answer {"status":"disabled", ...}: the agents keep running, tell the user to use the web platform,
-- and nothing is read or written. The helpers (fn_livestock_chat_*) are left in place: they are harmless, nothing else
-- calls them, and a re-apply of 099 replaces them.
-- Animals already registered through 099 are real data and are NOT touched; they can be listed with
--   metadata->>'migration' = '099'  (and metadata->>'source' IN ('REGULARIZACION_PADRON', 'COMPRA')).
-- Order in production: first restore the n8n workflows from their backups (099_RUNBOOK.md), then this file.
-- Re-applying 099_livestock_regularization.sql restores the tools.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 099_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 099_rollback.sql  -> commit
-- Then: 099_state_check.sql -v expect=rolled_back

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
    IF to_regprocedure('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_register_livestock_purchase_chat(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: the 099 tool functions were not found - 099 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_register_livestock_regularization(
    p_tenant_id        text,
    p_actor_email      text,
    p_channel          text,
    p_upp              text,
    p_lot              text,
    p_species          text,
    p_category         text,
    p_business_model   text,
    p_age_months       text,
    p_ear_tag          text,
    p_guide_folio      text,
    p_origin_upp_code  text,
    p_notes            text,
    p_confirmed        text,
    p_preview_hash     text,
    p_force_duplicate  text
)
RETURNS jsonb
LANGUAGE sql
AS $$
    SELECT jsonb_build_object('status', 'disabled',
        'message', 'El alta de animales por este chat está desactivada temporalmente. Regístralo en la plataforma web.')
$$;

CREATE OR REPLACE FUNCTION public.sp_register_livestock_purchase_chat(
    p_tenant_id        text,
    p_actor_email      text,
    p_channel          text,
    p_upp              text,
    p_lot              text,
    p_species          text,
    p_category         text,
    p_business_model   text,
    p_ear_tag          text,
    p_birth_date       text,
    p_weight_kg        text,
    p_purchase_price   text,
    p_seller_name      text,
    p_purchase_date    text,
    p_notes            text,
    p_confirmed        text,
    p_preview_hash     text,
    p_force_duplicate  text
)
RETURNS jsonb
LANGUAGE sql
AS $$
    SELECT jsonb_build_object('status', 'disabled',
        'message', 'El alta de animales por este chat está desactivada temporalmente. Regístralo en la plataforma web.')
$$;

-- CREATE OR REPLACE keeps the ACL; repeat the revoke so the rollback is correct on its own.
REVOKE ALL ON FUNCTION public.sp_register_livestock_regularization(text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sp_register_livestock_purchase_chat(text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text, text, text) FROM PUBLIC;

DO $$
BEGIN
    IF public.sp_register_livestock_regularization('1', 'x', 'CHAT_WEB', NULL, NULL, 'BOVINO', 'BECERRO', 'CRIA', '8',
           '9900000001', 'F', NULL, NULL, 'true', NULL, NULL)->>'status' <> 'disabled'
       OR public.sp_register_livestock_purchase_chat('1', 'x', 'CHAT_WEB', NULL, NULL, 'BOVINO', 'BECERRO', 'CRIA', NULL,
           NULL, NULL, '1000', 'Vendedor', NULL, NULL, 'true', NULL, NULL)->>'status' <> 'disabled' THEN
        RAISE EXCEPTION '099 rollback: the tool functions do not answer disabled';
    END IF;
    RAISE NOTICE '099 rollback: OK (tools disabled; helpers and data untouched)';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 099 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 099 rollback rolled back ***'
\endif
\endif
