-- 083_agri_chat_wrappers.sql
-- Palm phase 2b, stage 2: wrapper functions for the palm chat agent (Web Chat and WhatsApp).
--
-- The palm agent has its own tools (postgresTool nodes wired straight to the AI Agent, no MCP server). Each tool is a
-- one-line SELECT of one wrapper below. The tenant and the actor e-mail come from a n8n expression over the verified
-- session (Resolver Empresa Chat / Validar Token, Resolver Tenant), never from the LLM: no tool has a tenant or
-- e-mail parameter. This file adds ONLY functions: no table, no view, no crud_models row, no change to 080-082.
--
-- Fail-closed, in this order, on EVERY call (fn_agri_chat_ctx): the tenant must be a plain integer; the actor must be
-- an active member of an active company (fn_agri_actor_role); the company must be a palm company
-- (fn_company_business_domain = 'PALM'); the role must be allowed for the tool. Anything else answers a status
-- ('forbidden', 'not_palm') and touches no data. The underlying procedures (080/081) still validate role, company
-- and parents on their own: the wrappers add name resolution and friendly answers, they relax nothing.
--
-- Conventions (lessons of v1.18.2 and Rule 15 of the agro-erp CLAUDE.md):
--   * Every parameter is text. The wrapper parses it (NULLIF 'null' / 'undefined' / '' -> NULL; amounts accept
--     "1,300" and "$1,300.50"; dates only AAAA-MM-DD). The tool passes $n::text and String(...) / $fromAI(...,'string').
--   * Expected conditions are answers, not exceptions: jsonb with a 'status' and, when useful, a Spanish 'message'.
--       preview | recorded | voided | ok | disabled
--       need_info          + issues[] (type: missing | ambiguous | not_found | invalid, with field, message,
--                            candidates / options): all the problems of the request in ONE answer
--       duplicate_recent   (same actor, category, amount, date and scope in the last 2 minutes; force with
--                           p_force_duplicate = 'true')
--       forbidden | not_palm | not_found | invalid | already_void
--     Real database errors with a P00xx code (the 080/081 procedures) are returned as status 'invalid' with the
--     Spanish message and the code; any other error is raised.
--   * Writes are two-step: confirmed <> 'true' only validates and answers a 'preview' (nothing is written);
--     confirmed = 'true' revalidates everything and calls the 080/081 procedure.
--   * Names are resolved by lot / plantation code or name, accent- and punctuation-insensitive, exact first and then
--     partial; more than one match is never guessed (status need_info with candidates).
--   * Amounts are returned only to ADMIN / OWNER, except the expense the EDITOR is capturing right now (the preview
--     echoes what that user typed; the 'recorded' answer carries no amount, as sp_agri_record_expense).
--
-- Objects (all in public):
--   helpers   fn_agri_chat_txt, fn_agri_chat_key, fn_agri_chat_num, fn_agri_chat_date, fn_agri_chat_ctx,
--             fn_agri_chat_resolve_scope
--   tools     sp_agri_chat_catalog          (prompt context: categories, units, plantations and lots)
--             sp_agri_chat_structure        -> list_plantations_and_lots   (any member)
--             sp_agri_chat_lot_summary      -> get_lot_summary             (any member)
--             sp_agri_chat_record_expense   -> register_palm_expense       (ADMIN / OWNER / EDITOR)
--             sp_agri_chat_void_expense     -> void_palm_expense           (ADMIN / OWNER)
--             sp_agri_chat_recent_expenses  -> list_recent_palm_expenses   (ADMIN / OWNER)
--             sp_agri_chat_expense_balance  -> palm_expense_balance        (ADMIN / OWNER)
--             sp_agri_chat_record_row_census-> record_row_census           (ADMIN / OWNER / EDITOR)
--
-- Rollback: 083_rollback.sql (no DROP / DELETE: every tool function keeps its signature and answers 'disabled').
-- State:    083_state_check.sql -v expect=before|applied|rolled_back (read-only).
-- Numbering: 084 is reserved for electronic_rfid; agricultural events will be 085.
--
-- Usage (dry run is the default when apply is not given):
--   psql -v ON_ERROR_STOP=1 -f 083_agri_chat_wrappers.sql                 -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true  -f 083_agri_chat_wrappers.sql  -> commit
-- 083_tests.sql includes this file with `embedded` set (the tests own the transaction and roll it back).

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- 0) Preconditions --------------------------------------------------------------------------------------------

DO $$
BEGIN
    IF to_regprocedure('public.fn_company_business_domain(integer)') IS NULL
       OR to_regprocedure('public.sp_agri_record_expense(integer,uuid,uuid,uuid,date,numeric,numeric,varchar,varchar,text,boolean,varchar,varchar)') IS NULL
       OR to_regprocedure('public.sp_agri_record_row_census(integer,uuid,integer,varchar,date,text,varchar,integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migrations 080 and 081 are not applied here.';
    END IF;
END $$;

-- 1) Helpers --------------------------------------------------------------------------------------------------

