-- 104_agri_sale_invoices.sql
-- Palm sales registered from a CFDI 4.0 voucher: platform-managed company flags and issuer RFC list, an append-only sale
-- register with a void transition, an audit trail, one register procedure, one void procedure and the dashboard reads.
-- Database layer only: no crud_models row, no n8n change, no frontend, no parser change (those are later pull requests).
-- REQUIRES 080 and 081 (fn_agri_actor_role, fn_agri_today_cdmx, fn_agri_setting, fn_company_business_domain, agri_plantations,
-- agri_lots). Aborts if missing. Nothing existing is altered, replaced or dropped; 091/092/093 objects, fn_repro_ctx and
-- fn_reject_palm_company are not touched.
--
-- Tables
--   company_flags         platform-managed flags per company (is_test). Changed only by a platform seed (session setting
--                         app.platform_seed = 'on'). Not deletable. is_test cannot change once the company has issuer RFCs or sales.
--   company_issuer_rfcs   RFCs a palm company may issue sales vouchers with. Platform-managed like company_flags, never filled from a
--                         voucher. is_test is copied from company_flags on insert and is immutable.
--   agri_sale_invoices    one row per sale voucher. Append-only: the only UPDATE allowed is the ACTIVE -> VOID transition made by
--                         sp_agri_void_sale. At most one ACTIVE row per (id_company, uuid) and one ACTIVE row per uuid among non-test companies; a
--                         voided voucher can be loaded again by the same company (a new row; the VOID row stays).
--   agri_sale_audit       append-only trail of REGISTER / VOID / REJECT events. Stores codes only (never a voucher UUID).
-- Procedures
--   sp_agri_register_sale  direct load of a parsed voucher (no draft, no preview). ADMIN only, checked inside against the membership
--                          of the already-validated tenant. Amounts come ONLY from the parsed voucher: there is no amount parameter.
--   sp_agri_void_sale      ADMIN only, any time, reason 5..300 characters, audited, idempotent.
--   sp_agri_sales_balance  totals for the dashboard (ADMIN only), same call contract as sp_agri_expense_balance plus the previous period.
-- Views (to be registered in crud_models by a later pull request, ADMIN only): vw_agri_sale_list, vw_agri_sale_summary.
--
-- Parsed voucher contract (jsonb produced by cfdi-service; the parser extension is a separate pull request). Keys:
--   tipoComprobante, uuid, serie, folio, fechaEmision, fechaTimbrado, emisor{rfc,nombre}, receptor{rfc,nombre}, moneda,
--   subtotalCents, descuentoCents, totalCents (integer cents), traslados[], retenciones[] ({impuesto,tipoFactor,tasaOCuota,baseCents,
--   importeCents}), formaPago, metodoPago, sourceSha256 (optional, must equal p_source_sha256 when present) and
--   conceptos[] with exactly one {claveProdServ, claveUnidad, cantidad, valorUnitario, descripcion, importeCents}; cantidad and
--   valorUnitario are decimal strings or numbers with up to 6 decimals; importeCents is the concept amount in integer cents. Totals are
--   taken from the voucher as issued; the only arithmetic is: (1) concept amount versus quantity x unit price, within one cent for issuer
--   rounding; (2) subtotal = concept amount (single concept); (3) subtotal - discount + transferred - withheld = total, exact to the
--   cent. No tax is computed.
--
-- Answers (jsonb 'status'): OK | ALREADY_REGISTERED | FORBIDDEN | NOT_PALM | ISSUER_RFC_NOT_CONFIGURED | ISSUER_RFC_MISMATCH |
--   INVALID_VOUCHER (+ 'reason') | DUPLICATE. Expected failures are answers, never exceptions.
-- Errors raised by the guards: P0110 sale records are append-only / not valid, P0111 platform-managed table. Reads reuse P0080,
--   P0084, P0092, P0093 as sp_agri_expense_balance does.
-- Rollback: 104_rollback.sql (functions answer 'disabled'; tables and rows stay). State: 104_state_check.sql. Tests: 104_tests.sql.
-- Usage:   psql -v ON_ERROR_STOP=1 -f 104_agri_sale_invoices.sql (dry run) | ... -v apply=true -f ... (commit)

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
       OR to_regprocedure('public.fn_agri_today_cdmx()') IS NULL
       OR to_regprocedure('public.fn_agri_setting(text)') IS NULL
       OR to_regprocedure('public.fn_company_business_domain(integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migrations 080 and 081 are not applied here (agri helper functions missing).';
    END IF;
    IF to_regclass('public.companys') IS NULL OR to_regclass('public.agri_plantations') IS NULL OR to_regclass('public.agri_lots') IS NULL THEN
        RAISE EXCEPTION 'ABORT: companys / agri_plantations / agri_lots are missing.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'agri_plantations_id_company_key' AND conrelid = 'public.agri_plantations'::regclass)
       OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'agri_lots_id_plantation_company_key' AND conrelid = 'public.agri_lots'::regclass) THEN
        RAISE EXCEPTION 'ABORT: the composite keys of agri_plantations / agri_lots (080, 081) are missing.';
    END IF;
END $$;

