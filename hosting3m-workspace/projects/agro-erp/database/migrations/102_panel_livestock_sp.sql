-- 102_panel_livestock_sp.sql
-- Livestock intake from the web panel ("ALTA" of the cattle detail modal): ONE new two-step function,
-- sp_register_livestock_panel, that replaces the direct INSERT into cattle_livestock with the same safeguards migration
-- 099 gave the chat tools: verified company and actor, production unit (UPP) resolved inside the company, duplicate
-- detection, preview, preview_hash confirmation, metadata.source.
--
-- This file adds ONLY one function. No table, view, trigger, index, sequence, grant or crud_models row, and no existing
-- row or function is modified: the 099/100 functions are reused as they are (fn_livestock_chat_*) and their definitions
-- are compared before and after. Nothing calls the new function yet: it changes no visible behavior until the gateway
-- model (PR 2) and the panel (PR 3-4) use it. Role permissions for the gateway are NOT defined here (PR 2, crud_models);
-- the function still refuses anyone who is not an active ADMIN / OWNER / EDITOR of the company (fn_livestock_chat_ctx).
--
-- Signature (19 parameters; p_tenant_id is an integer because the gateway sends it as a bare number, everything else is
-- text because every value must travel as text):
--   p_tenant_id integer, p_upp, p_lot, p_species, p_category, p_business_model, p_ear_tag, p_fire_number,
--   p_electronic_rfid, p_weight_kg, p_birth_date, p_origin_upp, p_tb_test_date, p_br_test_date, p_notes, p_confirmed,
--   p_preview_hash, p_force_duplicate, p_actor_email   (the actor e-mail comes from the verified JWT in the gateway)
--
-- Rules (decided by the project owner):
--   * Weight is OPTIONAL (NULL when not given). TB and BR dates are OPTIONAL.
--   * The ear tag may be empty or "S/N" (any placeholder) in ANY species. The literal 'S/N' is never stored: the animal
--     gets the identifier 'S/N-<company>-<10 hex characters of its own id>' (unique, derived from the animal's id, kept
--     unique by the table's UNIQUE constraint with a retry) and metadata.no_official_tag = true. The preview carries a
--     warning; for a bovine it says the animal cannot be sold or leave until it has a 10-digit SINIIGA tag.
--     A typed tag is kept as typed, except for a bovine: it must be a 10-digit SINIIGA tag (as in 099).
--   * Warnings (never a rejection): no official tag; for a bovine without herd-free dictamen, TB / BR missing or older than
--     60 days (sp_procesar_salida_ganado blocks the exit in those cases); a fire number already used in the company.
--   * The birth date is received as typed (an animal born on the ranch is a valid intake); empty = today in Mexico City
--     (fn_livestock_chat_today). It cannot be in the future nor older than 40 years. It is never estimated from an age.
--   * UPP: fn_livestock_chat_resolve_upp. One active UPP: used by default. Several and none given: need_info with the
--     options. None: need_info. production_unit_id and lot_id are stored; p_origin_upp goes to the column upp_origen
--     (free text, up to 100 characters).
--   * Species empty = BOVINO (the column default). Category, business model and lot are validated by 099's
--     fn_livestock_chat_validate_common.
--   * metadata: source = 'PANEL_ALTA', registered_by, channel = 'PANEL_WEB', registered_at, notes, tool, migration = '102'
--     and no_official_tag. No preview_hash and no sensitive data.
--
-- Answers (jsonb 'status', Spanish 'message'), same states as 099:
--   preview | preview_required | recorded
--   need_info + issues[] (type missing | invalid | ambiguous | not_found; field; message; options; code)
--   duplicate | duplicate_other_company | exists_without_upp   (ear tag or electronic RFID already registered; never says
--                          which company)
--   duplicate_recent      (an animal with the same data and no identifier was registered by the same actor in the last
--                          2 minutes; forced with p_force_duplicate = 'true')
--   warnings[]            (never a rejection)
--   forbidden | palm | invalid (the database refused the row: nothing was written)
--
-- Fail-closed, in this order, on EVERY call: fn_livestock_chat_ctx (plain integer tenant -> active member of an active
-- company -> not palm -> role ADMIN / OWNER / EDITOR). Anything else answers a status and touches no data. The preview never
-- writes. The commit needs the exact preview_hash (32 hex) of the same company, actor and data.
--
-- DEPENDENCY: relies on n8n_user being a PostgreSQL superuser, like 099: the function is revoked from PUBLIC and no GRANT
-- is issued (see the suite CLAUDE.md). If that role ever stops being a superuser, add an explicit GRANT EXECUTE.
-- DEPENDENCY: migration 099 (the fn_livestock_chat_* helpers). 100 is not required.
-- NOTE: 099 aborts when it finds an unknown fn_livestock_chat_* signature; this migration adds none (the function is named
-- sp_register_livestock_panel and has no helper), so 099 can still be re-applied.
--
-- Usage: psql -X -v ON_ERROR_STOP=1 -f 102_panel_livestock_sp.sql                 (dry run: ROLLBACK)
--        psql -X -v ON_ERROR_STOP=1 -v apply=true -f 102_panel_livestock_sp.sql   (COMMIT)
-- Rollback: 102_rollback.sql. State: 102_state_check.sql. Tests: 102_tests.sql (LOCAL / throw-away database only).
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
CREATE TEMP TABLE IF NOT EXISTS tmp_102_fingerprint (k text PRIMARY KEY, v text) ON COMMIT DROP;

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(t.c, ', ') INTO v_missing
      FROM (VALUES ('cattle_livestock.id'), ('cattle_livestock.tenant_id'), ('cattle_livestock.species'),
                   ('cattle_livestock.category'), ('cattle_livestock.business_model'), ('cattle_livestock.current_status'),
                   ('cattle_livestock.rfid_siniiga'), ('cattle_livestock.electronic_rfid'), ('cattle_livestock.numero_fuego'),
                   ('cattle_livestock.birth_date'), ('cattle_livestock.current_weight_kg'),
                   ('cattle_livestock.production_unit_id'), ('cattle_livestock.lot_id'), ('cattle_livestock.upp_origen'),
                   ('cattle_livestock.tb_test_date'), ('cattle_livestock.br_test_date'), ('cattle_livestock.metadata'),
                   ('cattle_livestock.created_at')) AS t (c)
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns ic
                        WHERE ic.table_schema = 'public'
                          AND ic.table_name = split_part(t.c, '.', 1)
                          AND ic.column_name = split_part(t.c, '.', 2));
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'ABORT 102: missing columns: %', v_missing;
    END IF;

    -- The owner decided that weight and production unit are optional: the columns must accept NULL. The repository has a
    -- contradiction here (legacy load scripts of 2026-08 say "NOT NULL in production"; 099 inserts NULL and its tests assert it).
    -- This guard turns the doubt into an abort BEFORE anything is created, instead of a runtime 'invalid' answer.
    SELECT string_agg(ic.column_name, ', ') INTO v_missing
      FROM information_schema.columns ic
     WHERE ic.table_schema = 'public' AND ic.table_name = 'cattle_livestock'
       AND ic.column_name IN ('current_weight_kg', 'production_unit_id', 'rfid_siniiga', 'electronic_rfid', 'numero_fuego',
                              'lot_id', 'upp_origen', 'tb_test_date', 'br_test_date')
       AND ic.is_nullable = 'NO';
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'ABORT 102: these cattle_livestock columns are NOT NULL, which the optional fields need: %', v_missing;
    END IF;

    IF (SELECT count(*) FROM pg_constraint
         WHERE conname IN ('cattle_livestock_rfid_siniiga_key', 'cattle_livestock_electronic_rfid_key') AND contype = 'u'
           AND conrelid = 'public.cattle_livestock'::regclass) <> 2 THEN
        RAISE EXCEPTION 'ABORT 102: UNIQUE constraints cattle_livestock_rfid_siniiga_key / _electronic_rfid_key not found';
    END IF;

    SELECT string_agg(t.f, ', ') INTO v_missing
      FROM (VALUES ('fn_livestock_chat_txt(text)'), ('fn_livestock_chat_norm(text)'), ('fn_livestock_chat_num(text)'),
                   ('fn_livestock_chat_date(text)'), ('fn_livestock_chat_today()'),
                   ('fn_livestock_chat_is_placeholder(text)'), ('fn_livestock_chat_tag(text)'),
                   ('fn_livestock_chat_ctx(text,text)'), ('fn_livestock_chat_tag_conflict(integer,text)'),
                   ('fn_livestock_chat_tag_warnings(integer,text)'),
                   ('fn_livestock_chat_validate_common(integer,text,text,text,text,text)'),
                   ('fn_species_requires_bovine_compliance(character varying)'),
                   ('fn_has_official_ear_tag(character varying)'),
                   ('fn_is_herd_free(uuid,character varying,date)'),
                   ('fn_reject_palm_company(integer)')) AS t (f)
     WHERE to_regprocedure('public.' || t.f) IS NULL;
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'ABORT 102: required functions are missing (apply 099 first): %', v_missing;
    END IF;

    -- A function of this migration that already exists with a DIFFERENT signature would become an overload.
    SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_missing
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname = 'sp_register_livestock_panel'
       AND p.oid::regprocedure::text <>
           'sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)';
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'ABORT 102: unexpected existing signatures (would become overloads): %', v_missing;
    END IF;

    -- Fingerprint of every function 102 must NOT change: the 099/100 helpers and tools, and the palm guard.
    INSERT INTO tmp_102_fingerprint
    SELECT 'unchanged_functions',
           coalesce(md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), '|'
                                   ORDER BY p.oid::regprocedure::text)), 'none')
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND (p.proname LIKE 'fn\_livestock\_chat\_%'
            OR p.proname IN ('sp_register_livestock_regularization', 'sp_register_livestock_purchase_chat',
                             'fn_reject_palm_company', 'fn_species_requires_bovine_compliance', 'fn_has_official_ear_tag',
                             'fn_is_herd_free', 'sp_procesar_salida_ganado'))
    ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
    RAISE NOTICE '102: preconditions OK; unchanged-functions fingerprint %',
        (SELECT v FROM tmp_102_fingerprint WHERE k = 'unchanged_functions');
