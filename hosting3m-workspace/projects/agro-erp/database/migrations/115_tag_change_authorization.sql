-- 115_tag_change_authorization.sql (step 2 / PR 2a of the identifier change-control work, DATABASE ONLY). Migration 115 (113 is reserved).
-- Requires 114_identifier_history_tenant_guards.sql (step 1) applied first.
--
-- What it adds
--   * pending_authorizations.tipo_evento accepts CAMBIO_ARETE; the dispatcher of sp_resolver_autorizacion gets one new branch (patched in place, md5-gated).
--   * sp_assign_livestock_identifier   : chip, or fire number, ONLY when empty. ADMIN/EDITOR. No approval. Two calls: preview (returns a token), then execute with that token.
--   * sp_request_tag_change : ear tag (empty or not), replacement of an existing chip, change of an existing fire number. ALWAYS creates a pending request
--                             (type CAMBIO_ARETE); the animal is not touched. Same two-call preview/token flow.
--   * sp_cancel_tag_change  : the requester or an active ADMIN cancels a pending request, same local day (state CANCELADO).
--   * sp_apply_tag_change   : internal; only the dispatcher can run it (flag app.tag_dispatch). Revalidates everything at approval time.
--   * fn_resolve_identifier : current value wins; a retired value still finds the animal ("previous identifier").
--   * fn_pending_auth_one_pending_guard: message names the type for CAMBIO_ARETE (patched in place, md5-gated).
--   * vw_cattle_event_log   : a CAMBIO_ARETE request shows as SOLICITUD_CAMBIO_ARETE instead of a NULL event type (patched in place, count-gated).
--   * tag_change_previews   : single-use, 10-minute preview tokens bound to tenant, e-mail, animal and the exact parameters.
--
-- Session flags (transaction-local set_config(..., true); '' and unset mean the same, every reader uses NULLIF(current_setting(.., true), ''))
--   app.tag_dispatch             SET by the dispatcher branch of sp_resolver_autorizacion (value = request id) right before sp_apply_tag_change and cleared right
--                                after. READ by sp_apply_tag_change, which refuses to run without it. Nobody else sets it.
--   app.identifier_gate          SET (value = txid_current()) by sp_assign_livestock_identifier and by sp_apply_tag_change immediately before their UPDATE of an identifier
--                                column and cleared immediately after. READ by the guard trigger of the LATER guard PR (2d), which refuses a changed identifier
--                                unless the gate equals the current transaction id. Harmless until that trigger exists.
--   app.identifier_change_user / _reason / _notes
--                                SET by the same two functions around the UPDATE (actor e-mail, one of the history reasons, free text) and cleared after.
--                                READ by trg_log_identifier_changes (step 1).
--   These flags are an application-level guard (gateway, panel and fixed workflow queries); direct database sessions are out of their scope.
--
-- Decisions implemented: ADMIN/EDITOR only (OWNER is a separate PR); approval = active ADMIN via fn_is_active_company_admin (unchanged), self-approval allowed
-- exactly as for bajas; request valid until midnight (fn_authorization_expired); ear tag 10 digits only when fn_species_requires_bovine_compliance (BOVINO or
-- unknown species); a chip is 15 digits (fn_tag_rules()); "cannot use this value" is ONE generic outcome (global unique indexes, see DATABASE_SCHEMA notes).
--
-- BACKUP before applying anywhere that matters:
--   pg_dump -Fc -t public.pending_authorizations -t public.crud_models -f tag_change_before_<date>.dump hosting3m_db
--   and save the text of sp_resolver_autorizacion, fn_pending_auth_one_pending_guard and vw_cattle_event_log (\sf / pg_get_viewdef).
-- DRY RUN (default): psql -X -v ON_ERROR_STOP=1 -f 115_tag_change_authorization.sql ; commit with -v apply=true.
-- Idempotent. Rollback: 115_rollback.sql. Tests (throwaway database only): 115_tests.sql.
-- Error codes: P0135 (preview row for an animal of another company; never reachable through the functions). Expected outcomes are returned as {status}, not raised;
-- P0016/P0011/P0012/P0018 stay those of sp_resolver_autorizacion.

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

-- 0. Preconditions and drift guards --------------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_def text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_identifier_history' AND column_name = 'id_company') THEN
        RAISE EXCEPTION 'ABORT: step 1 (114_identifier_history_tenant_guards) is not applied: cattle_identifier_history.id_company is missing.';
    END IF;
    IF pg_get_functiondef('public.trg_log_identifier_changes()'::regprocedure) NOT LIKE '%identifier_change_notes%' THEN
        RAISE EXCEPTION 'ABORT: step 1 logger is not the live trg_log_identifier_changes().';
    END IF;
    FOREACH v_def IN ARRAY ARRAY['public.fn_is_active_company_admin(character varying,integer)', 'public.fn_authorization_expired(timestamp without time zone)',
                                 'public.fn_has_official_ear_tag(character varying)', 'public.fn_species_requires_bovine_compliance(character varying)',
                                 'public.fn_company_business_domain(integer)']
    LOOP
        IF to_regprocedure(v_def) IS NULL THEN RAISE EXCEPTION 'ABORT: % not found.', v_def; END IF;
    END LOOP;
    IF to_regclass('public.vw_cattle_event_log') IS NULL OR to_regclass('public.pending_authorizations') IS NULL OR to_regclass('public.historico_movimientos') IS NULL THEN
        RAISE EXCEPTION 'ABORT: a required table or view is missing.';
    END IF;
END $$;

-- 1. Rules and small helpers ---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_tag_rules() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $fn$
    SELECT jsonb_build_object('chip_digits', 15, 'siniiga_digits', 10, 'text_max', 50, 'reason_min', 3, 'reason_max', 500, 'preview_minutes', 10)