-- Trimmed text; NULL for '', 'null' and 'undefined' (what a tool sends for an omitted optional parameter).
CREATE OR REPLACE FUNCTION public.fn_agri_chat_txt(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN lower(btrim(coalesce(p, ''))) IN ('', 'null', 'undefined') THEN NULL ELSE btrim(p) END
$$;

-- Comparison key: no accents, lower case, letters and digits only ("L-01", "l 01" and "L01" are the same key).
CREATE OR REPLACE FUNCTION public.fn_agri_chat_key(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT regexp_replace(lower(translate(coalesce(p, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')), '[^a-z0-9]', '', 'g')
$$;

-- Number from text: removes spaces, "$" and thousands commas ("1,300" = 1300). NULL when empty or not a plain number.
CREATE OR REPLACE FUNCTION public.fn_agri_chat_num(p text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v text := public.fn_agri_chat_txt(p);
BEGIN
    IF v IS NULL THEN RETURN NULL; END IF;
    v := regexp_replace(v, '[\s$,]', '', 'g');
    IF v !~ '^[0-9]{1,12}(\.[0-9]{1,6})?$' THEN RETURN NULL; END IF;
    RETURN v::numeric;
END;
$$;

-- Date from AAAA-MM-DD (a longer ISO timestamp keeps its first 10 characters). NULL when empty or not a real date.
CREATE OR REPLACE FUNCTION public.fn_agri_chat_date(p text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v text := left(public.fn_agri_chat_txt(p), 10);
BEGIN
    IF v IS NULL OR v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RETURN NULL; END IF;
    RETURN v::date;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- Session gate. {ok:true, tenant, actor, role} or {ok:false, result:<answer for the tool>}.
-- Order: tenant shape -> active membership in an active company -> palm domain -> role allowed.
CREATE OR REPLACE FUNCTION public.fn_agri_chat_ctx(p_tenant_id text, p_actor_email text, p_allowed_roles text[], p_denied_message text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_t       text := public.fn_agri_chat_txt(p_tenant_id);
    v_tenant  integer;
    v_role    text;
BEGIN
    IF v_t IS NULL OR v_t !~ '^[0-9]{1,9}$' THEN
        RETURN jsonb_build_object('ok', false, 'result', jsonb_build_object('status', 'forbidden',
            'message', 'No pude identificar la empresa activa de esta sesión.'));
    END IF;
    v_tenant := v_t::integer;
    v_role := public.fn_agri_actor_role(v_tenant, p_actor_email);
    IF v_role IS NULL OR NOT EXISTS (SELECT 1 FROM public.companys c WHERE c.id_company = v_tenant AND c.is_active IS NOT FALSE) THEN
        RETURN jsonb_build_object('ok', false, 'result', jsonb_build_object('status', 'forbidden',
            'message', 'Tu usuario no tiene acceso a la empresa activa.'));
    END IF;
    IF public.fn_company_business_domain(v_tenant) IS DISTINCT FROM 'PALM' THEN
        RETURN jsonb_build_object('ok', false, 'result', jsonb_build_object('status', 'not_palm',
            'message', 'La empresa activa no es de palma; este asistente solo opera plantaciones de palma.'));
    END IF;
    IF NOT (v_role = ANY (p_allowed_roles)) THEN
        RETURN jsonb_build_object('ok', false, 'result', jsonb_build_object('status', 'forbidden', 'message', p_denied_message));
    END IF;
    RETURN jsonb_build_object('ok', true, 'tenant', v_tenant, 'actor', lower(btrim(p_actor_email)), 'role', v_role);
END;
$$;

-- Plantation / lot by name. Exact match on code or name first, then partial; never guesses.
-- Answers {status:'ok', plantation_id, plantation_code, plantation_name, lot_id, lot_code, lot_name} (lot_* NULL when no
-- lot was asked) or {status:'ambiguous' | 'not_found' | 'invalid', field, message, candidates | options}.
CREATE OR REPLACE FUNCTION public.fn_agri_chat_resolve_scope(p_tenant_id integer, p_plantation text, p_lot text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_pl     text := public.fn_agri_chat_txt(p_plantation);
    v_lt     text := public.fn_agri_chat_txt(p_lot);
    v_pk     text;
    v_lk     text;
    v_found  jsonb;
    v_n      integer;
    v_pid    uuid;
    v_pcode  text;
    v_pname  text;
BEGIN
    IF v_pl IS NOT NULL THEN
        v_pk := public.fn_agri_chat_key(v_pl);
        IF v_pk = '' THEN
            RETURN jsonb_build_object('status', 'invalid', 'field', 'plantation', 'message', 'No entendí el nombre de la plantación.');
        END IF;
        SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.plantation_code), '[]'::jsonb) INTO v_found
          FROM (SELECT p.id, p.plantation_code, p.plantation_name
                  FROM public.agri_plantations p
                 WHERE p.id_company = p_tenant_id AND p.is_active
                   AND (public.fn_agri_chat_key(p.plantation_code) = v_pk OR public.fn_agri_chat_key(p.plantation_name) = v_pk)) x;
        IF jsonb_array_length(v_found) = 0 THEN
            SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.plantation_code), '[]'::jsonb) INTO v_found
              FROM (SELECT p.id, p.plantation_code, p.plantation_name
                      FROM public.agri_plantations p
                     WHERE p.id_company = p_tenant_id AND p.is_active
                       AND (public.fn_agri_chat_key(p.plantation_code) LIKE '%' || v_pk || '%'
                            OR public.fn_agri_chat_key(p.plantation_name) LIKE '%' || v_pk || '%')) x;
        END IF;
        v_n := jsonb_array_length(v_found);
        IF v_n = 0 THEN
            RETURN jsonb_build_object('status', 'not_found', 'field', 'plantation',
                'message', 'No encontré esa plantación en la empresa.',
                'options', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', p.plantation_code, 'name', p.plantation_name)
                                                       ORDER BY p.plantation_code), '[]'::jsonb)
                              FROM (SELECT plantation_code, plantation_name FROM public.agri_plantations
                                     WHERE id_company = p_tenant_id AND is_active ORDER BY plantation_code LIMIT 15) p));
        ELSIF v_n > 1 THEN
            RETURN jsonb_build_object('status', 'ambiguous', 'field', 'plantation',
                'message', 'Ese nombre coincide con más de una plantación.',
                'candidates', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', e->>'plantation_code', 'name', e->>'plantation_name')), '[]'::jsonb)
                                 FROM (SELECT e FROM jsonb_array_elements(v_found) WITH ORDINALITY t(e, n) ORDER BY n LIMIT 5) s));
        END IF;
        v_pid := (v_found->0->>'id')::uuid;
        v_pcode := v_found->0->>'plantation_code';
        v_pname := v_found->0->>'plantation_name';
    END IF;

    IF v_lt IS NULL THEN
        RETURN jsonb_build_object('status', 'ok', 'plantation_id', v_pid, 'plantation_code', v_pcode, 'plantation_name', v_pname,
                                  'lot_id', NULL, 'lot_code', NULL, 'lot_name', NULL);
    END IF;

    v_lk := public.fn_agri_chat_key(v_lt);
    IF v_lk = '' THEN
        RETURN jsonb_build_object('status', 'invalid', 'field', 'lot', 'message', 'No entendí el nombre del lote.');
    END IF;

    -- Stage 1: code. Stage 2: name. Stage 3: partial on either. The first stage with a match decides.
    SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.plantation_code, x.lot_code), '[]'::jsonb) INTO v_found
      FROM (SELECT l.id AS lot_id, l.plantation_id, l.lot_code, l.lot_name, p.plantation_code, p.plantation_name
              FROM public.agri_lots l
              JOIN public.agri_plantations p ON p.id = l.plantation_id AND p.id_company = l.id_company
             WHERE l.id_company = p_tenant_id AND l.is_active AND p.is_active
               AND (v_pid IS NULL OR l.plantation_id = v_pid)
               AND public.fn_agri_chat_key(l.lot_code) = v_lk) x;
    IF jsonb_array_length(v_found) = 0 THEN
        SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.plantation_code, x.lot_code), '[]'::jsonb) INTO v_found
          FROM (SELECT l.id AS lot_id, l.plantation_id, l.lot_code, l.lot_name, p.plantation_code, p.plantation_name
                  FROM public.agri_lots l
                  JOIN public.agri_plantations p ON p.id = l.plantation_id AND p.id_company = l.id_company
                 WHERE l.id_company = p_tenant_id AND l.is_active AND p.is_active
                   AND (v_pid IS NULL OR l.plantation_id = v_pid)
                   AND public.fn_agri_chat_key(l.lot_name) = v_lk) x;
    END IF;
    IF jsonb_array_length(v_found) = 0 THEN
        SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.plantation_code, x.lot_code), '[]'::jsonb) INTO v_found
          FROM (SELECT l.id AS lot_id, l.plantation_id, l.lot_code, l.lot_name, p.plantation_code, p.plantation_name
                  FROM public.agri_lots l
                  JOIN public.agri_plantations p ON p.id = l.plantation_id AND p.id_company = l.id_company
                 WHERE l.id_company = p_tenant_id AND l.is_active AND p.is_active
                   AND (v_pid IS NULL OR l.plantation_id = v_pid)
                   AND (public.fn_agri_chat_key(l.lot_code) LIKE '%' || v_lk || '%'
                        OR public.fn_agri_chat_key(l.lot_name) LIKE '%' || v_lk || '%')) x;
    END IF;
    v_n := jsonb_array_length(v_found);
    IF v_n = 0 THEN
        RETURN jsonb_build_object('status', 'not_found', 'field', 'lot', 'message', 'No encontré ese lote en la empresa.',
            'options', (SELECT coalesce(jsonb_agg(jsonb_build_object('plantation', s.plantation_code, 'lot_code', s.lot_code, 'lot_name', s.lot_name)
                                                   ORDER BY s.plantation_code, s.lot_code), '[]'::jsonb)
                          FROM (SELECT p.plantation_code, l.lot_code, l.lot_name
                                  FROM public.agri_lots l
                                  JOIN public.agri_plantations p ON p.id = l.plantation_id AND p.id_company = l.id_company
                                 WHERE l.id_company = p_tenant_id AND l.is_active AND p.is_active
                                   AND (v_pid IS NULL OR l.plantation_id = v_pid)
                                 ORDER BY p.plantation_code, l.lot_code LIMIT 15) s));
    ELSIF v_n > 1 THEN
        RETURN jsonb_build_object('status', 'ambiguous', 'field', 'lot', 'message', 'Ese nombre coincide con más de un lote.',
            'candidates', (SELECT coalesce(jsonb_agg(jsonb_build_object('plantation', e->>'plantation_code', 'lot_code', e->>'lot_code', 'lot_name', e->>'lot_name')), '[]'::jsonb)
                             FROM (SELECT e FROM jsonb_array_elements(v_found) WITH ORDINALITY t(e, n) ORDER BY n LIMIT 5) s));
    END IF;
    RETURN jsonb_build_object('status', 'ok',
        'plantation_id', (v_found->0->>'plantation_id')::uuid, 'plantation_code', v_found->0->>'plantation_code',
        'plantation_name', v_found->0->>'plantation_name',
        'lot_id', (v_found->0->>'lot_id')::uuid, 'lot_code', v_found->0->>'lot_code', 'lot_name', v_found->0->>'lot_name');