END $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Tool: sp_register_livestock_panel.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sp_register_livestock_panel(
    p_tenant_id        integer,
    p_upp              text,
    p_lot              text,
    p_species          text,
    p_category         text,
    p_business_model   text,
    p_ear_tag          text,
    p_fire_number      text,
    p_electronic_rfid  text,
    p_weight_kg        text,
    p_birth_date       text,
    p_origin_upp       text,
    p_tb_test_date     text,
    p_br_test_date     text,
    p_notes            text,
    p_confirmed        text,
    p_preview_hash     text,
    p_force_duplicate  text,
    p_actor_email      text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    c_channel    constant text := 'PANEL_WEB';
    v_ctx        jsonb;
    v_tenant     integer;
    v_actor      text;
    v_common     jsonb;
    v_issues     jsonb;
    v_unit       uuid;
    v_bovine     boolean;
    v_today      date := public.fn_livestock_chat_today();
    v_tag_in     text := public.fn_livestock_chat_txt(p_ear_tag);
    v_tag        text;                 -- tag typed by the user (NULL when there is none)
    v_no_tag     boolean;
    v_store_tag  text;                 -- what rfid_siniiga receives
    v_conflict   jsonb;
    v_warn       jsonb := '[]'::jsonb;
    v_wobj       jsonb;
    v_fire       text := public.fn_livestock_chat_txt(p_fire_number);
    v_fire_n     integer;
    v_chip_in    text := public.fn_livestock_chat_txt(p_electronic_rfid);
    v_chip       text;
    v_weight_in  text := public.fn_livestock_chat_txt(p_weight_kg);
    v_weight     numeric;
    v_birth_in   text := public.fn_livestock_chat_txt(p_birth_date);
    v_birth      date;
    v_origin     text := public.fn_livestock_chat_txt(p_origin_upp);
    v_tb_in      text := public.fn_livestock_chat_txt(p_tb_test_date);
    v_br_in      text := public.fn_livestock_chat_txt(p_br_test_date);
    v_tb         date;
    v_br         date;
    v_free       boolean;
    v_notes      text := left(public.fn_livestock_chat_txt(p_notes), 500);
    v_data       jsonb;
    v_hash       text;
    v_preview    jsonb;
    v_id         uuid;
    v_try        integer;
BEGIN
    -- Session gate first: nothing below runs for a stranger.
    v_ctx := public.fn_livestock_chat_ctx(p_tenant_id::text, p_actor_email);
    IF NOT (v_ctx->>'ok')::boolean THEN
        RETURN v_ctx->'result';
    END IF;
    v_tenant := (v_ctx->>'tenant')::integer;
    v_actor := v_ctx->>'actor';

    -- Species (empty = BOVINO), category, business model, UPP and lot.
    v_common := public.fn_livestock_chat_validate_common(v_tenant,
                    coalesce(public.fn_livestock_chat_txt(p_species), 'BOVINO'),
                    p_category, p_business_model, p_upp, p_lot);
    v_issues := v_common->'issues';
    v_unit := (v_common->>'production_unit_id')::uuid;
    -- Unknown species stays strict (bovine regime), as fn_species_requires_bovine_compliance does.
    v_bovine := public.fn_species_requires_bovine_compliance((v_common->>'species')::varchar);

    -- Ear tag. Empty or a placeholder ("S/N", "sin arete"...) = no tag (allowed, with a warning).
    v_no_tag := v_tag_in IS NULL
                OR public.fn_livestock_chat_is_placeholder(v_tag_in)
                OR public.fn_livestock_chat_norm(v_tag_in) IN ('SIN ARETE', 'SIN ID', 'SIN IDENTIFICADOR');
    IF NOT v_no_tag THEN
        v_tag := public.fn_livestock_chat_tag(v_tag_in);
        IF v_bovine AND NOT public.fn_has_official_ear_tag(v_tag::varchar) THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'ear_tag',
                'message', 'El arete SINIIGA de un bovino debe tener exactamente 10 dígitos. Si el animal no tiene arete, déjalo vacío o escribe S/N.');
        ELSIF length(v_tag) > 100 THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'ear_tag',
                'message', 'El identificador es demasiado largo.');
        ELSE
            -- A registered tag ends the request: there is nothing else to ask for an animal that already exists.
            v_conflict := public.fn_livestock_chat_tag_conflict(v_tenant, v_tag);
            IF v_conflict IS NOT NULL THEN
                RETURN v_conflict || jsonb_build_object('empresa', v_ctx->>'company_name', 'arete', v_tag);
            END IF;
        END IF;
    END IF;

    -- Electronic RFID (chip): optional, exactly 15 digits, UNIQUE globally.
    IF v_chip_in IS NOT NULL THEN
        v_chip := regexp_replace(v_chip_in, '[\s.\-]', '', 'g');
        IF v_chip !~ '^[0-9]{15}$' THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'electronic_rfid',
                'message', 'El chip electrónico debe tener exactamente 15 dígitos.');
        ELSIF v_chip IS NOT DISTINCT FROM v_tag THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'electronic_rfid',
                'message', 'El chip electrónico no puede ser igual al arete.');
        ELSE
            v_conflict := public.fn_livestock_chat_tag_conflict(v_tenant, v_chip);
            IF v_conflict IS NOT NULL THEN
                RETURN v_conflict || jsonb_build_object('empresa', v_ctx->>'company_name', 'arete', v_chip,
                                                        'campo', 'electronic_rfid');
            END IF;
        END IF;
    END IF;

    -- Fire number: optional free text (column limit 50). A repeated one is a warning, never a rejection.
    IF v_fire IS NOT NULL AND length(v_fire) > 50 THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'fire_number',
            'message', 'El número de fuego es demasiado largo (máximo 50 caracteres).');
    END IF;

    -- Weight: optional, kilos greater than 0 (up to 2000), two decimals.
    IF v_weight_in IS NOT NULL THEN
        v_weight := public.fn_livestock_chat_num(regexp_replace(v_weight_in, '\s*(kg|kgs|kilos?)\s*$', '', 'i'));
        IF v_weight IS NULL OR v_weight <= 0 OR v_weight > 2000 THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'weight_kg',
                'message', 'El peso debe ser un número de kilos mayor que 0 (o déjalo vacío).');
        ELSE
            v_weight := round(v_weight, 2);
        END IF;
    END IF;

    -- Birth date as typed; empty = today in Mexico City. Not in the future, not older than 40 years.
    IF v_birth_in IS NULL THEN
        v_birth := v_today;
    ELSE
        v_birth := public.fn_livestock_chat_date(v_birth_in);
        IF v_birth IS NULL THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'birth_date',
                'message', 'La fecha de nacimiento debe tener el formato AAAA-MM-DD.');
        ELSIF v_birth > v_today THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'birth_date',
                'message', 'La fecha de nacimiento no puede ser futura.');
        ELSIF v_birth < v_today - interval '40 years' THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'birth_date',
                'message', 'La fecha de nacimiento es demasiado antigua. Revisa el año.');
        END IF;
    END IF;

    -- Origin UPP label: free text (column limit 100).
    IF v_origin IS NOT NULL AND length(v_origin) > 100 THEN
        v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'origin_upp',
            'message', 'La UPP de origen es demasiado larga (máximo 100 caracteres).');
    END IF;

    -- TB / BR dates: optional, a real date, not in the future.
    IF v_tb_in IS NOT NULL THEN
        v_tb := public.fn_livestock_chat_date(v_tb_in);
        IF v_tb IS NULL OR v_tb > v_today THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'tb_test_date',
                'message', 'La fecha de la prueba TB debe ser una fecha válida (AAAA-MM-DD) que no sea futura.');
        END IF;
    END IF;
    IF v_br_in IS NOT NULL THEN
        v_br := public.fn_livestock_chat_date(v_br_in);
        IF v_br IS NULL OR v_br > v_today THEN
            v_issues := v_issues || jsonb_build_object('type', 'invalid', 'field', 'br_test_date',
                'message', 'La fecha de la prueba de brucelosis debe ser una fecha válida (AAAA-MM-DD) que no sea futura.');
        END IF;
    END IF;

    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'need_info', 'empresa', v_ctx->>'company_name', 'issues', v_issues);
    END IF;

    -- Warnings (never a rejection). The same text reaches the preview of every channel.
    v_warn := public.fn_livestock_chat_tag_warnings(v_tenant, v_tag);        -- the tag is also a fire number
    IF v_fire IS NOT NULL THEN
        SELECT count(*) INTO v_fire_n
          FROM (SELECT 1 FROM public.cattle_livestock cl
                 WHERE cl.tenant_id = v_tenant AND cl.numero_fuego = v_fire LIMIT 5) m;
        IF v_fire_n > 0 THEN
            v_warn := v_warn || jsonb_build_array(jsonb_build_object('type', 'fire_number_repeated', 'field', 'fire_number',
                'message', 'Ese número de fuego ya lo tiene ' || CASE WHEN v_fire_n = 1 THEN 'otro animal'
                                                                       WHEN v_fire_n = 5 THEN 'al menos 5 animales'
                                                                       ELSE v_fire_n || ' animales' END
                           || ' de esta empresa. Revisa que no sea el mismo animal antes de confirmar.'));
        END IF;
    END IF;
    IF v_no_tag THEN
        v_warn := v_warn || jsonb_build_array(jsonb_build_object('type', 'no_official_tag', 'field', 'ear_tag',
            'message', CASE WHEN v_bovine
                            THEN 'Sin arete oficial: el animal se registrará con un identificador interno (S/N-…) y NO podrá venderse ni darse de salida hasta que tenga un arete SINIIGA de 10 dígitos.'
                            ELSE 'Sin arete: el animal se registrará con un identificador interno (S/N-…).' END));
    END IF;
    IF v_bovine THEN
        -- Same rule as sp_procesar_salida_ganado: blocked when the test is missing or older than 60 days, unless the UPP
        -- has a herd-free dictamen for that disease.
        v_free := v_unit IS NOT NULL AND public.fn_is_herd_free(v_unit, 'TB'::varchar, v_today);
        IF NOT coalesce(v_free, false) AND (v_tb IS NULL OR v_today - v_tb > 60) THEN
            v_warn := v_warn || jsonb_build_array(jsonb_build_object('type', 'tb_missing_or_expired', 'field', 'tb_test_date',
                'message', CASE WHEN v_tb IS NULL
                                THEN 'Prueba TB no registrada: la venta o salida de este animal se bloqueará hasta registrarla (salvo dictamen de hato libre de la UPP).'
                                ELSE 'La prueba TB tiene ' || (v_today - v_tb) || ' días (más de 60): la venta o salida se bloqueará hasta renovarla (salvo dictamen de hato libre de la UPP).' END));
        END IF;
        v_free := v_unit IS NOT NULL AND public.fn_is_herd_free(v_unit, 'BR'::varchar, v_today);
        IF NOT coalesce(v_free, false) AND (v_br IS NULL OR v_today - v_br > 60) THEN
            v_warn := v_warn || jsonb_build_array(jsonb_build_object('type', 'br_missing_or_expired', 'field', 'br_test_date',
                'message', CASE WHEN v_br IS NULL
                                THEN 'Prueba de brucelosis no registrada: la venta o salida de este animal se bloqueará hasta registrarla (salvo dictamen de hato libre de la UPP).'
                                ELSE 'La prueba de brucelosis tiene ' || (v_today - v_br) || ' días (más de 60): la venta o salida se bloqueará hasta renovarla (salvo dictamen de hato libre de la UPP).' END));
        END IF;
    END IF;
    v_wobj := CASE WHEN jsonb_array_length(v_warn) > 0 THEN jsonb_build_object('warnings', v_warn) ELSE '{}'::jsonb END;

    -- The hash covers the company, the actor and every normalized value (never the generated identifier).
    v_data := jsonb_build_object(
        'production_unit_id', v_common->>'production_unit_id', 'lot_id', v_common->>'lot_id',
        'species', v_common->>'species', 'category', v_common->>'category',
        'business_model', v_common->>'business_model', 'ear_tag', v_tag, 'no_official_tag', v_no_tag,
        'fire_number', v_fire, 'electronic_rfid', v_chip, 'weight_kg', v_weight, 'birth_date', v_birth,
        'origin_upp', v_origin, 'tb_test_date', v_tb, 'br_test_date', v_br, 'notes', v_notes);
    v_hash := md5(jsonb_build_object('kind', 'PANEL_ALTA', 'tenant', v_tenant, 'actor', v_actor, 'data', v_data)::text);
    v_preview := jsonb_strip_nulls(jsonb_build_object(
        'empresa', v_ctx->>'company_name', 'upp', v_common->>'upp', 'upp_code', v_common->>'upp_code',
        'lote', v_common->>'lot', 'especie', v_common->>'species', 'categoria', v_common->>'category',
        'modelo_negocio', v_common->>'business_model', 'arete', v_tag, 'sin_arete_oficial', v_no_tag,
        'numero_fuego', v_fire, 'rfid_electronico', v_chip, 'peso_kg', v_weight, 'fecha_nacimiento', v_birth,
        'upp_origen', v_origin, 'prueba_tb', v_tb, 'prueba_br', v_br, 'notas', v_notes));

    IF lower(coalesce(public.fn_livestock_chat_txt(p_confirmed), '')) <> 'true' THEN
        RETURN v_wobj || jsonb_build_object('status', 'preview', 'preview', v_preview, 'preview_hash', v_hash,
            'message', 'Vista previa del alta: todavía no se guardó nada. Revísala y confirma para registrar.');
    END IF;
    IF public.fn_livestock_chat_txt(p_preview_hash) IS DISTINCT FROM v_hash THEN
        RETURN v_wobj || jsonb_build_object('status', 'preview_required', 'preview', v_preview, 'preview_hash', v_hash,
            'message', 'Falta la vista previa o los datos cambiaron: revisa esta vista previa y confirma otra vez.');
    END IF;

    -- Double confirmation for an animal with no identifier at all (nothing unique protects it).
    IF v_no_tag AND v_chip IS NULL AND lower(coalesce(public.fn_livestock_chat_txt(p_force_duplicate), '')) <> 'true' THEN
        SELECT cl.id INTO v_id
          FROM public.cattle_livestock cl
         WHERE cl.tenant_id = v_tenant
           AND cl.metadata->>'source' = 'PANEL_ALTA'
           AND cl.metadata->>'registered_by' = v_actor
           AND cl.metadata->>'no_official_tag' = 'true'
           AND cl.created_at > localtimestamp - interval '2 minutes'
           AND cl.species IS NOT DISTINCT FROM v_common->>'species'
           AND cl.category IS NOT DISTINCT FROM v_common->>'category'
           AND cl.business_model IS NOT DISTINCT FROM v_common->>'business_model'
           AND cl.birth_date IS NOT DISTINCT FROM v_birth
           AND cl.production_unit_id IS NOT DISTINCT FROM v_unit
           AND cl.lot_id IS NOT DISTINCT FROM (v_common->>'lot_id')::uuid
           AND cl.numero_fuego IS NOT DISTINCT FROM v_fire
           AND cl.current_weight_kg IS NOT DISTINCT FROM v_weight
         LIMIT 1;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('status', 'duplicate_recent', 'livestock_id', v_id, 'preview', v_preview,
                'message', 'Un animal igual y sin identificador se registró hace menos de 2 minutos. Si de verdad es otro '
                           || 'animal, confirma que es otro y se registrará.');
        END IF;
    END IF;

    -- Insert. An animal without a tag gets 'S/N-<company>-<10 hex of its own id>'; a (very unlikely) collision of that
    -- identifier is retried with a new id. A collision of a typed tag or chip is answered as a duplicate.
    FOR v_try IN 1..5 LOOP
        v_id := gen_random_uuid();
        v_store_tag := CASE WHEN v_no_tag
                            THEN 'S/N-' || v_tenant::text || '-' || upper(left(replace(v_id::text, '-', ''), 10))
                            ELSE v_tag END;
        BEGIN
            INSERT INTO public.cattle_livestock (
                id, tenant_id, species, category, business_model, current_status, rfid_siniiga, numero_fuego,
                electronic_rfid, birth_date, current_weight_kg, production_unit_id, lot_id, upp_origen, tb_test_date,
                br_test_date, metadata, created_at)
            VALUES (
                v_id, v_tenant, v_common->>'species', v_common->>'category', v_common->>'business_model', 'ACTIVO',
                v_store_tag, v_fire, v_chip, v_birth, v_weight, v_unit, (v_common->>'lot_id')::uuid, v_origin, v_tb, v_br,
                jsonb_strip_nulls(jsonb_build_object(
                    'source', 'PANEL_ALTA',
                    'registered_by', v_actor,
                    'channel', c_channel,
                    'registered_at', to_char(now() AT TIME ZONE 'America/Mexico_City', 'YYYY-MM-DD"T"HH24:MI:SS'),
                    'no_official_tag', CASE WHEN v_no_tag THEN true END,
                    'notes', v_notes,
                    'tool', 'sp_register_livestock_panel',
                    'migration', '102')),
                now());
            EXIT;
        EXCEPTION
            WHEN unique_violation THEN
                v_conflict := CASE WHEN v_tag IS NOT NULL THEN public.fn_livestock_chat_tag_conflict(v_tenant, v_tag) END;
                IF v_conflict IS NOT NULL THEN
                    RETURN v_conflict || jsonb_build_object('empresa', v_ctx->>'company_name', 'arete', v_tag);
                END IF;
                v_conflict := CASE WHEN v_chip IS NOT NULL THEN public.fn_livestock_chat_tag_conflict(v_tenant, v_chip) END;
                IF v_conflict IS NOT NULL THEN
                    RETURN v_conflict || jsonb_build_object('empresa', v_ctx->>'company_name', 'arete', v_chip,
                                                            'campo', 'electronic_rfid');
                END IF;
                IF NOT v_no_tag OR v_try = 5 THEN
                    RETURN jsonb_build_object('status', 'duplicate', 'code', 'P0116',
                        'message', 'Ese identificador ya está registrado. No se guardó nada.');
                END IF;
                v_id := NULL;           -- generated identifier collided: try again with a new id
            WHEN raise_exception OR no_data_found OR check_violation OR foreign_key_violation OR not_null_violation THEN
                RETURN jsonb_build_object('status', 'invalid', 'code', SQLSTATE,
                    'message', 'La base de datos rechazó el registro y no se guardó nada. Revisa la UPP y el lote.');
        END;
    END LOOP;

    RETURN v_wobj || jsonb_build_object('status', 'recorded', 'livestock_id', v_id, 'preview', v_preview,
        'identificador', v_store_tag, 'message', 'Animal registrado.');
