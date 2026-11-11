-- 099_livestock_regularization.sql
-- Livestock intake from the chat agents (Web Chat and WhatsApp): a new "regularization" intake for real animals that were
-- never captured (evidence: the transit guide), and a hardened purchase intake. Both are two-step (preview, then commit
-- with the preview_hash after the user's "Sí") and answer a jsonb 'status' instead of silent empty results.
--
-- WHY: on 2026-11-05 a real calf that was missing from the system was registered through the purchase tool with an
-- invented price (0), seller ("desconocido") and purchase date, and an origin UPP code as production_unit_name, which
-- resolved nothing: the animal was created with no production unit, no lot and a false metadata.source = 'COMPRA'.
--
-- This file adds ONLY functions: no table, view, trigger, index or crud_models row, and no existing row is modified.
-- The two tool functions are called by postgresTool nodes wired straight to the livestock AI Agents (palm pattern, 083).
-- The tenant, the actor e-mail and the channel come from n8n expressions over the verified session
-- (Resolver Empresa Chat / Validar Token, Resolver Tenant), never from the LLM.
--
-- Fail-closed, in this order, on EVERY call (fn_livestock_chat_ctx): the tenant must be a plain integer; the actor must be
-- an active member of an active company; the company must not be a palm company; the role must be ADMIN, OWNER or
-- EDITOR (CUSTOMER is read-only). Anything else answers a status and touches no data.
--
-- Production unit (UPP): resolved inside the verified company, active units only. No name given: exactly one active UPP
-- is used, none or several answer need_info. A name given: exact match (case-, accent- and space-insensitive) on
-- ranch_name, or on upp_code written with or without dashes ("070650000001" = "07-065-0000-001"). Never a partial match.
-- Lot: optional; exact (same normalization), active and inside the resolved UPP.
--
-- Status answers (Spanish 'message' for the user; 'code' only for traceability):
--   preview | preview_required | recorded
--   need_info + issues[] (type: missing | invalid | ambiguous | not_found; field; message; options; code): all the
--                         problems of the request in ONE answer
--   duplicate | duplicate_other_company | exists_without_upp   (rfid_siniiga / electronic_rfid already registered;
--                         never says which company)
--   warnings[]            (never a rejection) the tag is also the fire number (numero_fuego) of an animal of the company
--   duplicate_recent      (same preview recorded by the same company in the last 2 minutes, only for animals without an
--                          ear tag; forced with p_force_duplicate = 'true')
--   forbidden | palm | invalid (the database refused the row: nothing was written)
--
-- ERRCODE series (P0114-P0119 free in the repo and in the live pg_proc, checked 2026-11-05). The functions answer a
-- status; the code travels in the answer for traceability:
--   P0114  production unit not resolved (none active, several without a name, not found or ambiguous)
--   P0115  lot not found, inactive or outside the resolved production unit
--   P0116  ear tag already registered (same company, same company without UPP, or another company)
--   P0117  invalid purchase data (price missing or not greater than 0, seller missing or a placeholder)
--   P0118  missing regularization evidence (bovine ear tag, bovine guide folio, approximate age)
--   P0119  reserved
--
-- Objects (all in public):
--   helpers  fn_livestock_chat_txt, fn_livestock_chat_norm, fn_livestock_chat_upp_code, fn_livestock_chat_num,
--            fn_livestock_chat_date, fn_livestock_chat_today, fn_livestock_chat_is_placeholder, fn_livestock_chat_tag,
--            fn_livestock_chat_species, fn_livestock_chat_ctx, fn_livestock_chat_resolve_upp,
--            fn_livestock_chat_resolve_lot, fn_livestock_chat_valid_categories, fn_livestock_chat_category,
--            fn_livestock_chat_tag_conflict, fn_livestock_chat_tag_warnings, fn_livestock_chat_validate_common
--   tools    sp_register_livestock_regularization  -> register_livestock_regularization   (ADMIN / OWNER / EDITOR)
--            sp_register_livestock_purchase_chat    -> register_livestock_purchase         (ADMIN / OWNER / EDITOR)
--
-- DEPENDENCY: the two tool functions are revoked from PUBLIC and no GRANT is issued; they rely on n8n_user being a
-- PostgreSQL superuser (see the suite CLAUDE.md). If that role ever stops being a superuser, add an explicit GRANT EXECUTE.
-- DEPENDENCY: cattle_livestock_rfid_siniiga_key and cattle_livestock_electronic_rfid_key (UNIQUE, global) are the last
-- line against a duplicate ear tag under concurrency; the functions catch the unique_violation and answer a status.
-- NOTE: the human "Sí" is required by the prompt; the database can only require that the commit carries the exact
-- preview_hash of the same company, actor and data (it cannot prove a human answered).
-- NOTE: fn_reject_palm_company is NOT called (it raises P0094); the palm check is answered as status 'palm' with the same
-- text. Its definition must not change: the self-check compares its md5 before and after.
--
-- Usage: psql -v ON_ERROR_STOP=1 -f 099_livestock_regularization.sql                 (dry run: ROLLBACK)
--        psql -v ON_ERROR_STOP=1 -v apply=true -f 099_livestock_regularization.sql   (COMMIT)
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- ---------------------------------------------------------------------------------------------
-- 0. Preconditions. Nothing is created before they pass.
-- ---------------------------------------------------------------------------------------------
CREATE TEMP TABLE IF NOT EXISTS tmp_099_fingerprint (k text PRIMARY KEY, v text) ON COMMIT DROP;

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(t.c, ', ') INTO v_missing
      FROM (VALUES ('cattle_livestock.tenant_id'), ('cattle_livestock.species'), ('cattle_livestock.category'),
                   ('cattle_livestock.business_model'), ('cattle_livestock.current_status'),
                   ('cattle_livestock.rfid_siniiga'), ('cattle_livestock.electronic_rfid'),
                   ('cattle_livestock.numero_fuego'), ('cattle_livestock.birth_date'),
                   ('cattle_livestock.current_weight_kg'), ('cattle_livestock.production_unit_id'),
                   ('cattle_livestock.lot_id'), ('cattle_livestock.leased_site_id'), ('cattle_livestock.metadata'),
                   ('production_units.id_company'), ('production_units.ranch_name'), ('production_units.upp_code'),
                   ('production_units.is_active'), ('production_unit_lots.id_company'),
                   ('production_unit_lots.production_unit_id'), ('production_unit_lots.lot_name'),
                   ('production_unit_lots.is_active'), ('user_companies.email'), ('user_companies.id_company'),
                   ('user_companies.role'), ('user_companies.is_active'), ('users.email'), ('users.is_active'),
                   ('companys.company_name'), ('companys.is_active'),
                   ('cattle_lifestage_catalog.especie'), ('cattle_lifestage_catalog.categoria_origen'),
                   ('cattle_lifestage_catalog.categoria_destino')) AS t (c)
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns ic
                        WHERE ic.table_schema = 'public'
                          AND ic.table_name = split_part(t.c, '.', 1)
                          AND ic.column_name = split_part(t.c, '.', 2));
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'ABORT 099: missing columns: %', v_missing;
    END IF;

    IF (SELECT count(*) FROM pg_constraint
         WHERE conname IN ('cattle_livestock_rfid_siniiga_key', 'cattle_livestock_electronic_rfid_key') AND contype = 'u'
           AND conrelid = 'public.cattle_livestock'::regclass) <> 2 THEN
        RAISE EXCEPTION 'ABORT 099: UNIQUE constraints cattle_livestock_rfid_siniiga_key / _electronic_rfid_key not found';
    END IF;

    -- The fixed category lists of the non-bovine species must be accepted by the table's CHECK.
    SELECT string_agg(c, ', ') INTO v_missing
      FROM unnest(ARRAY['BORREGA', 'BORREGO', 'BUCERRA', 'BUCERRO', 'BUFALA', 'BUFALO', 'CABALLO', 'CABALLO_CASTRADO',
                        'POTRANCA', 'POTRO', 'YEGUA']) AS c
     WHERE position('''' || c || '''' IN (SELECT pg_get_constraintdef(oid) FROM pg_constraint
                                           WHERE conname = 'cattle_livestock_category_check'
                                             AND conrelid = 'public.cattle_livestock'::regclass)) = 0;
    IF v_missing IS NOT NULL OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cattle_livestock_category_check'
                                                AND conrelid = 'public.cattle_livestock'::regclass) THEN
        RAISE EXCEPTION 'ABORT 099: cattle_livestock_category_check missing or without: %', coalesce(v_missing, '(constraint)');
    END IF;

    IF to_regprocedure('public.fn_company_business_domain(integer)') IS NULL
       OR to_regprocedure('public.fn_species_requires_bovine_compliance(character varying)') IS NULL
       OR to_regprocedure('public.fn_has_official_ear_tag(character varying)') IS NULL
       OR to_regprocedure('public.fn_reject_palm_company(integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT 099: a required function is missing (fn_company_business_domain, '
                        'fn_species_requires_bovine_compliance, fn_has_official_ear_tag or fn_reject_palm_company)';
    END IF;

    -- A function of this migration that already exists with a DIFFERENT signature would become an overload.
    SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_missing
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND (p.proname LIKE 'fn\_livestock\_chat\_%' OR p.proname IN ('sp_register_livestock_regularization',
                                                                     'sp_register_livestock_purchase_chat'))
       AND p.oid::regprocedure::text NOT IN (
           'fn_livestock_chat_txt(text)', 'fn_livestock_chat_norm(text)', 'fn_livestock_chat_upp_code(text)',
           'fn_livestock_chat_num(text)', 'fn_livestock_chat_date(text)', 'fn_livestock_chat_today()',
           'fn_livestock_chat_is_placeholder(text)', 'fn_livestock_chat_tag(text)', 'fn_livestock_chat_species(text)',
           'fn_livestock_chat_ctx(text,text)', 'fn_livestock_chat_resolve_upp(integer,text)',
           'fn_livestock_chat_resolve_lot(integer,uuid,text)', 'fn_livestock_chat_valid_categories(text)',
           'fn_livestock_chat_category(text,text)', 'fn_livestock_chat_tag_conflict(integer,text)',
           'fn_livestock_chat_tag_warnings(integer,text)',
           'fn_livestock_chat_validate_common(integer,text,text,text,text,text)',
           'sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)',
           'sp_register_livestock_purchase_chat(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)');
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'ABORT 099: unexpected existing signatures (would become overloads): %', v_missing;
    END IF;

    INSERT INTO tmp_099_fingerprint VALUES
        ('fn_reject_palm_company', md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure)))
    ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
    RAISE NOTICE '099: preconditions OK; fn_reject_palm_company md5 %',
        (SELECT v FROM tmp_099_fingerprint WHERE k = 'fn_reject_palm_company');
