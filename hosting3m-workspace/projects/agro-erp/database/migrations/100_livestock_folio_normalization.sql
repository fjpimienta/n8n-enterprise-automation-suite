-- 100_livestock_folio_normalization.sql
-- Normalizes the transit guide folio typed in the livestock regularization chat tool: upper case and runs of white space
-- collapsed to one space. Hyphens and every other character are kept. Until now the folio was stored as typed (trimmed only).
--
-- This file adds ONE helper function and replaces ONE function:
--   * public.fn_livestock_chat_folio(text)  (new, IMMUTABLE)
--   * public.sp_register_livestock_regularization(...)  CREATE OR REPLACE with the 099 body and ONE changed line:
--       v_folio := public.fn_livestock_chat_folio(p_guide_folio)   (099 used public.fn_livestock_chat_txt(p_guide_folio))
-- The body below is extracted from 099_livestock_regularization.sql by a script, not retyped. Signature, ACL (REVOKE from
-- PUBLIC) and COMMENT are the 099 ones. No table, view, trigger, index or crud_models row is touched and NO existing row is
-- modified or back-filled: animals already registered keep the folio they have.
-- The folio is used only by the regularization tool (preview, preview_hash and metadata). Because the preview_hash is built
-- from the normalized folio, 'prueba-1' and 'PRUEBA-1' give the same hash.
--
-- Usage: psql -X -v ON_ERROR_STOP=1 -f 100_livestock_folio_normalization.sql                 (dry run: ROLLBACK)
--        psql -X -v ON_ERROR_STOP=1 -v apply=true -f 100_livestock_folio_normalization.sql   (COMMIT)
-- Rollback: 100_rollback.sql. State: 100_state_check.sql.
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
-- 0. Preconditions: 099 must be applied and its regularization tool must be the real one (not the rollback stub).
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_def text;
BEGIN
    IF to_regprocedure('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.fn_livestock_chat_txt(text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: 099 is not applied here (regularization tool or fn_livestock_chat_txt missing).';
    END IF;
    v_def := pg_get_functiondef('public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure);
    IF v_def NOT LIKE '%REGULARIZACION_PADRON%' OR v_def LIKE '%''disabled''%' THEN
        RAISE EXCEPTION 'ABORT: the regularization tool is the 099 rollback stub; re-apply 099 first.';
    END IF;
    RAISE NOTICE '100: preconditions OK';
END $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Helper. NULL when fn_livestock_chat_txt() is NULL (empty, 'null', 'undefined'); otherwise upper case with runs of
--    white space collapsed to one space. Accents and punctuation (hyphens included) are kept.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_livestock_chat_folio(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN public.fn_livestock_chat_txt(p) IS NULL THEN NULL
                ELSE upper(regexp_replace(public.fn_livestock_chat_txt(p), '\s+', ' ', 'g'))
           END
$$;

-- ---------------------------------------------------------------------------------------------
-- 2. Tool: register_livestock_regularization. 099 body, extracted by script; only the v_folio initialization differs.
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
    v_folio      text := public.fn_livestock_chat_folio(p_guide_folio);
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

REVOKE ALL ON FUNCTION public.sp_register_livestock_regularization(text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text) FROM PUBLIC;

COMMENT ON FUNCTION public.sp_register_livestock_regularization(text, text, text, text, text, text, text, text,
    text, text, text, text, text, text, text, text) IS
  '099: chat tool register_livestock_regularization (preview / commit with preview_hash). Tenant, actor and channel come '
  'from the verified n8n session. Rolled back by 099_rollback.sql (body -> status disabled).';

-- ---------------------------------------------------------------------------------------------
-- 3. Self-check
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_r   jsonb;
    c_reg constant text := 'public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)';
BEGIN
    IF to_regprocedure('public.fn_livestock_chat_folio(text)') IS NULL OR to_regprocedure(c_reg) IS NULL THEN
        RAISE EXCEPTION '100: a function is missing after the migration';
    END IF;
    IF pg_get_functiondef(c_reg::regprocedure) NOT LIKE '%fn_livestock_chat_folio(p_guide_folio)%' THEN
        RAISE EXCEPTION '100: the regularization tool does not use fn_livestock_chat_folio';
    END IF;
    IF EXISTS (SELECT 1 FROM aclexplode(coalesce((SELECT proacl FROM pg_proc WHERE oid = c_reg::regprocedure),
                                                 acldefault('f', (SELECT proowner FROM pg_proc WHERE oid = c_reg::regprocedure)))) a
                WHERE a.grantee = 0) THEN
        RAISE EXCEPTION '100: PUBLIC can execute the regularization tool';
    END IF;
    IF public.fn_livestock_chat_folio('  g-001 ') IS DISTINCT FROM 'G-001'
       OR public.fn_livestock_chat_folio('ab   cd' || E'\t' || 'ef') IS DISTINCT FROM 'AB CD EF'
       OR public.fn_livestock_chat_folio('prueba-1') IS DISTINCT FROM 'PRUEBA-1'
       OR public.fn_livestock_chat_folio('') IS NOT NULL
       OR public.fn_livestock_chat_folio('null') IS NOT NULL
       OR public.fn_livestock_chat_folio(NULL) IS NOT NULL THEN
        RAISE EXCEPTION '100: fn_livestock_chat_folio returned an unexpected value';
    END IF;
    -- Data-free smoke: a malformed tenant is still refused before anything is read.
    v_r := public.sp_register_livestock_regularization('abc', 'nobody@example.test', 'CHAT_WEB', NULL, NULL, 'BOVINO',
        'BECERRO', 'CRIA', '8', '9900000001', 'f-1', NULL, NULL, 'true', NULL, NULL);
    IF v_r->>'status' <> 'forbidden' THEN
        RAISE EXCEPTION '100: smoke test expected forbidden, got %', v_r;
    END IF;
    RAISE NOTICE '100: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 100 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 100 rolled back ***'
\endif
\endif