-- 1) Platform-managed tables ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.company_flags (
    id_company  integer     PRIMARY KEY REFERENCES public.companys (id_company),
    is_test     boolean     NOT NULL DEFAULT false,
    created_by  text        NOT NULL DEFAULT current_user CONSTRAINT ck_company_flags_by CHECK (btrim(created_by) <> ''),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.company_flags IS
  '104: platform-managed flags per company (is_test). Changed only by a platform seed (app.platform_seed = on); not deletable; is_test is fixed once the company has issuer RFCs or sales. Not in crud_models.';

CREATE TABLE IF NOT EXISTS public.company_issuer_rfcs (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company  integer     NOT NULL REFERENCES public.companys (id_company),
    rfc         text        NOT NULL CONSTRAINT ck_company_issuer_rfcs_rfc CHECK (rfc ~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    is_active   boolean     NOT NULL DEFAULT true,
    is_test     boolean     NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now(),
    created_by  text        NOT NULL DEFAULT current_user CONSTRAINT ck_company_issuer_rfcs_by CHECK (btrim(created_by) <> ''),
    CONSTRAINT uq_company_issuer_rfcs_company_rfc UNIQUE (id_company, rfc)
);
-- A real (non-test) issuer RFC belongs to one active company at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_company_issuer_rfcs_active_real
    ON public.company_issuer_rfcs (rfc) WHERE is_active AND NOT is_test;
COMMENT ON TABLE public.company_issuer_rfcs IS
  '104: RFCs a palm company may issue sales vouchers with. Platform-managed (app.platform_seed = on), never filled from a voucher, not deletable, is_test copied from company_flags and immutable. Not in crud_models.';

-- 2) Sale register and audit ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agri_sale_invoices (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company          integer     NOT NULL REFERENCES public.companys (id_company),
    uuid                text        NOT NULL CONSTRAINT ck_agri_sale_invoices_uuid CHECK (uuid ~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$'),
    emisor_rfc          text        NOT NULL CONSTRAINT ck_agri_sale_invoices_emisor CHECK (emisor_rfc ~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    emisor_name         text,
    receptor_rfc        text        NOT NULL CONSTRAINT ck_agri_sale_invoices_receptor CHECK (receptor_rfc ~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    buyer_name          text        NOT NULL CONSTRAINT ck_agri_sale_invoices_buyer CHECK (btrim(buyer_name) <> '' AND length(buyer_name) <= 150),
    serie               text,
    folio               text,
    issued_at           timestamp   NOT NULL,   -- CFDI Fecha: local issuer time (America/Mexico_City), no time zone
    stamped_at          timestamp   NOT NULL,
    currency            text        NOT NULL DEFAULT 'MXN' CONSTRAINT ck_agri_sale_invoices_currency CHECK (currency = 'MXN'),
    subtotal_cents      bigint      NOT NULL CONSTRAINT ck_agri_sale_invoices_subtotal CHECK (subtotal_cents >= 0),
    discount_cents      bigint      NOT NULL DEFAULT 0 CONSTRAINT ck_agri_sale_invoices_discount CHECK (discount_cents >= 0),
    total_cents         bigint      NOT NULL CONSTRAINT ck_agri_sale_invoices_total CHECK (total_cents BETWEEN 1 AND 999999999999),
    taxes               jsonb       NOT NULL CONSTRAINT ck_agri_sale_invoices_taxes CHECK (jsonb_typeof(taxes) = 'object'),
    payment_form        text        NOT NULL CONSTRAINT ck_agri_sale_invoices_form CHECK (payment_form ~ '^[0-9]{2}$'),
    payment_method      text        NOT NULL CONSTRAINT ck_agri_sale_invoices_method CHECK (payment_method = 'PUE'),
    product_key         text        NOT NULL CONSTRAINT ck_agri_sale_invoices_product CHECK (product_key ~ '^[0-9]{8}$'),
    unit_code           text        NOT NULL CONSTRAINT ck_agri_sale_invoices_unit CHECK (unit_code = 'KGM'),
    quantity            numeric(18, 6) NOT NULL CONSTRAINT ck_agri_sale_invoices_qty CHECK (quantity > 0),
    unit_price          numeric(18, 6) NOT NULL CONSTRAINT ck_agri_sale_invoices_price CHECK (unit_price > 0),
    ticket_ref          text        CONSTRAINT ck_agri_sale_invoices_ticket CHECK (ticket_ref IS NULL OR ticket_ref ~ '^[A-Za-z0-9-]{1,30}$'),
    ticket_warning      boolean     NOT NULL DEFAULT false,
    plantation_id       uuid,
    lot_id              uuid,
    source_sha256       text        NOT NULL CONSTRAINT ck_agri_sale_invoices_sha CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    original_path       text        NOT NULL CONSTRAINT ck_agri_sale_invoices_path CHECK (original_path ~ '^[A-Za-z0-9_./-]+$' AND original_path !~ '\.\.' AND original_path !~ '^/' AND length(original_path) <= 300),
    sat_status          text        NOT NULL CONSTRAINT ck_agri_sale_invoices_sat CHECK (sat_status IN ('VIGENTE', 'SKIPPED_TEST')),
    is_test             boolean     NOT NULL DEFAULT false,
    status              text        NOT NULL DEFAULT 'ACTIVE' CONSTRAINT ck_agri_sale_invoices_status CHECK (status IN ('ACTIVE', 'VOID')),
    void_reason         text,
    voided_by_email     text,
    voided_at           timestamptz,
    registered_by_email text        NOT NULL CONSTRAINT ck_agri_sale_invoices_by CHECK (registered_by_email = lower(btrim(registered_by_email)) AND registered_by_email <> ''),
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_agri_sale_invoices_id_company UNIQUE (id, id_company),
    CONSTRAINT fk_agri_sale_invoices_plantation FOREIGN KEY (plantation_id, id_company)
        REFERENCES public.agri_plantations (id, id_company),
    CONSTRAINT fk_agri_sale_invoices_lot FOREIGN KEY (lot_id, plantation_id, id_company)
        REFERENCES public.agri_lots (id, plantation_id, id_company),
    -- With plantation_id NULL the composite lot key would not be checked (MATCH SIMPLE).
    CONSTRAINT ck_agri_sale_invoices_lot_needs_plantation CHECK (lot_id IS NULL OR plantation_id IS NOT NULL),
    CONSTRAINT ck_agri_sale_invoices_ticket_warning CHECK (ticket_ref IS NOT NULL OR ticket_warning),
    -- Skipping the SAT answer is a test-company privilege only.
    CONSTRAINT ck_agri_sale_invoices_sat_test CHECK (sat_status = 'VIGENTE' OR is_test),
    CONSTRAINT ck_agri_sale_invoices_void CHECK (
        (status = 'ACTIVE' AND void_reason IS NULL AND voided_by_email IS NULL AND voided_at IS NULL)
        OR (status = 'VOID' AND coalesce(length(btrim(void_reason)), 0) BETWEEN 5 AND 300 AND btrim(coalesce(voided_by_email, '')) <> '' AND voided_at IS NOT NULL))
);
-- One ACTIVE row per voucher in a company (a voided voucher can be loaded again), and one ACTIVE row per real (non-test) voucher UUID across
-- companies; test companies may reuse any UUID.
CREATE UNIQUE INDEX IF NOT EXISTS uq_agri_sale_invoices_company_uuid_active ON public.agri_sale_invoices (id_company, uuid) WHERE status = 'ACTIVE';
CREATE UNIQUE INDEX IF NOT EXISTS uq_agri_sale_invoices_uuid_real ON public.agri_sale_invoices (uuid) WHERE NOT is_test AND status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_agri_sale_invoices_company_date ON public.agri_sale_invoices (id_company, (issued_at::date)) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_agri_sale_invoices_company_ticket ON public.agri_sale_invoices (id_company, upper(ticket_ref)) WHERE ticket_ref IS NOT NULL AND status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_agri_sale_invoices_company_created ON public.agri_sale_invoices (id_company, created_at DESC);
COMMENT ON TABLE public.agri_sale_invoices IS
  '104: palm sale vouchers (CFDI). Written only by sp_agri_register_sale; the only UPDATE is the ACTIVE -> VOID transition of sp_agri_void_sale; never deleted (P0110). Amounts come from the voucher. Not in crud_models.';

CREATE TABLE IF NOT EXISTS public.agri_sale_audit (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company  integer     NOT NULL REFERENCES public.companys (id_company),
    sale_id     uuid,
    event       text        NOT NULL CONSTRAINT ck_agri_sale_audit_event CHECK (event IN ('REGISTER', 'VOID', 'REJECT')),
    code        text        NOT NULL CONSTRAINT ck_agri_sale_audit_code CHECK (code ~ '^[A-Z0-9_]{1,60}$'),
    actor_email text        NOT NULL CONSTRAINT ck_agri_sale_audit_actor CHECK (actor_email = lower(btrim(actor_email)) AND actor_email <> ''),
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_agri_sale_audit_sale FOREIGN KEY (sale_id, id_company)
        REFERENCES public.agri_sale_invoices (id, id_company)
);
CREATE INDEX IF NOT EXISTS idx_agri_sale_audit_company ON public.agri_sale_audit (id_company, created_at DESC);
COMMENT ON TABLE public.agri_sale_audit IS
  '104: append-only trail of sale events (REGISTER, VOID, REJECT). Stores event codes and the actor only: no voucher UUID, no amounts. Not in crud_models.';

-- 3) Guards ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_trg_company_flags_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
        RAISE EXCEPTION 'company_flags rows are not deletable.' USING ERRCODE = 'P0111';
    END IF;
    IF public.fn_agri_setting('app.platform_seed') IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'company_flags is platform-managed: it is changed only by a platform seed.' USING ERRCODE = 'P0111';
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.id_company IS DISTINCT FROM OLD.id_company THEN
        RAISE EXCEPTION 'company_flags: the company cannot change.' USING ERRCODE = 'P0111';
    END IF;
    IF (TG_OP = 'INSERT' AND NEW.is_test) OR (TG_OP = 'UPDATE' AND NEW.is_test IS DISTINCT FROM OLD.is_test) THEN
        IF EXISTS (SELECT 1 FROM public.company_issuer_rfcs WHERE id_company = NEW.id_company)
           OR EXISTS (SELECT 1 FROM public.agri_sale_invoices WHERE id_company = NEW.id_company) THEN
            RAISE EXCEPTION 'company_flags: is_test is fixed once the company has issuer RFCs or sales.' USING ERRCODE = 'P0111';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' THEN NEW.updated_at := now(); END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.fn_trg_company_issuer_rfcs_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
        RAISE EXCEPTION 'company_issuer_rfcs rows are not deletable: deactivate the RFC instead.' USING ERRCODE = 'P0111';
    END IF;
    IF public.fn_agri_setting('app.platform_seed') IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'company_issuer_rfcs is platform-managed: it is changed only by a platform seed.' USING ERRCODE = 'P0111';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF public.fn_company_business_domain(NEW.id_company) IS DISTINCT FROM 'PALM' THEN
            RAISE EXCEPTION 'company_issuer_rfcs: only palm companies have issuer RFCs.' USING ERRCODE = 'P0111';
        END IF;
        NEW.is_test := coalesce((SELECT f.is_test FROM public.company_flags f WHERE f.id_company = NEW.id_company), false);
        RETURN NEW;
    END IF;
    IF (to_jsonb(NEW) - 'is_active') IS DISTINCT FROM (to_jsonb(OLD) - 'is_active') THEN
        RAISE EXCEPTION 'company_issuer_rfcs: only is_active can change.' USING ERRCODE = 'P0111';
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.fn_trg_agri_sale_invoices_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_tr  bigint;
    v_ret bigint;
BEGIN
    IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
        RAISE EXCEPTION 'Sale records are not deleted: void them with a reason.' USING ERRCODE = 'P0110';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF public.fn_agri_setting('app.agri_sale_void') IS DISTINCT FROM 'on'
           OR OLD.status <> 'ACTIVE' OR NEW.status <> 'VOID'
           OR (to_jsonb(NEW) - ARRAY['status', 'void_reason', 'voided_by_email', 'voided_at'])
              IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status', 'void_reason', 'voided_by_email', 'voided_at']) THEN
            RAISE EXCEPTION 'A registered sale is not modified: it can only be voided.' USING ERRCODE = 'P0110';
        END IF;
        RETURN NEW;
    END IF;

    -- INSERT: the flag is derived from the platform-managed table, whatever the caller sent.
    NEW.is_test := coalesce((SELECT f.is_test FROM public.company_flags f WHERE f.id_company = NEW.id_company), false);
    IF NEW.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'A sale cannot be registered already voided.' USING ERRCODE = 'P0110';
    END IF;
    IF public.fn_company_business_domain(NEW.id_company) IS DISTINCT FROM 'PALM' THEN
        RAISE EXCEPTION 'Sales are registered only for palm companies.' USING ERRCODE = 'P0093';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.company_issuer_rfcs r
                    WHERE r.id_company = NEW.id_company AND r.rfc = NEW.emisor_rfc AND r.is_active) THEN
        RAISE EXCEPTION 'The issuer RFC is not an active issuer RFC of the company.' USING ERRCODE = 'P0110';
    END IF;
    IF NEW.receptor_rfc = NEW.emisor_rfc THEN
        RAISE EXCEPTION 'The buyer cannot be the issuer.' USING ERRCODE = 'P0110';
    END IF;
    SELECT coalesce(sum((x ->> 'importeCents')::bigint), 0) INTO v_tr  FROM jsonb_array_elements(coalesce(NEW.taxes -> 'traslados', '[]'::jsonb)) x;
    SELECT coalesce(sum((x ->> 'importeCents')::bigint), 0) INTO v_ret FROM jsonb_array_elements(coalesce(NEW.taxes -> 'retenciones', '[]'::jsonb)) x;
    IF NEW.subtotal_cents - NEW.discount_cents + v_tr - v_ret <> NEW.total_cents THEN
        RAISE EXCEPTION 'The voucher amounts do not reconcile.' USING ERRCODE = 'P0110';
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.fn_trg_agri_sale_audit_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'agri_sale_audit is append-only.' USING ERRCODE = 'P0110';
END $$;

DO $$
DECLARE
    t record;
BEGIN
    FOR t IN
        SELECT * FROM (VALUES
            ('trg_company_flags_guard_row',        'company_flags',        'BEFORE INSERT OR UPDATE OR DELETE', 'ROW',       'fn_trg_company_flags_guard'),
            ('trg_company_flags_guard_trunc',      'company_flags',        'BEFORE TRUNCATE',                  'STATEMENT', 'fn_trg_company_flags_guard'),
            ('trg_company_issuer_rfcs_guard_row',  'company_issuer_rfcs',  'BEFORE INSERT OR UPDATE OR DELETE', 'ROW',       'fn_trg_company_issuer_rfcs_guard'),
            ('trg_company_issuer_rfcs_guard_trunc','company_issuer_rfcs',  'BEFORE TRUNCATE',                  'STATEMENT', 'fn_trg_company_issuer_rfcs_guard'),
            ('trg_agri_sale_invoices_guard_row',   'agri_sale_invoices',   'BEFORE INSERT OR UPDATE OR DELETE', 'ROW',       'fn_trg_agri_sale_invoices_guard'),
            ('trg_agri_sale_invoices_guard_trunc', 'agri_sale_invoices',   'BEFORE TRUNCATE',                  'STATEMENT', 'fn_trg_agri_sale_invoices_guard'),
            ('trg_agri_sale_audit_guard_row',      'agri_sale_audit',      'BEFORE UPDATE OR DELETE',          'ROW',       'fn_trg_agri_sale_audit_guard'),
            ('trg_agri_sale_audit_guard_trunc',    'agri_sale_audit',      'BEFORE TRUNCATE',                  'STATEMENT', 'fn_trg_agri_sale_audit_guard')
        ) AS v(tgname, tbl, timing, level, fn)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = t.tgname AND tgrelid = ('public.' || t.tbl)::regclass) THEN
            EXECUTE format('CREATE TRIGGER %I %s ON public.%I FOR EACH %s EXECUTE FUNCTION public.%I()',
                           t.tgname, t.timing, t.tbl, t.level, t.fn);
        END IF;
    END LOOP;
END $$;

-- 4) Procedures -----------------------------------------------------------------------------------------