END $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Text helpers. Every tool parameter arrives as text (lessons of v1.18.2 and Rule 15).
-- ---------------------------------------------------------------------------------------------
-- Trimmed text; NULL for empty, 'null' and 'undefined' (what n8n / the LLM send for "nothing").
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_txt(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN lower(btrim(coalesce(p, ''))) IN ('', 'null', 'undefined') THEN NULL ELSE btrim(p) END
$$;

-- Comparison key: upper case, accents removed (own translate(); the unaccent extension is not installed in production),
-- runs of white space collapsed to one space. Punctuation is kept: the match stays exact.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_norm(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN public.fn_livestock_chat_txt(p) IS NULL THEN NULL
                ELSE btrim(regexp_replace(upper(translate(p, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')), '\s+', ' ', 'g'))
           END
$$;

-- Official UPP code EE-MMM-NNNN-SSS from text written with or without dashes, spaces or dots. NULL otherwise.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_upp_code(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN d ~ '^[0-9]{12}$'
                THEN substr(d, 1, 2) || '-' || substr(d, 3, 3) || '-' || substr(d, 6, 4) || '-' || substr(d, 10, 3)
           END
      FROM (SELECT regexp_replace(coalesce(public.fn_livestock_chat_txt(p), ''), '[\s.\-]', '', 'g') AS d) s
$$;

-- Number from text: removes spaces, "$" and thousands commas ("1,300" = 1300). NULL when empty or not a plain number.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_num(p text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v text := public.fn_livestock_chat_txt(p);
BEGIN
    IF v IS NULL THEN RETURN NULL; END IF;
    v := regexp_replace(v, '[\s$,]', '', 'g');
    IF v !~ '^-?[0-9]{1,12}(\.[0-9]{1,6})?$' THEN RETURN NULL; END IF;
    RETURN v::numeric;
END;
$$;

-- Date from AAAA-MM-DD (a longer ISO timestamp keeps its first 10 characters). NULL when empty or not a real date.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_date(p text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v text := left(public.fn_livestock_chat_txt(p), 10);
BEGIN
    IF v IS NULL OR v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RETURN NULL; END IF;
    RETURN v::date;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- "Today" for the business (Mexico City), independent of the server time zone.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_today()
RETURNS date
LANGUAGE sql
STABLE
AS $$
    SELECT (now() AT TIME ZONE 'America/Mexico_City')::date
$$;

-- Placeholder instead of a real value ("desconocido", "no sé", "n/a", "-", "?"...). Empty counts as a placeholder.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_is_placeholder(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT k = '' OR k IN ('DESCONOCIDO', 'DESCONOCIDA', 'DESCONOCIDOS', 'NO SE', 'NO LO SE', 'NO SABEMOS', 'NA', 'N A',
                           'NINGUNO', 'NINGUNA', 'SIN VENDEDOR', 'SIN NOMBRE', 'SIN DATO', 'SIN DATOS', 'NO APLICA',
                           'NULL', 'NULO', 'X', 'XX', 'XXX', 'SN', 'S N', 'ANONIMO', 'ANONIMA', 'NADIE', 'OTRO',
                           'VENDEDOR', 'NO DISPONIBLE', 'ND', 'N D', 'PENDIENTE')
      FROM (SELECT btrim(regexp_replace(regexp_replace(coalesce(public.fn_livestock_chat_norm(p), ''),
                                                       '[^A-Z0-9 ]', ' ', 'g'), '\s+', ' ', 'g')) AS k) s
$$;

-- Ear tag as stored: a numeric tag loses spaces, dashes and dots ("07 2475 7014" = "0724757014"); any other tag is
-- kept as typed (trimmed). NULL when empty.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_tag(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN v IS NULL THEN NULL
                WHEN regexp_replace(v, '[\s.\-]', '', 'g') ~ '^[0-9]+$' THEN regexp_replace(v, '[\s.\-]', '', 'g')
                ELSE v
           END
      FROM (SELECT public.fn_livestock_chat_txt(p) AS v) s
$$;

-- Species of the lifestage catalog (BOVINO, BUFALO, BORREGO, EQUIDO) from common spellings. NULL when unknown.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_species(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE public.fn_livestock_chat_norm(p)
               WHEN 'BOVINO' THEN 'BOVINO'  WHEN 'BOVINA' THEN 'BOVINO'  WHEN 'BOVINOS' THEN 'BOVINO'
               WHEN 'BUFALO' THEN 'BUFALO'  WHEN 'BUFALA' THEN 'BUFALO'  WHEN 'BUFALOS' THEN 'BUFALO'
               WHEN 'BORREGO' THEN 'BORREGO' WHEN 'BORREGA' THEN 'BORREGO' WHEN 'OVINO' THEN 'BORREGO'
               WHEN 'OVEJA' THEN 'BORREGO'  WHEN 'BORREGOS' THEN 'BORREGO'
               WHEN 'EQUIDO' THEN 'EQUIDO'  WHEN 'EQUINO' THEN 'EQUIDO'  WHEN 'EQUIDOS' THEN 'EQUIDO'
           END
$$;

-- ---------------------------------------------------------------------------------------------
-- 2. Session gate. {ok:true, tenant, actor, role, company_name} or {ok:false, result:<answer for the tool>}.
--    Order: tenant shape -> active membership in an active company -> not palm -> role ADMIN / OWNER / EDITOR.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_ctx(p_tenant_id text, p_actor_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_t        text := public.fn_livestock_chat_txt(p_tenant_id);
    v_actor    text := lower(public.fn_livestock_chat_txt(p_actor_email));
    v_tenant   integer;
    v_role     text;
    v_company  text;
BEGIN
    IF v_t IS NULL OR v_t !~ '^[0-9]{1,9}$' THEN
        RETURN jsonb_build_object('ok', false, 'result', jsonb_build_object('status', 'forbidden',
            'message', 'No pude identificar la empresa activa de esta sesión.'));
    END IF;
    v_tenant := v_t::integer;

    SELECT upper(uc.role) INTO v_role
      FROM public.user_companies uc
      JOIN public.users u ON lower(u.email) = lower(uc.email)
     WHERE lower(uc.email) = v_actor
       AND uc.id_company = v_tenant
       AND uc.is_active IS TRUE
       AND u.is_active IS NOT FALSE
     LIMIT 1;
    SELECT c.company_name INTO v_company
      FROM public.companys c
     WHERE c.id_company = v_tenant AND c.is_active IS NOT FALSE;
    IF v_actor IS NULL OR v_role IS NULL OR v_company IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'result', jsonb_build_object('status', 'forbidden',
            'message', 'Tu usuario no tiene acceso a la empresa activa.'));
    END IF;

    IF public.fn_company_business_domain(v_tenant) IS NOT DISTINCT FROM 'PALM' THEN
        RETURN jsonb_build_object('ok', false, 'result', jsonb_build_object('status', 'palm', 'code', 'P0094',
            'message', 'Esta empresa es de palma; usa el registro de palma. Las herramientas de ganadería no aplican a plantaciones.'));
    END IF;

    IF v_role NOT IN ('ADMIN', 'OWNER', 'EDITOR') THEN
        RETURN jsonb_build_object('ok', false, 'result', jsonb_build_object('status', 'forbidden',
            'message', 'Tu rol en esta empresa es de solo lectura: no puedes dar de alta animales.'));
    END IF;

    RETURN jsonb_build_object('ok', true, 'tenant', v_tenant, 'actor', v_actor, 'role', v_role, 'company_name', v_company);
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- 3. Resolution of the production unit, the lot and the category, and the ear-tag conflict check.
-- ---------------------------------------------------------------------------------------------
-- {status:'ok', production_unit_id, upp, upp_code} or an issue {status/type, field:'upp', message, options, code}.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_resolve_upp(p_tenant integer, p_upp text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_key      text := public.fn_livestock_chat_norm(p_upp);
    v_code     text := public.fn_livestock_chat_upp_code(p_upp);
    v_options  jsonb;
    v_n        integer;
    v_id       uuid;
    v_name     text;
    v_ucode    text;
BEGIN
    SELECT coalesce(jsonb_agg(jsonb_build_object('upp', pu.ranch_name, 'upp_code', pu.upp_code)
                              ORDER BY pu.ranch_name, pu.upp_code), '[]'::jsonb)
      INTO v_options
      FROM public.production_units pu
     WHERE pu.id_company = p_tenant AND pu.is_active IS TRUE;

    SELECT count(*), (array_agg(pu.id ORDER BY pu.id))[1], min(pu.ranch_name), min(pu.upp_code)
      INTO v_n, v_id, v_name, v_ucode
      FROM public.production_units pu
     WHERE pu.id_company = p_tenant
       AND pu.is_active IS TRUE
       AND (v_key IS NULL
            OR public.fn_livestock_chat_norm(pu.ranch_name) = v_key
            OR (v_code IS NOT NULL AND pu.upp_code = v_code));

    IF v_n = 1 THEN
        RETURN jsonb_build_object('status', 'ok', 'production_unit_id', v_id, 'upp', v_name, 'upp_code', v_ucode);
    END IF;

    IF v_key IS NULL AND v_n = 0 THEN
        RETURN jsonb_build_object('status', 'missing', 'type', 'missing', 'field', 'upp', 'code', 'P0114',
            'message', 'La empresa no tiene ninguna UPP activa registrada. Regístrala en la plataforma antes de dar de alta animales.');
    ELSIF v_key IS NULL THEN
        RETURN jsonb_build_object('status', 'ambiguous', 'type', 'ambiguous', 'field', 'upp', 'code', 'P0114',
            'message', 'La empresa tiene varias UPP activas: indica en cuál queda el animal.', 'options', v_options);
    ELSIF v_n = 0 THEN
        RETURN jsonb_build_object('status', 'not_found', 'type', 'not_found', 'field', 'upp', 'code', 'P0114',
            'message', 'No encontré esa UPP entre las UPP activas de la empresa. Indica el nombre o el código exacto.',
            'options', v_options);
    END IF;
    RETURN jsonb_build_object('status', 'ambiguous', 'type', 'ambiguous', 'field', 'upp', 'code', 'P0114',
        'message', 'Ese nombre coincide con más de una UPP: indica el código de la UPP.', 'options', v_options);
END;
$$;

-- {status:'ok', lot_id, lot} or an issue {status/type, field:'lot', message, options, code}. p_lot must not be empty.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_resolve_lot(p_tenant integer, p_unit uuid, p_lot text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_key      text := public.fn_livestock_chat_norm(p_lot);
    v_options  jsonb;
    v_n        integer;
    v_id       uuid;
    v_name     text;
    v_other    text;
BEGIN
    SELECT coalesce(jsonb_agg(l.lot_name ORDER BY l.lot_name), '[]'::jsonb) INTO v_options
      FROM public.production_unit_lots l
     WHERE l.id_company = p_tenant AND l.production_unit_id = p_unit AND l.is_active IS TRUE;

    SELECT count(*), (array_agg(l.id ORDER BY l.id))[1], min(l.lot_name) INTO v_n, v_id, v_name
      FROM public.production_unit_lots l
     WHERE l.id_company = p_tenant
       AND l.production_unit_id = p_unit
       AND l.is_active IS TRUE
       AND public.fn_livestock_chat_norm(l.lot_name) = v_key;

    IF v_n = 1 THEN
        RETURN jsonb_build_object('status', 'ok', 'lot_id', v_id, 'lot', v_name);
    ELSIF v_n > 1 THEN
        RETURN jsonb_build_object('status', 'ambiguous', 'type', 'ambiguous', 'field', 'lot', 'code', 'P0115',
            'message', 'Ese nombre coincide con más de un lote de la UPP.', 'options', v_options);
    END IF;

    -- Same company, another active UPP: say so (it is the user's own data), so the user can correct the UPP.
    SELECT min(pu.ranch_name) INTO v_other
      FROM public.production_unit_lots l
      JOIN public.production_units pu ON pu.id = l.production_unit_id AND pu.is_active IS TRUE
     WHERE l.id_company = p_tenant AND l.production_unit_id <> p_unit AND l.is_active IS TRUE
       AND public.fn_livestock_chat_norm(l.lot_name) = v_key;
    IF v_other IS NOT NULL THEN
        RETURN jsonb_build_object('status', 'not_found', 'type', 'not_found', 'field', 'lot', 'code', 'P0115',
            'message', 'Ese lote pertenece a otra UPP de la empresa (' || v_other || '), no a la UPP indicada.',
            'options', v_options);
    END IF;
    RETURN jsonb_build_object('status', 'not_found', 'type', 'not_found', 'field', 'lot', 'code', 'P0115',
        'message', 'No encontré ese lote activo en la UPP indicada.', 'options', v_options);
END;
$$;

-- Valid categories per species. BOVINO: the lifestage catalog (origin or destination of a transition). The other
-- species have no catalog rows in production (2026-11-05): a fixed list per species, taken from the categories in use and
-- from the cattle_livestock_category_check, so a category of another species is never accepted (a BUFALO cannot be a
-- NOVILLO). Extending the catalog to the other species is debt (099_RUNBOOK.md).
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_valid_categories(p_species text)
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
    SELECT CASE p_species
               WHEN 'BOVINO' THEN (
                   SELECT array_agg(DISTINCT c ORDER BY c)
                     FROM (SELECT upper(categoria_origen) AS c FROM public.cattle_lifestage_catalog
                            WHERE upper(especie) = 'BOVINO'
                           UNION
                           SELECT upper(categoria_destino) FROM public.cattle_lifestage_catalog
                            WHERE upper(especie) = 'BOVINO') s)
               WHEN 'BORREGO' THEN ARRAY['BORREGA', 'BORREGO']
               WHEN 'BUFALO'  THEN ARRAY['BUCERRA', 'BUCERRO', 'BUFALA', 'BUFALO']
               WHEN 'EQUIDO'  THEN ARRAY['CABALLO', 'CABALLO_CASTRADO', 'POTRANCA', 'POTRO', 'YEGUA']
           END
$$;

-- Category for the species ("VAQUILLA" of the guides = NOVILLONA; spaces = underscores).
-- {status:'ok', category, mapped_from} or {status:'invalid', options}. p_species must already be canonical.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_category(p_species text, p_category text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_in      text := replace(public.fn_livestock_chat_norm(p_category), ' ', '_');
    v_cat     text;
    v_valid   text[] := public.fn_livestock_chat_valid_categories(p_species);
BEGIN
    v_cat := CASE v_in WHEN 'VAQUILLA' THEN 'NOVILLONA' WHEN 'VAQUILLONA' THEN 'NOVILLONA' ELSE v_in END;

    IF v_cat IS NOT NULL AND v_cat = ANY (coalesce(v_valid, '{}'::text[])) THEN
        RETURN jsonb_build_object('status', 'ok', 'category', v_cat,
                                  'mapped_from', CASE WHEN v_cat <> v_in THEN v_in END);
    END IF;
    IF v_valid IS NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'type', 'invalid', 'field', 'category', 'options', '[]'::jsonb,
            'message', 'El catálogo de etapas no tiene categorías para la especie ' || p_species
                       || '; pide a un administrador que lo configure.');
    END IF;
    RETURN jsonb_build_object('status', 'invalid', 'type', 'invalid', 'field', 'category', 'options', to_jsonb(v_valid),
        'message', 'Esa categoría no corresponde a la especie ' || p_species || '.');
END;
$$;

-- NULL when the tag is free; otherwise the answer for the tool. The other company is never named.
-- Only rfid_siniiga and electronic_rfid reject (both UNIQUE globally); a numero_fuego match is a warning
-- (fn_livestock_chat_tag_warnings), because fire numbers can repeat by capture error (agro-erp CLAUDE.md, Rule 4).
-- Same company first (more useful message): an active animal without UPP and without leased site -> exists_without_upp;
-- any other animal of the company -> duplicate. Then any other company.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_tag_conflict(p_tenant integer, p_tag text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    r record;
BEGIN
    IF p_tag IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT cl.category, cl.current_status, cl.production_unit_id, cl.leased_site_id, pu.ranch_name AS upp
      INTO r
      FROM public.cattle_livestock cl
      LEFT JOIN public.production_units pu ON pu.id = cl.production_unit_id
     WHERE cl.tenant_id = p_tenant
       AND (cl.rfid_siniiga = p_tag OR cl.electronic_rfid = p_tag)
     ORDER BY (upper(cl.current_status) IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO')), cl.id
     LIMIT 1;
    IF FOUND THEN
        IF r.production_unit_id IS NULL AND r.leased_site_id IS NULL
           AND upper(r.current_status) NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO') THEN
            RETURN jsonb_build_object('status', 'exists_without_upp', 'code', 'P0116',
                'category', r.category, 'current_status', r.current_status,
                'message', 'Ese arete ya existe en esta empresa (' || r.category || ', ' || r.current_status
                           || ') pero sin UPP asignada. No se crea otro animal: asígnale la UPP desde la plataforma.');
        END IF;
        RETURN jsonb_build_object('status', 'duplicate', 'code', 'P0116',
            'category', r.category, 'current_status', r.current_status, 'upp', r.upp,
            'message', 'Ese arete ya pertenece a un animal de esta empresa (' || r.category || ', ' || r.current_status
                       || coalesce(', UPP ' || r.upp, '') || '). No se crea otro animal.');
    END IF;

    IF EXISTS (SELECT 1 FROM public.cattle_livestock cl
                WHERE cl.tenant_id <> p_tenant AND (cl.rfid_siniiga = p_tag OR cl.electronic_rfid = p_tag)) THEN
        RETURN jsonb_build_object('status', 'duplicate_other_company', 'code', 'P0116',
            'message', 'Ese arete ya está registrado en otra empresa del sistema. No se puede dar de alta otra vez: '
                       || 'revisa el número o consulta a un administrador.');
    END IF;
    RETURN NULL;
END;
$$;

-- Warnings (never a rejection): the tag also appears as the fire number (numero_fuego) of animals of the same company.
-- Returns a jsonb array (empty when nothing matches), at most 5 animals described by category and status.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_tag_warnings(p_tenant integer, p_tag text)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT CASE WHEN count(*) = 0 THEN '[]'::jsonb
                ELSE jsonb_build_array(jsonb_build_object(
                    'type', 'fire_number_match', 'field', 'ear_tag',
                    'animals', jsonb_agg(jsonb_build_object('category', m.category, 'current_status', m.current_status)),
                    'message', 'Ese número también aparece como número de fuego de '
                               || CASE WHEN count(*) = 1 THEN 'otro animal'
                                       WHEN count(*) = 5 THEN 'al menos 5 animales'
                                       ELSE count(*) || ' animales' END
                               || ' de esta empresa. Revisa que no sea el mismo animal antes de confirmar.'))
           END
      FROM (SELECT cl.category, cl.current_status
              FROM public.cattle_livestock cl
             WHERE p_tag IS NOT NULL AND cl.tenant_id = p_tenant AND cl.numero_fuego = p_tag
             ORDER BY cl.created_at, cl.id
             LIMIT 5) m
$$;

-- Validation shared by both intakes: species, category, business model, production unit and lot.
-- Returns {issues:[...], species, category, category_mapped_from, business_model, production_unit_id, upp, upp_code,
-- lot_id, lot}. Never writes.
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_validate_common(
    p_tenant integer, p_species text, p_category text, p_business_model text, p_upp text, p_lot text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_issues   jsonb := '[]'::jsonb;
    v_species  text := public.fn_livestock_chat_species(p_species);
    v_cat      jsonb;
    v_bm       text := public.fn_livestock_chat_norm(p_business_model);
    v_upp      jsonb;
    v_lot      jsonb;
BEGIN
    IF public.fn_livestock_chat_txt(p_species) IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'species',
            'message', '¿De qué especie es el animal? (BOVINO, BUFALO, BORREGO o EQUIDO)');
    ELSIF v_species IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'species',
            'message', 'No reconozco esa especie.', 'options', '["BOVINO","BUFALO","BORREGO","EQUIDO"]'::jsonb);
    END IF;

    IF public.fn_livestock_chat_txt(p_category) IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'category',
            'message', '¿Qué categoría es el animal? (por ejemplo VACA, BECERRO, NOVILLONA)');
    ELSIF v_species IS NOT NULL THEN
        v_cat := public.fn_livestock_chat_category(v_species, p_category);
        IF v_cat->>'status' <> 'ok' THEN
            v_issues := v_issues || (v_cat - 'status');
        END IF;
    END IF;

    IF v_bm IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'business_model',
            'message', '¿El animal es de CRIA, ENGORDA o REPRODUCCION?');
    ELSIF v_bm NOT IN ('CRIA', 'ENGORDA', 'REPRODUCCION') THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'business_model',
            'message', 'El modelo de negocio debe ser CRIA, ENGORDA o REPRODUCCION.',
            'options', '["CRIA","ENGORDA","REPRODUCCION"]'::jsonb);
    END IF;

    v_upp := public.fn_livestock_chat_resolve_upp(p_tenant, p_upp);
    IF v_upp->>'status' <> 'ok' THEN
        v_issues := v_issues || (v_upp - 'status');
    ELSIF public.fn_livestock_chat_txt(p_lot) IS NOT NULL THEN
        v_lot := public.fn_livestock_chat_resolve_lot(p_tenant, (v_upp->>'production_unit_id')::uuid, p_lot);
        IF v_lot->>'status' <> 'ok' THEN
            v_issues := v_issues || (v_lot - 'status');
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'issues', v_issues,
        'species', v_species,
        'category', v_cat->>'category',
        'category_mapped_from', v_cat->>'mapped_from',
        'business_model', CASE WHEN v_bm IN ('CRIA', 'ENGORDA', 'REPRODUCCION') THEN v_bm END,
        'production_unit_id', v_upp->>'production_unit_id',
        'upp', v_upp->>'upp',
        'upp_code', v_upp->>'upp_code',
        'lot_id', CASE WHEN v_lot->>'status' = 'ok' THEN v_lot->>'lot_id' END,
        'lot', CASE WHEN v_lot->>'status' = 'ok' THEN v_lot->>'lot' END);
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- 4. Tool: register_livestock_regularization.
--    A real animal that was never captured (it was not bought). Evidence: the transit guide. Bovine regime
--    (fn_species_requires_bovine_compliance): official ear tag and guide folio are required; other species: optional.
--    The birth date is estimated from the approximate age (0-240 months). No price, seller or purchase date.
-- ---------------------------------------------------------------------------------------------
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
LANGUAGE plpgsql
AS $$
DECLARE
    v_ctx        jsonb;
    v_tenant     integer;
    v_actor      text;
    v_channel    text;
    v_common     jsonb;
    v_issues     jsonb;
    v_bovine     boolean;
    v_tag        text := public.fn_livestock_chat_tag(p_ear_tag);
    v_conflict   jsonb;
    v_warn       jsonb;
    v_wobj       jsonb;
    v_folio      text := public.fn_livestock_chat_txt(p_guide_folio);
    v_origin_raw text := public.fn_livestock_chat_txt(p_origin_upp_code);
    v_origin     text;
    v_age_txt    text;
    v_age        numeric;
    v_birth      date;
    v_notes      text := left(public.fn_livestock_chat_txt(p_notes), 500);
    v_data       jsonb;
    v_hash       text;
    v_preview    jsonb;
    v_id         uuid;
BEGIN
    v_ctx := public.fn_livestock_chat_ctx(p_tenant_id, p_actor_email);
    IF NOT (v_ctx->>'ok')::boolean THEN
        RETURN v_ctx->'result';
    END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    v_actor := v_ctx->>'actor';
    v_channel := CASE upper(coalesce(public.fn_livestock_chat_txt(p_channel), ''))
                     WHEN 'CHAT_WEB' THEN 'CHAT_WEB' WHEN 'WHATSAPP' THEN 'WHATSAPP' ELSE 'DESCONOCIDO' END;

    v_common := public.fn_livestock_chat_validate_common(v_tenant, p_species, p_category, p_business_model, p_upp, p_lot);
    v_issues := v_common->'issues';
    -- Unknown species stays strict (bovine regime), as fn_species_requires_bovine_compliance does.
    v_bovine := public.fn_species_requires_bovine_compliance((v_common->>'species')::varchar);

    -- Ear tag. A registered tag ends the request: there is nothing else to ask for an animal that already exists.
    IF v_tag IS NULL THEN
        IF v_bovine THEN
            v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'ear_tag', 'code', 'P0118',
                'message', 'Para bovinos el arete oficial SINIIGA (10 dígitos) es obligatorio.');
        END IF;
    ELSIF v_bovine AND NOT public.fn_has_official_ear_tag(v_tag::varchar) THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'ear_tag', 'code', 'P0118',
            'message', 'El arete SINIIGA de un bovino debe tener exactamente 10 dígitos.');
    ELSIF length(v_tag) > 100 THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'ear_tag',
            'message', 'El identificador es demasiado largo.');
    ELSE
        v_conflict := public.fn_livestock_chat_tag_conflict(v_tenant, v_tag);
        IF v_conflict IS NOT NULL THEN
            RETURN v_conflict || jsonb_build_object('empresa', v_ctx->>'company_name', 'arete', v_tag);
        END IF;
    END IF;

    -- Guide folio (the evidence). A placeholder is not a folio.
    IF v_folio IS NOT NULL AND public.fn_livestock_chat_is_placeholder(v_folio) THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'guide_folio',
            'code', CASE WHEN v_bovine THEN 'P0118' END,
            'message', 'El folio de la guía de tránsito debe ser el número real de la guía.');
    ELSIF v_folio IS NULL AND v_bovine THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'guide_folio', 'code', 'P0118',
            'message', 'Para bovinos el folio de la guía de tránsito es obligatorio: es la evidencia de la regularización.');
    ELSIF length(v_folio) > 60 THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'guide_folio',
            'message', 'El folio de la guía es demasiado largo.');
    END IF;

    -- Origin UPP code of the guide: stored, never blocks.
    v_origin := coalesce(public.fn_livestock_chat_upp_code(v_origin_raw), left(v_origin_raw, 30));

    -- Approximate age in months, 0 to 240 ("8", "8 meses", "1.5").
    v_age_txt := public.fn_livestock_chat_txt(p_age_months);
    IF v_age_txt IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'age_months', 'code', 'P0118',
            'message', '¿Qué edad aproximada tiene el animal, en meses?');
    ELSE
        v_age_txt := replace(regexp_replace(lower(v_age_txt), '\s*(meses|mes)\s*$', ''), ',', '.');
        IF v_age_txt ~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' THEN
            v_age := v_age_txt::numeric;
        END IF;
        IF v_age IS NULL OR v_age < 0 OR v_age > 240 THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'age_months', 'code', 'P0118',
                'message', 'La edad aproximada debe ser un número de meses entre 0 y 240.');
        END IF;
    END IF;

    -- numero_fuego matches of the same company: warnings only (never a rejection).
    v_warn := public.fn_livestock_chat_tag_warnings(v_tenant, v_tag);
    v_wobj := CASE WHEN jsonb_array_length(v_warn) > 0 THEN jsonb_build_object('warnings', v_warn) ELSE '{}'::jsonb END;

    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN v_wobj || jsonb_build_object('status', 'need_info', 'empresa', v_ctx->>'company_name', 'issues', v_issues);
    END IF;

    v_birth := public.fn_livestock_chat_today() - round(v_age * 30.4375)::integer;
    v_data := jsonb_build_object(
        'production_unit_id', v_common->>'production_unit_id', 'lot_id', v_common->>'lot_id',
        'species', v_common->>'species', 'category', v_common->>'category',
        'business_model', v_common->>'business_model', 'ear_tag', v_tag, 'guide_folio', v_folio,
        'origin_upp_code', v_origin, 'age_months', v_age, 'birth_date', v_birth, 'notes', v_notes);
    v_hash := md5(jsonb_build_object('kind', 'REGULARIZACION_PADRON', 'tenant', v_tenant, 'actor', v_actor,
                                     'data', v_data)::text);
    v_preview := jsonb_strip_nulls(jsonb_build_object(
        'empresa', v_ctx->>'company_name', 'upp', v_common->>'upp', 'upp_code', v_common->>'upp_code',
        'lote', v_common->>'lot', 'especie', v_common->>'species', 'categoria', v_common->>'category',
        'categoria_dictada', v_common->>'category_mapped_from', 'modelo_negocio', v_common->>'business_model',
        'arete', v_tag, 'guia_transito', v_folio, 'upp_origen_guia', v_origin,
        'edad_aproximada_meses', v_age, 'fecha_nacimiento_estimada', v_birth, 'notas', v_notes));

    IF lower(coalesce(public.fn_livestock_chat_txt(p_confirmed), '')) <> 'true' THEN
        RETURN v_wobj || jsonb_build_object('status', 'preview', 'preview', v_preview, 'preview_hash', v_hash,
            'message', 'Vista previa de la regularización: todavía no se guardó nada. Muéstrala y pide "Sí" para registrar.');
    END IF;
    IF public.fn_livestock_chat_txt(p_preview_hash) IS DISTINCT FROM v_hash THEN
        RETURN v_wobj || jsonb_build_object('status', 'preview_required', 'preview', v_preview, 'preview_hash', v_hash,
            'message', 'Falta la vista previa o los datos cambiaron: muestra esta vista previa y pide "Sí" otra vez.');
    END IF;

    -- Double "Sí" for an animal without ear tag (nothing unique protects it).
    IF v_tag IS NULL AND lower(coalesce(public.fn_livestock_chat_txt(p_force_duplicate), '')) <> 'true' THEN
        SELECT cl.id INTO v_id
          FROM public.cattle_livestock cl
         WHERE cl.tenant_id = v_tenant
           AND cl.metadata->>'preview_hash' = v_hash
           AND cl.created_at > localtimestamp - interval '2 minutes'
         LIMIT 1;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('status', 'duplicate_recent', 'livestock_id', v_id, 'preview', v_preview,
                'message', 'Este mismo animal se registró hace menos de 2 minutos. Si de verdad es otro animal igual, '
                           || 'confirma que es otro y se registrará.');
        END IF;
    END IF;

    BEGIN
        INSERT INTO public.cattle_livestock (
            tenant_id, species, category, business_model, current_status, rfid_siniiga, birth_date,
            current_weight_kg, production_unit_id, lot_id, metadata, created_at)
        VALUES (
            v_tenant, v_common->>'species', v_common->>'category', v_common->>'business_model', 'ACTIVO', v_tag, v_birth,
            NULL, (v_common->>'production_unit_id')::uuid, (v_common->>'lot_id')::uuid,
            jsonb_strip_nulls(jsonb_build_object(
                'source', 'REGULARIZACION_PADRON',
                'guide_folio', v_folio,
                'origin_upp_code', v_origin,
                'origin_upp_code_valid', CASE WHEN v_origin_raw IS NOT NULL
                                              THEN public.fn_livestock_chat_upp_code(v_origin_raw) IS NOT NULL END,
                'birth_date_estimated', true,
                'reported_age_months', v_age,
                'category_reported', v_common->>'category_mapped_from',
                'registered_by', v_actor,
                'channel', v_channel,
                'registered_at', to_char(now() AT TIME ZONE 'America/Mexico_City', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'notes', v_notes,
                'tool', 'sp_register_livestock_regularization',
                'migration', '099',
                'preview_hash', v_hash)),
            now())
        RETURNING id INTO v_id;
    EXCEPTION
        WHEN unique_violation THEN
            v_conflict := public.fn_livestock_chat_tag_conflict(v_tenant, v_tag);
            RETURN coalesce(v_conflict, jsonb_build_object('status', 'duplicate', 'code', 'P0116',
                'message', 'Ese identificador ya está registrado. No se guardó nada.'))
                   || jsonb_build_object('empresa', v_ctx->>'company_name', 'arete', v_tag);
        WHEN raise_exception OR no_data_found OR check_violation OR foreign_key_violation OR not_null_violation THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', SQLSTATE,
                'message', 'La base de datos rechazó el registro y no se guardó nada. Revisa la UPP y el lote.');
    END;

    RETURN v_wobj || jsonb_build_object('status', 'recorded', 'livestock_id', v_id, 'preview', v_preview,
        'message', 'Animal registrado por regularización de padrón.');
END;
$$;

-- ---------------------------------------------------------------------------------------------
-- 5. Tool: register_livestock_purchase (hardened). Replaces the MCP tool of the same name, whose node is neutralized in
--    n8n. Price greater than 0 and a real seller are required; the UPP must resolve; the lot is exact, active and inside
--    the UPP. Metadata keeps the keys read by vw_cattle_event_log (source, purchase_price, seller_name, purchase_date).
-- ---------------------------------------------------------------------------------------------
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
LANGUAGE plpgsql
AS $$
DECLARE
    v_ctx        jsonb;
    v_tenant     integer;
    v_actor      text;
    v_channel    text;
    v_common     jsonb;
    v_issues     jsonb;
    v_today      date := public.fn_livestock_chat_today();
    v_tag        text := public.fn_livestock_chat_tag(p_ear_tag);
    v_conflict   jsonb;
    v_warn       jsonb;
    v_wobj       jsonb;
    v_birth      date;
    v_weight     numeric;
    v_price      numeric;
    v_seller     text := public.fn_livestock_chat_txt(p_seller_name);
    v_pdate      date;
    v_notes      text := left(public.fn_livestock_chat_txt(p_notes), 500);
    v_data       jsonb;
    v_hash       text;
    v_preview    jsonb;
    v_id         uuid;
BEGIN
    v_ctx := public.fn_livestock_chat_ctx(p_tenant_id, p_actor_email);
    IF NOT (v_ctx->>'ok')::boolean THEN
        RETURN v_ctx->'result';
    END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    v_actor := v_ctx->>'actor';
    v_channel := CASE upper(coalesce(public.fn_livestock_chat_txt(p_channel), ''))
                     WHEN 'CHAT_WEB' THEN 'CHAT_WEB' WHEN 'WHATSAPP' THEN 'WHATSAPP' ELSE 'DESCONOCIDO' END;

    v_common := public.fn_livestock_chat_validate_common(v_tenant, p_species, p_category, p_business_model, p_upp, p_lot);
    v_issues := v_common->'issues';

    -- Ear tag: optional (unchanged rule for purchases); a registered tag ends the request.
    IF v_tag IS NOT NULL THEN
        IF length(v_tag) > 100 THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'ear_tag',
                'message', 'El identificador es demasiado largo.');
        ELSE
            v_conflict := public.fn_livestock_chat_tag_conflict(v_tenant, v_tag);
            IF v_conflict IS NOT NULL THEN
                RETURN v_conflict || jsonb_build_object('empresa', v_ctx->>'company_name', 'arete', v_tag);
            END IF;
        END IF;
    END IF;

    -- Price: required and greater than 0.
    IF public.fn_livestock_chat_txt(p_purchase_price) IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'purchase_price', 'code', 'P0117',
            'message', '¿En cuánto se compró el animal? Si el animal no se compró, es una regularización, no una compra.');
    ELSE
        v_price := public.fn_livestock_chat_num(p_purchase_price);
        IF v_price IS NULL OR v_price <= 0 THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'purchase_price', 'code', 'P0117',
                'message', 'El precio de compra debe ser un número mayor que 0. Si el animal no se compró, es una '
                           || 'regularización, no una compra.');
        END IF;
    END IF;

    -- Seller: required and not a placeholder.
    IF v_seller IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', 'missing', 'field', 'seller_name', 'code', 'P0117',
            'message', '¿A quién se le compró el animal?');
    ELSIF public.fn_livestock_chat_is_placeholder(v_seller) OR length(v_seller) < 2 THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'seller_name', 'code', 'P0117',
            'message', 'Necesito el nombre real del vendedor. Si el animal no se compró, es una regularización, no una compra.');
    ELSIF length(v_seller) > 255 THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'seller_name',
            'message', 'El nombre del vendedor es demasiado largo.');
    END IF;

    -- Purchase date: optional (today), never in the future.
    IF public.fn_livestock_chat_txt(p_purchase_date) IS NULL THEN
        v_pdate := v_today;
    ELSE
        v_pdate := public.fn_livestock_chat_date(p_purchase_date);
        IF v_pdate IS NULL OR v_pdate > v_today OR v_pdate < DATE '2000-01-01' THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'purchase_date',
                'message', 'La fecha de compra debe ser AAAA-MM-DD y no puede ser futura.');
        END IF;
    END IF;

    -- Birth date: optional, never in the future.
    IF public.fn_livestock_chat_txt(p_birth_date) IS NOT NULL THEN
        v_birth := public.fn_livestock_chat_date(p_birth_date);
        IF v_birth IS NULL OR v_birth > v_today OR v_birth < DATE '1990-01-01' THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'birth_date',
                'message', 'La fecha de nacimiento debe ser AAAA-MM-DD y no puede ser futura.');
        END IF;
    END IF;

    -- Weight: optional, only a number the user said.
    IF public.fn_livestock_chat_txt(p_weight_kg) IS NOT NULL THEN
        v_weight := public.fn_livestock_chat_num(regexp_replace(p_weight_kg, '\s*(kg|kgs|kilos?)\s*$', '', 'i'));
        IF v_weight IS NULL OR v_weight <= 0 OR v_weight > 2000 THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'weight_kg',
                'message', 'El peso debe ser un número de kilos mayor que 0.');
        END IF;
    END IF;

    -- numero_fuego matches of the same company: warnings only (never a rejection).
    v_warn := public.fn_livestock_chat_tag_warnings(v_tenant, v_tag);
    v_wobj := CASE WHEN jsonb_array_length(v_warn) > 0 THEN jsonb_build_object('warnings', v_warn) ELSE '{}'::jsonb END;

    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN v_wobj || jsonb_build_object('status', 'need_info', 'empresa', v_ctx->>'company_name', 'issues', v_issues);
    END IF;

    v_data := jsonb_build_object(
        'production_unit_id', v_common->>'production_unit_id', 'lot_id', v_common->>'lot_id',
        'species', v_common->>'species', 'category', v_common->>'category',
        'business_model', v_common->>'business_model', 'ear_tag', v_tag, 'birth_date', v_birth, 'weight_kg', v_weight,
        'purchase_price', v_price, 'seller_name', v_seller, 'purchase_date', v_pdate, 'notes', v_notes);
    v_hash := md5(jsonb_build_object('kind', 'COMPRA', 'tenant', v_tenant, 'actor', v_actor, 'data', v_data)::text);
    v_preview := jsonb_strip_nulls(jsonb_build_object(
        'empresa', v_ctx->>'company_name', 'upp', v_common->>'upp', 'upp_code', v_common->>'upp_code',
        'lote', v_common->>'lot', 'especie', v_common->>'species', 'categoria', v_common->>'category',
        'categoria_dictada', v_common->>'category_mapped_from', 'modelo_negocio', v_common->>'business_model',
        'arete', v_tag, 'fecha_nacimiento', v_birth, 'peso_kg', v_weight, 'precio_compra', v_price,
        'vendedor', v_seller, 'fecha_compra', v_pdate, 'notas', v_notes));

    IF lower(coalesce(public.fn_livestock_chat_txt(p_confirmed), '')) <> 'true' THEN
        RETURN v_wobj || jsonb_build_object('status', 'preview', 'preview', v_preview, 'preview_hash', v_hash,
            'message', 'Vista previa de la compra: todavía no se guardó nada. Muéstrala y pide "Sí" para registrar.');
    END IF;
    IF public.fn_livestock_chat_txt(p_preview_hash) IS DISTINCT FROM v_hash THEN
        RETURN v_wobj || jsonb_build_object('status', 'preview_required', 'preview', v_preview, 'preview_hash', v_hash,
            'message', 'Falta la vista previa o los datos cambiaron: muestra esta vista previa y pide "Sí" otra vez.');
    END IF;

    IF v_tag IS NULL AND lower(coalesce(public.fn_livestock_chat_txt(p_force_duplicate), '')) <> 'true' THEN
        SELECT cl.id INTO v_id
          FROM public.cattle_livestock cl
         WHERE cl.tenant_id = v_tenant
           AND cl.metadata->>'preview_hash' = v_hash
           AND cl.created_at > localtimestamp - interval '2 minutes'
         LIMIT 1;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('status', 'duplicate_recent', 'livestock_id', v_id, 'preview', v_preview,
                'message', 'Esta misma compra se registró hace menos de 2 minutos. Si de verdad es otro animal igual, '
                           || 'confirma que es otro y se registrará.');
        END IF;
    END IF;

    BEGIN
        INSERT INTO public.cattle_livestock (
            tenant_id, species, category, business_model, current_status, rfid_siniiga, birth_date,
            current_weight_kg, production_unit_id, lot_id, metadata, created_at)
        VALUES (
            v_tenant, v_common->>'species', v_common->>'category', v_common->>'business_model', 'ACTIVO', v_tag, v_birth,
            v_weight, (v_common->>'production_unit_id')::uuid, (v_common->>'lot_id')::uuid,
            jsonb_strip_nulls(jsonb_build_object(
                'source', 'COMPRA',
                'purchase_price', v_price,
                'seller_name', v_seller,
                'purchase_date', to_char(v_pdate, 'YYYY-MM-DD'),
                'category_reported', v_common->>'category_mapped_from',
                'registered_by', v_actor,
                'channel', v_channel,
                'registered_at', to_char(now() AT TIME ZONE 'America/Mexico_City', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'notes', v_notes,
                'tool', 'sp_register_livestock_purchase_chat',
                'migration', '099',
                'preview_hash', v_hash)),
            now())
        RETURNING id INTO v_id;
    EXCEPTION
        WHEN unique_violation THEN
            v_conflict := public.fn_livestock_chat_tag_conflict(v_tenant, v_tag);
            RETURN coalesce(v_conflict, jsonb_build_object('status', 'duplicate', 'code', 'P0116',
                'message', 'Ese identificador ya está registrado. No se guardó nada.'))
                   || jsonb_build_object('empresa', v_ctx->>'company_name', 'arete', v_tag);
        WHEN raise_exception OR no_data_found OR check_violation OR foreign_key_violation OR not_null_violation THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', SQLSTATE,
                'message', 'La base de datos rechazó el registro y no se guardó nada. Revisa la UPP y el lote.');
    END;

    RETURN v_wobj || jsonb_build_object('status', 'recorded', 'livestock_id', v_id, 'preview', v_preview,
        'message', 'Compra registrada.');
