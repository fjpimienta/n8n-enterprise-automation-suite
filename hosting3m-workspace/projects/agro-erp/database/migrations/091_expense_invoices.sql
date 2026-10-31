-- 091_expense_invoices.sql
-- CFDI invoices behind cattle expenses: per-company RFCs, append-only invoice records, one atomic register procedure.
-- REQUIRES 084 (fn_repro_ctx). Aborts if missing. Nothing existing is altered, replaced or dropped.
-- UNTESTED: never executed. Run 091_tests.sql on LOCAL first.
-- Tables:  company_tax_ids     RFCs a company may receive invoices for (several per company; the same RFC may belong to several companies)
--          expense_invoices    APPEND-ONLY, UNIQUE (id_company, uuid), one row per registered CFDI, linked to its cattle_expenses row
-- Tools:   sp_company_tax_id_set        ADMIN/OWNER only, NOT an agent tool; never sets qa_skip_sat
--          sp_expense_invoice_register  preview unless p_confirmed = 'true'; the company comes from the validated session, never from the RFC
-- Rules:   amount = total with taxes (exact cents); no tax amount is ever computed, only reconciled; SAT status is validated by the caller
--          (n8n) and passed in; SKIPPED_TEST is accepted only for a receiver RFC with qa_skip_sat = true (set by SQL seed only).
-- Errors:  P0095 append-only / not deletable, P0096 cross-company reference.
-- Rollback: 091_rollback.sql. State: 091_state_check.sql. Tests: 091_tests.sql.
-- Usage:   psql -v ON_ERROR_STOP=1 -f 091_expense_invoices.sql (dry run) | ... -v apply=true -f ... (commit)

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
    IF to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 084 is not applied here (fn_repro_ctx missing).';
    END IF;
    IF to_regclass('public.companys') IS NULL OR to_regclass('public.cattle_expenses') IS NULL OR to_regclass('public.user_companies') IS NULL THEN
        RAISE EXCEPTION 'ABORT: companys / cattle_expenses / user_companies are missing.';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.company_tax_ids (
    id_company       integer NOT NULL REFERENCES public.companys (id_company),
    rfc              text    NOT NULL CONSTRAINT ck_company_tax_ids_rfc CHECK (rfc ~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    label            text,
    is_active        boolean NOT NULL DEFAULT true,
    qa_skip_sat      boolean NOT NULL DEFAULT false,
    created_by_email text    NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id_company, rfc)
);