$fn$;

CREATE OR REPLACE FUNCTION public.fn_tag_result(p_status text, p_extra jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $fn$
    SELECT jsonb_build_object('status', p_status, 'applied', false) || coalesce(p_extra, '{}'::jsonb)
$fn$;

-- Tenant as text -> integer, NULL when it is not a plain positive integer (never raises).
CREATE OR REPLACE FUNCTION public.fn_tag_parse_tenant(p_tenant text) RETURNS integer LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN btrim(coalesce(p_tenant, '')) ~ '^[0-9]{1,9}$' AND btrim(p_tenant)::bigint BETWEEN 1 AND 2147483647 THEN btrim(p_tenant)::integer END
$fn$;

-- Same rule as the get_livestock_info tool (its JS: message.replace(/\b\d(?:\s+\d\b){2,}/g, m => m.replace(/\s+/g, ''))): only a run of THREE OR MORE
-- single digits separated by whitespace (Whisper-style dictation "9 9 9 8 8") loses its spaces. Nothing else is changed: grouped digits ("99 00 00"),
-- hyphens, dots, letters and CASE stay as they are, and leading zeros are kept (text). Edge spaces are trimmed; '' and NULL give NULL.
-- (The lookups compare case-insensitively on top of this; get_livestock_info compares exactly, and will use fn_resolve_identifier from PR 2b.)
CREATE OR REPLACE FUNCTION public.fn_normalize_identifier(p_value text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
    v text;
    m text;
BEGIN
    v := NULLIF(regexp_replace(coalesce(p_value, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g'), '');
    IF v IS NULL THEN RETURN NULL; END IF;
    FOR m IN SELECT (regexp_matches(v, '\m\d(?:\s+\d\M){2,}', 'g'))[1] LOOP
        v := replace(v, m, regexp_replace(m, '\s+', '', 'g'));
    END LOOP;
    RETURN v;
END;
$fn$;

-- Role of an e-mail in a company, only when user, membership and company are all active (case-insensitive e-mail). NULL otherwise.
CREATE OR REPLACE FUNCTION public.fn_tag_member_role(p_tenant integer, p_email text) RETURNS text LANGUAGE sql STABLE SET search_path = public, pg_temp AS $fn$
    SELECT upper(uc.role)
      FROM public.user_companies uc
      JOIN public.users u ON lower(u.email) = lower(uc.email) AND u.is_active = true
      JOIN public.companys c ON c.id_company = uc.id_company AND c.is_active = true
     WHERE p_tenant IS NOT NULL AND NULLIF(btrim(p_email), '') IS NOT NULL
       AND uc.id_company = p_tenant AND lower(uc.email) = lower(btrim(p_email)) AND uc.is_active = true
     LIMIT 1
$fn$;

CREATE OR REPLACE FUNCTION public.fn_tag_status_blocked(p_status text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
    SELECT coalesce(p_status, '') IN ('VENDIDO', 'FINALIZADO', 'BAJA_DEPURACION_DATOS', 'BAJA_MORTANDAD')
$fn$;

-- NULL when the value is acceptable for that identifier type, otherwise a short code.
CREATE OR REPLACE FUNCTION public.fn_tag_format_error(p_type text, p_value text, p_species text) RETURNS text LANGUAGE sql STABLE SET search_path = public, pg_temp AS $fn$
    SELECT CASE
        WHEN p_value IS NULL THEN 'empty'
        WHEN p_value ~ '[[:cntrl:]]' THEN 'control_chars'
        WHEN length(p_value) > (public.fn_tag_rules() ->> 'text_max')::integer THEN 'too_long'
        WHEN p_type = 'CHIP' AND p_value !~ ('^[0-9]{' || (public.fn_tag_rules() ->> 'chip_digits') || '}$') THEN 'chip_format'
        WHEN p_type = 'SINIIGA' AND public.fn_species_requires_bovine_compliance(p_species) AND NOT public.fn_has_official_ear_tag(p_value) THEN 'siniiga_format'
    END
$fn$;

-- True when a chip / ear tag value cannot be used inside the company: held by ANOTHER animal in any of the three current columns, or retired from an animal of
-- the company (history of that type). Other companies are NOT looked at here: the global unique indexes catch them at UPDATE time (same generic outcome).
CREATE OR REPLACE FUNCTION public.fn_tag_value_unavailable(p_tenant integer, p_type text, p_value text, p_exclude uuid) RETURNS boolean LANGUAGE sql STABLE SET search_path = public, pg_temp AS $fn$
    SELECT EXISTS (SELECT 1 FROM public.cattle_livestock c
                    WHERE c.tenant_id = p_tenant AND c.id <> p_exclude
                      AND upper(btrim(p_value)) IN (upper(btrim(c.rfid_siniiga)), upper(btrim(c.electronic_rfid)), upper(btrim(c.numero_fuego))))
        OR EXISTS (SELECT 1 FROM public.cattle_identifier_history h
                    WHERE h.id_company = p_tenant AND h.identifier_type = p_type AND upper(btrim(h.previous_value)) = upper(btrim(p_value)))
$fn$;

-- Fire numbers may repeat (project Rule 4): only a count, to warn.
CREATE OR REPLACE FUNCTION public.fn_tag_fuego_duplicates(p_tenant integer, p_value text, p_exclude uuid) RETURNS integer LANGUAGE sql STABLE SET search_path = public, pg_temp AS $fn$
    SELECT count(*)::integer FROM public.cattle_livestock c
     WHERE c.tenant_id = p_tenant AND c.id <> p_exclude AND upper(btrim(c.numero_fuego)) = upper(btrim(p_value))
$fn$;

-- 2. Alias lookup: current value wins; only when nothing current matches, previously held values are returned ------------------------------
CREATE OR REPLACE FUNCTION public.fn_resolve_identifier(p_tenant integer, p_identifier text)
RETURNS TABLE (livestock_id uuid, matched text, identifier_type text)
LANGUAGE sql STABLE SET search_path = public, pg_temp AS $fn$
    WITH n AS (SELECT upper(public.fn_normalize_identifier(p_identifier)) AS v),
    cur AS (
        SELECT c.id AS livestock_id,
               CASE WHEN upper(btrim(c.rfid_siniiga)) = n.v THEN 'SINIIGA' WHEN upper(btrim(c.electronic_rfid)) = n.v THEN 'CHIP' ELSE 'FUEGO' END AS identifier_type
          FROM public.cattle_livestock c, n
         WHERE p_tenant IS NOT NULL AND n.v IS NOT NULL AND c.tenant_id = p_tenant
           AND n.v IN (upper(btrim(c.rfid_siniiga)), upper(btrim(c.electronic_rfid)), upper(btrim(c.numero_fuego)))
    ),
    prev AS (
        SELECT DISTINCT ON (h.cattle_livestock_id) h.cattle_livestock_id AS livestock_id, h.identifier_type
          FROM public.cattle_identifier_history h
          JOIN public.cattle_livestock c ON c.id = h.cattle_livestock_id AND c.tenant_id = p_tenant, n
         WHERE p_tenant IS NOT NULL AND n.v IS NOT NULL AND h.id_company = p_tenant AND upper(btrim(h.previous_value)) = n.v
         ORDER BY h.cattle_livestock_id, h.changed_at DESC
    )
    SELECT cur.livestock_id, 'CURRENT'::text, cur.identifier_type FROM cur
    UNION ALL
    SELECT prev.livestock_id, 'PREVIOUS'::text, prev.identifier_type FROM prev WHERE NOT EXISTS (SELECT 1 FROM cur)
$fn$;

-- 3. Preview tokens --------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tag_change_previews (
    token        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company   integer NOT NULL REFERENCES public.companys (id_company) ON DELETE CASCADE,
    email        text NOT NULL CHECK (email = lower(btrim(email)) AND email <> ''),
    operation    text NOT NULL CHECK (operation IN ('ASSIGN', 'REQUEST')),
    livestock_id uuid NOT NULL REFERENCES public.cattle_livestock (id) ON DELETE CASCADE,
    params_hash  text NOT NULL CHECK (params_hash ~ '^[0-9a-f]{32}$'),
    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    used_at      timestamptz,
    CONSTRAINT tag_change_previews_expiry_check CHECK (expires_at > created_at),
    CONSTRAINT tag_change_previews_used_check   CHECK (used_at IS NULL OR used_at >= created_at)
);
-- The animal must belong to the company of the token (a composite FK would need a new unique index on the hot table).
CREATE OR REPLACE FUNCTION public.trg_tag_change_previews_company() RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $fn$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.cattle_livestock c WHERE c.id = NEW.livestock_id AND c.tenant_id = NEW.id_company) THEN
        RAISE EXCEPTION 'Preview refused: the animal does not belong to the company' USING ERRCODE = 'P0135';
    END IF;
    RETURN NEW;
END;
$fn$;
CREATE OR REPLACE TRIGGER trg_tag_change_previews_company BEFORE INSERT ON public.tag_change_previews
    FOR EACH ROW EXECUTE FUNCTION public.trg_tag_change_previews_company();
CREATE INDEX IF NOT EXISTS idx_tag_change_previews_company ON public.tag_change_previews (id_company, created_at);
COMMENT ON TABLE public.tag_change_previews IS
    'Single-use preview tokens for sp_assign_livestock_identifier / sp_request_tag_change. Proves a preview was made for exactly these parameters; it does NOT prove the user said yes (the prompt must ask). Not exposed by the gateway.';

-- 4. pending_authorizations accepts CAMBIO_ARETE --------------------------------------------------------------------------------------
ALTER TABLE public.pending_authorizations DROP CONSTRAINT IF EXISTS pending_authorizations_tipo_check;
ALTER TABLE public.pending_authorizations ADD CONSTRAINT pending_authorizations_tipo_check
    CHECK (tipo_evento::text = ANY (ARRAY['BAJA_MORTANDAD', 'VENTA', 'CAMBIO_ARETE']));

-- 5. sp_assign_livestock_identifier ----------------------------------------------------------------------------------------------------------------
-- p_tag_type: CHIP or FUEGO. Works only when that identifier is empty. p_preview_token empty = preview; with the token returned by the preview = execute.
CREATE OR REPLACE FUNCTION public.sp_assign_livestock_identifier(
    p_tenant text, p_email text, p_identifier text, p_tag_type text, p_value text, p_preview_token text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path = public, pg_temp AS $fn$
DECLARE
    v_tenant integer; v_email text; v_type text; v_ident text; v_value text; v_role text;
    v_n integer; v_id uuid; v_kind text; v_row public.cattle_livestock%ROWTYPE;
    v_dups integer := 0; v_hash text; v_token uuid; v_tok public.tag_change_previews%ROWTYPE; v_rows integer; v_chip text;
BEGIN
    v_tenant := public.fn_tag_parse_tenant(p_tenant);
    IF v_tenant IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["tenant"]}'); END IF;
    v_email := lower(NULLIF(btrim(p_email), ''));
    IF v_email IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["email"]}'); END IF;
    v_type := upper(NULLIF(btrim(p_tag_type), ''));
    IF v_type IS NULL OR v_type NOT IN ('CHIP', 'FUEGO') THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["tag_type"]}'); END IF;
    v_ident := public.fn_normalize_identifier(p_identifier);
    v_value := public.fn_normalize_identifier(p_value);
    IF v_ident IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["identifier"]}'); END IF;
    IF v_value IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["value"]}'); END IF;
    IF v_type = 'FUEGO' THEN v_value := upper(v_value); END IF;

    v_role := public.fn_tag_member_role(v_tenant, v_email);
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'EDITOR') THEN RETURN public.fn_tag_result('forbidden'); END IF;
    IF public.fn_company_business_domain(v_tenant) = 'PALM' THEN RETURN public.fn_tag_result('not_livestock'); END IF;

    SELECT count(*), (array_agg(r.livestock_id))[1], min(r.matched) INTO v_n, v_id, v_kind FROM public.fn_resolve_identifier(v_tenant, v_ident) r;
    IF v_n = 0 THEN RETURN public.fn_tag_result('not_found'); END IF;
    IF v_n > 1 THEN RETURN public.fn_tag_result('ambiguous', jsonb_build_object('matches', v_n)); END IF;
    IF v_kind = 'PREVIOUS' THEN RETURN public.fn_tag_result('previous_identifier_only'); END IF;

    SELECT * INTO v_row FROM public.cattle_livestock WHERE id = v_id AND tenant_id = v_tenant FOR UPDATE;
    IF NOT FOUND THEN RETURN public.fn_tag_result('not_found'); END IF;
    IF public.fn_tag_status_blocked(v_row.current_status) THEN RETURN public.fn_tag_result('animal_not_eligible'); END IF;

    IF (v_type = 'CHIP' AND NULLIF(btrim(v_row.electronic_rfid), '') IS NOT NULL) OR (v_type = 'FUEGO' AND NULLIF(btrim(v_row.numero_fuego), '') IS NOT NULL) THEN
        RETURN public.fn_tag_result('not_empty', '{"use":"request_tag_change"}');
    END IF;
    IF public.fn_tag_format_error(v_type, v_value, v_row.species) IS NOT NULL THEN
        RETURN public.fn_tag_result('invalid_input', jsonb_build_object('issues', jsonb_build_array(public.fn_tag_format_error(v_type, v_value, v_row.species))));
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(v_tenant::text || ':' || v_type || ':' || upper(v_value), 0));
    IF v_type = 'CHIP' AND public.fn_tag_value_unavailable(v_tenant, v_type, v_value, v_row.id) THEN RETURN public.fn_tag_result('identifier_unavailable'); END IF;
    IF v_type = 'FUEGO' THEN v_dups := public.fn_tag_fuego_duplicates(v_tenant, v_value, v_row.id); END IF;

    v_hash := md5(concat_ws('|', 'ASSIGN', v_tenant, v_email, v_row.id, v_type, upper(v_value)));

    IF NULLIF(btrim(p_preview_token), '') IS NULL THEN
        INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at)
        VALUES (v_tenant, v_email, 'ASSIGN', v_row.id, v_hash, now() + make_interval(mins => (public.fn_tag_rules() ->> 'preview_minutes')::integer))
        RETURNING token INTO v_token;
        RETURN public.fn_tag_result('preview', jsonb_build_object(
            'preview_token', v_token, 'valid_minutes', (public.fn_tag_rules() ->> 'preview_minutes')::integer,
            'impact', jsonb_build_object('tag_type', v_type, 'old', NULL::text, 'new', v_value,
                                         'animal', jsonb_build_object('category', v_row.category, 'ear_tag', v_row.rfid_siniiga, 'fire_number', v_row.numero_fuego)),
            'duplicates_in_company', v_dups,
            'warning', CASE WHEN v_dups > 0 THEN 'FUEGO_DUPLICATE' END));
    END IF;

    -- Execute: the token must be a uuid, unused, unexpired and bound to exactly these parameters
    IF btrim(p_preview_token) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN public.fn_tag_result('preview_required'); END IF;
    SELECT * INTO v_tok FROM public.tag_change_previews WHERE token = btrim(p_preview_token)::uuid FOR UPDATE;
    IF NOT FOUND OR v_tok.used_at IS NOT NULL OR v_tok.expires_at <= now() OR v_tok.id_company <> v_tenant OR v_tok.email <> v_email
       OR v_tok.operation <> 'ASSIGN' OR v_tok.livestock_id <> v_row.id OR v_tok.params_hash <> v_hash THEN
        RETURN public.fn_tag_result('preview_required');
    END IF;
    UPDATE public.tag_change_previews SET used_at = now() WHERE token = v_tok.token;

    BEGIN
        PERFORM set_config('app.identifier_gate', txid_current()::text, true);
        PERFORM set_config('app.identifier_change_user', v_email, true);
        PERFORM set_config('app.identifier_change_reason', 'INITIAL_ASSIGNMENT', true);
        PERFORM set_config('app.identifier_change_notes', 'Assigned through the assistant after a confirmed preview', true);
        IF v_type = 'CHIP' THEN
            UPDATE public.cattle_livestock SET electronic_rfid = v_value WHERE id = v_row.id AND tenant_id = v_tenant AND NULLIF(btrim(electronic_rfid), '') IS NULL;
        ELSE
            UPDATE public.cattle_livestock SET numero_fuego = v_value WHERE id = v_row.id AND tenant_id = v_tenant AND NULLIF(btrim(numero_fuego), '') IS NULL;
        END IF;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN unique_violation THEN
        RETURN public.fn_tag_result('identifier_unavailable');
    END;
    PERFORM set_config('app.identifier_gate', '', true);
    PERFORM set_config('app.identifier_change_user', '', true);
    PERFORM set_config('app.identifier_change_reason', '', true);
    PERFORM set_config('app.identifier_change_notes', '', true);
    IF v_rows <> 1 THEN RETURN public.fn_tag_result('conflict'); END IF;

    v_chip := CASE WHEN v_type = 'CHIP' THEN v_value ELSE v_row.electronic_rfid END;
    INSERT INTO public.historico_movimientos (livestock_id, electronic_rfid, tenant_id, tipo_movimiento, notes)
    VALUES (v_row.id, v_chip, v_tenant, 'CAMBIO_ARETE',
            'Tipo: ' || CASE v_type WHEN 'CHIP' THEN 'ELECTRONIC_RFID' ELSE 'NUMERO_FUEGO' END || '. Anterior: (vacío). Nuevo: ' || v_value || '. Cambiado por: ' || v_email);
    RETURN jsonb_build_object('status', 'applied', 'applied', true, 'livestock_id', v_row.id, 'tag_type', v_type, 'new', v_value, 'duplicates_in_company', v_dups);