END;
$$;

-- 2) Read tools -----------------------------------------------------------------------------------------------

-- Context of the agent prompt: company name, the actor's role, active categories, units, plantations and lots. Names are data: newlines are removed
-- and each one is cut at 60 characters before it reaches the prompt.
CREATE OR REPLACE FUNCTION public.sp_agri_chat_catalog(p_tenant_id text, p_actor_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ctx     jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_actor_email, ARRAY['ADMIN', 'OWNER', 'EDITOR', 'CUSTOMER'], 'Sin acceso.');
    v_tenant  integer;
BEGIN
    IF NOT (v_ctx->>'ok')::boolean THEN RETURN v_ctx->'result'; END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    RETURN jsonb_build_object('status', 'ok',
        'company_name', (SELECT left(regexp_replace(c.company_name, '[\r\n\t]+', ' ', 'g'), 60) FROM public.companys c WHERE c.id_company = v_tenant),
        'role', v_ctx->>'role',
        'categories', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', c.category_code,
                              'name', left(regexp_replace(c.category_name, '[\r\n\t]+', ' ', 'g'), 60)) ORDER BY c.sort_order, c.category_code), '[]'::jsonb)
                         FROM public.agri_expense_categories c WHERE c.id_company = v_tenant AND c.is_active),
        'units', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', u.unit_code, 'name', u.unit_name) ORDER BY u.sort_order), '[]'::jsonb)
                    FROM public.agri_unit_catalog u WHERE u.is_active),
        'plantations', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                                'code', left(regexp_replace(p.plantation_code, '[\r\n\t]+', ' ', 'g'), 60),
                                'name', left(regexp_replace(p.plantation_name, '[\r\n\t]+', ' ', 'g'), 60),
                                'lots', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                                                'code', left(regexp_replace(l.lot_code, '[\r\n\t]+', ' ', 'g'), 60),
                                                'name', left(regexp_replace(coalesce(l.lot_name, ''), '[\r\n\t]+', ' ', 'g'), 60)) ORDER BY l.lot_code), '[]'::jsonb)
                                           FROM (SELECT lot_code, lot_name FROM public.agri_lots
                                                  WHERE plantation_id = p.id AND id_company = p.id_company AND is_active
                                                  ORDER BY lot_code LIMIT 80) l)
                            ) ORDER BY p.plantation_code), '[]'::jsonb)
                          FROM public.agri_plantations p WHERE p.id_company = v_tenant AND p.is_active));
END;
$$;
COMMENT ON FUNCTION public.sp_agri_chat_catalog(text, text) IS
  'Palm chat agent: prompt context (categories, units, plantations, lots) of the active palm company. Any active member.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_structure(p_tenant_id text, p_actor_email text, p_plantation text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ctx     jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_actor_email, ARRAY['ADMIN', 'OWNER', 'EDITOR', 'CUSTOMER'], 'Sin acceso.');
    v_tenant  integer;
    v_scope   jsonb;
BEGIN
    IF NOT (v_ctx->>'ok')::boolean THEN RETURN v_ctx->'result'; END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    v_scope := public.fn_agri_chat_resolve_scope(v_tenant, p_plantation, NULL);
    IF v_scope->>'status' <> 'ok' THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', jsonb_build_array(jsonb_build_object('type',
            CASE v_scope->>'status' WHEN 'ambiguous' THEN 'ambiguous' WHEN 'not_found' THEN 'not_found' ELSE 'invalid' END) || v_scope));
    END IF;
    RETURN jsonb_build_object('status', 'ok', 'plantations', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
                   'code', s.plantation_code, 'name', s.plantation_name, 'is_default', s.is_default,
                   'total_area_ha', s.total_area_ha, 'planted_area_ha', s.planted_area_ha,
                   'active_lots', s.active_lots, 'active_rows', s.active_rows,
                   'alive_plants', s.alive_plants, 'missing_plants', s.missing_plants,
                   'lots', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                                    'lot_code', ls.lot_code, 'lot_name', ls.lot_name, 'area_ha', ls.area_ha,
                                    'active_rows', ls.active_rows, 'alive_plants', ls.alive_plants) ORDER BY ls.lot_code), '[]'::jsonb)
                              FROM (SELECT lot_code, lot_name, area_ha, active_rows, alive_plants
                                      FROM public.vw_agri_lot_summary
                                     WHERE id_company = v_tenant AND plantation_id = s.id AND is_active
                                     ORDER BY lot_code LIMIT 60) ls)
               ) ORDER BY s.plantation_code), '[]'::jsonb)
          FROM public.vw_agri_plantation_summary s
         WHERE s.id_company = v_tenant AND s.is_active
           AND (v_scope->>'plantation_id' IS NULL OR s.id = (v_scope->>'plantation_id')::uuid)));
