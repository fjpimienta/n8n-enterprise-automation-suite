-- 115_rollback.sql. No DROP of data; nothing is deleted.
-- Order: roll back the guard PR (2d), if applied, FIRST; then this one; then step 1 (114_identifier_history_tenant_guards) last.
-- Does:   reverses the three in-place patches (dispatcher, one-pending guard message, event-log CASE) back to the exact measured text;
--         restores the tipo CHECK to the two original values; turns the four public functions into stubs that answer {"status":"disabled"}.
-- Keeps:  the helper functions (fn_tag_*, fn_normalize_identifier, fn_resolve_identifier: read-only and harmless) and the tag_change_previews table.
-- Refuses (changes nothing) when any CAMBIO_ARETE row exists in pending_authorizations: cancel or resolve them first, or the CHECK cannot go back.
--   psql -X -v ON_ERROR_STOP=1 -f 115_rollback.sql                -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 115_rollback.sql  -> commit

\if :{?embedded}
\else
\set ON_ERROR_STOP on
\endif
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

DO $$
DECLARE n integer;
BEGIN
    SELECT count(*) INTO n FROM public.pending_authorizations WHERE tipo_evento = 'CAMBIO_ARETE';
    IF n > 0 THEN
        RAISE EXCEPTION 'ABORT rollback: % CAMBIO_ARETE request(s) exist (any state). Resolve or move them first; nothing was changed.', n;
    END IF;
END $$;

-- 1. Dispatcher: remove the branch (exact inverse of the patch; the md5 is checked by the tests)
DO $patch$
DECLARE
    v_def text := pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure);
    v_pat text := $r$(\s+)ELSIF v_request\.tipo_evento = 'CAMBIO_ARETE' THEN.*?\1ELSE(\s+)RAISE EXCEPTION 'Tipo de evento % no tiene despachador configurado'$r$;
BEGIN
    IF v_def NOT LIKE '%''CAMBIO_ARETE''%' THEN RAISE NOTICE 'dispatcher has no CAMBIO_ARETE branch'; RETURN; END IF;
    IF regexp_count(v_def, v_pat) <> 1 THEN RAISE EXCEPTION 'ABORT rollback: dispatcher branch not found exactly once.'; END IF;
    EXECUTE regexp_replace(v_def, v_pat, $r$\1ELSE\2RAISE EXCEPTION 'Tipo de evento % no tiene despachador configurado'$r$);
END $patch$;

-- 2. One-pending guard message
DO $patch$
DECLARE v_def text := pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure);
BEGIN
    IF v_def NOT LIKE '%''CAMBIO_ARETE''%' THEN RAISE NOTICE 'guard has no CAMBIO_ARETE message'; RETURN; END IF;
    EXECUTE replace(v_def, ' WHEN ''CAMBIO_ARETE'' THEN ''cambio de arete''', '');
END $patch$;

-- 3. Event log CASE
DO $patch$
DECLARE v_def text := pg_get_viewdef('public.vw_cattle_event_log'::regclass, true);
BEGIN
    IF v_def NOT LIKE '%SOLICITUD_CAMBIO_ARETE%' THEN RAISE NOTICE 'event log has no CAMBIO_ARETE branch'; RETURN; END IF;
    EXECUTE 'CREATE OR REPLACE VIEW public.vw_cattle_event_log AS ' ||
            rtrim(replace(v_def, ' WHEN ''CAMBIO_ARETE''::text THEN ''SOLICITUD_CAMBIO_ARETE''::text', ''), E';\n\t ');
END $patch$;

-- 4. CHECK back to the two original values
ALTER TABLE public.pending_authorizations DROP CONSTRAINT IF EXISTS pending_authorizations_tipo_check;
ALTER TABLE public.pending_authorizations ADD CONSTRAINT pending_authorizations_tipo_check CHECK (tipo_evento::text = ANY (ARRAY['BAJA_MORTANDAD', 'VENTA']));

-- 5. The public functions answer "disabled" (same signatures; nothing is dropped)
CREATE OR REPLACE FUNCTION public.sp_assign_livestock_identifier(p_tenant text, p_email text, p_identifier text, p_tag_type text, p_value text, p_preview_token text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $fn$ SELECT jsonb_build_object('status', 'disabled', 'applied', false) $fn$;
CREATE OR REPLACE FUNCTION public.sp_request_tag_change(p_tenant text, p_email text, p_identifier text, p_tag_type text, p_new_value text, p_reason text, p_preview_token text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $fn$ SELECT jsonb_build_object('status', 'disabled', 'applied', false) $fn$;
CREATE OR REPLACE FUNCTION public.sp_cancel_tag_change(p_tenant text, p_email text, p_request_id text)
RETURNS jsonb LANGUAGE sql AS $fn$ SELECT jsonb_build_object('status', 'disabled', 'applied', false) $fn$;
CREATE OR REPLACE FUNCTION public.sp_apply_tag_change(p_request_id uuid, p_approver_email text)
RETURNS jsonb LANGUAGE sql AS $fn$ SELECT jsonb_build_object('success', false, 'motivo', 'disabled') $fn$;

DO $$
BEGIN
    IF pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure) LIKE '%CAMBIO_ARETE%' THEN RAISE EXCEPTION 'POST-CHECK rollback: dispatcher still patched.'; END IF;
    RAISE NOTICE '115_tag_change_authorization rollback: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo 'rollback: COMMITTED'
\else
ROLLBACK;
\echo 'rollback: DRY RUN, rolled back. Re-run with -v apply=true to commit.'
\endif
\endif