END;
$fn$;

-- 6. sp_request_tag_change --------------------------------------------------------------------------------------------------------------
-- p_tag_type: SINIIGA, CHIP or FUEGO. Always pending: the animal is not modified here.
CREATE OR REPLACE FUNCTION public.sp_request_tag_change(
    p_tenant text, p_email text, p_identifier text, p_tag_type text, p_new_value text, p_reason text, p_preview_token text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path = public, pg_temp AS $fn$
DECLARE
    v_tenant integer; v_email text; v_type text; v_ident text; v_value text; v_reason text; v_role text;
    v_n integer; v_id uuid; v_kind text; v_row public.cattle_livestock%ROWTYPE; v_old text; v_dups integer := 0;
    v_pending text; v_hash text; v_token uuid; v_tok public.tag_change_previews%ROWTYPE; v_req uuid;
BEGIN
    v_tenant := public.fn_tag_parse_tenant(p_tenant);
    IF v_tenant IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["tenant"]}'); END IF;
    v_email := lower(NULLIF(btrim(p_email), ''));
    IF v_email IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["email"]}'); END IF;
    v_type := upper(NULLIF(btrim(p_tag_type), ''));
    IF v_type IS NULL OR v_type NOT IN ('SINIIGA', 'CHIP', 'FUEGO') THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["tag_type"]}'); END IF;
    v_ident := public.fn_normalize_identifier(p_identifier);
    v_value := public.fn_normalize_identifier(p_new_value);
    v_reason := NULLIF(regexp_replace(coalesce(p_reason, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g'), '');
    IF v_ident IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["identifier"]}'); END IF;
    IF v_value IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["new_value"]}'); END IF;
    IF v_type IN ('SINIIGA', 'FUEGO') THEN v_value := upper(v_value); END IF;
    IF v_reason IS NULL OR length(v_reason) < (public.fn_tag_rules() ->> 'reason_min')::integer OR length(v_reason) > (public.fn_tag_rules() ->> 'reason_max')::integer
       OR v_reason ~ '[[:cntrl:]]' THEN
        RETURN public.fn_tag_result('invalid_input', '{"issues":["reason"]}');
    END IF;

    v_role := public.fn_tag_member_role(v_tenant, v_email);
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'EDITOR') THEN RETURN public.fn_tag_result('forbidden'); END IF;
    IF public.fn_company_business_domain(v_tenant) = 'PALM' THEN RETURN public.fn_tag_result('not_livestock'); END IF;

    SELECT count(*), (array_agg(r.livestock_id))[1], min(r.matched) INTO v_n, v_id, v_kind FROM public.fn_resolve_identifier(v_tenant, v_ident) r;
    IF v_n = 0 THEN RETURN public.fn_tag_result('not_found'); END IF;
    IF v_n > 1 THEN RETURN public.fn_tag_result('ambiguous', jsonb_build_object('matches', v_n)); END IF;
    IF v_kind = 'PREVIOUS' THEN RETURN public.fn_tag_result('previous_identifier_only'); END IF;

    SELECT * INTO v_row FROM public.cattle_livestock WHERE id = v_id AND tenant_id = v_tenant FOR UPDATE;
    IF NOT FOUND THEN RETURN public.fn_tag_result('not_found'); END IF;
    IF public.fn_tag_status_blocked(v_row.current_status) THEN RETURN public.fn_tag_result('animal_not_eligible'); END IF;

    v_old := public.fn_normalize_identifier(CASE v_type WHEN 'SINIIGA' THEN v_row.rfid_siniiga WHEN 'CHIP' THEN v_row.electronic_rfid ELSE v_row.numero_fuego END);
    IF v_type IN ('CHIP', 'FUEGO') AND v_old IS NULL THEN RETURN public.fn_tag_result('use_assign_livestock_identifier'); END IF;
    IF public.fn_tag_format_error(v_type, v_value, v_row.species) IS NOT NULL THEN
        RETURN public.fn_tag_result('invalid_input', jsonb_build_object('issues', jsonb_build_array(public.fn_tag_format_error(v_type, v_value, v_row.species))));
    END IF;
    IF upper(coalesce(v_old, '')) = upper(v_value) THEN RETURN public.fn_tag_result('no_change'); END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(v_tenant::text || ':' || v_type || ':' || upper(v_value), 0));
    IF v_type IN ('SINIIGA', 'CHIP') AND public.fn_tag_value_unavailable(v_tenant, v_type, v_value, v_row.id) THEN RETURN public.fn_tag_result('identifier_unavailable'); END IF;
    IF v_type = 'FUEGO' THEN v_dups := public.fn_tag_fuego_duplicates(v_tenant, v_value, v_row.id); END IF;

    SELECT pa.tipo_evento INTO v_pending FROM public.pending_authorizations pa WHERE pa.livestock_id = v_row.id AND pa.estado = 'PENDIENTE' LIMIT 1;
    IF v_pending IS NOT NULL THEN RETURN public.fn_tag_result('pending_exists', jsonb_build_object('pending_type', v_pending)); END IF;

    v_hash := md5(concat_ws('|', 'REQUEST', v_tenant, v_email, v_row.id, v_type, upper(v_value), v_reason, coalesce(upper(v_old), '')));

    IF NULLIF(btrim(p_preview_token), '') IS NULL THEN
        INSERT INTO public.tag_change_previews (id_company, email, operation, livestock_id, params_hash, expires_at)
        VALUES (v_tenant, v_email, 'REQUEST', v_row.id, v_hash, now() + make_interval(mins => (public.fn_tag_rules() ->> 'preview_minutes')::integer))
        RETURNING token INTO v_token;
        RETURN public.fn_tag_result('preview', jsonb_build_object(
            'preview_token', v_token, 'valid_minutes', (public.fn_tag_rules() ->> 'preview_minutes')::integer,
            'impact', jsonb_build_object('tag_type', v_type, 'old', v_old, 'new', v_value, 'reason', v_reason,
                                         'animal', jsonb_build_object('category', v_row.category, 'ear_tag', v_row.rfid_siniiga, 'fire_number', v_row.numero_fuego)),
            'requires_admin_approval', true,
            'duplicates_in_company', v_dups,
            'warning', CASE WHEN v_dups > 0 THEN 'FUEGO_DUPLICATE' END));
    END IF;

    IF btrim(p_preview_token) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN public.fn_tag_result('preview_required'); END IF;
    SELECT * INTO v_tok FROM public.tag_change_previews WHERE token = btrim(p_preview_token)::uuid FOR UPDATE;
    IF NOT FOUND OR v_tok.used_at IS NOT NULL OR v_tok.expires_at <= now() OR v_tok.id_company <> v_tenant OR v_tok.email <> v_email
       OR v_tok.operation <> 'REQUEST' OR v_tok.livestock_id <> v_row.id OR v_tok.params_hash <> v_hash THEN
        RETURN public.fn_tag_result('preview_required');
    END IF;
    UPDATE public.tag_change_previews SET used_at = now() WHERE token = v_tok.token;

    BEGIN
        INSERT INTO public.pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email)
        VALUES (v_tenant, v_row.id, 'CAMBIO_ARETE',
                jsonb_build_object('tag_type', v_type, 'old_value', v_old, 'new_value', v_value, 'reason', v_reason), v_email)
        RETURNING id INTO v_req;
    EXCEPTION WHEN unique_violation OR SQLSTATE 'P0036' THEN
        RETURN public.fn_tag_result('pending_exists');
    END;
    RETURN jsonb_build_object('status', 'requested', 'applied', false, 'request_id', v_req, 'livestock_id', v_row.id, 'tag_type', v_type,
                              'valid_until', 'end of today (Mexico City)', 'duplicates_in_company', v_dups);