END;
$$;
COMMENT ON FUNCTION public.sp_agri_chat_structure(text, text, text) IS
  'Palm chat agent, list_plantations_and_lots: plantations and lots of the active palm company, no amounts. Any active member.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_lot_summary(p_tenant_id text, p_actor_email text, p_lot text, p_plantation text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ctx     jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_actor_email, ARRAY['ADMIN', 'OWNER', 'EDITOR', 'CUSTOMER'], 'Sin acceso.');
    v_tenant  integer;
    v_scope   jsonb;
BEGIN
    IF NOT (v_ctx->>'ok')::boolean THEN RETURN v_ctx->'result'; END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    IF public.fn_agri_chat_txt(p_lot) IS NULL THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', jsonb_build_array(jsonb_build_object(
            'type', 'missing', 'field', 'lot', 'message', 'Indica de qué lote quieres el resumen.')));
    END IF;
    v_scope := public.fn_agri_chat_resolve_scope(v_tenant, p_plantation, p_lot);
    IF v_scope->>'status' <> 'ok' THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', jsonb_build_array(jsonb_build_object('type',
            CASE v_scope->>'status' WHEN 'ambiguous' THEN 'ambiguous' WHEN 'not_found' THEN 'not_found' ELSE 'invalid' END) || v_scope));
    END IF;
    RETURN (SELECT jsonb_build_object('status', 'ok',
                'plantation_name', s.plantation_name, 'lot_code', s.lot_code, 'lot_name', s.lot_name, 'area_ha', s.area_ha,
                'planting_date', s.planting_date, 'planting_date_is_approx', s.planting_date_is_approx,
                'variety', s.variety_name, 'age_years', s.age_years,
                'productive_stage', s.productive_stage, 'productive_stage_note', 'Etapa orientativa por años desde la siembra.',
                'effective_tenure', s.effective_tenure, 'active_rows', s.active_rows,
                'planting_positions', s.planting_positions, 'alive_plants', s.alive_plants, 'missing_plants', s.missing_plants,
                'real_density_plants_ha', s.real_density_plants_ha, 'design_density_plants_ha', s.design_density_plants_ha,
                'density_pct_of_design', s.density_pct_of_design, 'last_census_date', s.last_census_date)
              FROM public.vw_agri_lot_summary s
             WHERE s.id_company = v_tenant AND s.id = (v_scope->>'lot_id')::uuid);
END;
$$;
COMMENT ON FUNCTION public.sp_agri_chat_lot_summary(text, text, text, text) IS
  'Palm chat agent, get_lot_summary: one lot of the active palm company, no amounts. Any active member.';

-- 3) Expenses -------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_agri_chat_record_expense(
    p_tenant_id        text,
    p_actor_email      text,
    p_category_code    text,
    p_amount           text,
    p_expense_date     text,
    p_plantation       text,
    p_lot              text,
    p_quantity         text,
    p_unit_code        text,
    p_supplier_name    text,
    p_description      text,
    p_is_invoiced      text,
    p_invoice_folio    text,
    p_confirmed        text,
    p_force_duplicate  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    c_window        constant interval := interval '2 minutes';
    v_ctx           jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_actor_email, ARRAY['ADMIN', 'OWNER', 'EDITOR'],
                                                     'Tu rol en la empresa no permite registrar gastos.');
    v_tenant        integer;
    v_actor         text;
    v_confirmed     boolean := lower(coalesce(public.fn_agri_chat_txt(p_confirmed), 'false')) = 'true';
    v_force         boolean := lower(coalesce(public.fn_agri_chat_txt(p_force_duplicate), 'false')) = 'true';
    v_issues        jsonb := '[]'::jsonb;
    v_code          text := public.fn_agri_chat_txt(p_category_code);
    v_cat           record;
    v_amount_txt    text := public.fn_agri_chat_txt(p_amount);
    v_amount        numeric := public.fn_agri_chat_num(p_amount);
    v_date_txt      text := public.fn_agri_chat_txt(p_expense_date);
    v_date          date := public.fn_agri_chat_date(p_expense_date);
    v_qty_txt       text := public.fn_agri_chat_txt(p_quantity);
    v_qty           numeric := public.fn_agri_chat_num(p_quantity);
    v_unit_txt      text := public.fn_agri_chat_txt(p_unit_code);
    v_unit_code     text;
    v_unit_name     text;
    v_folio         text := left(public.fn_agri_chat_txt(p_invoice_folio), 60);
    v_inv_txt       text := lower(public.fn_agri_chat_txt(p_is_invoiced));
    v_invoiced      boolean;
    v_supplier      text := left(public.fn_agri_chat_txt(p_supplier_name), 150);
    v_desc          text := left(public.fn_agri_chat_txt(p_description), 500);
    v_scope         jsonb;
    v_pid           uuid;
    v_lid           uuid;
    v_scope_kind    text;
    v_scope_label   text;
    v_dup           timestamp;
    v_summary       jsonb;
    v_res           jsonb;