END;
$$;

REVOKE ALL ON FUNCTION public.sp_register_livestock_panel(integer, text, text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text, text) FROM PUBLIC;

COMMENT ON FUNCTION public.sp_register_livestock_panel(integer, text, text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text, text) IS
  '102: web panel livestock intake (preview / commit with preview_hash). The tenant and the actor e-mail come from the '
  'verified gateway session. Rolled back by 102_rollback.sql (the function is dropped; animals already registered stay).';

-- ---------------------------------------------------------------------------------------------
-- 2. Self-check
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_r jsonb;
BEGIN
    IF to_regprocedure('public.sp_register_livestock_panel(integer,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION '102: the function is missing after the migration';
    END IF;
    IF (SELECT coalesce(md5(string_agg(p.oid::regprocedure::text || ':' || md5(pg_get_functiondef(p.oid)), '|'
                                       ORDER BY p.oid::regprocedure::text)), 'none')
          FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace
           AND (p.proname LIKE 'fn\_livestock\_chat\_%'
                OR p.proname IN ('sp_register_livestock_regularization', 'sp_register_livestock_purchase_chat',
                                 'fn_reject_palm_company', 'fn_species_requires_bovine_compliance', 'fn_has_official_ear_tag',
                                 'fn_is_herd_free', 'sp_procesar_salida_ganado')))
       IS DISTINCT FROM (SELECT v FROM tmp_102_fingerprint WHERE k = 'unchanged_functions') THEN
        RAISE EXCEPTION '102: a 099/100 function (or the palm guard) changed during the migration';
    END IF;
    -- Data-free smoke: an empty tenant and a stranger are refused before anything is read.
    v_r := public.sp_register_livestock_panel(NULL, NULL, NULL, 'BOVINO', 'BECERRO', 'CRIA', '9900000001', NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, 'true', NULL, NULL, 'nobody@example.test');
    IF v_r->>'status' <> 'forbidden' THEN
        RAISE EXCEPTION '102: smoke test expected forbidden, got %', v_r;
    END IF;
    v_r := public.sp_register_livestock_panel(-1, NULL, NULL, 'BOVINO', 'BECERRO', 'CRIA', '9900000001', NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, 'true', NULL, NULL, 'nobody@example.test');
    IF v_r->>'status' <> 'forbidden' THEN
        RAISE EXCEPTION '102: smoke test expected forbidden, got %', v_r;
    END IF;
    RAISE NOTICE '102: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 102 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 102 rolled back ***'
\endif
\endif