END;
$fn$;

-- 7. sp_cancel_tag_change ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sp_cancel_tag_change(p_tenant text, p_email text, p_request_id text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path = public, pg_temp AS $fn$
DECLARE
    v_tenant integer; v_email text; v_role text; v_req public.pending_authorizations%ROWTYPE;
BEGIN
    v_tenant := public.fn_tag_parse_tenant(p_tenant);
    IF v_tenant IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["tenant"]}'); END IF;
    v_email := lower(NULLIF(btrim(p_email), ''));
    IF v_email IS NULL THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["email"]}'); END IF;
    IF btrim(coalesce(p_request_id, '')) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN public.fn_tag_result('invalid_input', '{"issues":["request_id"]}'); END IF;

    v_role := public.fn_tag_member_role(v_tenant, v_email);
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'EDITOR') THEN RETURN public.fn_tag_result('forbidden'); END IF;

    SELECT * INTO v_req FROM public.pending_authorizations WHERE id = btrim(p_request_id)::uuid AND id_company = v_tenant AND tipo_evento = 'CAMBIO_ARETE' FOR UPDATE;
    IF NOT FOUND THEN RETURN public.fn_tag_result('not_found'); END IF;
    IF NOT (lower(v_req.solicitado_por_email) = v_email OR public.fn_is_active_company_admin(v_email, v_tenant)) THEN RETURN public.fn_tag_result('forbidden'); END IF;
    IF v_req.estado <> 'PENDIENTE' THEN RETURN public.fn_tag_result('not_pending', jsonb_build_object('state', v_req.estado)); END IF;
    IF public.fn_authorization_expired(v_req.fecha_solicitud) THEN RETURN public.fn_tag_result('expired'); END IF;

    UPDATE public.pending_authorizations
       SET estado = 'CANCELADO', resuelto_por_email = v_email, fecha_resolucion = now(), notas_resolucion = 'Cancelled before resolution'
     WHERE id = v_req.id;
    RETURN jsonb_build_object('status', 'cancelled', 'applied', false, 'request_id', v_req.id);