BEGIN
    IF NOT (v_ctx->>'ok')::boolean THEN RETURN v_ctx->'result'; END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    v_actor := v_ctx->>'actor';

    -- Category: the code first, then the exact name (same key rule). Never guessed.
    IF v_code IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'category_code', 'message', 'Falta la categoría del gasto.');
    ELSE
        SELECT c.id, c.category_code, c.category_name INTO v_cat
          FROM public.agri_expense_categories c
         WHERE c.id_company = v_tenant AND c.is_active
           AND (c.category_code = upper(btrim(v_code)) OR public.fn_agri_chat_key(c.category_name) = public.fn_agri_chat_key(v_code))
         ORDER BY (c.category_code = upper(btrim(v_code))) DESC
         LIMIT 1;
        IF NOT FOUND THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'category_code',
                'message', 'Esa categoría no existe en la empresa; elige una de las opciones.',
                'options', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', category_code, 'name', category_name) ORDER BY sort_order), '[]'::jsonb)
                              FROM public.agri_expense_categories WHERE id_company = v_tenant AND is_active));
        END IF;
    END IF;

    IF v_amount_txt IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'amount', 'message', 'Falta el monto del gasto.');
    ELSIF v_amount IS NULL OR v_amount <= 0 OR v_amount <> round(v_amount, 2) OR v_amount > 9999999999.99 THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'amount',
            'message', 'El monto debe ser un número mayor que 0, con máximo 2 decimales.');
    END IF;

    IF v_date_txt IS NULL THEN
        v_date := public.fn_agri_today_cdmx();
    ELSIF v_date IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'expense_date', 'message', 'No entendí la fecha; usa el formato AAAA-MM-DD.');
    ELSIF v_date > public.fn_agri_today_cdmx() THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'expense_date', 'message', 'La fecha del gasto no puede ser futura.');
    END IF;

    -- Quantity and unit go together.
    IF v_qty_txt IS NOT NULL AND (v_qty IS NULL OR v_qty <= 0 OR v_qty <> round(v_qty, 3) OR v_qty > 999999999.999) THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'quantity', 'message', 'La cantidad debe ser un número mayor que 0, con máximo 3 decimales.');
    END IF;
    IF v_unit_txt IS NOT NULL THEN
        SELECT u.unit_code, u.unit_name INTO v_unit_code, v_unit_name
          FROM public.agri_unit_catalog u
         WHERE u.is_active AND (u.unit_code = upper(btrim(v_unit_txt)) OR public.fn_agri_chat_key(u.unit_name) = public.fn_agri_chat_key(v_unit_txt))
         ORDER BY (u.unit_code = upper(btrim(v_unit_txt))) DESC LIMIT 1;
        IF NOT FOUND THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'unit_code', 'message', 'Esa unidad no está en el catálogo.',
                'options', (SELECT jsonb_agg(jsonb_build_object('code', unit_code, 'name', unit_name) ORDER BY sort_order)
                              FROM public.agri_unit_catalog WHERE is_active));
        END IF;
    END IF;
    IF v_qty_txt IS NOT NULL AND v_unit_txt IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'unit_code', 'message', 'Indica la unidad de la cantidad.');
    ELSIF v_qty_txt IS NULL AND v_unit_txt IS NOT NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'quantity', 'message', 'Indica la cantidad de esa unidad.');
    END IF;

    -- Invoice: a folio implies invoiced unless the user said it was not.
    v_invoiced := CASE WHEN v_inv_txt IN ('true', 't', '1') THEN true WHEN v_inv_txt IN ('false', 'f', '0') THEN false END;
    IF v_folio IS NOT NULL AND v_invoiced IS NULL THEN v_invoiced := true; END IF;
    v_invoiced := coalesce(v_invoiced, false);
    IF v_folio IS NOT NULL AND NOT v_invoiced THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'invoice_folio', 'message', 'El folio de factura solo aplica a un gasto facturado.');
    END IF;

    -- Scope: none = general expense of the company.
    v_scope := public.fn_agri_chat_resolve_scope(v_tenant, p_plantation, p_lot);
    IF v_scope->>'status' <> 'ok' THEN
        v_issues := v_issues || (jsonb_build_object('type', CASE v_scope->>'status' WHEN 'ambiguous' THEN 'ambiguous' WHEN 'not_found' THEN 'not_found' ELSE 'invalid' END) || v_scope);
    ELSE
        v_pid := (v_scope->>'plantation_id')::uuid;
        v_lid := (v_scope->>'lot_id')::uuid;
    END IF;

    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', v_issues);
    END IF;

    v_scope_kind := CASE WHEN v_lid IS NOT NULL THEN 'LOT' WHEN v_pid IS NOT NULL THEN 'PLANTATION' ELSE 'GENERAL' END;
    v_scope_label := CASE v_scope_kind
                         WHEN 'LOT' THEN (v_scope->>'plantation_name') || ' / ' || (v_scope->>'lot_code')
                                         || coalesce(' — ' || (v_scope->>'lot_name'), '')
                         WHEN 'PLANTATION' THEN v_scope->>'plantation_name'
                         ELSE 'General de la empresa (sin plantación ni lote)'
                     END;

    -- Same actor, category, amount, date and scope within the window: a double call or a double tap.
    IF NOT v_force THEN
        SELECT e.created_at INTO v_dup
          FROM public.agri_expenses e
         WHERE e.id_company = v_tenant AND lower(e.reported_by_email) = v_actor AND NOT e.is_void
           AND e.category_id = v_cat.id AND e.amount = v_amount AND e.expense_date = v_date
           AND e.plantation_id IS NOT DISTINCT FROM v_pid AND e.lot_id IS NOT DISTINCT FROM v_lid
           AND e.created_at >= public.fn_agri_utc_now() - c_window
         ORDER BY e.created_at DESC LIMIT 1;
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'duplicate_recent',
                'message', 'Ya registraste un gasto idéntico (misma categoría, monto, fecha y alcance) hace menos de 2 minutos. '
                           || 'Si de verdad es otro gasto igual, confírmaselo al usuario y repite la llamada con force_duplicate = true.');
        END IF;
    END IF;

    v_summary := jsonb_build_object('category_code', v_cat.category_code, 'category_name', v_cat.category_name,
        'amount', v_amount, 'expense_date', v_date, 'scope', v_scope_kind, 'scope_label', v_scope_label,
        'quantity', v_qty, 'unit_code', v_unit_code, 'unit_name', v_unit_name,
        'supplier_name', v_supplier, 'description', v_desc, 'is_invoiced', v_invoiced, 'invoice_folio', v_folio);

    IF NOT v_confirmed THEN
        RETURN jsonb_build_object('status', 'preview', 'summary', v_summary);
    END IF;

    BEGIN
        v_res := public.sp_agri_record_expense(v_tenant, v_pid, v_lid, v_cat.id, v_date, v_amount, v_qty, v_unit_code,
                                               v_supplier, v_desc, v_invoiced, v_folio, v_actor);
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE LIKE 'P00%' THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', SQLSTATE, 'message', SQLERRM);
        END IF;
        RAISE;
    END;
    -- No amount in the answer (the EDITOR does not read amounts).
    RETURN jsonb_build_object('status', 'recorded', 'message', 'Gasto registrado', 'expense_id', v_res->>'expense_id',
                              'expense_date', v_date, 'scope', v_scope_kind, 'scope_label', v_scope_label);