-- Internal: writes one audit row (code only) when the actor is a member of an existing company; never raises for expected cases.
CREATE OR REPLACE FUNCTION public.fn_agri_sale_audit(p_tenant_id integer, p_sale_id uuid, p_event text, p_code text, p_actor text)
RETURNS void LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    INSERT INTO public.agri_sale_audit (id_company, sale_id, event, code, actor_email)
    VALUES (p_tenant_id, p_sale_id, p_event, p_code, lower(btrim(p_actor)));
END $$;

-- Internal: audits and builds a rejection answer. The answer carries no information about other companies.
CREATE OR REPLACE FUNCTION public.fn_agri_sale_reject(p_tenant_id integer, p_actor text, p_status text, p_code text, p_message text, p_extra jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    PERFORM public.fn_agri_sale_audit(p_tenant_id, NULL, 'REJECT', p_code, p_actor);
    RETURN jsonb_build_object('status', p_status, 'code', p_code, 'message', p_message) || coalesce(p_extra, '{}'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.sp_agri_register_sale(
    p_tenant_id integer, p_actor_email text, p_parsed jsonb, p_sat_status text, p_original_path text, p_source_sha256 text
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    -- Oldest accepted voucher date, in days before today (America/Mexico_City). The owner may change this value.
    c_max_age_days constant integer := 365;
    c_rfc          constant text := '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$';
    c_uuid         constant text := '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$';
    c_qty          constant text := '^[0-9]{1,12}(\.[0-9]{1,6})?$';
    c_ticket       constant text := '\(\s*ticket\s*#?\s*([A-Za-z0-9-]{1,30})\s*\)';
    v_actor        text := lower(btrim(coalesce(p_actor_email, '')));
    v_role         text;
    v_active       boolean;
    v_is_test      boolean;
    v_bad          boolean := false;
    v_reason       text;
    j              jsonb := p_parsed;
    c              jsonb;
    v_nconc        integer;
    v_tipo         text;
    v_moneda       text;
    v_metodo       text;
    v_forma        text;
    v_uuid         text;
    v_emisor       text;
    v_receptor     text;
    v_emisor_nm    text;
    v_buyer        text;
    v_serie        text;
    v_folio        text;
    v_sub          bigint;
    v_disc         bigint;
    v_total        bigint;
    v_tr           bigint;
    v_ret          bigint;
    v_issued       timestamp;
    v_stamped      timestamp;
    v_taxes        jsonb;
    v_product      text;
    v_unit         text;
    v_qty_txt      text;
    v_price_txt    text;
    v_conc_txt     text;
    v_qty          numeric;
    v_price        numeric;
    v_desc         text;
    v_hash_in      text;
    v_sha          text := lower(btrim(coalesce(p_source_sha256, '')));
    v_path         text := btrim(coalesce(p_original_path, ''));
    v_sat_in       text := upper(btrim(coalesce(p_sat_status, '')));
    v_sat          text;
    v_today        date := public.fn_agri_today_cdmx();
    v_tickets      text[];
    v_ticket       text;
    v_ticket_warn  boolean := false;
    v_warnings     jsonb := '[]'::jsonb;
    v_ex           record;
    v_id           uuid;
BEGIN
    -- Tenant, membership, role and domain: fail-closed, in this order. The role is read from the membership, never from the caller.
    IF p_tenant_id IS NULL THEN
        RETURN jsonb_build_object('status', 'FORBIDDEN', 'code', 'FORBIDDEN', 'message', 'No pude identificar la empresa activa.');
    END IF;
    v_role := public.fn_agri_actor_role(p_tenant_id, v_actor);
    SELECT c0.is_active IS NOT FALSE INTO v_active FROM public.companys c0 WHERE c0.id_company = p_tenant_id;
    IF v_role IS NULL OR v_active IS NOT TRUE THEN
        RETURN jsonb_build_object('status', 'FORBIDDEN', 'code', 'FORBIDDEN', 'message', 'Tu usuario no tiene acceso a la empresa activa.');
    END IF;
    IF v_role <> 'ADMIN' THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'FORBIDDEN', 'FORBIDDEN', 'Solo un administrador de la empresa puede registrar ventas.');
    END IF;
    IF public.fn_company_business_domain(p_tenant_id) IS DISTINCT FROM 'PALM' THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'NOT_PALM', 'NOT_PALM', 'La empresa activa no es de palma.');
    END IF;
    v_is_test := coalesce((SELECT f.is_test FROM public.company_flags f WHERE f.id_company = p_tenant_id), false);

    -- Read the voucher. Anything that does not parse is an invalid voucher.
    BEGIN
        IF j IS NULL OR jsonb_typeof(j) <> 'object' THEN RAISE EXCEPTION 'not an object'; END IF;
        v_tipo      := j ->> 'tipoComprobante';
        v_moneda    := j ->> 'moneda';
        v_metodo    := j ->> 'metodoPago';
        v_forma     := j ->> 'formaPago';
        v_uuid      := upper(j ->> 'uuid');
        v_emisor    := upper(j #>> '{emisor,rfc}');
        v_receptor  := upper(j #>> '{receptor,rfc}');
        v_emisor_nm := nullif(left(regexp_replace(coalesce(j #>> '{emisor,nombre}', ''), '[[:cntrl:]]', '', 'g'), 150), '');
        v_buyer     := btrim(left(regexp_replace(coalesce(j #>> '{receptor,nombre}', ''), '[[:cntrl:]]', '', 'g'), 150));
        v_serie     := nullif(left(regexp_replace(coalesce(j ->> 'serie', ''), '[[:cntrl:]]', '', 'g'), 25), '');
        v_folio     := nullif(left(regexp_replace(coalesce(j ->> 'folio', ''), '[[:cntrl:]]', '', 'g'), 40), '');
        v_hash_in   := lower(j ->> 'sourceSha256');
        v_sub       := (j ->> 'subtotalCents')::bigint;
        v_disc      := coalesce((j ->> 'descuentoCents')::bigint, 0);
        v_total     := (j ->> 'totalCents')::bigint;
        IF coalesce(j ->> 'fechaEmision', '') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'
           OR coalesce(j ->> 'fechaTimbrado', '') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$' THEN
            RAISE EXCEPTION 'bad date';
        END IF;
        v_issued    := (j ->> 'fechaEmision')::timestamp;
        v_stamped   := (j ->> 'fechaTimbrado')::timestamp;
        v_taxes     := jsonb_build_object('traslados', coalesce(j -> 'traslados', '[]'::jsonb), 'retenciones', coalesce(j -> 'retenciones', '[]'::jsonb));
        IF jsonb_typeof(v_taxes -> 'traslados') <> 'array' OR jsonb_typeof(v_taxes -> 'retenciones') <> 'array' THEN RAISE EXCEPTION 'bad taxes'; END IF;
        SELECT coalesce(sum((x ->> 'importeCents')::bigint), 0) INTO v_tr  FROM jsonb_array_elements(v_taxes -> 'traslados') x;
        SELECT coalesce(sum((x ->> 'importeCents')::bigint), 0) INTO v_ret FROM jsonb_array_elements(v_taxes -> 'retenciones') x;
        IF jsonb_typeof(j -> 'conceptos') <> 'array' THEN RAISE EXCEPTION 'bad conceptos'; END IF;
        v_nconc := jsonb_array_length(j -> 'conceptos');
        IF v_nconc = 1 THEN
            c           := (j -> 'conceptos') -> 0;
            v_product   := c ->> 'claveProdServ';
            v_unit      := upper(c ->> 'claveUnidad');
            v_qty_txt   := c ->> 'cantidad';
            v_price_txt := c ->> 'valorUnitario';
            v_conc_txt  := c ->> 'importeCents';
            v_desc      := regexp_replace(coalesce(c ->> 'descripcion', ''), '[[:cntrl:]]', ' ', 'g');
        END IF;
    EXCEPTION WHEN others THEN
        v_bad := true;
    END;

    IF v_bad THEN v_reason := 'BAD_PAYLOAD';
    ELSIF v_uuid IS NULL OR v_uuid !~ c_uuid THEN v_reason := 'UUID';
    END IF;

    -- Idempotency inside the company: the same voucher answers with its ACTIVE sale. A voided sale does not block a new load.
    IF v_reason IS NULL THEN
        SELECT s.id, s.status, s.total_cents, s.issued_at, s.ticket_ref INTO v_ex
          FROM public.agri_sale_invoices s WHERE s.id_company = p_tenant_id AND s.uuid = v_uuid AND s.status = 'ACTIVE';
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'ALREADY_REGISTERED', 'sale_id', v_ex.id, 'warnings', '[]'::jsonb,
                'message', 'Esta venta ya estaba registrada.');
        END IF;
    END IF;

    -- Voucher rules (reason codes).
    IF v_reason IS NULL THEN
        IF v_tipo IS DISTINCT FROM 'I' THEN v_reason := 'TIPO';
        ELSIF v_moneda IS DISTINCT FROM 'MXN' THEN v_reason := 'CURRENCY';
        ELSIF v_metodo IS DISTINCT FROM 'PUE' THEN v_reason := 'PAYMENT_METHOD';
        ELSIF v_emisor IS NULL OR v_emisor !~ c_rfc THEN v_reason := 'ISSUER_RFC_FORMAT';
        ELSIF v_receptor IS NULL OR v_receptor !~ c_rfc THEN v_reason := 'BUYER_RFC_FORMAT';
        ELSIF v_receptor = v_emisor THEN v_reason := 'BUYER_IS_ISSUER';
        ELSIF v_buyer = '' THEN v_reason := 'BUYER_NAME';
        ELSIF v_sha !~ '^[0-9a-f]{64}$' OR (v_hash_in IS NOT NULL AND v_hash_in <> v_sha) THEN v_reason := 'HASH';
        ELSIF v_path = '' OR length(v_path) > 300 OR v_path !~ '^[A-Za-z0-9_./-]+$' OR v_path ~ '\.\.'
              OR v_path !~ ('^' || p_tenant_id::text || '/[0-9]{4}/(0[1-9]|1[0-2])/' || v_sha || '\.xml$') THEN v_reason := 'PATH';
        ELSIF v_forma IS NULL OR v_forma !~ '^[0-9]{2}$' THEN v_reason := 'PAYMENT_FORM';
        ELSIF v_nconc IS DISTINCT FROM 1 THEN v_reason := 'CONCEPT_COUNT';
        ELSIF v_product IS NULL OR v_product !~ '^[0-9]{8}$' THEN v_reason := 'PRODUCT_KEY';
        ELSIF v_unit IS DISTINCT FROM 'KGM' THEN v_reason := 'UNIT';
        ELSIF v_qty_txt IS NULL OR v_qty_txt !~ c_qty OR v_price_txt IS NULL OR v_price_txt !~ c_qty THEN v_reason := 'QUANTITY';
        ELSIF v_conc_txt IS NULL OR v_conc_txt !~ '^[0-9]{1,13}$' THEN v_reason := 'CONCEPT_AMOUNT';
        END IF;
    END IF;
    IF v_reason IS NULL THEN
        v_qty := v_qty_txt::numeric;
        v_price := v_price_txt::numeric;
        IF v_qty <= 0 OR v_price <= 0 THEN v_reason := 'QUANTITY';
        ELSIF v_sub IS NULL OR v_total IS NULL OR v_sub < 0 OR v_disc < 0 OR v_disc > v_sub OR v_total <= 0 OR v_total > 999999999999 THEN v_reason := 'AMOUNTS';
        ELSIF v_sub - v_disc + v_tr - v_ret <> v_total THEN v_reason := 'AMOUNTS_MISMATCH';
        ELSIF v_sub <> v_conc_txt::bigint
              OR abs(round(v_qty * v_price * 100) - v_conc_txt::bigint) > 1 THEN v_reason := 'AMOUNTS_MISMATCH_CONCEPT';
        ELSIF v_issued::date > v_today OR v_stamped::date > v_today THEN v_reason := 'DATE_FUTURE';
        ELSIF v_issued::date < v_today - c_max_age_days THEN v_reason := 'DATE_TOO_OLD';
        END IF;
    END IF;
    IF v_reason IS NOT NULL THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'INVALID_VOUCHER', 'INVALID_VOUCHER_' || v_reason,
            'El comprobante no se pudo registrar.', jsonb_build_object('reason', v_reason));
    END IF;

    -- Issuer RFC list of the company (platform-managed).
    IF NOT EXISTS (SELECT 1 FROM public.company_issuer_rfcs r WHERE r.id_company = p_tenant_id AND r.is_active) THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'ISSUER_RFC_NOT_CONFIGURED', 'ISSUER_RFC_NOT_CONFIGURED',
            'La empresa no tiene un RFC emisor configurado para registrar ventas.');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.company_issuer_rfcs r WHERE r.id_company = p_tenant_id AND r.is_active AND r.rfc = v_emisor) THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'ISSUER_RFC_MISMATCH', 'ISSUER_RFC_MISMATCH',
            'El RFC emisor del comprobante no corresponde a la empresa.');
    END IF;

    -- SAT answer: VIGENTE always; a test company may proceed when the SAT has no answer (SKIPPED_TEST); CANCELADO never.
    IF v_sat_in = 'VIGENTE' THEN v_sat := 'VIGENTE';
    ELSIF v_is_test AND v_sat_in IN ('NO_ENCONTRADO', 'ERROR', 'SKIPPED_TEST') THEN v_sat := 'SKIPPED_TEST';
    ELSE
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'INVALID_VOUCHER', 'INVALID_VOUCHER_SAT_NOT_VALID',
            'El comprobante no esta vigente ante el SAT o no se pudo verificar.', jsonb_build_object('reason', 'SAT_NOT_VALID'));
    END IF;

    -- Ticket reference "(ticket N)" in the description: exactly one recognizable match, otherwise none and a warning.
    SELECT array_agg(m[1]) INTO v_tickets FROM regexp_matches(v_desc, c_ticket, 'gi') AS m;
    IF v_tickets IS NOT NULL AND array_length(v_tickets, 1) = 1 THEN
        v_ticket := v_tickets[1];
    ELSE
        v_ticket_warn := true;
        v_warnings := v_warnings || to_jsonb('ticket_missing_or_unrecognized'::text);
    END IF;

    -- Serialize concurrent loads of the same voucher, then re-check the company and the cross-company rule for real companies.
    PERFORM pg_advisory_xact_lock(hashtextextended('agri_sale:' || v_uuid, 0));
    SELECT s.id INTO v_ex FROM public.agri_sale_invoices s WHERE s.id_company = p_tenant_id AND s.uuid = v_uuid AND s.status = 'ACTIVE';
    IF FOUND THEN
        RETURN jsonb_build_object('status', 'ALREADY_REGISTERED', 'sale_id', v_ex.id, 'warnings', '[]'::jsonb, 'message', 'Esta venta ya estaba registrada.');
    END IF;
    -- A real company cannot load a voucher UUID that another real company holds, ACTIVE or VOID. The answer is the same generic one.
    IF NOT v_is_test AND EXISTS (SELECT 1 FROM public.agri_sale_invoices s WHERE s.uuid = v_uuid AND NOT s.is_test AND s.id_company <> p_tenant_id) THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'DUPLICATE', 'DUPLICATE_UUID', 'No se pudo registrar la factura.');
    END IF;
    IF EXISTS (SELECT 1 FROM public.agri_sale_invoices s WHERE s.id_company = p_tenant_id AND s.uuid = v_uuid AND s.status = 'VOID') THEN
        v_warnings := v_warnings || to_jsonb('previous_sale_voided'::text);
    END IF;

    IF v_ticket IS NOT NULL AND EXISTS (SELECT 1 FROM public.agri_sale_invoices s
                                         WHERE s.id_company = p_tenant_id AND s.status = 'ACTIVE' AND upper(s.ticket_ref) = upper(v_ticket)) THEN
        v_warnings := v_warnings || to_jsonb('ticket_already_used'::text);
    END IF;

    BEGIN
        INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, emisor_name, receptor_rfc, buyer_name, serie, folio, issued_at, stamped_at,
                                               currency, subtotal_cents, discount_cents, total_cents, taxes, payment_form, payment_method,
                                               product_key, unit_code, quantity, unit_price, ticket_ref, ticket_warning,
                                               source_sha256, original_path, sat_status, registered_by_email)
        VALUES (p_tenant_id, v_uuid, v_emisor, v_emisor_nm, v_receptor, v_buyer, v_serie, v_folio, v_issued, v_stamped,
                'MXN', v_sub, v_disc, v_total, v_taxes, v_forma, 'PUE',
                v_product, 'KGM', v_qty, v_price, v_ticket, v_ticket_warn,
                v_sha, v_path, v_sat, v_actor)
        RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'DUPLICATE', 'DUPLICATE_UUID', 'No se pudo registrar la factura.');
    END;

    PERFORM public.fn_agri_sale_audit(p_tenant_id, v_id, 'REGISTER', 'OK', v_actor);
    RETURN jsonb_build_object('status', 'OK', 'sale_id', v_id, 'warnings', v_warnings,
        'summary', jsonb_build_object('folio', coalesce(v_serie, '') || coalesce(v_folio, ''), 'sale_date', v_issued::date,
            'buyer_name', v_buyer, 'total_amount', round(v_total::numeric / 100, 2), 'quantity_kg', v_qty, 'unit_price', v_price,
            'ticket_ref', v_ticket, 'sat_status', v_sat));
END $$;
COMMENT ON FUNCTION public.sp_agri_register_sale(integer, text, jsonb, text, text, text) IS
  'Registers a palm sale from a parsed CFDI (direct load). ADMIN of a palm company only; issuer RFC from the platform-managed list; amounts only from the voucher; idempotent per company; answers a status, never raises for expected cases.';

CREATE OR REPLACE FUNCTION public.sp_agri_void_sale(p_tenant_id integer, p_actor_email text, p_sale_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_actor  text := lower(btrim(coalesce(p_actor_email, '')));
    v_role   text;
    v_active boolean;
    v_reason text := btrim(regexp_replace(coalesce(p_reason, ''), '[[:cntrl:]]', ' ', 'g'));
    v_sale   record;
BEGIN
    IF p_tenant_id IS NULL OR p_sale_id IS NULL THEN
        RETURN jsonb_build_object('status', 'FORBIDDEN', 'code', 'FORBIDDEN', 'message', 'No pude identificar la empresa activa.');
    END IF;
    v_role := public.fn_agri_actor_role(p_tenant_id, v_actor);
    SELECT c0.is_active IS NOT FALSE INTO v_active FROM public.companys c0 WHERE c0.id_company = p_tenant_id;
    IF v_role IS NULL OR v_active IS NOT TRUE THEN
        RETURN jsonb_build_object('status', 'FORBIDDEN', 'code', 'FORBIDDEN', 'message', 'Tu usuario no tiene acceso a la empresa activa.');
    END IF;
    IF v_role <> 'ADMIN' THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'FORBIDDEN', 'FORBIDDEN', 'Solo un administrador de la empresa puede anular ventas.');
    END IF;
    IF public.fn_company_business_domain(p_tenant_id) IS DISTINCT FROM 'PALM' THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'NOT_PALM', 'NOT_PALM', 'La empresa activa no es de palma.');
    END IF;
    IF length(v_reason) NOT BETWEEN 5 AND 300 THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'INVALID_REASON', 'VOID_INVALID_REASON', 'El motivo de la anulacion debe tener entre 5 y 300 caracteres.');
    END IF;

    SELECT s.id, s.status INTO v_sale FROM public.agri_sale_invoices s WHERE s.id = p_sale_id AND s.id_company = p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'NOT_FOUND', 'VOID_NOT_FOUND', 'La venta no existe en la empresa activa.');
    END IF;
    IF v_sale.status = 'VOID' THEN
        RETURN jsonb_build_object('status', 'ALREADY_VOID', 'sale_id', v_sale.id, 'message', 'La venta ya estaba anulada.');
    END IF;

    PERFORM set_config('app.agri_sale_void', 'on', true);
    UPDATE public.agri_sale_invoices
       SET status = 'VOID', void_reason = v_reason, voided_by_email = v_actor, voided_at = now()
     WHERE id = p_sale_id AND id_company = p_tenant_id;
    PERFORM set_config('app.agri_sale_void', '', true);

    PERFORM public.fn_agri_sale_audit(p_tenant_id, p_sale_id, 'VOID', 'VOID_OK', v_actor);
    RETURN jsonb_build_object('status', 'OK', 'sale_id', p_sale_id);