END;
$fn$;

-- 8. sp_apply_tag_change (internal: only the dispatcher) ----------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sp_apply_tag_change(p_request_id uuid, p_approver_email text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path = public, pg_temp AS $fn$
DECLARE
    v_req public.pending_authorizations%ROWTYPE; v_row public.cattle_livestock%ROWTYPE;
    v_type text; v_old text; v_new text; v_cur text; v_reason text; v_approver text; v_rows integer; v_hist_reason text; v_chip text;
BEGIN
    IF NULLIF(current_setting('app.tag_dispatch', true), '') IS DISTINCT FROM p_request_id::text THEN
        RETURN jsonb_build_object('success', false, 'motivo', 'sp_apply_tag_change only runs from the authorization dispatcher');
    END IF;
    v_approver := lower(NULLIF(btrim(p_approver_email), ''));
    SELECT * INTO v_req FROM public.pending_authorizations WHERE id = p_request_id FOR UPDATE;
    IF NOT FOUND OR v_req.tipo_evento <> 'CAMBIO_ARETE' OR v_req.estado <> 'PENDIENTE' THEN
        RETURN jsonb_build_object('success', false, 'motivo', 'Request is not a pending tag change');
    END IF;
    IF v_approver IS NULL OR NOT public.fn_is_active_company_admin(v_approver, v_req.id_company) THEN
        RETURN jsonb_build_object('success', false, 'motivo', 'Approver is not an active ADMIN of the company');
    END IF;

    v_type := v_req.payload ->> 'tag_type';
    v_old := public.fn_normalize_identifier(v_req.payload ->> 'old_value');
    v_new := public.fn_normalize_identifier(v_req.payload ->> 'new_value');
    v_reason := v_req.payload ->> 'reason';
    IF v_type IS NULL OR v_type NOT IN ('SINIIGA', 'CHIP', 'FUEGO') OR v_new IS NULL THEN
        RETURN jsonb_build_object('success', false, 'motivo', 'Malformed request payload');
    END IF;

    SELECT * INTO v_row FROM public.cattle_livestock WHERE id = v_req.livestock_id AND tenant_id = v_req.id_company FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'motivo', 'Animal not found in the company'); END IF;
    IF public.fn_tag_status_blocked(v_row.current_status) THEN RETURN jsonb_build_object('success', false, 'motivo', 'The animal is no longer eligible (sold or deregistered)'); END IF;

    v_cur := public.fn_normalize_identifier(CASE v_type WHEN 'SINIIGA' THEN v_row.rfid_siniiga WHEN 'CHIP' THEN v_row.electronic_rfid ELSE v_row.numero_fuego END);
    IF upper(coalesce(v_cur, '')) <> upper(coalesce(v_old, '')) THEN
        RETURN jsonb_build_object('success', false, 'motivo', 'The current value changed after the request was made; reject it and request again');
    END IF;
    IF public.fn_tag_format_error(v_type, v_new, v_row.species) IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'motivo', 'The new value no longer passes the format rules');
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_req.id_company::text || ':' || v_type || ':' || upper(v_new), 0));
    IF v_type IN ('SINIIGA', 'CHIP') AND public.fn_tag_value_unavailable(v_req.id_company, v_type, v_new, v_row.id) THEN
        RETURN jsonb_build_object('success', false, 'motivo', 'identifier_unavailable');
    END IF;

    v_hist_reason := CASE v_type WHEN 'FUEGO' THEN 'CAPTURE_CORRECTION' ELSE 'AUTHORIZED_CHANGE' END;
    BEGIN
        PERFORM set_config('app.identifier_gate', txid_current()::text, true);
        PERFORM set_config('app.identifier_change_user', v_approver, true);
        PERFORM set_config('app.identifier_change_reason', v_hist_reason, true);
        PERFORM set_config('app.identifier_change_notes', left(v_reason || ' (requested by ' || v_req.solicitado_por_email || ')', 1000), true);
        IF v_type = 'SINIIGA' THEN
            UPDATE public.cattle_livestock SET rfid_siniiga = v_new WHERE id = v_row.id AND tenant_id = v_req.id_company;
        ELSIF v_type = 'CHIP' THEN
            UPDATE public.cattle_livestock SET electronic_rfid = v_new WHERE id = v_row.id AND tenant_id = v_req.id_company;
        ELSE
            UPDATE public.cattle_livestock SET numero_fuego = v_new WHERE id = v_row.id AND tenant_id = v_req.id_company;
        END IF;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object('success', false, 'motivo', 'identifier_unavailable');
    END;
    PERFORM set_config('app.identifier_gate', '', true);
    PERFORM set_config('app.identifier_change_user', '', true);
    PERFORM set_config('app.identifier_change_reason', '', true);
    PERFORM set_config('app.identifier_change_notes', '', true);
    IF v_rows <> 1 THEN RETURN jsonb_build_object('success', false, 'motivo', 'The animal could not be updated'); END IF;

    v_chip := CASE WHEN v_type = 'CHIP' THEN v_new ELSE v_row.electronic_rfid END;
    INSERT INTO public.historico_movimientos (livestock_id, electronic_rfid, tenant_id, tipo_movimiento, notes)
    VALUES (v_row.id, coalesce(v_chip, v_cur), v_req.id_company, 'CAMBIO_ARETE',
            'Tipo: ' || CASE v_type WHEN 'CHIP' THEN 'ELECTRONIC_RFID' WHEN 'SINIIGA' THEN 'RFID_SINIIGA' ELSE 'NUMERO_FUEGO' END
            || '. Anterior: ' || coalesce(v_cur, '(vacío)') || '. Nuevo: ' || v_new || '. Motivo: ' || v_reason || '. Cambiado por: ' || v_approver);
    RETURN jsonb_build_object('success', true, 'applied', true, 'tag_type', v_type, 'livestock_id', v_row.id);
