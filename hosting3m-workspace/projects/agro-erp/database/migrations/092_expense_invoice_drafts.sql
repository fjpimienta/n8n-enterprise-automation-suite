-- 092_expense_invoice_drafts.sql
-- Server-side drafts so the agent never handles invoice JSON. The channel workflow (Chat Web / WhatsApp) parses the XML via cfdi-service,
-- stores the original, and creates a draft; the agent only sees a draft_id and a short summary.
-- REQUIRES 091. Nothing existing is altered, replaced or dropped.
-- Table:   expense_invoice_drafts   rows immutable except previewed_* / consumed_at; never deletable (P0095)
-- Workflow-only (NOT an agent tool): sp_expense_invoice_draft_create
-- Agent tools: sp_expense_invoice_preview (writes nothing but the preview mark) and sp_expense_invoice_confirm
--   confirm is refused (preview_required) unless a preview of the SAME draft with the SAME category/description/date happened in the last 15 min.
-- Rollback: 092_rollback.sql. State: 092_state_check.sql. Tests: 092_tests.sql.
-- Usage:   psql -v ON_ERROR_STOP=1 -f 092_expense_invoice_drafts.sql (dry run) | ... -v apply=true -f ... (commit)

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
    IF to_regprocedure('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 091 is not applied here.';
    END IF;
    IF pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure) LIKE '%''disabled''%' THEN
        RAISE EXCEPTION 'ABORT: 091 is rolled back (register is disabled); re-apply 091 first.';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.expense_invoice_drafts (
    id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company         integer     NOT NULL REFERENCES public.companys (id_company),
    user_email         text        NOT NULL CONSTRAINT ck_eid_email CHECK (user_email = lower(btrim(user_email)) AND length(user_email) BETWEEN 3 AND 254),
    channel            text        NOT NULL CONSTRAINT ck_eid_channel CHECK (channel IN ('CHAT_WEB', 'WHATSAPP')),
    invoice            jsonb       NOT NULL,
    source_sha256      text        NOT NULL CONSTRAINT ck_eid_sha CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    original_path      text        NOT NULL CONSTRAINT ck_eid_path CHECK (original_path ~ '^[1-9][0-9]{0,9}/[0-9]{4}/(0[1-9]|1[0-2])/[0-9a-f]{64}\.xml$'),
    sat_status         text        NOT NULL CONSTRAINT ck_eid_sat CHECK (sat_status IN ('VIGENTE', 'CANCELADO', 'NO_ENCONTRADO', 'ERROR')),
    previewed_hash     text,
    previewed_at       timestamptz,
    consumed_at        timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    expires_at         timestamptz NOT NULL DEFAULT now() + interval '30 minutes'
);
CREATE INDEX IF NOT EXISTS ix_eid_company_user ON public.expense_invoice_drafts (id_company, user_email, created_at DESC);
COMMENT ON TABLE public.expense_invoice_drafts IS '092: server-side CFDI drafts (agent sees only the id). Immutable except previewed_hash/previewed_at/consumed_at; not deletable (P0095). Not in crud_models.';

CREATE OR REPLACE FUNCTION public.fn_trg_expense_invoice_drafts_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (to_jsonb(OLD) - 'previewed_hash' - 'previewed_at' - 'consumed_at') IS DISTINCT FROM (to_jsonb(NEW) - 'previewed_hash' - 'previewed_at' - 'consumed_at') THEN
            RAISE EXCEPTION 'expense_invoice_drafts: only the preview mark and consumed_at can change.' USING ERRCODE = 'P0095';
        END IF;
        IF OLD.consumed_at IS NOT NULL AND NEW.consumed_at IS DISTINCT FROM OLD.consumed_at THEN
            RAISE EXCEPTION 'expense_invoice_drafts: consumed_at cannot change once set.' USING ERRCODE = 'P0095';
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'expense_invoice_drafts rows are not deletable.' USING ERRCODE = 'P0095';
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_eid_guard_row' AND tgrelid = 'public.expense_invoice_drafts'::regclass) THEN
        CREATE TRIGGER trg_eid_guard_row BEFORE UPDATE OR DELETE ON public.expense_invoice_drafts
            FOR EACH ROW EXECUTE FUNCTION public.fn_trg_expense_invoice_drafts_guard();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_eid_guard_trunc' AND tgrelid = 'public.expense_invoice_drafts'::regclass) THEN
        CREATE TRIGGER trg_eid_guard_trunc BEFORE TRUNCATE ON public.expense_invoice_drafts
            FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trg_expense_invoice_drafts_guard();
    END IF;
END $$;