END $$;
COMMENT ON FUNCTION public.sp_agri_void_sale(integer, text, uuid, text) IS
  'Voids a palm sale (ADMIN only, any time, reason 5..300 characters, audited, idempotent). The only change a registered sale accepts.';

-- 5) Reads ----------------------------------------------------------------------------------------------

-- Same call contract as sp_agri_expense_balance (no category filter) plus the previous period of the same length. Voided sales are
-- excluded; the sale date is the voucher Fecha (local time, America/Mexico_City). Amounts are voucher totals (ADMIN only).
CREATE OR REPLACE FUNCTION public.sp_agri_sales_balance(
    p_tenant_id      integer,
    p_date_from      date,
    p_date_to        date,
    p_grain          varchar,
    p_plantation_id  uuid,
    p_lot_id         uuid,
    p_actor_email    varchar
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    c_max_years     constant integer := 10;
    c_max_day_span  constant integer := 366;
    v_role          text := public.fn_agri_actor_role(p_tenant_id, p_actor_email);
    v_grain         text := upper(btrim(coalesce(p_grain, 'MONTH')));
    v_from          date := coalesce(p_date_from, date_trunc('month', public.fn_agri_today_cdmx()::timestamp)::date);
    v_to            date := coalesce(p_date_to, public.fn_agri_today_cdmx());
    v_prev_to       date;
    v_prev_from     date;
    v_step          interval;
    v_lot           record;
    v_cur_total     numeric;
    v_prev_total    numeric;
    v_prev_count    bigint;
    v_result        jsonb;
BEGIN
    IF v_role IS NULL OR v_role <> 'ADMIN' THEN
        RAISE EXCEPTION 'Solo un administrador de la empresa puede consultar el balance de ventas.' USING ERRCODE = 'P0084';
    END IF;
    IF public.fn_company_business_domain(p_tenant_id) IS DISTINCT FROM 'PALM' THEN
        RAISE EXCEPTION 'La empresa activa no es de palma.' USING ERRCODE = 'P0093';
    END IF;
    IF v_grain NOT IN ('DAY', 'WEEK', 'MONTH', 'YEAR') THEN
        RAISE EXCEPTION 'Periodo no válido: usa DAY, WEEK, MONTH o YEAR.' USING ERRCODE = 'P0092';
    END IF;
    IF v_from > v_to THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final.' USING ERRCODE = 'P0092';
    END IF;
    IF v_to >= (v_from + make_interval(years => c_max_years))::date THEN
        RAISE EXCEPTION 'El rango máximo es de % años.', c_max_years USING ERRCODE = 'P0092';
    END IF;
    IF v_grain = 'DAY' AND v_to - v_from + 1 > c_max_day_span THEN
        RAISE EXCEPTION 'Por día, el rango máximo es de % días.', c_max_day_span USING ERRCODE = 'P0092';
    END IF;
    IF p_plantation_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.agri_plantations WHERE id = p_plantation_id AND id_company = p_tenant_id) THEN
        RAISE EXCEPTION 'La plantación no existe o no pertenece a la empresa activa.' USING ERRCODE = 'P0080';
    END IF;
    IF p_lot_id IS NOT NULL THEN
        SELECT plantation_id INTO v_lot FROM public.agri_lots WHERE id = p_lot_id AND id_company = p_tenant_id;
        IF NOT FOUND OR (p_plantation_id IS NOT NULL AND v_lot.plantation_id <> p_plantation_id) THEN
            RAISE EXCEPTION 'El lote no existe o no pertenece a la plantación seleccionada.' USING ERRCODE = 'P0080';
        END IF;
    END IF;

    v_step := CASE v_grain WHEN 'DAY' THEN interval '1 day' WHEN 'WEEK' THEN interval '1 week'
                           WHEN 'MONTH' THEN interval '1 month' ELSE interval '1 year' END;
    v_prev_to := v_from - 1;
    v_prev_from := v_prev_to - (v_to - v_from);

    SELECT coalesce(sum(s.total_cents), 0)::numeric / 100 INTO v_cur_total
      FROM public.agri_sale_invoices s
     WHERE s.id_company = p_tenant_id AND s.status = 'ACTIVE' AND s.issued_at::date BETWEEN v_from AND v_to
       AND (p_plantation_id IS NULL OR s.plantation_id = p_plantation_id) AND (p_lot_id IS NULL OR s.lot_id = p_lot_id);
    SELECT coalesce(sum(s.total_cents), 0)::numeric / 100, count(*) INTO v_prev_total, v_prev_count
      FROM public.agri_sale_invoices s
     WHERE s.id_company = p_tenant_id AND s.status = 'ACTIVE' AND s.issued_at::date BETWEEN v_prev_from AND v_prev_to
       AND (p_plantation_id IS NULL OR s.plantation_id = p_plantation_id) AND (p_lot_id IS NULL OR s.lot_id = p_lot_id);

    WITH f AS (
        SELECT s.*, date_trunc(lower(v_grain), s.issued_at)::date AS period_start
          FROM public.agri_sale_invoices s
         WHERE s.id_company = p_tenant_id
           AND s.status = 'ACTIVE'
           AND s.issued_at::date BETWEEN v_from AND v_to
           AND (p_plantation_id IS NULL OR s.plantation_id = p_plantation_id)
           AND (p_lot_id IS NULL OR s.lot_id = p_lot_id)
    ),
    periods AS (
        SELECT gs::date AS period_start, (gs + v_step - interval '1 day')::date AS period_end
          FROM generate_series(date_trunc(lower(v_grain), v_from::timestamp), v_to::timestamp, v_step) AS gs
    )
    SELECT jsonb_build_object(
        'success',        true,
        'grain',          v_grain,
        'date_from',      v_from,
        'date_to',        v_to,
        'total_amount',   (SELECT coalesce(sum(total_cents), 0)::numeric / 100 FROM f),
        'sale_count',     (SELECT count(*) FROM f),
        'total_quantity_kg', (SELECT coalesce(sum(quantity), 0) FROM f),
        'general_amount', (SELECT coalesce(sum(total_cents), 0)::numeric / 100 FROM f WHERE plantation_id IS NULL),
        'previous', jsonb_build_object('date_from', v_prev_from, 'date_to', v_prev_to, 'total_amount', v_prev_total, 'sale_count', v_prev_count),
        'delta_pct',      CASE WHEN v_prev_total > 0 THEN round((v_cur_total - v_prev_total) / v_prev_total * 100, 2) END,
        'by_period', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'period_start', p.period_start, 'period_end', p.period_end,
                       'total_amount', coalesce(x.total, 0), 'sale_count', coalesce(x.n, 0), 'quantity_kg', coalesce(x.qty, 0))
                   ORDER BY p.period_start), '[]'::jsonb)
              FROM periods p
              LEFT JOIN (SELECT period_start, sum(total_cents)::numeric / 100 AS total, count(*) AS n, sum(quantity) AS qty FROM f GROUP BY 1) x
                ON x.period_start = p.period_start),
        'by_plantation', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'plantation_id', x.plantation_id, 'plantation_code', p.plantation_code,
                       'plantation_name', p.plantation_name, 'total_amount', x.total, 'sale_count', x.n)
                   ORDER BY x.total DESC), '[]'::jsonb)
              FROM (SELECT plantation_id, sum(total_cents)::numeric / 100 AS total, count(*) AS n FROM f GROUP BY 1) x
              LEFT JOIN public.agri_plantations p ON p.id = x.plantation_id AND p.id_company = p_tenant_id)
    ) INTO v_result;

    RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.sp_agri_sales_balance(integer, date, date, varchar, uuid, uuid, varchar) IS
  'Sales totals of a palm company for a range and filters (ADMIN only), voided excluded: total, count, kg, by period / plantation, previous period and delta. Errors: P0080, P0084, P0092, P0093.';