END;
$fn$;

-- 9. Dispatcher branch in sp_resolver_autorizacion (patched in place; refuses any text other than the measured one) -----------------------
DO $patch$
DECLARE
    v_oid regprocedure := 'public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure;
    v_def text := pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure);
    v_pat text := $r$(\s+)ELSE(\s+)RAISE EXCEPTION 'Tipo de evento % no tiene despachador configurado'$r$;
    v_rep text := $r$\1ELSIF v_request.tipo_evento = 'CAMBIO_ARETE' THEN\1    PERFORM set_config('app.tag_dispatch', p_request_id::text, true);\1    SELECT public.sp_apply_tag_change(p_request_id, p_resuelto_por_email) INTO v_resultado_sp;\1    PERFORM set_config('app.tag_dispatch', '', true);\1ELSE\2RAISE EXCEPTION 'Tipo de evento % no tiene despachador configurado'$r$;
BEGIN
    IF v_def LIKE '%''CAMBIO_ARETE''%' THEN
        RAISE NOTICE 'dispatcher already patched';
        RETURN;
    END IF;
    IF md5(v_def) <> '84913beb0d1f4d0b4168c4789fa6c4b5' THEN
        RAISE EXCEPTION 'ABORT: sp_resolver_autorizacion differs from the measured text (md5 %). Compare with production and rebuild from the live text. Nothing was changed.', md5(v_def);
    END IF;
    IF regexp_count(v_def, v_pat) <> 1 THEN
        RAISE EXCEPTION 'ABORT: expected exactly one dispatcher ELSE branch, found %.', regexp_count(v_def, v_pat);
    END IF;
    EXECUTE regexp_replace(v_def, v_pat, v_rep);