END;
$$;
COMMENT ON FUNCTION public.sp_agri_chat_record_expense(text, text, text, text, text, text, text, text, text, text, text, text, text, text, text) IS
  'Palm chat agent, register_palm_expense (ADMIN/OWNER/EDITOR). confirmed <> true -> preview, nothing written; confirmed = true -> sp_agri_record_expense. 2-minute duplicate guard (force_duplicate = true overrides).';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_recent_expenses(
    p_tenant_id      text,
    p_actor_email    text,
    p_limit          text DEFAULT NULL,
    p_date_from      text DEFAULT NULL,
    p_category_code  text DEFAULT NULL,
    p_lot            text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ctx      jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_actor_email, ARRAY['ADMIN', 'OWNER'],
                                                'Solo un administrador de la empresa puede consultar los gastos con sus montos.');
    v_tenant   integer;
    v_limit    integer;
    v_from_txt text := public.fn_agri_chat_txt(p_date_from);
    v_from     date := public.fn_agri_chat_date(p_date_from);
    v_code     text := public.fn_agri_chat_txt(p_category_code);
    v_cat_id   uuid;
    v_issues   jsonb := '[]'::jsonb;
    v_scope    jsonb;
BEGIN
    IF NOT (v_ctx->>'ok')::boolean THEN RETURN v_ctx->'result'; END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    v_limit := CASE WHEN public.fn_agri_chat_txt(p_limit) ~ '^[0-9]{1,3}$' THEN least(greatest(public.fn_agri_chat_txt(p_limit)::integer, 1), 10) ELSE 5 END;

    IF v_from_txt IS NOT NULL AND v_from IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'date_from', 'message', 'No entendí la fecha; usa el formato AAAA-MM-DD.');
    END IF;
    IF v_code IS NOT NULL THEN
        SELECT c.id INTO v_cat_id FROM public.agri_expense_categories c
         WHERE c.id_company = v_tenant AND c.is_active
           AND (c.category_code = upper(btrim(v_code)) OR public.fn_agri_chat_key(c.category_name) = public.fn_agri_chat_key(v_code))
         ORDER BY (c.category_code = upper(btrim(v_code))) DESC LIMIT 1;
        IF NOT FOUND THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'category_code', 'message', 'Esa categoría no existe en la empresa.',
                'options', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', category_code, 'name', category_name) ORDER BY sort_order), '[]'::jsonb)
                              FROM public.agri_expense_categories WHERE id_company = v_tenant AND is_active));
        END IF;
    END IF;
    v_scope := public.fn_agri_chat_resolve_scope(v_tenant, NULL, p_lot);
    IF v_scope->>'status' <> 'ok' THEN
        v_issues := v_issues || (jsonb_build_object('type', CASE v_scope->>'status' WHEN 'ambiguous' THEN 'ambiguous' WHEN 'not_found' THEN 'not_found' ELSE 'invalid' END) || v_scope);
    END IF;
    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', v_issues);
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'expenses', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
                   'ref', left(x.id::text, 8), 'expense_date', x.expense_date, 'category_name', x.category_name,
                   'amount', x.amount, 'plantation_name', x.plantation_name, 'lot_code', x.lot_code,
                   'supplier_name', x.supplier_name, 'description', left(x.description, 120),
                   'reported_by_email', x.reported_by_email) ORDER BY x.expense_date DESC, x.created_at DESC), '[]'::jsonb)
          FROM (SELECT * FROM public.vw_agri_expense_list e
                 WHERE e.id_company = v_tenant AND NOT e.is_void
                   AND (v_from IS NULL OR e.expense_date >= v_from)
                   AND (v_cat_id IS NULL OR e.category_id = v_cat_id)
                   AND (v_scope->>'lot_id' IS NULL OR e.lot_id = (v_scope->>'lot_id')::uuid)
                 ORDER BY e.expense_date DESC, e.created_at DESC LIMIT v_limit) x));
END;
$$;
COMMENT ON FUNCTION public.sp_agri_chat_recent_expenses(text, text, text, text, text, text) IS
  'Palm chat agent, list_recent_palm_expenses (ADMIN/OWNER, with amounts): last N non-voided expenses; ref = first 8 characters of the id.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_void_expense(
    p_tenant_id     text,
    p_actor_email   text,
    p_expense_ref   text,
    p_reason        text,
    p_confirmed     text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_ctx        jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_actor_email, ARRAY['ADMIN', 'OWNER'],
                                                  'Solo un administrador de la empresa puede anular gastos.');
    v_tenant     integer;
    v_actor      text;
    v_ref        text := lower(public.fn_agri_chat_txt(p_expense_ref));
    v_reason     text := left(public.fn_agri_chat_txt(p_reason), 300);
    v_confirmed  boolean := lower(coalesce(public.fn_agri_chat_txt(p_confirmed), 'false')) = 'true';
    v_issues     jsonb := '[]'::jsonb;
    v_found      jsonb;
    v_n          integer;
    v_e          jsonb;
    v_res        jsonb;
BEGIN
    IF NOT (v_ctx->>'ok')::boolean THEN RETURN v_ctx->'result'; END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    v_actor := v_ctx->>'actor';

    IF v_ref IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'expense_ref', 'message', 'Indica qué gasto anular (usa la lista de gastos recientes).');
    ELSIF v_ref !~ '^[0-9a-f-]{8,36}$' THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'expense_ref', 'message', 'La referencia del gasto no es válida; toma la "ref" de la lista de gastos recientes.');
    END IF;
    IF v_reason IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'reason', 'message', 'Falta el motivo de la anulación.');
    END IF;
    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', v_issues);
    END IF;

    SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_found
      FROM (SELECT e.id, e.is_void, e.expense_date, e.category_name, e.amount, e.plantation_name, e.lot_code, e.supplier_name,
                   left(e.description, 120) AS description
              FROM public.vw_agri_expense_list e
             WHERE e.id_company = v_tenant AND e.id::text LIKE v_ref || '%'
             LIMIT 2) x;
    v_n := jsonb_array_length(v_found);
    IF v_n = 0 THEN
        RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontré ese gasto en la empresa.');
    ELSIF v_n > 1 THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', jsonb_build_array(jsonb_build_object('type', 'ambiguous',
            'field', 'expense_ref', 'message', 'La referencia coincide con más de un gasto; usa más caracteres.')));
    END IF;
    v_e := v_found->0;
    IF (v_e->>'is_void')::boolean THEN
        RETURN jsonb_build_object('status', 'already_void', 'message', 'Ese gasto ya estaba anulado.');
    END IF;

    IF NOT v_confirmed THEN
        RETURN jsonb_build_object('status', 'preview', 'summary', (v_e - 'id' - 'is_void') || jsonb_build_object('reason', v_reason));
    END IF;
    BEGIN
        v_res := public.sp_agri_void_expense(v_tenant, (v_e->>'id')::uuid, v_reason, v_actor);
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE LIKE 'P00%' THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', SQLSTATE, 'message', SQLERRM);
        END IF;
        RAISE;
    END;
    RETURN jsonb_build_object('status', 'voided', 'message', 'Gasto anulado');