-- Views (id_company and created_at are required by the gateway). Registered in crud_models by a later pull request (ADMIN only).
CREATE OR REPLACE VIEW public.vw_agri_sale_list AS
SELECT
    s.id,
    s.id_company,
    s.uuid,
    coalesce(s.serie, '') || coalesce(s.folio, '') AS cfdi_folio,
    s.issued_at,
    s.issued_at::date AS sale_date,
    s.buyer_name,
    s.receptor_rfc AS buyer_rfc,
    s.quantity,
    s.unit_code,
    s.unit_price,
    s.subtotal_cents::numeric / 100 AS subtotal_amount,
    s.discount_cents::numeric / 100 AS discount_amount,
    s.total_cents::numeric / 100 AS total_amount,
    s.payment_form,
    s.payment_method,
    s.ticket_ref,
    s.ticket_warning,
    s.plantation_id,
    p.plantation_code,
    p.plantation_name,
    s.lot_id,
    l.lot_code,
    l.lot_name,
    s.sat_status,
    s.is_test,
    s.status,
    s.void_reason,
    s.voided_by_email,
    s.voided_at,
    s.registered_by_email,
    s.created_at
FROM public.agri_sale_invoices s
LEFT JOIN public.agri_plantations p ON p.id = s.plantation_id AND p.id_company = s.id_company
LEFT JOIN public.agri_lots l ON l.id = s.lot_id AND l.id_company = s.id_company;
COMMENT ON VIEW public.vw_agri_sale_list IS '104: sale list of a company, voided sales included with their status (ADMIN only; amounts).';