END $patch$;

-- 10. One-pending guard: message names the type (patched in place, md5-gated) --------------------------------------------------------------
DO $patch$
DECLARE
    v_def text := pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure);
    v_pat text := $r$(WHEN 'BAJA_MORTANDAD' THEN 'baja por mortandad')(\s+ELSE lower\(v_tipo\) END)$r$;
BEGIN
    IF v_def LIKE '%''CAMBIO_ARETE''%' THEN RAISE NOTICE 'guard already patched'; RETURN; END IF;
    IF md5(v_def) <> 'aec290a3825f398bbfb7389923377abe' THEN
        RAISE EXCEPTION 'ABORT: fn_pending_auth_one_pending_guard differs from the measured text (md5 %). Nothing was changed.', md5(v_def);
    END IF;
    IF regexp_count(v_def, v_pat) <> 1 THEN RAISE EXCEPTION 'ABORT: guard CASE not found exactly once.'; END IF;
    EXECUTE regexp_replace(v_def, v_pat, $r$\1 WHEN 'CAMBIO_ARETE' THEN 'cambio de arete'\2$r$);
END $patch$;

-- 11. Event log: a tag-change request is no longer a NULL event type (patched in place, exactly-one-match gate) ---------------------------
DO $patch$
DECLARE
    v_def text := pg_get_viewdef('public.vw_cattle_event_log'::regclass, true);
    v_pat text := $r$(WHEN 'VENTA'::text THEN 'SOLICITUD_VENTA'::text)(\s+ELSE NULL::text)$r$;