END;
$$;
COMMENT ON FUNCTION public.sp_agri_chat_void_expense(text, text, text, text, text) IS
  'Palm chat agent, void_palm_expense (ADMIN/OWNER): expense_ref = id prefix (8+ hex) from the recent list; reason required; confirmed <> true -> preview.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_expense_balance(
    p_tenant_id      text,
    p_actor_email    text,
    p_period         text DEFAULT NULL,
    p_date_from      text DEFAULT NULL,
    p_date_to        text DEFAULT NULL,
    p_plantation     text DEFAULT NULL,
    p_lot            text DEFAULT NULL,
    p_category_code  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    -- The role check comes before anything is read: an EDITOR gets the polite refusal and no figure.
    v_ctx      jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_actor_email, ARRAY['ADMIN', 'OWNER'],
                                                'El balance de gastos solo lo consultan los administradores de la empresa.');
    v_tenant   integer;
    v_period   text := upper(coalesce(public.fn_agri_chat_txt(p_period), 'THIS_MONTH'));
    v_today    date := public.fn_agri_today_cdmx();
    v_from     date;
    v_to       date;
    v_grain    text := 'MONTH';
    v_code     text := public.fn_agri_chat_txt(p_category_code);
    v_cat_id   uuid;
    v_issues   jsonb := '[]'::jsonb;
    v_scope    jsonb;
    v_res      jsonb;
BEGIN
    IF NOT (v_ctx->>'ok')::boolean THEN RETURN v_ctx->'result'; END IF;
    v_tenant := (v_ctx->>'tenant')::integer;

    IF v_period = 'TODAY' THEN v_from := v_today; v_to := v_today; v_grain := 'DAY';
    ELSIF v_period = 'THIS_WEEK' THEN v_from := date_trunc('week', v_today::timestamp)::date; v_to := v_today; v_grain := 'WEEK';
    ELSIF v_period = 'THIS_MONTH' THEN v_from := date_trunc('month', v_today::timestamp)::date; v_to := v_today;
    ELSIF v_period = 'LAST_MONTH' THEN
        v_from := (date_trunc('month', v_today::timestamp) - interval '1 month')::date;
        v_to := (date_trunc('month', v_today::timestamp) - interval '1 day')::date;
    ELSIF v_period = 'THIS_YEAR' THEN v_from := date_trunc('year', v_today::timestamp)::date; v_to := v_today;
    ELSIF v_period = 'CUSTOM' THEN
        v_from := public.fn_agri_chat_date(p_date_from);
        v_to := public.fn_agri_chat_date(p_date_to);
        IF v_from IS NULL OR v_to IS NULL THEN
            v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'date_from', 'message', 'Para un periodo personalizado indica fecha inicial y final (AAAA-MM-DD).');
        ELSIF v_from > v_to THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'date_from', 'message', 'La fecha inicial no puede ser posterior a la final.');
        END IF;
    ELSE
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'period',
            'message', 'Periodo no válido: usa TODAY, THIS_WEEK, THIS_MONTH, LAST_MONTH, THIS_YEAR o CUSTOM.');
    END IF;

    IF v_code IS NOT NULL THEN
        SELECT c.id INTO v_cat_id FROM public.agri_expense_categories c
         WHERE c.id_company = v_tenant AND c.is_active
           AND (c.category_code = upper(btrim(v_code)) OR public.fn_agri_chat_key(c.category_name) = public.fn_agri_chat_key(v_code))
         ORDER BY (c.category_code = upper(btrim(v_code))) DESC LIMIT 1;
        IF NOT FOUND THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'category_code', 'message', 'Esa categoría no existe en la empresa.',
                'options', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', category_code, 'name', category_name) ORDER BY sort_order), '[]'::jsonb)
                              FROM public.agri_expense_categories WHERE id_company = v_tenant AND is_active));
        END IF;
    END IF;
    v_scope := public.fn_agri_chat_resolve_scope(v_tenant, p_plantation, p_lot);
    IF v_scope->>'status' <> 'ok' THEN
        v_issues := v_issues || (jsonb_build_object('type', CASE v_scope->>'status' WHEN 'ambiguous' THEN 'ambiguous' WHEN 'not_found' THEN 'not_found' ELSE 'invalid' END) || v_scope);
    END IF;
    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', v_issues);
    END IF;

    BEGIN
        v_res := public.sp_agri_expense_balance(v_tenant, v_from, v_to, v_grain, (v_scope->>'plantation_id')::uuid,
                                                (v_scope->>'lot_id')::uuid, v_cat_id, v_ctx->>'actor');
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE LIKE 'P00%' THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', SQLSTATE, 'message', SQLERRM);
        END IF;
        RAISE;
    END;
    RETURN jsonb_build_object('status', 'ok', 'scope', 'Total de TODA la empresa (no solo del usuario)', 'period', v_period,
        'date_from', v_res->'date_from', 'date_to', v_res->'date_to',
        'total_amount', v_res->'total_amount', 'expense_count', v_res->'expense_count', 'general_amount', v_res->'general_amount',
        'by_category', (SELECT coalesce(jsonb_agg(jsonb_build_object('category_name', s.e->>'category_name', 'total_amount', s.e->'total_amount',
                                                                      'expense_count', s.e->'expense_count') ORDER BY s.n), '[]'::jsonb)
                          FROM (SELECT e, n FROM jsonb_array_elements(v_res->'by_category') WITH ORDINALITY t(e, n) ORDER BY n LIMIT 5) s),
        'by_lot', (SELECT coalesce(jsonb_agg(jsonb_build_object('lot_code', s.e->>'lot_code', 'lot_name', s.e->>'lot_name', 'total_amount', s.e->'total_amount',
                                                                 'expense_count', s.e->'expense_count') ORDER BY s.n), '[]'::jsonb)
                     FROM (SELECT e, n FROM jsonb_array_elements(v_res->'by_lot') WITH ORDINALITY t(e, n) ORDER BY n LIMIT 5) s),
        'by_plantation', (SELECT coalesce(jsonb_agg(jsonb_build_object('plantation_name', coalesce(s.e->>'plantation_name', 'General'),
                                                                        'total_amount', s.e->'total_amount', 'expense_count', s.e->'expense_count') ORDER BY s.n), '[]'::jsonb)
                            FROM (SELECT e, n FROM jsonb_array_elements(v_res->'by_plantation') WITH ORDINALITY t(e, n) ORDER BY n LIMIT 5) s));
END;
$$;
COMMENT ON FUNCTION public.sp_agri_chat_expense_balance(text, text, text, text, text, text, text, text) IS
  'Palm chat agent, palm_expense_balance (ADMIN/OWNER; EDITOR gets a polite refusal before any read): totals of the whole company for a named period.';