CREATE OR REPLACE VIEW public.vw_agri_sale_summary AS
SELECT
    md5(concat_ws('|', s.id_company, g.grain, g.period_start, s.plantation_id, s.lot_id)) AS id,
    s.id_company,
    g.grain,
    g.period_start,
    g.period_end,
    s.plantation_id,
    p.plantation_code,
    p.plantation_name,
    s.lot_id,
    l.lot_code,
    l.lot_name,
    sum(s.total_cents)::numeric / 100 AS total_amount,
    sum(s.quantity)                   AS total_quantity,
    count(*)::integer                 AS sale_count,
    max(s.created_at)                 AS created_at
FROM public.agri_sale_invoices s
CROSS JOIN LATERAL (VALUES
    ('DAY',   s.issued_at::date,                                  s.issued_at::date),
    ('WEEK',  date_trunc('week',  s.issued_at)::date,             (date_trunc('week',  s.issued_at) + interval '6 days')::date),
    ('MONTH', date_trunc('month', s.issued_at)::date,             (date_trunc('month', s.issued_at) + interval '1 month' - interval '1 day')::date),
    ('YEAR',  date_trunc('year',  s.issued_at)::date,             (date_trunc('year',  s.issued_at) + interval '1 year' - interval '1 day')::date)
) AS g(grain, period_start, period_end)
LEFT JOIN public.agri_plantations p ON p.id = s.plantation_id AND p.id_company = s.id_company
LEFT JOIN public.agri_lots l ON l.id = s.lot_id AND l.id_company = s.id_company
WHERE s.status = 'ACTIVE'
GROUP BY s.id_company, g.grain, g.period_start, g.period_end, s.plantation_id, p.plantation_code, p.plantation_name,
         s.lot_id, l.lot_code, l.lot_name;
COMMENT ON VIEW public.vw_agri_sale_summary IS '104: sale totals by period grain, plantation and lot; active sales only (ADMIN only; amounts).';

-- 6) Post-checks ----------------------------------------------------------------------------------------

DO $$
BEGIN
    IF (SELECT count(*) FROM pg_trigger WHERE tgrelid IN ('public.company_flags'::regclass, 'public.company_issuer_rfcs'::regclass,
                                                           'public.agri_sale_invoices'::regclass, 'public.agri_sale_audit'::regclass)
                                              AND tgname LIKE 'trg\_%guard\_%' AND NOT tgisinternal) <> 8 THEN
        RAISE EXCEPTION '104: expected 8 guard triggers';
    END IF;
    IF to_regprocedure('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_agri_void_sale(integer,text,uuid,text)') IS NULL
       OR to_regprocedure('public.sp_agri_sales_balance(integer,date,date,character varying,uuid,uuid,character varying)') IS NULL THEN
        RAISE EXCEPTION '104: procedures missing';
    END IF;
    RAISE NOTICE '104: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 104 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 104 rolled back ***'
\endif
\endif