BEGIN
    IF v_def LIKE '%SOLICITUD_CAMBIO_ARETE%' THEN RAISE NOTICE 'event log already patched'; RETURN; END IF;
    IF regexp_count(v_def, v_pat) <> 1 THEN
        RAISE EXCEPTION 'ABORT: the SOLICITUD_* CASE of vw_cattle_event_log was not found exactly once (found %). Nothing was changed.', regexp_count(v_def, v_pat);
    END IF;
    EXECUTE 'CREATE OR REPLACE VIEW public.vw_cattle_event_log AS ' ||
            rtrim(regexp_replace(v_def, v_pat, $r$\1 WHEN 'CAMBIO_ARETE'::text THEN 'SOLICITUD_CAMBIO_ARETE'::text\2$r$), E';\n\t ');
END $patch$;

-- 12. Post-checks ---------------------------------------------------------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pending_authorizations_tipo_check' AND pg_get_constraintdef(oid) LIKE '%CAMBIO_ARETE%') THEN RAISE EXCEPTION 'POST-CHECK: tipo CHECK.'; END IF;
    IF pg_get_functiondef('public.sp_resolver_autorizacion(uuid,character varying,character varying,text,jsonb)'::regprocedure) NOT LIKE '%sp_apply_tag_change%' THEN RAISE EXCEPTION 'POST-CHECK: dispatcher.'; END IF;
    IF pg_get_functiondef('public.fn_pending_auth_one_pending_guard()'::regprocedure) NOT LIKE '%cambio de arete%' THEN RAISE EXCEPTION 'POST-CHECK: one-pending guard.'; END IF;
    IF pg_get_viewdef('public.vw_cattle_event_log'::regclass, true) NOT LIKE '%SOLICITUD_CAMBIO_ARETE%' THEN RAISE EXCEPTION 'POST-CHECK: event log.'; END IF;
    IF to_regprocedure('public.sp_assign_livestock_identifier(text,text,text,text,text,text)') IS NULL OR to_regprocedure('public.sp_request_tag_change(text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_cancel_tag_change(text,text,text)') IS NULL OR to_regprocedure('public.sp_apply_tag_change(uuid,text)') IS NULL THEN
        RAISE EXCEPTION 'POST-CHECK: a function is missing.';
    END IF;
    RAISE NOTICE '115_tag_change_authorization: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '115_tag_change_authorization: COMMITTED'
\else
ROLLBACK;
\echo '115_tag_change_authorization: DRY RUN, rolled back. Re-run with -v apply=true to commit.'
\endif
\endif