-- 4) Row census -----------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_agri_chat_record_row_census(
    p_tenant_id      text,
    p_actor_email    text,
    p_lot            text,
    p_plantation     text,
    p_row_number     text,
    p_alive_plants   text,
    p_reason         text,
    p_census_date    text,
    p_notes          text,
    p_confirmed      text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_ctx        jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_actor_email, ARRAY['ADMIN', 'OWNER', 'EDITOR'],
                                                  'Tu rol en la empresa no permite registrar conteos.');
    v_tenant     integer;
    v_actor      text;
    v_confirmed  boolean := lower(coalesce(public.fn_agri_chat_txt(p_confirmed), 'false')) = 'true';
    v_issues     jsonb := '[]'::jsonb;
    v_lot_txt    text := public.fn_agri_chat_txt(p_lot);
    v_rn_txt     text := public.fn_agri_chat_txt(p_row_number);
    v_alive_txt  text := public.fn_agri_chat_txt(p_alive_plants);
    v_reason     text := upper(coalesce(public.fn_agri_chat_txt(p_reason), 'CENSO'));
    v_date_txt   text := public.fn_agri_chat_txt(p_census_date);
    v_date       date := public.fn_agri_chat_date(p_census_date);
    v_notes      text := left(public.fn_agri_chat_txt(p_notes), 300);
    v_scope      jsonb;
    v_row        record;
    v_alive      integer;
    v_rn         integer;
    v_res        jsonb;
BEGIN
    IF NOT (v_ctx->>'ok')::boolean THEN RETURN v_ctx->'result'; END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    v_actor := v_ctx->>'actor';

    IF v_lot_txt IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'lot', 'message', 'Falta el lote del conteo.');
    END IF;
    IF v_rn_txt IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'row_number', 'message', 'Falta el número de fila.');
    ELSIF v_rn_txt !~ '^[0-9]{1,6}$' OR v_rn_txt::integer = 0 THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'row_number', 'message', 'El número de fila debe ser un entero mayor que 0.');
    END IF;
    IF v_alive_txt IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'alive_plants', 'message', 'Falta el número de plantas vivas.');
    ELSIF v_alive_txt !~ '^[0-9]{1,6}$' THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'alive_plants', 'message', 'Las plantas vivas deben ser un entero de 0 en adelante.');
    END IF;
    IF v_reason NOT IN ('CENSO', 'RESIEMBRA', 'PERDIDA', 'CORRECCION_CAPTURA') THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'reason', 'message', 'Motivo no válido: usa CENSO, RESIEMBRA, PERDIDA o CORRECCION_CAPTURA.');
    END IF;
    IF v_date_txt IS NULL THEN
        v_date := public.fn_agri_today_cdmx();
    ELSIF v_date IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'census_date', 'message', 'No entendí la fecha; usa el formato AAAA-MM-DD.');
    ELSIF v_date > public.fn_agri_today_cdmx() THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'census_date', 'message', 'La fecha del conteo no puede ser futura.');
    END IF;

    IF v_lot_txt IS NOT NULL THEN
        v_scope := public.fn_agri_chat_resolve_scope(v_tenant, p_plantation, v_lot_txt);
        IF v_scope->>'status' <> 'ok' THEN
            v_issues := v_issues || (jsonb_build_object('type', CASE v_scope->>'status' WHEN 'ambiguous' THEN 'ambiguous' WHEN 'not_found' THEN 'not_found' ELSE 'invalid' END) || v_scope);
        END IF;
    END IF;
    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', v_issues);
    END IF;

    v_rn := v_rn_txt::integer;
    v_alive := v_alive_txt::integer;
    SELECT r.id, r.row_number, r.planting_positions, r.alive_plants, r.last_census_date INTO v_row
      FROM public.agri_rows r
     WHERE r.id_company = v_tenant AND r.lot_id = (v_scope->>'lot_id')::uuid AND r.row_number = v_rn AND r.is_active;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', jsonb_build_array(jsonb_build_object(
            'type', 'not_found', 'field', 'row_number', 'message', 'Esa fila no existe en el lote.',
            'rows_available', (SELECT jsonb_build_object('count', count(*), 'first', min(row_number), 'last', max(row_number))
                                 FROM public.agri_rows WHERE id_company = v_tenant AND lot_id = (v_scope->>'lot_id')::uuid AND is_active))));
    END IF;
    IF v_alive > v_row.planting_positions THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', jsonb_build_array(jsonb_build_object(
            'type', 'invalid', 'field', 'alive_plants',
            'message', format('La fila %s tiene %s puntos de plantación; no puede haber %s plantas vivas.', v_rn, v_row.planting_positions, v_alive))));
    END IF;

    IF NOT v_confirmed THEN
        RETURN jsonb_build_object('status', 'preview', 'summary', jsonb_build_object(
            'plantation_name', v_scope->>'plantation_name', 'lot_code', v_scope->>'lot_code', 'lot_name', v_scope->>'lot_name',
            'row_number', v_rn, 'planting_positions', v_row.planting_positions,
            'previous_alive_plants', v_row.alive_plants, 'new_alive_plants', v_alive, 'change', v_alive - v_row.alive_plants,
            'reason', v_reason, 'census_date', v_date, 'last_census_date', v_row.last_census_date, 'notes', v_notes));
    END IF;

    BEGIN
        -- planting_positions stays NULL: the chat never changes them (ADMIN / OWNER do it in the web).
        v_res := public.sp_agri_record_row_census(v_tenant, v_row.id, v_alive, v_reason, v_date, v_notes, v_actor, NULL);
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE LIKE 'P00%' THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', SQLSTATE, 'message', SQLERRM);
        END IF;
        RAISE;
    END;
    RETURN jsonb_build_object('status', 'recorded', 'message', 'Conteo registrado', 'lot_code', v_scope->>'lot_code', 'row_number', v_rn,
                              'previous_alive_plants', v_res->'previous_alive', 'alive_plants', v_res->'alive_plants',
                              'census_date', v_date, 'changed', v_res->'changed');
END;
$$;
COMMENT ON FUNCTION public.sp_agri_chat_record_row_census(text, text, text, text, text, text, text, text, text, text) IS
  'Palm chat agent, record_row_census (ADMIN/OWNER/EDITOR): lot + row number + alive plants; confirmed <> true -> preview (before/after); never changes planting_positions.';

-- 5) Sanity ---------------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY['sp_agri_chat_catalog', 'sp_agri_chat_structure', 'sp_agri_chat_lot_summary', 'sp_agri_chat_record_expense',
                        'sp_agri_chat_void_expense', 'sp_agri_chat_recent_expenses', 'sp_agri_chat_expense_balance',
                        'sp_agri_chat_record_row_census', 'fn_agri_chat_ctx', 'fn_agri_chat_resolve_scope']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '083: missing functions: %', v_missing;
    END IF;
    IF public.fn_agri_chat_num('$1,300.50') <> 1300.50 OR public.fn_agri_chat_num('abc') IS NOT NULL THEN
        RAISE EXCEPTION '083: fn_agri_chat_num sanity failed';
    END IF;
    RAISE NOTICE '083: OK';
END $$;

\if :{?embedded}
\echo '*** 083 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 083 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