-- Hash of what the user is shown, so confirm can only register exactly what was previewed.
CREATE OR REPLACE FUNCTION public.fn_expense_invoice_params_hash(p_category text, p_description text, p_expense_date text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT md5(upper(btrim(coalesce(p_category, ''))) || '|' || btrim(coalesce(p_description, '')) || '|' || btrim(coalesce(p_expense_date, '')))
$$;

-- SAT status handed to sp_expense_invoice_register: a QA company RFC may skip a NO_ENCONTRADO/ERROR answer; CANCELADO never.
CREATE OR REPLACE FUNCTION public.fn_expense_invoice_draft_sat(p_company integer, p_draft public.expense_invoice_drafts)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN p_draft.sat_status = 'VIGENTE' THEN 'VIGENTE'
        WHEN p_draft.sat_status IN ('NO_ENCONTRADO', 'ERROR') AND EXISTS (
            SELECT 1 FROM public.company_tax_ids t
             WHERE t.id_company = p_company AND t.rfc = upper(p_draft.invoice #>> '{receptor,rfc}') AND t.is_active IS TRUE AND t.qa_skip_sat IS TRUE
        ) THEN 'SKIPPED_TEST'
        ELSE p_draft.sat_status
    END
$$;

-- Workflow-only. The caller (n8n channel workflow) has already parsed the XML, checked SAT and stored the original.
CREATE OR REPLACE FUNCTION public.sp_expense_invoice_draft_create(
    p_tenant_id text, p_user_email text, p_channel text, p_invoice text, p_original_path text, p_sat_status text
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_co    integer;
    v_email text := lower(btrim(coalesce(p_user_email, '')));
    v_role  text;
    j       jsonb;
    v_sha   text;
    v_id    uuid;
    v_exp   timestamptz;
BEGIN
    v_co := public.fn_repro_ctx(p_tenant_id, p_user_email);
    SELECT uc.role INTO v_role FROM public.user_companies uc
     WHERE uc.id_company = v_co AND lower(uc.email) = v_email AND uc.is_active IS TRUE LIMIT 1;
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'EDITOR', 'OWNER') THEN
        RETURN jsonb_build_object('status', 'forbidden', 'message', 'Tu rol no permite registrar facturas.');
    END IF;
    BEGIN
        j := p_invoice::jsonb;
        IF jsonb_typeof(j) <> 'object' THEN RAISE EXCEPTION 'not an object'; END IF;
        v_sha := lower(j ->> 'sourceSha256');
        IF upper(j ->> 'uuid') !~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' THEN RAISE EXCEPTION 'bad uuid'; END IF;
    EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_INVOICE', 'message', 'La factura no tiene el formato esperado.');
    END;
    IF v_sha IS NULL OR v_sha !~ '^[0-9a-f]{64}$' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_HASH', 'message', 'Falta la huella del archivo original.');
    END IF;
    IF p_original_path IS NULL OR p_original_path NOT LIKE (v_co::text || '/%') OR p_original_path !~ ('/' || v_sha || '\.xml$') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'ORIGINAL_PATH_INVALID', 'message', 'La ruta del archivo original no corresponde a esta empresa o a esta factura.');
    END IF;
    IF upper(btrim(coalesce(p_channel, ''))) NOT IN ('CHAT_WEB', 'WHATSAPP') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_CHANNEL', 'message', 'Canal no valido.');
    END IF;
    IF upper(btrim(coalesce(p_sat_status, ''))) NOT IN ('VIGENTE', 'CANCELADO', 'NO_ENCONTRADO', 'ERROR') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_SAT_STATUS', 'message', 'Estatus SAT no valido.');
    END IF;
    INSERT INTO public.expense_invoice_drafts (id_company, user_email, channel, invoice, source_sha256, original_path, sat_status)
    VALUES (v_co, v_email, upper(btrim(p_channel)), j, v_sha, p_original_path, upper(btrim(p_sat_status)))
    RETURNING id, expires_at INTO v_id, v_exp;
    RETURN jsonb_build_object('status', 'draft_created', 'draft_id', v_id, 'expires_at', v_exp,
        'summary', jsonb_build_object(
            'emisor_name', left(regexp_replace(coalesce(j #>> '{emisor,nombre}', ''), '[[:cntrl:]]', '', 'g'), 150),
            'emisor_rfc', upper(j #>> '{emisor,rfc}'), 'receptor_rfc', upper(j #>> '{receptor,rfc}'),
            'cfdi_folio', left(coalesce(j ->> 'serie', '') || coalesce(j ->> 'folio', ''), 40),
            'issued_at', j ->> 'fechaEmision', 'amount', (j ->> 'totalCents')::numeric / 100,
            'sat_status', upper(btrim(p_sat_status)),
            'concepts', coalesce((SELECT jsonb_agg(jsonb_build_object('clave', x ->> 'claveProdServ',
                           'description', left(regexp_replace(coalesce(x ->> 'descripcion', ''), '[[:cntrl:]]', '', 'g'), 80),
                           'amount', (x ->> 'importeCents')::numeric / 100))
                         FROM (SELECT x FROM jsonb_array_elements(coalesce(j -> 'conceptos', '[]'::jsonb)) WITH ORDINALITY AS t(x, n) ORDER BY n LIMIT 5) q), '[]'::jsonb)));
END $$;

-- Agent tool 1: preview. Writes nothing except the preview mark.
CREATE OR REPLACE FUNCTION public.sp_expense_invoice_preview(
    p_tenant_id text, p_user_email text, p_draft_id text, p_category text,
    p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_co    integer;
    v_email text := lower(btrim(coalesce(p_user_email, '')));
    d       public.expense_invoice_drafts;
    r       jsonb;
BEGIN
    v_co := public.fn_repro_ctx(p_tenant_id, p_user_email);
    BEGIN
        SELECT * INTO d FROM public.expense_invoice_drafts
         WHERE id = p_draft_id::uuid AND id_company = v_co AND user_email = v_email FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontre ese borrador de factura.');
    END;
    IF NOT FOUND THEN RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontre ese borrador de factura.'); END IF;
    IF d.consumed_at IS NOT NULL THEN RETURN jsonb_build_object('status', 'already_registered', 'message', 'Esta factura ya se proceso.'); END IF;
    IF d.expires_at < now() THEN RETURN jsonb_build_object('status', 'draft_expired', 'message', 'El borrador expiro; vuelve a enviar el archivo.'); END IF;
    r := public.sp_expense_invoice_register(p_tenant_id, p_user_email, d.invoice::text, p_category, p_description, p_expense_date,
                                            d.original_path, public.fn_expense_invoice_draft_sat(v_co, d), 'false');
    IF r ->> 'status' = 'preview' THEN
        UPDATE public.expense_invoice_drafts
           SET previewed_hash = public.fn_expense_invoice_params_hash(p_category, p_description, p_expense_date), previewed_at = now()
         WHERE id = d.id;
    END IF;
    RETURN r || jsonb_build_object('draft_id', d.id);
END $$;

-- Agent tool 2: confirm. Only after a matching preview (same draft, same category/description/date) in the last 15 minutes.
CREATE OR REPLACE FUNCTION public.sp_expense_invoice_confirm(
    p_tenant_id text, p_user_email text, p_draft_id text, p_category text,
    p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_co    integer;
    v_email text := lower(btrim(coalesce(p_user_email, '')));
    d       public.expense_invoice_drafts;
    r       jsonb;
BEGIN
    v_co := public.fn_repro_ctx(p_tenant_id, p_user_email);
    BEGIN
        SELECT * INTO d FROM public.expense_invoice_drafts
         WHERE id = p_draft_id::uuid AND id_company = v_co AND user_email = v_email FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontre ese borrador de factura.');
    END;
    IF NOT FOUND THEN RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontre ese borrador de factura.'); END IF;
    IF d.consumed_at IS NOT NULL THEN RETURN jsonb_build_object('status', 'already_registered', 'message', 'Esta factura ya se proceso.'); END IF;
    IF d.expires_at < now() THEN RETURN jsonb_build_object('status', 'draft_expired', 'message', 'El borrador expiro; vuelve a enviar el archivo.'); END IF;
    IF d.previewed_at IS NULL OR d.previewed_at < now() - interval '15 minutes'
       OR d.previewed_hash IS DISTINCT FROM public.fn_expense_invoice_params_hash(p_category, p_description, p_expense_date) THEN
        RETURN jsonb_build_object('status', 'preview_required',
            'message', 'Antes de registrar, muestra la vista previa con esta misma categoria, fecha y descripcion y espera el Si del usuario.');
    END IF;
    r := public.sp_expense_invoice_register(p_tenant_id, p_user_email, d.invoice::text, p_category, p_description, p_expense_date,
                                            d.original_path, public.fn_expense_invoice_draft_sat(v_co, d), 'true');
    IF r ->> 'status' IN ('recorded', 'duplicate') THEN
        UPDATE public.expense_invoice_drafts SET consumed_at = now() WHERE id = d.id;
    END IF;
    RETURN r || jsonb_build_object('draft_id', d.id);
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 092 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 092 rolled back ***'
\endif
\endif