END;
$$;

REVOKE ALL ON FUNCTION public.sp_register_livestock_regularization(text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sp_register_livestock_purchase_chat(text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text, text, text) FROM PUBLIC;

COMMENT ON FUNCTION public.sp_register_livestock_regularization(text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text) IS
  '099: chat tool register_livestock_regularization (preview / commit with preview_hash). Tenant, actor and channel come '
  'from the verified n8n session. Rolled back by 099_rollback.sql (body -> status disabled).';
COMMENT ON FUNCTION public.sp_register_livestock_purchase_chat(text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text, text, text) IS
  '099: chat tool register_livestock_purchase (preview / commit with preview_hash; price > 0, real seller, UPP '
  'required). Rolled back by 099_rollback.sql (body -> status disabled).';

-- ---------------------------------------------------------------------------------------------
-- 6. Self-check
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_r jsonb;
BEGIN
    IF to_regprocedure('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_register_livestock_purchase_chat(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.fn_livestock_chat_validate_common(integer,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION '099: a function is missing after the migration';
    END IF;
    IF md5(pg_get_functiondef('public.fn_reject_palm_company(integer)'::regprocedure))
       IS DISTINCT FROM (SELECT v FROM tmp_099_fingerprint WHERE k = 'fn_reject_palm_company') THEN
        RAISE EXCEPTION '099: fn_reject_palm_company changed during the migration';
    END IF;
    -- Data-free smoke: a malformed tenant is refused before anything is read.
    v_r := public.sp_register_livestock_regularization('abc', 'nobody@example.test', 'CHAT_WEB', NULL, NULL, 'BOVINO',
        'BECERRO', 'CRIA', '8', '9900000001', 'F-1', NULL, NULL, 'true', NULL, NULL);
    IF v_r->>'status' <> 'forbidden' THEN
        RAISE EXCEPTION '099: smoke test expected forbidden, got %', v_r;
    END IF;
    v_r := public.sp_register_livestock_purchase_chat('abc', 'nobody@example.test', 'CHAT_WEB', NULL, NULL, 'BOVINO',
        'BECERRO', 'CRIA', NULL, NULL, NULL, '1000', 'Vendedor', NULL, NULL, 'true', NULL, NULL);
    IF v_r->>'status' <> 'forbidden' THEN
        RAISE EXCEPTION '099: smoke test expected forbidden, got %', v_r;
    END IF;
    IF public.fn_livestock_chat_upp_code('070650000001') IS DISTINCT FROM '07-065-0000-001'
       OR public.fn_livestock_chat_norm('  La   Bendición ') IS DISTINCT FROM 'LA BENDICION'
       OR NOT public.fn_livestock_chat_is_placeholder('Desconocido')
       OR public.fn_livestock_chat_tag('07 2475 7014') IS DISTINCT FROM '0724757014'
       OR 'NOVILLO' = ANY (public.fn_livestock_chat_valid_categories('BUFALO'))
       OR NOT ('BUFALA' = ANY (public.fn_livestock_chat_valid_categories('BUFALO'))) THEN
        RAISE EXCEPTION '099: a helper returned an unexpected value';
    END IF;
    RAISE NOTICE '099: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 099 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 099 rolled back ***'
\endif
\endif
