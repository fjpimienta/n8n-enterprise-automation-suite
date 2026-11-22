-- 111_palm_expense_invoices.sql
-- A PALM company registers an expense backed by a CFDI voucher RECEIVED by the company (for example fuel), mirroring 091 / 092 / 093 for livestock
-- with palm-specific objects. SQL only: no n8n, no frontend, no cfdi-service change, no crud_models row.
-- REQUIRES 080, 081, 083 (chat helpers), 092 (expense_invoice_drafts), 104 (company_flags) and 109 (classifier, not the rollback stub). Aborts if missing.
--
-- Objects (all new; nothing existing is replaced or dropped)
--   agri_expense_invoices                       append-only link voucher <-> agri_expenses row (ACTIVE -> VOID is the only change)
--   fn_agri_cfdi_category(text)                 IMMUTABLE product-key prefix -> expense category code (seeded with fuel only)
--   fn_agri_cfdi_unit(text)                     IMMUTABLE SAT unit key -> agri_unit_catalog code
--   fn_agri_expense_invoice_params_hash(...)    hash of category, description, date, plantation and lot (preview / confirm gate)
--   sp_agri_expense_invoice_draft_create        workflow only: stores the parsed voucher as a draft (reuses expense_invoice_drafts)
--   sp_agri_expense_invoice_preview / _confirm  the two agent tools (the model only handles the draft id)
--   sp_agri_expense_invoice_register            the single implementation behind both (unconfirmed = nothing written)
--   fn_trg_agri_expenses_void_invoice + trigger on agri_expenses: voiding an invoice-backed expense voids its link in the same transaction
--   agri_expenses: UNIQUE (id, id_company) so the link can reference the expense and its company together (the id is already the primary key)
--
-- Rules
--   * The company comes from the verified session (tenant + e-mail) through fn_agri_chat_ctx / fn_agri_actor_role: active membership of an active
--     palm company, role ADMIN or OWNER (the preview shows amounts). EDITOR keeps manual capture. Never a client-supplied company.
--   * Role gate: only a voucher whose RECEIVER is a company RFC (109 role EXPENSE) is accepted. SALE, AMBIGUOUS, UNKNOWN (any reason) and any
--     classifier failure refuse with a fixed message and write nothing. Palm RFCs are platform-managed (company_issuer_rfcs): nothing is registered here.
--   * SAT: VIGENTE. A company flagged is_test (company_flags) also accepts NO_ENCONTRADO / ERROR / SKIPPED_TEST, stored as SKIPPED_TEST. CANCELADO never.
--   * No sale rules. Multi-concept vouchers are allowed. Warnings (cash payment form, uso CFDI different from the company's usual, date older than
--     365 days) are informational lines in the preview and never block.
--   * Plantation and lot are not in the voucher: default is a general company expense (both NULL). Resolved by code / name like the palm chat
--     (exact first, then partial, ambiguity never guessed, a lot must belong to the plantation). A single active plantation is only PROPOSED.
--   * Category: from the product keys when every concept maps to the same company category; otherwise the preview lists the company categories and
--     asks. Quantity and unit are set only for a voucher with exactly ONE concept whose unit is mapped; otherwise both NULL.
--   * The expense row is written by sp_agri_record_expense (same transaction), so its validations are not duplicated. amount = voucher total in exact
--     cents / 100; is_invoiced = true; invoice_folio = serie + folio; reported_by_email = the verified session e-mail.
--   * Duplicates: advisory lock per (company, UUID), check, re-check, unique ACTIVE (id_company, uuid); the duplicate answer carries the registered date.
--     The draft is marked consumed only for recorded / duplicate (done by the confirm procedure).
--   * Voiding the expense (sp_agri_void_expense) voids the link, which frees the UUID so a mistaken registration can be redone.
--   * No function that already exists is replaced, so no drift guard is needed; the only existing object touched is agri_expenses (one unique
--     constraint and one AFTER UPDATE trigger).
--   * Privileges and attributes follow 091 / 092 / 104: plain plpgsql VOLATILE functions, no SECURITY DEFINER, no REVOKE (the workflow role is a superuser).
--
-- Error codes reused: P0093 (not a palm company), P0095 (append-only), P0096 (cross-company), P0092 (invalid data). Answers are statuses, not exceptions.
-- Rollback: 111_rollback.sql replaces the four procedures with a fail-closed stub ({status: disabled}); tables, helpers and the trigger stay.
-- State:    111_state_check.sql. Tests: 111_tests.sql, 111_mutation_check.sh. Runbook: 111_RUNBOOK.md.
-- Usage:    psql -X -v ON_ERROR_STOP=1 -f 111_palm_expense_invoices.sql                (dry run: ROLLBACK)
--           psql -X -v ON_ERROR_STOP=1 -v apply=true -f 111_palm_expense_invoices.sql  (COMMIT)

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
DECLARE
    v_sig text;