CREATE TABLE IF NOT EXISTS public.expense_invoices (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company          integer NOT NULL REFERENCES public.companys (id_company),
    uuid                text    NOT NULL CONSTRAINT ck_expense_invoices_uuid CHECK (uuid ~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$'),
    emisor_rfc          text    NOT NULL CONSTRAINT ck_expense_invoices_emisor CHECK (emisor_rfc ~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    emisor_name         text,
    receptor_rfc        text    NOT NULL CONSTRAINT ck_expense_invoices_receptor CHECK (receptor_rfc ~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    serie               text,
    folio               text,
    issued_at           timestamp NOT NULL,
    stamped_at          timestamp NOT NULL,
    currency            text    NOT NULL DEFAULT 'MXN' CONSTRAINT ck_expense_invoices_currency CHECK (currency = 'MXN'),
    subtotal_cents      bigint  NOT NULL CONSTRAINT ck_expense_invoices_subtotal CHECK (subtotal_cents >= 0),
    discount_cents      bigint  NOT NULL DEFAULT 0 CONSTRAINT ck_expense_invoices_discount CHECK (discount_cents >= 0),
    total_cents         bigint  NOT NULL CONSTRAINT ck_expense_invoices_total CHECK (total_cents BETWEEN 1 AND 999999999999),
    taxes               jsonb   NOT NULL,
    source_sha256       text    NOT NULL CONSTRAINT ck_expense_invoices_sha CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    original_path       text    NOT NULL CONSTRAINT ck_expense_invoices_path CHECK (original_path ~ '^[A-Za-z0-9_./-]+$' AND original_path !~ '\.\.' AND original_path !~ '^/' AND length(original_path) <= 300),
    sat_status          text    NOT NULL CONSTRAINT ck_expense_invoices_sat CHECK (sat_status IN ('VIGENTE', 'SKIPPED_TEST')),
    expense_id          uuid    NOT NULL UNIQUE REFERENCES public.cattle_expenses (id) ON DELETE RESTRICT,
    registered_by_email text    NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_expense_invoices_company_uuid UNIQUE (id_company, uuid)
);
CREATE INDEX IF NOT EXISTS idx_expense_invoices_company ON public.expense_invoices (id_company, created_at DESC);

COMMENT ON TABLE public.company_tax_ids   IS '091: RFCs a company may receive invoices for. Not deletable (deactivate). qa_skip_sat is set by SQL seed only. Not in crud_models.';
COMMENT ON TABLE public.expense_invoices  IS '091: append-only CFDI records linked to cattle_expenses (P0095). Written only by sp_expense_invoice_register. Not in crud_models.';

CREATE OR REPLACE FUNCTION public.fn_trg_company_tax_ids_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'TRUNCATE' OR TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'company_tax_ids rows are not deletable: deactivate the RFC instead.' USING ERRCODE = 'P0095';
    END IF;
    IF NEW.id_company IS DISTINCT FROM OLD.id_company OR NEW.rfc IS DISTINCT FROM OLD.rfc THEN
        RAISE EXCEPTION 'company_tax_ids: company and RFC cannot change.' USING ERRCODE = 'P0095';
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.fn_trg_expense_invoices_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_t integer;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT tenant_id INTO v_t FROM public.cattle_expenses WHERE id = NEW.expense_id;
        IF v_t IS DISTINCT FROM NEW.id_company THEN
            RAISE EXCEPTION 'expense_invoices: the expense belongs to another company.' USING ERRCODE = 'P0096';
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'expense_invoices is append-only.' USING ERRCODE = 'P0095';
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_company_tax_ids_guard_row' AND tgrelid = 'public.company_tax_ids'::regclass) THEN
        CREATE TRIGGER trg_company_tax_ids_guard_row BEFORE UPDATE OR DELETE ON public.company_tax_ids
            FOR EACH ROW EXECUTE FUNCTION public.fn_trg_company_tax_ids_guard();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_company_tax_ids_guard_trunc' AND tgrelid = 'public.company_tax_ids'::regclass) THEN
        CREATE TRIGGER trg_company_tax_ids_guard_trunc BEFORE TRUNCATE ON public.company_tax_ids
            FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trg_company_tax_ids_guard();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expense_invoices_guard_row' AND tgrelid = 'public.expense_invoices'::regclass) THEN
        CREATE TRIGGER trg_expense_invoices_guard_row BEFORE INSERT OR UPDATE OR DELETE ON public.expense_invoices
            FOR EACH ROW EXECUTE FUNCTION public.fn_trg_expense_invoices_guard();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expense_invoices_guard_trunc' AND tgrelid = 'public.expense_invoices'::regclass) THEN
        CREATE TRIGGER trg_expense_invoices_guard_trunc BEFORE TRUNCATE ON public.expense_invoices
            FOR EACH STATEMENT EXECUTE FUNCTION public.fn_trg_expense_invoices_guard();
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_company_tax_id_set(
    p_tenant_id text, p_user_email text, p_rfc text, p_label text DEFAULT NULL, p_active text DEFAULT 'true'
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_co    integer;
    v_email text := lower(btrim(coalesce(p_user_email, '')));
    v_role  text;
    v_rfc   text := upper(btrim(coalesce(p_rfc, '')));
    v_act   boolean := lower(btrim(coalesce(p_active, 'true'))) <> 'false';
    v_label text := nullif(left(regexp_replace(btrim(coalesce(p_label, '')), '[[:cntrl:]]', '', 'g'), 100), '');
BEGIN
    v_co := public.fn_repro_ctx(p_tenant_id, p_user_email);
    SELECT uc.role INTO v_role FROM public.user_companies uc
     WHERE uc.id_company = v_co AND lower(uc.email) = v_email AND uc.is_active IS TRUE LIMIT 1;
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'OWNER') THEN
        RETURN jsonb_build_object('status', 'forbidden', 'message', 'Solo un ADMIN puede registrar RFC de la empresa.');
    END IF;
    IF v_rfc !~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_RFC', 'message', 'El RFC no tiene un formato valido.');
    END IF;
    INSERT INTO public.company_tax_ids (id_company, rfc, label, is_active, created_by_email)
    VALUES (v_co, v_rfc, v_label, v_act, v_email)
    ON CONFLICT (id_company, rfc) DO UPDATE
        SET label = coalesce(EXCLUDED.label, public.company_tax_ids.label), is_active = EXCLUDED.is_active, updated_at = now();
    RETURN jsonb_build_object('status', 'saved', 'rfc', v_rfc, 'is_active', v_act);
END $$;

CREATE OR REPLACE FUNCTION public.sp_expense_invoice_register(
    p_tenant_id text, p_user_email text, p_invoice text, p_category text,
    p_description text DEFAULT NULL, p_expense_date text DEFAULT NULL,
    p_original_path text DEFAULT NULL, p_sat_status text DEFAULT NULL, p_confirmed text DEFAULT 'false'
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_co        integer;
    v_email     text := lower(btrim(coalesce(p_user_email, '')));
    v_role      text;
    j           jsonb;
    v_uuid      text;
    v_emisor    text;
    v_receptor  text;
    v_emisor_nm text;
    v_serie     text;
    v_folio     text;
    v_sub       bigint;
    v_disc      bigint;
    v_total     bigint;
    v_tr        bigint;
    v_ret       bigint;
    v_issued    timestamp;
    v_stamped   timestamp;
    v_sha       text;
    v_taxes     jsonb;
    v_date      date;
    v_today     date := (now() AT TIME ZONE 'America/Mexico_City')::date;
    v_cat       text := upper(btrim(coalesce(p_category, '')));
    v_path      text := btrim(coalesce(p_original_path, ''));
    v_sat       text := upper(btrim(coalesce(p_sat_status, '')));
    v_skip      boolean;
    v_desc      text;
    v_dup_date  date;
    v_dup_total bigint;
    v_exp_id    uuid;
    v_confirmed boolean := lower(btrim(coalesce(p_confirmed, 'false'))) = 'true';
    c_rfc       constant text := '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$';
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
        v_uuid      := upper(j ->> 'uuid');
        v_emisor    := upper(j #>> '{emisor,rfc}');
        v_receptor  := upper(j #>> '{receptor,rfc}');
        v_emisor_nm := left(regexp_replace(coalesce(j #>> '{emisor,nombre}', ''), '[[:cntrl:]]', '', 'g'), 150);
        v_serie     := left(regexp_replace(coalesce(j ->> 'serie', ''), '[[:cntrl:]]', '', 'g'), 25);
        v_folio     := left(regexp_replace(coalesce(j ->> 'folio', ''), '[[:cntrl:]]', '', 'g'), 40);
        v_sub       := (j ->> 'subtotalCents')::bigint;
        v_disc      := coalesce((j ->> 'descuentoCents')::bigint, 0);
        v_total     := (j ->> 'totalCents')::bigint;
        v_issued    := (j ->> 'fechaEmision')::timestamp;
        v_stamped   := (j ->> 'fechaTimbrado')::timestamp;
        v_sha       := lower(j ->> 'sourceSha256');
        v_taxes     := jsonb_build_object('traslados', coalesce(j -> 'traslados', '[]'::jsonb), 'retenciones', coalesce(j -> 'retenciones', '[]'::jsonb));
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
        RETURN jsonb_build_object('status', 'invalid', 'code', 'AMOUNTS_MISMATCH',
            'message', format('Los importes no cuadran: subtotal %s - descuento %s + traslados %s - retenciones %s no es el total %s (centavos).', v_sub, v_disc, v_tr, v_ret, v_total));
    END IF;
    IF v_cat = '' OR length(v_cat) > 50 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'CATEGORY_REQUIRED', 'message', 'Falta la categoria del gasto (maximo 50 caracteres).');
    END IF;
    IF v_path = '' OR length(v_path) > 300 OR v_path !~ '^[A-Za-z0-9_./-]+$' OR v_path ~ '\.\.' OR left(v_path, length(v_co::text) + 1) <> v_co::text || '/' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'ORIGINAL_PATH_INVALID', 'message', 'La ruta del archivo original no es valida para esta empresa.');
    END IF;
    BEGIN
        v_date := coalesce(nullif(btrim(coalesce(p_expense_date, '')), '')::date, v_issued::date);
    EXCEPTION WHEN others THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'INVALID_DATE', 'message', 'La fecha del gasto no es valida.');
    END;
    IF v_date > v_today THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'DATE_IN_FUTURE', 'message', 'La fecha del gasto no puede ser futura.');
    END IF;

    SELECT t.qa_skip_sat INTO v_skip FROM public.company_tax_ids t
     WHERE t.id_company = v_co AND t.rfc = v_receptor AND t.is_active IS TRUE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'rfc_not_registered',
            'message', 'El RFC receptor de la factura no esta registrado para esta empresa. Un ADMIN debe registrarlo antes.');
    END IF;
    IF NOT (v_sat = 'VIGENTE' OR (v_sat = 'SKIPPED_TEST' AND v_skip IS TRUE)) THEN
        RETURN jsonb_build_object('status', 'sat_not_valid', 'message', 'La factura no esta vigente ante el SAT o no se pudo verificar.');
    END IF;

    SELECT e.expense_date, i.total_cents INTO v_dup_date, v_dup_total
      FROM public.expense_invoices i JOIN public.cattle_expenses e ON e.id = i.expense_id
     WHERE i.id_company = v_co AND i.uuid = v_uuid;
    IF FOUND THEN
        RETURN jsonb_build_object('status', 'duplicate', 'expense_date', v_dup_date, 'amount', v_dup_total::numeric / 100,
            'message', 'Esta factura ya esta registrada en esta empresa.');
    END IF;

    v_desc := coalesce(nullif(left(regexp_replace(btrim(coalesce(p_description, '')), '[[:cntrl:]]', '', 'g'), 300), ''),
                       left(btrim(concat_ws(' ', 'CFDI', v_serie || v_folio, v_emisor_nm)), 300));

    IF NOT v_confirmed THEN
        RETURN jsonb_build_object('status', 'preview', 'emisor_name', v_emisor_nm, 'emisor_rfc', v_emisor, 'receptor_rfc', v_receptor,
            'cfdi_folio', v_serie || v_folio, 'expense_date', v_date, 'category', v_cat, 'description', v_desc,
            'amount', v_total::numeric / 100, 'subtotal', v_sub::numeric / 100, 'discount', v_disc::numeric / 100,
            'taxes_transferred', v_tr::numeric / 100, 'taxes_withheld', v_ret::numeric / 100, 'sat_status', v_sat);
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(v_co::text || ':' || v_uuid, 0));
    SELECT e.expense_date, i.total_cents INTO v_dup_date, v_dup_total
      FROM public.expense_invoices i JOIN public.cattle_expenses e ON e.id = i.expense_id
     WHERE i.id_company = v_co AND i.uuid = v_uuid;
    IF FOUND THEN
        RETURN jsonb_build_object('status', 'duplicate', 'expense_date', v_dup_date, 'amount', v_dup_total::numeric / 100,
            'message', 'Esta factura ya esta registrada en esta empresa.');
    END IF;

    BEGIN
        INSERT INTO public.cattle_expenses (tenant_id, expense_date, category, amount, description)
        VALUES (v_co, v_date, v_cat, (v_total::numeric / 100)::numeric(12, 2), v_desc)
        RETURNING id INTO v_exp_id;
        INSERT INTO public.expense_invoices (id_company, uuid, emisor_rfc, emisor_name, receptor_rfc, serie, folio, issued_at, stamped_at,
                                             currency, subtotal_cents, discount_cents, total_cents, taxes, source_sha256, original_path,
                                             sat_status, expense_id, registered_by_email)
        VALUES (v_co, v_uuid, v_emisor, nullif(v_emisor_nm, ''), v_receptor, nullif(v_serie, ''), nullif(v_folio, ''), v_issued, v_stamped,
                'MXN', v_sub, v_disc, v_total, v_taxes, v_sha, v_path, v_sat, v_exp_id, v_email);
    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object('status', 'duplicate', 'message', 'Esta factura ya esta registrada en esta empresa.');
    END;

    RETURN jsonb_build_object('status', 'recorded', 'cfdi_folio', v_serie || v_folio, 'expense_date', v_date, 'category', v_cat,
        'amount', v_total::numeric / 100, 'sat_status', v_sat);
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 091 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 091 rolled back ***'
\endif
\endif