BEGIN
    IF to_regclass('public.agri_expenses') IS NULL OR to_regprocedure('public.sp_agri_record_expense(integer,uuid,uuid,uuid,date,numeric,numeric,varchar,varchar,text,boolean,varchar,varchar)') IS NULL THEN
        RAISE EXCEPTION 'ABORT 111: migrations 080 and 081 must be applied first.';
    END IF;
    IF to_regprocedure('public.fn_agri_chat_ctx(text,text,text[],text)') IS NULL OR to_regprocedure('public.fn_agri_chat_resolve_scope(integer,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT 111: migration 083 (chat helpers) must be applied first.';
    END IF;
    IF to_regclass('public.expense_invoice_drafts') IS NULL THEN
        RAISE EXCEPTION 'ABORT 111: migration 092 (expense_invoice_drafts) must be applied first.';
    END IF;
    IF to_regclass('public.company_flags') IS NULL THEN
        RAISE EXCEPTION 'ABORT 111: migration 104 (company_flags) must be applied first.';
    END IF;
    IF to_regprocedure('public.fn_classify_cfdi_role_detail(integer,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT 111: migration 109 (classifier) must be applied first.';
    END IF;
    IF (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.fn_classify_cfdi_role_detail(integer,text,text)')) LIKE '%''DISABLED''%' THEN
        RAISE EXCEPTION 'ABORT 111: the 109 classifier is rolled back (stub); the palm expense procedures would refuse every voucher.';
    END IF;
    -- A function that already carries one of our names must be ours (or our rollback stub): never overwrite something unknown.
    FOR v_sig IN SELECT unnest(ARRAY[
        'public.sp_agri_expense_invoice_draft_create(text,text,text,text,text,text)',
        'public.sp_agri_expense_invoice_preview(text,text,text,text,text,text,text,text)',
        'public.sp_agri_expense_invoice_confirm(text,text,text,text,text,text,text,text)',
        'public.sp_agri_expense_invoice_register(text,text,text,text,text,text,text,text,text,text,text)']) LOOP
        IF to_regprocedure(v_sig) IS NOT NULL
           AND (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure(v_sig)) NOT LIKE '%111 palm expense invoice%' THEN
            RAISE EXCEPTION 'ABORT 111: % exists and is not a 111 function.', v_sig;
        END IF;
    END LOOP;
END $$;

-- 1) Pure mapping helpers (a one-line change adds a key) ----------------------------------------------------------------

-- Product key (ClaveProdServ) -> company expense category code. Seeded with fuel only.
-- TODO(verify against the SAT catalog and a SYNTHETIC voucher): the fuel family is assumed to be the 1510 prefix of the SAT product catalog
-- ("combustibles"); confirm the exact keys (diesel, gasoline) before relying on it. To add a family, add one WHEN line.
CREATE OR REPLACE FUNCTION public.fn_agri_cfdi_category(p_clave text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN left(btrim(coalesce(p_clave, '')), 4) = '1510' THEN 'COMBUSTIBLE'
    END
$$;
COMMENT ON FUNCTION public.fn_agri_cfdi_category(text) IS
  '111: SAT product key prefix -> agri_expense_categories.category_code. Seeded with fuel only; TODO(verify) the exact SAT key family.';

-- SAT unit key (ClaveUnidad) -> agri_unit_catalog.unit_code. Unknown -> NULL (no quantity).
CREATE OR REPLACE FUNCTION public.fn_agri_cfdi_unit(p_clave_unidad text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE upper(btrim(coalesce(p_clave_unidad, '')))
        WHEN 'LTR' THEN 'L'
        WHEN 'KGM' THEN 'KG'
        WHEN 'H87' THEN 'PZA'
        WHEN 'E48' THEN 'SERVICIO'
    END
$$;
COMMENT ON FUNCTION public.fn_agri_cfdi_unit(text) IS
  '111: SAT unit key -> agri_unit_catalog.unit_code (liters, kilograms, piece, service). Unknown -> NULL.';

-- What the user saw in the preview: category, description, date, plantation and lot as typed (empty and the text null are the same).
CREATE OR REPLACE FUNCTION public.fn_agri_expense_invoice_params_hash(p_category text, p_description text, p_expense_date text, p_plantation text, p_lot text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT md5(upper(coalesce(public.fn_agri_chat_txt(p_category), '')) || '|' || coalesce(public.fn_agri_chat_txt(p_description), '')
               || '|' || coalesce(public.fn_agri_chat_txt(p_expense_date), '')
               || '|' || lower(coalesce(public.fn_agri_chat_txt(p_plantation), '')) || '|' || lower(coalesce(public.fn_agri_chat_txt(p_lot), '')))
$$;

-- 2) Link table -------------------------------------------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'agri_expenses_id_company_key' AND conrelid = 'public.agri_expenses'::regclass) THEN
        ALTER TABLE public.agri_expenses ADD CONSTRAINT agri_expenses_id_company_key UNIQUE (id, id_company);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.agri_expense_invoices (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company          integer     NOT NULL REFERENCES public.companys (id_company),
    uuid                text        NOT NULL CONSTRAINT ck_agri_expense_invoices_uuid CHECK (uuid ~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$'),
    emisor_rfc          text        NOT NULL CONSTRAINT ck_agri_expense_invoices_emisor CHECK (emisor_rfc ~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    emisor_name         text,
    receptor_rfc        text        NOT NULL CONSTRAINT ck_agri_expense_invoices_receptor CHECK (receptor_rfc ~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    serie               text,
    folio               text,
    issued_at           timestamp   NOT NULL,
    stamped_at          timestamp   NOT NULL,
    currency            text        NOT NULL DEFAULT 'MXN' CONSTRAINT ck_agri_expense_invoices_currency CHECK (currency = 'MXN'),
    subtotal_cents      bigint      NOT NULL CONSTRAINT ck_agri_expense_invoices_subtotal CHECK (subtotal_cents >= 0),
    discount_cents      bigint      NOT NULL DEFAULT 0 CONSTRAINT ck_agri_expense_invoices_discount CHECK (discount_cents >= 0),
    total_cents         bigint      NOT NULL CONSTRAINT ck_agri_expense_invoices_total CHECK (total_cents > 0),
    taxes               jsonb       NOT NULL DEFAULT '{}'::jsonb,
    payment_form        text,
    payment_method      text,
    uso_cfdi            text,
    source_sha256       text        NOT NULL CONSTRAINT ck_agri_expense_invoices_sha CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    original_path       text        NOT NULL,
    sat_status          text        NOT NULL CONSTRAINT ck_agri_expense_invoices_sat CHECK (sat_status IN ('VIGENTE', 'SKIPPED_TEST')),
    is_test             boolean     NOT NULL DEFAULT false,
    expense_id          uuid        NOT NULL,
    status              text        NOT NULL DEFAULT 'ACTIVE' CONSTRAINT ck_agri_expense_invoices_status CHECK (status IN ('ACTIVE', 'VOID')),
    void_reason         text,
    voided_by_email     text,
    voided_at           timestamp,
    registered_by_email text        NOT NULL CONSTRAINT ck_agri_expense_invoices_by CHECK (btrim(registered_by_email) <> ''),
    created_at          timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
    CONSTRAINT uq_agri_expense_invoices_expense UNIQUE (expense_id),
    CONSTRAINT fk_agri_expense_invoices_expense FOREIGN KEY (expense_id, id_company) REFERENCES public.agri_expenses (id, id_company),
    CONSTRAINT ck_agri_expense_invoices_sat_test CHECK (sat_status = 'VIGENTE' OR is_test),
    CONSTRAINT ck_agri_expense_invoices_path CHECK (original_path ~ '^[1-9][0-9]{0,9}/[0-9]{4}/(0[1-9]|1[0-2])/[0-9a-f]{64}\.xml$'
                                                    AND original_path LIKE id_company::text || '/%' AND original_path LIKE '%/' || source_sha256 || '.xml'),
    CONSTRAINT ck_agri_expense_invoices_void CHECK ((status = 'ACTIVE' AND voided_at IS NULL) OR (status = 'VOID' AND voided_at IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_agri_expense_invoices_active_uuid ON public.agri_expense_invoices (id_company, uuid) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS ix_agri_expense_invoices_company ON public.agri_expense_invoices (id_company, created_at DESC);
COMMENT ON TABLE public.agri_expense_invoices IS
  '111: append-only link between a received CFDI voucher and its agri_expenses row. Written only by sp_agri_expense_invoice_register; the only change is ACTIVE -> VOID, made when the expense is voided. Not deletable (P0095). Not in crud_models.';

CREATE OR REPLACE FUNCTION public.fn_trg_agri_expense_invoices_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_exp record;
BEGIN
    IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
        RAISE EXCEPTION 'agri_expense_invoices rows are not deletable: void the expense instead.' USING ERRCODE = 'P0095';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF public.fn_agri_setting('app.agri_expense_invoice_void') IS DISTINCT FROM 'on'
           OR OLD.status <> 'ACTIVE' OR NEW.status <> 'VOID'
           OR (to_jsonb(NEW) - ARRAY['status', 'void_reason', 'voided_by_email', 'voided_at'])
              IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status', 'void_reason', 'voided_by_email', 'voided_at']) THEN
            RAISE EXCEPTION 'agri_expense_invoices is append-only: the only change is ACTIVE -> VOID.' USING ERRCODE = 'P0095';
        END IF;
        RETURN NEW;
    END IF;
    -- INSERT
    SELECT e.id_company, e.is_void INTO v_exp FROM public.agri_expenses e WHERE e.id = NEW.expense_id;
    IF NOT FOUND OR v_exp.id_company IS DISTINCT FROM NEW.id_company THEN
        RAISE EXCEPTION 'agri_expense_invoices: the expense belongs to another company.' USING ERRCODE = 'P0096';
    END IF;
    IF v_exp.is_void OR NEW.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'agri_expense_invoices: a voucher is linked only to an active expense.' USING ERRCODE = 'P0092';
    END IF;
    IF public.fn_company_business_domain(NEW.id_company) IS DISTINCT FROM 'PALM' THEN
        RAISE EXCEPTION 'agri_expense_invoices: palm companies only.' USING ERRCODE = 'P0093';
    END IF;
    NEW.is_test := coalesce((SELECT f.is_test FROM public.company_flags f WHERE f.id_company = NEW.id_company), false);
    RETURN NEW;
END $$;

-- Voiding an invoice-backed expense voids its link in the same transaction (this frees the UUID).
CREATE OR REPLACE FUNCTION public.fn_trg_agri_expenses_void_invoice()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.is_void AND NOT OLD.is_void THEN
        PERFORM set_config('app.agri_expense_invoice_void', 'on', true);
        UPDATE public.agri_expense_invoices
           SET status = 'VOID', void_reason = NEW.void_reason, voided_by_email = NEW.voided_by_email, voided_at = NEW.voided_at
         WHERE expense_id = NEW.id AND id_company = NEW.id_company AND status = 'ACTIVE';
        PERFORM set_config('app.agri_expense_invoice_void', '', true);
    END IF;
    RETURN NULL;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_agri_expense_invoices_guard_row' AND tgrelid = 'public.agri_expense_invoices'::regclass) THEN
        CREATE TRIGGER trg_agri_expense_invoices_guard_row BEFORE INSERT OR UPDATE OR DELETE ON public.agri_expense_invoices
            FOR EACH ROW EXECUTE FUNCTION public.fn_trg_agri_expense_invoices_guard();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_agri_expense_invoices_guard_trunc' AND tgrelid = 'public.agri_expense_invoices'::regclass) THEN
        CREATE TRIGGER trg_agri_expense_invoices_guard_trunc BEFORE TRUNCATE ON public.agri_expense_invoices
            FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trg_agri_expense_invoices_guard();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_agri_expenses_void_invoice' AND tgrelid = 'public.agri_expenses'::regclass) THEN
        CREATE TRIGGER trg_agri_expenses_void_invoice AFTER UPDATE ON public.agri_expenses
            FOR EACH ROW EXECUTE FUNCTION public.fn_trg_agri_expenses_void_invoice();
    END IF;
END $$;
ALTER TABLE public.agri_expenses ENABLE TRIGGER trg_agri_expenses_void_invoice;

-- 3) Draft (workflow only) -----------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_agri_expense_invoice_draft_create(
    p_tenant_id text, p_user_email text, p_channel text, p_invoice text, p_original_path text, p_sat_status text
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    -- 111 palm expense invoice
    v_ctx   jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_user_email, ARRAY['ADMIN', 'OWNER'], 'Tu rol en la empresa no permite registrar facturas como gasto.');
    v_co    integer;
    v_actor text;
    j       jsonb;
    v_sha   text;
    v_id    uuid;
    v_exp   timestamptz;
BEGIN
    IF NOT (v_ctx ->> 'ok')::boolean THEN RETURN v_ctx -> 'result'; END IF;
    v_co := (v_ctx ->> 'tenant')::integer;
    v_actor := v_ctx ->> 'actor';
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
    VALUES (v_co, v_actor, upper(btrim(p_channel)), j, v_sha, p_original_path, upper(btrim(p_sat_status)))
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
                         FROM (SELECT x FROM jsonb_array_elements(CASE WHEN jsonb_typeof(j -> 'conceptos') = 'array' THEN j -> 'conceptos' ELSE '[]'::jsonb END)
                                        WITH ORDINALITY AS t(x, n) ORDER BY n LIMIT 5) q), '[]'::jsonb)));
END $$;

-- 4) Register: the single implementation (unconfirmed = nothing written) -------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_agri_expense_invoice_register(
    p_tenant_id text, p_user_email text, p_invoice text, p_original_path text, p_sat_status text,
    p_category text DEFAULT NULL, p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL,
    p_plantation text DEFAULT NULL, p_lot text DEFAULT NULL, p_confirmed text DEFAULT 'false'
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    -- 111 palm expense invoice
    v_ctx        jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_user_email, ARRAY['ADMIN', 'OWNER'], 'Tu rol en la empresa no permite registrar facturas como gasto.');
    v_co         integer;
    v_actor      text;
    v_role       text;
    v_confirmed  boolean := lower(btrim(coalesce(p_confirmed, 'false'))) = 'true';
    c_rfc        constant text := '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$';
    j            jsonb;
    v_uuid       text;
    v_emisor     text;
    v_receptor   text;
    v_emisor_nm  text;
    v_serie      text;
    v_folio      text;
    v_sub        bigint;
    v_disc       bigint;
    v_total      bigint;
    v_tr         bigint;
    v_ret        bigint;
    v_issued     timestamp;
    v_stamped    timestamp;
    v_sha        text;
    v_taxes      jsonb;
    v_pay_form   text;
    v_pay_method text;
    v_uso        text;
    v_tipo       text;
    v_concepts   jsonb;
    v_path       text := btrim(coalesce(p_original_path, ''));
    v_sat_in     text := upper(btrim(coalesce(p_sat_status, '')));
    v_sat        text;
    v_is_test    boolean;
    v_cls        jsonb;
    v_crole      text;
    v_creason    text;
    v_date_txt   text := public.fn_agri_chat_txt(p_expense_date);
    v_date       date;
    v_today      date := public.fn_agri_today_cdmx();
    v_issues     jsonb := '[]'::jsonb;
    v_warns      jsonb := '[]'::jsonb;
    v_usual      text;
    v_cat_txt    text := public.fn_agri_chat_txt(p_category);
    v_cat_id     uuid;
    v_cat_code   text;
    v_cat_name   text;
    v_cat_src    text;
    v_mapped     text[];
    v_unmapped   boolean;
    v_scope      jsonb;
    v_pid        uuid;
    v_lid        uuid;
    v_scope_kind text;
    v_scope_lbl  text;
    v_prop       jsonb;
    v_qty        numeric;
    v_qty_txt    text;
    v_unit       text;
    v_desc       text;
    v_supplier   text;
    v_folio_full text;
    v_dup_date   date;
    v_dup_total  bigint;
    v_res        jsonb;
    v_exp_id     uuid;
    v_summary    jsonb;
BEGIN
    IF NOT (v_ctx ->> 'ok')::boolean THEN RETURN v_ctx -> 'result'; END IF;
    v_co := (v_ctx ->> 'tenant')::integer;
    v_actor := v_ctx ->> 'actor';
    v_role := v_ctx ->> 'role';

    -- Shape of the voucher ----------------------------------------------------------------------------------------------------
    BEGIN
        j := p_invoice::jsonb;
        IF jsonb_typeof(j) <> 'object' THEN RAISE EXCEPTION 'not an object'; END IF;
        v_uuid       := upper(j ->> 'uuid');
        v_emisor     := upper(j #>> '{emisor,rfc}');
        v_receptor   := upper(j #>> '{receptor,rfc}');
        v_emisor_nm  := left(regexp_replace(coalesce(j #>> '{emisor,nombre}', ''), '[[:cntrl:]]', '', 'g'), 150);
        v_serie      := left(regexp_replace(coalesce(j ->> 'serie', ''), '[[:cntrl:]]', '', 'g'), 25);
        v_folio      := left(regexp_replace(coalesce(j ->> 'folio', ''), '[[:cntrl:]]', '', 'g'), 40);
        v_sub        := (j ->> 'subtotalCents')::bigint;
        v_disc       := coalesce((j ->> 'descuentoCents')::bigint, 0);
        v_total      := (j ->> 'totalCents')::bigint;
        v_issued     := (j ->> 'fechaEmision')::timestamp;
        v_stamped    := (j ->> 'fechaTimbrado')::timestamp;
        v_sha        := lower(j ->> 'sourceSha256');
        v_pay_form   := left(regexp_replace(coalesce(j ->> 'formaPago', ''), '[[:cntrl:]]', '', 'g'), 10);
        v_pay_method := left(regexp_replace(coalesce(j ->> 'metodoPago', ''), '[[:cntrl:]]', '', 'g'), 10);
        v_uso        := left(regexp_replace(coalesce(j #>> '{receptor,usoCfdi}', ''), '[[:cntrl:]]', '', 'g'), 10);
        v_tipo       := upper(btrim(coalesce(j ->> 'tipoComprobante', 'I')));
        v_concepts   := CASE WHEN jsonb_typeof(j -> 'conceptos') = 'array' THEN j -> 'conceptos' ELSE '[]'::jsonb END;
        v_taxes      := jsonb_build_object('traslados', coalesce(j -> 'traslados', '[]'::jsonb), 'retenciones', coalesce(j -> 'retenciones', '[]'::jsonb));
        SELECT coalesce(sum((x ->> 'importeCents')::bigint), 0) INTO v_tr  FROM jsonb_array_elements(v_taxes -> 'traslados') x;
        SELECT coalesce(sum((x ->> 'importeCents')::bigint), 0) INTO v_ret FROM jsonb_array_elements(v_taxes -> 'retenciones') x;
    EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_INVOICE', 'message', 'La factura no tiene el formato esperado.');
    END;
    IF v_uuid IS NULL OR v_uuid !~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_UUID', 'message', 'La factura no trae un UUID de timbre valido.');
    END IF;
    IF v_emisor IS NULL OR v_emisor !~ c_rfc OR v_receptor IS NULL OR v_receptor !~ c_rfc THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_RFC', 'message', 'El RFC del emisor o del receptor no es valido.');
    END IF;
    IF v_tipo <> 'I' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'UNSUPPORTED_TYPE', 'message', 'Solo se aceptan facturas de ingreso (tipo I).');
    END IF;
    IF coalesce(j ->> 'moneda', '') <> 'MXN' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'UNSUPPORTED_CURRENCY', 'message', 'Solo se aceptan facturas en MXN.');
    END IF;
    IF v_sha IS NULL OR v_sha !~ '^[0-9a-f]{64}$' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_HASH', 'message', 'Falta la huella del archivo original.');
    END IF;
    IF v_sub IS NULL OR v_total IS NULL OR v_issued IS NULL OR v_stamped IS NULL
       OR v_sub < 0 OR v_disc < 0 OR v_disc > v_sub OR v_total <= 0 OR v_total > 999999999999 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_AMOUNT', 'message', 'Los importes de la factura no son validos.');
    END IF;
    IF v_sub - v_disc + v_tr - v_ret <> v_total THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'AMOUNTS_MISMATCH', 'message', 'Los importes de la factura no cuadran con su total.');
    END IF;
    IF v_path !~ '^[1-9][0-9]{0,9}/[0-9]{4}/(0[1-9]|1[0-2])/[0-9a-f]{64}\.xml$' OR left(v_path, length(v_co::text) + 1) <> v_co::text || '/'
       OR v_path !~ ('/' || v_sha || '\.xml$') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'ORIGINAL_PATH_INVALID', 'message', 'La ruta del archivo original no es valida para esta empresa.');
    END IF;

    -- Role gate: only a voucher RECEIVED by the company (109 role EXPENSE) goes on. Fixed messages, nothing written, fail closed. -------------
    BEGIN
        v_cls := public.fn_classify_cfdi_role_detail(v_co, v_emisor, v_receptor);
    EXCEPTION WHEN others THEN
        v_cls := NULL;
    END;
    v_crole := v_cls ->> 'role';
    v_creason := v_cls ->> 'reason';
    IF v_crole = 'EXPENSE' THEN
        NULL;
    ELSIF v_crole = 'SALE' THEN
        RETURN jsonb_build_object('status', 'not_an_expense', 'code', 'ROLE_SALE', 'message', 'Esta factura parece una venta (tu empresa aparece como emisora), no un gasto. No la registré.');
    ELSIF v_crole = 'AMBIGUOUS' THEN
        RETURN jsonb_build_object('status', 'not_an_expense', 'code', 'ROLE_AMBIGUOUS', 'message', 'No puedo decidir si es compra o venta porque tu empresa aparece como emisora y receptora. No la registré.');
    ELSIF v_crole = 'UNKNOWN' AND v_creason = 'NEITHER' THEN
        RETURN jsonb_build_object('status', 'rfc_not_registered', 'code', 'ROLE_UNKNOWN', 'message', 'El RFC receptor de la factura no corresponde a esta empresa. Un administrador de la plataforma debe registrarlo; no registré la factura.');
    ELSE
        RETURN jsonb_build_object('status', 'not_an_expense', 'code', 'ROLE_UNAVAILABLE', 'message', 'No pude clasificar la factura como gasto. No la registré; intenta de nuevo o avisa al administrador.');
    END IF;

    -- SAT --------------------------------------------------------------------------------------------------------------------------
    v_is_test := coalesce((SELECT f.is_test FROM public.company_flags f WHERE f.id_company = v_co), false);
    IF v_sat_in = 'VIGENTE' THEN
        v_sat := 'VIGENTE';
    ELSIF v_is_test AND v_sat_in IN ('NO_ENCONTRADO', 'ERROR', 'SKIPPED_TEST') THEN
        v_sat := 'SKIPPED_TEST';
    ELSE
        RETURN jsonb_build_object('status', 'sat_not_valid', 'message', 'La factura no esta vigente ante el SAT o no se pudo verificar.');
    END IF;

    -- Duplicate (an ACTIVE voucher of this company) -----------------------------------------------------------------------------------
    SELECT e.expense_date, i.total_cents INTO v_dup_date, v_dup_total
      FROM public.agri_expense_invoices i JOIN public.agri_expenses e ON e.id = i.expense_id AND e.id_company = i.id_company
     WHERE i.id_company = v_co AND i.uuid = v_uuid AND i.status = 'ACTIVE';
    IF FOUND THEN
        RETURN jsonb_build_object('status', 'duplicate', 'expense_date', v_dup_date, 'amount', v_dup_total::numeric / 100,
            'message', 'Esta factura ya esta registrada en esta empresa.');
    END IF;

    -- Date ---------------------------------------------------------------------------------------------------------------------------
    IF v_date_txt IS NULL THEN
        v_date := v_issued::date;
    ELSE
        v_date := public.fn_agri_chat_date(v_date_txt);
        IF v_date IS NULL THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_DATE', 'message', 'La fecha del gasto no es valida; usa el formato AAAA-MM-DD.');
        END IF;
    END IF;
    IF v_date > v_today THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'DATE_IN_FUTURE', 'message', 'La fecha del gasto no puede ser futura.');
    END IF;

    -- Category: the user's choice, else the one every concept maps to; never invented -----------------------------------------------------
    IF v_cat_txt IS NOT NULL THEN
        SELECT c.id, c.category_code, c.category_name INTO v_cat_id, v_cat_code, v_cat_name
          FROM public.agri_expense_categories c
         WHERE c.id_company = v_co AND c.is_active
           AND (c.category_code = upper(btrim(v_cat_txt)) OR public.fn_agri_chat_key(c.category_name) = public.fn_agri_chat_key(v_cat_txt))
         ORDER BY (c.category_code = upper(btrim(v_cat_txt))) DESC LIMIT 1;
        v_cat_src := 'USER';
    ELSE
        SELECT array_agg(DISTINCT m.code) FILTER (WHERE m.code IS NOT NULL), coalesce(bool_or(m.code IS NULL), true)
          INTO v_mapped, v_unmapped
          FROM (SELECT public.fn_agri_cfdi_category(c ->> 'claveProdServ') AS code FROM jsonb_array_elements(v_concepts) c) m;
        IF NOT v_unmapped AND coalesce(array_length(v_mapped, 1), 0) = 1 THEN
            SELECT c.id, c.category_code, c.category_name INTO v_cat_id, v_cat_code, v_cat_name
              FROM public.agri_expense_categories c WHERE c.id_company = v_co AND c.is_active AND c.category_code = v_mapped[1];
            v_cat_src := 'VOUCHER';
        END IF;
    END IF;
    IF v_cat_id IS NULL THEN
        v_issues := v_issues || jsonb_build_object('type', CASE WHEN v_cat_txt IS NULL THEN 'missing' ELSE 'invalid' END, 'field', 'category_code',
            'message', CASE WHEN v_cat_txt IS NULL THEN 'No pude deducir la categoría del gasto desde la factura; elige una de las opciones.'
                            ELSE 'Esa categoría no existe en la empresa; elige una de las opciones.' END,
            'options', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', category_code, 'name', category_name) ORDER BY sort_order), '[]'::jsonb)
                          FROM public.agri_expense_categories WHERE id_company = v_co AND is_active));
    END IF;

    -- Plantation / lot: none = general expense of the company ------------------------------------------------------------------------------
    v_scope := public.fn_agri_chat_resolve_scope(v_co, p_plantation, p_lot);
    IF v_scope ->> 'status' <> 'ok' THEN
        v_issues := v_issues || (jsonb_build_object('type', CASE v_scope ->> 'status' WHEN 'ambiguous' THEN 'ambiguous' WHEN 'not_found' THEN 'not_found' ELSE 'invalid' END) || v_scope);
    ELSE
        v_pid := (v_scope ->> 'plantation_id')::uuid;
        v_lid := (v_scope ->> 'lot_id')::uuid;
    END IF;
    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'need_info', 'issues', v_issues);
    END IF;
    v_scope_kind := CASE WHEN v_lid IS NOT NULL THEN 'LOT' WHEN v_pid IS NOT NULL THEN 'PLANTATION' ELSE 'GENERAL' END;
    v_scope_lbl := CASE v_scope_kind
                       WHEN 'LOT' THEN (v_scope ->> 'plantation_name') || ' / ' || (v_scope ->> 'lot_code') || coalesce(' — ' || (v_scope ->> 'lot_name'), '')
                       WHEN 'PLANTATION' THEN v_scope ->> 'plantation_name'
                       ELSE 'General de la empresa (sin plantación ni lote)' END;
    -- A single active plantation is only proposed, never applied.
    IF v_scope_kind = 'GENERAL' AND (SELECT count(*) FROM public.agri_plantations WHERE id_company = v_co AND is_active) = 1 THEN
        SELECT jsonb_build_object('code', p.plantation_code, 'name', p.plantation_name) INTO v_prop
          FROM public.agri_plantations p WHERE p.id_company = v_co AND p.is_active;
    END IF;

    -- Quantity and unit: only a voucher with exactly ONE concept with a mapped unit ---------------------------------------------------------
    IF jsonb_array_length(v_concepts) = 1 THEN
        v_unit := public.fn_agri_cfdi_unit(v_concepts -> 0 ->> 'claveUnidad');
        v_qty_txt := regexp_replace(regexp_replace(btrim(coalesce(v_concepts -> 0 ->> 'cantidad', '')), '(\.[0-9]*[1-9])0+$', '\1'), '\.0*$', '');
        IF v_unit IS NOT NULL AND v_qty_txt ~ '^[0-9]{1,9}(\.[0-9]{1,3})?$'
           AND EXISTS (SELECT 1 FROM public.agri_unit_catalog u WHERE u.unit_code = v_unit AND u.is_active) THEN
            v_qty := v_qty_txt::numeric;
            IF v_qty <= 0 THEN v_qty := NULL; END IF;
        END IF;
        IF v_qty IS NULL THEN v_unit := NULL; END IF;
    END IF;

    v_supplier := nullif(btrim(v_emisor_nm), '');
    v_folio_full := nullif(left(v_serie || v_folio, 60), '');
    v_desc := coalesce(left(public.fn_agri_chat_txt(p_description), 500),
                       left(btrim(concat_ws(' ', 'CFDI', nullif(v_serie || v_folio, ''), v_emisor_nm)), 300));

    -- Warnings: informational, never block ---------------------------------------------------------------------------------------------------
    IF v_pay_form = '01' THEN
        v_warns := v_warns || to_jsonb('La factura indica pago en efectivo.'::text);
    END IF;
    SELECT i.uso_cfdi INTO v_usual FROM public.agri_expense_invoices i
     WHERE i.id_company = v_co AND i.status = 'ACTIVE' AND i.uso_cfdi IS NOT NULL
     GROUP BY i.uso_cfdi ORDER BY count(*) DESC, i.uso_cfdi LIMIT 1;
    IF v_usual IS NOT NULL AND nullif(v_uso, '') IS NOT NULL AND v_uso <> v_usual THEN
        v_warns := v_warns || to_jsonb('El uso de CFDI de esta factura es distinto del que suele usar la empresa.'::text);
    END IF;
    IF v_date < v_today - 365 THEN
        v_warns := v_warns || to_jsonb('La fecha del gasto tiene más de 365 días.'::text);
    END IF;

    v_summary := jsonb_build_object('emisor_name', v_supplier, 'emisor_rfc', v_emisor, 'receptor_rfc', v_receptor, 'cfdi_folio', coalesce(v_serie || v_folio, ''),
        'expense_date', v_date, 'amount', v_total::numeric / 100, 'subtotal', v_sub::numeric / 100, 'discount', v_disc::numeric / 100,
        'taxes_transferred', v_tr::numeric / 100, 'taxes_withheld', v_ret::numeric / 100, 'sat_status', v_sat,
        'category_code', v_cat_code, 'category_name', v_cat_name, 'category_source', v_cat_src,
        'description', v_desc, 'supplier_name', v_supplier, 'quantity', v_qty, 'unit_code', v_unit,
        'scope', v_scope_kind, 'scope_label', v_scope_lbl, 'concepts', jsonb_array_length(v_concepts));

    IF NOT v_confirmed THEN
        RETURN jsonb_build_object('status', 'preview', 'summary', v_summary, 'warnings', v_warns)
            || CASE WHEN v_prop IS NOT NULL THEN jsonb_build_object('plantation_proposal', v_prop,
                   'scope_question', 'La factura no indica plantación ni lote. Se registrará como gasto general de la empresa; si prefieres asignarla a la plantación ' || (v_prop ->> 'name') || ', indícalo.')
               WHEN v_scope_kind = 'GENERAL' THEN jsonb_build_object('scope_question', 'La factura no indica plantación ni lote. Se registrará como gasto general de la empresa; si prefieres asignarla a una plantación o lote, indícalo.')
               ELSE '{}'::jsonb END;
    END IF;

    -- Confirmed: serialise per (company, UUID), re-check, then write through sp_agri_record_expense -----------------------------------------------------
    PERFORM pg_advisory_xact_lock(hashtextextended(v_co::text || ':agri-expense-invoice:' || v_uuid, 0));
    SELECT e.expense_date, i.total_cents INTO v_dup_date, v_dup_total
      FROM public.agri_expense_invoices i JOIN public.agri_expenses e ON e.id = i.expense_id AND e.id_company = i.id_company
     WHERE i.id_company = v_co AND i.uuid = v_uuid AND i.status = 'ACTIVE';
    IF FOUND THEN
        RETURN jsonb_build_object('status', 'duplicate', 'expense_date', v_dup_date, 'amount', v_dup_total::numeric / 100,
            'message', 'Esta factura ya esta registrada en esta empresa.');
    END IF;

    BEGIN
        v_res := public.sp_agri_record_expense(v_co, v_pid, v_lid, v_cat_id, v_date, v_total::numeric / 100, v_qty, v_unit,
                                               left(v_supplier, 150), v_desc, true, v_folio_full, v_actor);
        v_exp_id := (v_res ->> 'expense_id')::uuid;
        INSERT INTO public.agri_expense_invoices (id_company, uuid, emisor_rfc, emisor_name, receptor_rfc, serie, folio, issued_at, stamped_at, currency,
                                                  subtotal_cents, discount_cents, total_cents, taxes, payment_form, payment_method, uso_cfdi,
                                                  source_sha256, original_path, sat_status, expense_id, registered_by_email)
        VALUES (v_co, v_uuid, v_emisor, nullif(v_emisor_nm, ''), v_receptor, nullif(v_serie, ''), nullif(v_folio, ''), v_issued, v_stamped, 'MXN',
                v_sub, v_disc, v_total, v_taxes, nullif(v_pay_form, ''), nullif(v_pay_method, ''), nullif(v_uso, ''),
                v_sha, v_path, v_sat, v_exp_id, v_actor);
    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object('status', 'duplicate', 'message', 'Esta factura ya esta registrada en esta empresa.');
        WHEN OTHERS THEN
            IF SQLSTATE LIKE 'P00%' THEN
                RETURN jsonb_build_object('status', 'invalid', 'code', SQLSTATE, 'message', SQLERRM);
            END IF;
            RAISE;
    END;

    RETURN jsonb_build_object('status', 'recorded', 'message', 'Gasto registrado', 'expense_id', v_exp_id, 'cfdi_folio', coalesce(v_serie || v_folio, ''),
        'expense_date', v_date, 'amount', v_total::numeric / 100, 'category_code', v_cat_code, 'scope', v_scope_kind, 'scope_label', v_scope_lbl,
        'sat_status', v_sat, 'warnings', v_warns);
END $$;

-- 5) The two agent tools --------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_agri_expense_invoice_preview(
    p_tenant_id text, p_user_email text, p_draft_id text, p_category text,
    p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL, p_plantation text DEFAULT NULL, p_lot text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    -- 111 palm expense invoice
    v_ctx jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_user_email, ARRAY['ADMIN', 'OWNER'], 'Tu rol en la empresa no permite registrar facturas como gasto.');
    v_co  integer;
    d     public.expense_invoice_drafts;
    r     jsonb;
BEGIN
    IF NOT (v_ctx ->> 'ok')::boolean THEN RETURN v_ctx -> 'result'; END IF;
    v_co := (v_ctx ->> 'tenant')::integer;
    BEGIN
        SELECT * INTO d FROM public.expense_invoice_drafts
         WHERE id = p_draft_id::uuid AND id_company = v_co AND user_email = (v_ctx ->> 'actor') FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontre ese borrador de factura.');
    END;
    IF NOT FOUND THEN RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontre ese borrador de factura.'); END IF;
    IF d.consumed_at IS NOT NULL THEN RETURN jsonb_build_object('status', 'already_registered', 'message', 'Esta factura ya se proceso.'); END IF;
    IF d.expires_at < now() THEN RETURN jsonb_build_object('status', 'draft_expired', 'message', 'El borrador expiro; vuelve a enviar el archivo.'); END IF;
    r := public.sp_agri_expense_invoice_register(p_tenant_id, p_user_email, d.invoice::text, d.original_path, d.sat_status,
                                                 p_category, p_description, p_expense_date, p_plantation, p_lot, 'false');
    IF r ->> 'status' = 'preview' THEN
        UPDATE public.expense_invoice_drafts
           SET previewed_hash = public.fn_agri_expense_invoice_params_hash(p_category, p_description, p_expense_date, p_plantation, p_lot), previewed_at = now()
         WHERE id = d.id;
    END IF;
    RETURN r || jsonb_build_object('draft_id', d.id);
END $$;

CREATE OR REPLACE FUNCTION public.sp_agri_expense_invoice_confirm(
    p_tenant_id text, p_user_email text, p_draft_id text, p_category text,
    p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL, p_plantation text DEFAULT NULL, p_lot text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    -- 111 palm expense invoice
    v_ctx jsonb := public.fn_agri_chat_ctx(p_tenant_id, p_user_email, ARRAY['ADMIN', 'OWNER'], 'Tu rol en la empresa no permite registrar facturas como gasto.');
    v_co  integer;
    d     public.expense_invoice_drafts;
    r     jsonb;
BEGIN
    IF NOT (v_ctx ->> 'ok')::boolean THEN RETURN v_ctx -> 'result'; END IF;
    v_co := (v_ctx ->> 'tenant')::integer;
    BEGIN
        SELECT * INTO d FROM public.expense_invoice_drafts
         WHERE id = p_draft_id::uuid AND id_company = v_co AND user_email = (v_ctx ->> 'actor') FOR UPDATE;
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontre ese borrador de factura.');
    END;
    IF NOT FOUND THEN RETURN jsonb_build_object('status', 'not_found', 'message', 'No encontre ese borrador de factura.'); END IF;
    IF d.consumed_at IS NOT NULL THEN RETURN jsonb_build_object('status', 'already_registered', 'message', 'Esta factura ya se proceso.'); END IF;
    IF d.expires_at < now() THEN RETURN jsonb_build_object('status', 'draft_expired', 'message', 'El borrador expiro; vuelve a enviar el archivo.'); END IF;
    IF d.previewed_at IS NULL OR d.previewed_at < now() - interval '15 minutes'
       OR d.previewed_hash IS DISTINCT FROM public.fn_agri_expense_invoice_params_hash(p_category, p_description, p_expense_date, p_plantation, p_lot) THEN
        RETURN jsonb_build_object('status', 'preview_required',
            'message', 'Antes de registrar, muestra la vista previa con esta misma categoria, fecha, descripcion, plantacion y lote y espera el Si del usuario.');
    END IF;
    r := public.sp_agri_expense_invoice_register(p_tenant_id, p_user_email, d.invoice::text, d.original_path, d.sat_status,
                                                 p_category, p_description, p_expense_date, p_plantation, p_lot, 'true');
    IF r ->> 'status' IN ('recorded', 'duplicate') THEN
        UPDATE public.expense_invoice_drafts SET consumed_at = now() WHERE id = d.id;
    END IF;
    RETURN r || jsonb_build_object('draft_id', d.id);
END $$;

COMMENT ON FUNCTION public.sp_agri_expense_invoice_register(text, text, text, text, text, text, text, text, text, text, text) IS
  '111: registers (confirmed) or previews a CFDI voucher RECEIVED by a palm company as an expense (ADMIN/OWNER). Role gate by the 109 classifier, SAT rules, scope and category resolution, writes through sp_agri_record_expense. Answers statuses; unconfirmed writes nothing.';
COMMENT ON FUNCTION public.sp_agri_expense_invoice_preview(text, text, text, text, text, text, text, text) IS
  '111: agent tool 1 (palm). Preview of a draft voucher; writes only the preview mark.';
COMMENT ON FUNCTION public.sp_agri_expense_invoice_confirm(text, text, text, text, text, text, text, text) IS
  '111: agent tool 2 (palm). Registers after a matching preview (same category, description, date, plantation and lot) in the last 15 minutes.';
COMMENT ON FUNCTION public.sp_agri_expense_invoice_draft_create(text, text, text, text, text, text) IS
  '111: workflow only (palm). Stores the parsed voucher as a draft; the agent sees only the draft id.';

-- 6) Self-check ---------------------------------------------------------------------------------------------------------------------

DO $$
BEGIN
    IF to_regclass('public.agri_expense_invoices') IS NULL
       OR to_regprocedure('public.sp_agri_expense_invoice_draft_create(text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_agri_expense_invoice_preview(text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_agri_expense_invoice_confirm(text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_agri_expense_invoice_register(text,text,text,text,text,text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION '111: an object is missing after the change';
    END IF;
    IF (SELECT count(*) FROM public.crud_models WHERE table_name ~ 'agri_expense_invoice|expense_invoice' OR model_name ~ 'agri_expense_invoice') <> 0 THEN
        RAISE EXCEPTION '111: an object is registered in crud_models';
    END IF;
    RAISE NOTICE '111: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 111 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 111 rolled back ***'
\endif
\endif
