-- 081_agri_expenses.sql
-- Palm module, phase 2a: agricultural expenses (capture, per-company category catalog and balance).
--
-- Business rules (confirmed by the project owner, 2026-10-20):
--   * The security boundary is id_company. Every expense carries the id_company of its plantation, lot and
--     category: BEFORE triggers reject any mismatch with messages that never reveal the other company, and
--     composite FKs make the mismatch impossible at the database level.
--   * An expense may be general (no plantation), per plantation, or per lot. A lot always belongs to the
--     plantation of the expense (composite FK (lot_id, plantation_id, id_company)); when only the lot is
--     given, the procedure takes its plantation.
--   * Writes only through procedures, so the actor always comes from the verified JWT (the generic insert of
--     v6/CRUD does not fill it): sp_agri_record_expense (ADMIN, OWNER, EDITOR: capturing an expense is a field
--     operation) and sp_agri_void_expense (ADMIN, OWNER). An expense is never modified nor deleted: it is
--     voided with a reason and captured again.
--   * Amounts are read by ADMIN / OWNER only (event authorization matrix: financial restrictions apply to
--     READ access). The EDITOR only receives "Gasto registrado" from the capture procedure.
--   * The balance is computed in SQL: vw_agri_expense_summary (one row per period x plantation x lot x
--     category, for the table and the CSV) and sp_agri_expense_balance (totals of any filter combination,
--     for the totals and the dashboard card). Voided expenses are excluded from both.
--   * expense_date is the business date chosen by the user (America/Mexico_City); "today" and "not in the
--     future" are evaluated in America/Mexico_City (fn_agri_today_cdmx). Timestamps are naive UTC.
--   * Category catalog per company (agri_expense_categories), unique code and name among active rows,
--     written by ADMIN / OWNER through the generic CRUD; retired with is_active = false. category_code and
--     id_company are immutable. A company receives the 13 initial categories when its FIRST plantation is
--     created (trigger on agri_plantations), never by its industry text; this migration seeds only the
--     companies that already have a plantation (company 10, "Plantación de Pruebas", at the time of writing).
--   * Unit catalog (agri_unit_catalog) is GLOBAL and READ-ONLY through the gateway: it grows only through a
--     migration (debt: global catalogs editable by any company ADMIN, see CLAUDE.md).
--   * receipt_url exists but no procedure writes it yet: uploads wait for the INTERNAL_SECRET rotation of
--     the Media Server.
--
-- Gateway notes (v6/CRUD):
--   * No model has `id` in allowed_fields (pattern of 080). agri_expenses and agri_expense_summary are views,
--     read-only. The three procedures must be registered in spConfigByModel (Build Query) with tenantPosition 0
--     and actorEmailField 'actor_email'; a parameter missing from paramOrder is silently dropped.
--   * call_sp is validated as an INSERT by Security Validation, so the balance (a read) is granted through
--     allowed_roles_insert = 'ADMIN,OWNER'.
--   * Optional uuid parameters must arrive as null, never '' (`''::uuid` fails).
--
-- Objects:
--   fn_company_business_domain(id_company)  'PALM' | 'LIVESTOCK' | NULL, same rule as business-domain.util.ts
--   agri_unit_catalog          (new, global, read-only)  seed: KG, TON, L, PZA, BULTO, JORNAL, HA, VIAJE, SERVICIO
--   agri_expense_categories    (new, per company)
--   agri_expenses              (new, never updated outside the void procedure, never deleted)
--   agri_lots                  + UNIQUE (id, plantation_id, id_company) for the expense lot FK
--   fn_agri_seed_expense_categories(id_company)  idempotent; only when the company has no categories at all
--   trg_agri_plantations_seed_expense_categories (AFTER INSERT on agri_plantations)
--   sp_agri_record_expense, sp_agri_void_expense, sp_agri_expense_balance
--   vw_agri_expense_list, vw_agri_expense_summary (expose id_company and created_at)
--   crud_models: 7 agri_* models (upsert ON CONFLICT (model_name)), backed up first
--
-- Error codes (messages in Spanish, shown as-is by the UI). P0080-P0084 keep their 080 meaning:
--   P0080  record not found or not in the active company (plantation, lot, category, expense; lot outside
--          the plantation)
--   P0081  inactive parent (company, plantation, lot)
--   P0082  immutable column changed (category: id_company, category_code)
--   P0083  expense date in the future (America/Mexico_City)
--   P0084  role not allowed for the operation
--   P0090  an expense was updated (outside the void), deleted or truncated
--   P0091  invalid void (missing reason, already voided)
--   P0092  invalid expense data or balance request (amount, quantity/unit, unit, inactive category, invoice
--          folio, period, range)
--   P0093  the active company is not a palm company
--
-- Rollback: 081_rollback.sql (no DROP / DELETE: disables the 7 models and the seeding trigger).
-- State:    081_state_check.sql -v expect=before|applied|rolled_back (read-only).
--
-- Usage (dry run is the default when apply is not given):
--   psql -v ON_ERROR_STOP=1 -f 081_agri_expenses.sql                 -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=false -f 081_agri_expenses.sql  -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true  -f 081_agri_expenses.sql  -> commit
-- 081_tests.sql includes this file with `embedded` set: it then neither opens nor ends the transaction
-- (the tests own it and always roll it back).

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- 0) Preconditions and backup ---------------------------------------------------------------------------

DO $$
BEGIN
    IF to_regclass('public.agri_plantations') IS NULL OR to_regprocedure('public.fn_agri_actor_role(integer,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 080 is not applied here.';
    END IF;
END $$;

-- Backup of the crud_models rows this migration may overwrite (first run only: a re-apply after the
-- rollback keeps the original pre-081 state).
CREATE TABLE IF NOT EXISTS crud_models_backup_20261020_081 AS
SELECT m.*, now() AS backed_up_at
  FROM crud_models m
 WHERE m.model_name IN ('agri_unit_catalog', 'agri_expense_categories', 'agri_expenses', 'agri_expense_summary',
                        'agri_record_expense', 'agri_void_expense', 'agri_expense_balance');

-- 1) Business domain of a company ---------------------------------------------------------------------

-- Same rule as projects/agro-erp/src/app/shared/utils/business-domain.util.ts (industry without accents,
-- lowercase: 'agricultura' -> PALM, 'ganader' -> LIVESTOCK, anything else -> NULL). Phase 2b uses it to
-- keep the livestock chat tools away from palm companies.
CREATE OR REPLACE FUNCTION public.fn_company_business_domain(p_id_company integer)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
               WHEN s.industry LIKE '%agricultura%' THEN 'PALM'
               WHEN s.industry LIKE '%ganader%'     THEN 'LIVESTOCK'
           END
      FROM (SELECT lower(translate(btrim(coalesce(c.industry, '')),
                                   'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) AS industry
              FROM public.companys c
             WHERE c.id_company = p_id_company) s
$$;
COMMENT ON FUNCTION public.fn_company_business_domain(integer) IS
  'PALM / LIVESTOCK / NULL from companys.industry, same rule as the agro-erp frontend (business-domain.util.ts).';

-- 2) Global unit catalog (read-only through the gateway) ------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agri_unit_catalog (
    id          uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    unit_code   varchar(20)  NOT NULL,
    unit_name   varchar(80)  NOT NULL,
    sort_order  integer      NOT NULL DEFAULT 100,
    is_active   boolean      NOT NULL DEFAULT true,
    created_at  timestamp    NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
    CONSTRAINT agri_unit_catalog_code_key UNIQUE (unit_code),
    CONSTRAINT agri_unit_catalog_code_format_check CHECK (unit_code ~ '^[A-Z0-9_]+$'),
    CONSTRAINT agri_unit_catalog_name_check CHECK (btrim(unit_name) <> '')
);
COMMENT ON TABLE public.agri_unit_catalog IS
  'Global unit-of-measure catalog for agricultural expenses (no id_company). Read-only through the gateway; grows only through migrations.';

INSERT INTO public.agri_unit_catalog (unit_code, unit_name, sort_order) VALUES
    ('KG',       'Kilogramos', 10),
    ('TON',      'Toneladas',  20),
    ('L',        'Litros',     30),
    ('PZA',      'Piezas',     40),
    ('BULTO',    'Bultos',     50),
    ('JORNAL',   'Jornales',   60),
    ('HA',       'Hectáreas',  70),
    ('VIAJE',    'Viajes',     80),
    ('SERVICIO', 'Servicios',  90)
ON CONFLICT (unit_code) DO NOTHING;

-- 3) Expense categories (per company) ----------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.agri_expense_categories (
    id             uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company     integer       NOT NULL REFERENCES public.companys(id_company),
    category_code  varchar(40)   NOT NULL,
    category_name  varchar(120)  NOT NULL,
    sort_order     integer       NOT NULL DEFAULT 100,
    is_active      boolean       NOT NULL DEFAULT true,
    created_at     timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
    updated_at     timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
    CONSTRAINT agri_expense_categories_id_company_key UNIQUE (id, id_company),
    CONSTRAINT agri_expense_categories_code_format_check CHECK (category_code ~ '^[A-Z0-9_]+$'),
    CONSTRAINT agri_expense_categories_name_check CHECK (btrim(category_name) <> '')
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_agri_expense_categories_code_active
    ON public.agri_expense_categories (id_company, category_code) WHERE is_active;
CREATE UNIQUE INDEX IF NOT EXISTS uq_agri_expense_categories_name_active
    ON public.agri_expense_categories (id_company, upper(btrim(category_name))) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_agri_expense_categories_company ON public.agri_expense_categories (id_company);
COMMENT ON TABLE public.agri_expense_categories IS
  'Agricultural expense categories of a company. Seeded on the first plantation (fn_agri_seed_expense_categories); retired with is_active = false.';

-- 4) Expenses -------------------------------------------------------------------------------------------

-- Target of the expense lot FK: the lot must belong to the expense plantation and company.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'agri_lots_id_plantation_company_key' AND conrelid = 'public.agri_lots'::regclass) THEN
        ALTER TABLE public.agri_lots
            ADD CONSTRAINT agri_lots_id_plantation_company_key UNIQUE (id, plantation_id, id_company);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.agri_expenses (
    id                 uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company         integer       NOT NULL REFERENCES public.companys(id_company),
    plantation_id      uuid,                       -- NULL = general expense of the company
    lot_id             uuid,                       -- NULL = expense of the whole plantation (or general)
    category_id        uuid          NOT NULL,
    expense_date       date          NOT NULL,
    amount             numeric(12,2) NOT NULL,
    quantity           numeric(12,3),
    unit_code          varchar(20)   REFERENCES public.agri_unit_catalog(unit_code),
    supplier_name      varchar(150),
    description        text,
    is_invoiced        boolean       NOT NULL DEFAULT false,
    invoice_folio      varchar(60),
    receipt_url        text,                       -- no writer yet (uploads pending, see header)
    reported_by_email  varchar(255)  NOT NULL,     -- from the verified JWT, never from the client
    is_void            boolean       NOT NULL DEFAULT false,
    void_reason        text,
    voided_by_email    varchar(255),
    voided_at          timestamp,
    created_at         timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'UTC'),
    CONSTRAINT agri_expenses_plantation_fkey FOREIGN KEY (plantation_id, id_company)
        REFERENCES public.agri_plantations (id, id_company),
    CONSTRAINT agri_expenses_lot_fkey FOREIGN KEY (lot_id, plantation_id, id_company)
        REFERENCES public.agri_lots (id, plantation_id, id_company),
    CONSTRAINT agri_expenses_category_fkey FOREIGN KEY (category_id, id_company)
        REFERENCES public.agri_expense_categories (id, id_company),
    -- With plantation_id NULL the composite lot FK would not be checked (MATCH SIMPLE).
    CONSTRAINT agri_expenses_lot_needs_plantation_check CHECK (lot_id IS NULL OR plantation_id IS NOT NULL),
    CONSTRAINT agri_expenses_amount_check CHECK (amount > 0),
    CONSTRAINT agri_expenses_quantity_check CHECK (quantity IS NULL OR quantity > 0),
    CONSTRAINT agri_expenses_quantity_unit_pair_check CHECK ((quantity IS NULL) = (unit_code IS NULL)),
    CONSTRAINT agri_expenses_folio_only_if_invoiced_check CHECK (is_invoiced OR invoice_folio IS NULL),
    CONSTRAINT agri_expenses_reported_by_check CHECK (btrim(reported_by_email) <> ''),
    CONSTRAINT agri_expenses_void_consistency_check CHECK (
        (NOT is_void AND void_reason IS NULL AND voided_by_email IS NULL AND voided_at IS NULL)
        OR (is_void AND btrim(coalesce(void_reason, '')) <> '' AND btrim(coalesce(voided_by_email, '')) <> ''
            AND voided_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_agri_expenses_company_date ON public.agri_expenses (id_company, expense_date);
CREATE INDEX IF NOT EXISTS idx_agri_expenses_plantation ON public.agri_expenses (plantation_id);
CREATE INDEX IF NOT EXISTS idx_agri_expenses_lot ON public.agri_expenses (lot_id);
CREATE INDEX IF NOT EXISTS idx_agri_expenses_category ON public.agri_expenses (category_id);
COMMENT ON TABLE public.agri_expenses IS
  'Agricultural expenses. Written by sp_agri_record_expense; never updated (except the void by sp_agri_void_expense) nor deleted.';

-- 5) Seeding of the initial categories ------------------------------------------------------------------

-- Idempotent: inserts the 13 initial categories only when the company has NO category at all (active or
-- not), so a company that retired them never gets them back. Returns the number of rows inserted.
CREATE OR REPLACE FUNCTION public.fn_agri_seed_expense_categories(p_id_company integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_n integer;
BEGIN
    -- Serialize concurrent first plantations of the same company.
    PERFORM pg_advisory_xact_lock(hashtext('agri_expense_categories_seed'), p_id_company);
    IF EXISTS (SELECT 1 FROM public.agri_expense_categories WHERE id_company = p_id_company) THEN
        RETURN 0;
    END IF;

    INSERT INTO public.agri_expense_categories (id_company, category_code, category_name, sort_order)
    SELECT p_id_company, v.code, v.name, v.sort_order
      FROM (VALUES
          ('FERTILIZANTES',            'Fertilizantes',               10),
          ('AGROQUIMICOS',             'Agroquímicos',                20),
          ('SEMILLAS_PLANTULAS',       'Semillas y plántulas',        30),
          ('MANO_OBRA',                'Mano de obra',                40),
          ('COMBUSTIBLE',              'Combustible',                 50),
          ('MANTENIMIENTO_MAQUINARIA', 'Mantenimiento de maquinaria', 60),
          ('HERRAMIENTAS_EQUIPO',      'Herramientas y equipo',       70),
          ('FLETES_TRANSPORTE',        'Fletes y transporte',         80),
          ('RENTA_TIERRA',             'Renta de tierra',             90),
          ('RIEGO',                    'Riego',                      100),
          ('SERVICIOS_DRON_ASPERSION', 'Servicios (dron/aspersión)', 110),
          ('GASTOS_ADMINISTRATIVOS',   'Gastos administrativos',     120),
          ('OTROS',                    'Otros',                      130)
      ) AS v(code, name, sort_order);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$$;
COMMENT ON FUNCTION public.fn_agri_seed_expense_categories(integer) IS
  'Seeds the 13 initial expense categories of a company that has none (idempotent). Called by trg_agri_plantations_seed_expense_categories.';

CREATE OR REPLACE FUNCTION public.fn_agri_plantation_seed_expense_categories()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.fn_agri_seed_expense_categories(NEW.id_company);
    RETURN NULL;
END;
$$;

-- 6) Guards ----------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_agri_expense_category_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_company_active boolean;
BEGIN
    NEW.category_code := upper(btrim(NEW.category_code));
    NEW.category_name := btrim(NEW.category_name);

    IF TG_OP = 'UPDATE' THEN
        IF NEW.id_company IS DISTINCT FROM OLD.id_company THEN
            RAISE EXCEPTION 'La empresa de una categoría no se puede cambiar.' USING ERRCODE = 'P0082';
        END IF;
        IF NEW.category_code IS DISTINCT FROM OLD.category_code THEN
            RAISE EXCEPTION 'La clave de una categoría no se puede cambiar: desactívala y crea otra.'
                USING ERRCODE = 'P0082';
        END IF;
    END IF;

    -- Creating or reactivating requires an active company.
    IF NEW.is_active AND (TG_OP = 'INSERT' OR NOT OLD.is_active) THEN
        SELECT c.is_active INTO v_company_active FROM public.companys c WHERE c.id_company = NEW.id_company;
        IF v_company_active IS FALSE THEN
            RAISE EXCEPTION 'La empresa está inactiva: no se pueden registrar ni reactivar categorías.'
                USING ERRCODE = 'P0081';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- Validates every new expense whatever the path (procedure or direct SQL); the role is checked by the
-- procedure. An expense is never modified, except the void transition made by sp_agri_void_expense.
CREATE OR REPLACE FUNCTION public.fn_agri_expense_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_parent record;
BEGIN
    IF TG_OP IN ('DELETE', 'TRUNCATE') THEN
        RAISE EXCEPTION 'Los gastos no se borran: se anulan con un motivo.' USING ERRCODE = 'P0090';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF public.fn_agri_setting('app.agri_expense_void') IS DISTINCT FROM 'on'
           OR OLD.is_void OR NOT NEW.is_void
           OR (to_jsonb(NEW) - ARRAY['is_void', 'void_reason', 'voided_by_email', 'voided_at'])
              IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['is_void', 'void_reason', 'voided_by_email', 'voided_at']) THEN
            RAISE EXCEPTION 'Un gasto registrado no se modifica: anúlalo y captúralo de nuevo.' USING ERRCODE = 'P0090';
        END IF;
        RETURN NEW;
    END IF;

    -- INSERT
    IF NEW.is_void THEN
        RAISE EXCEPTION 'Un gasto no se puede registrar ya anulado.' USING ERRCODE = 'P0092';
    END IF;
    IF NEW.lot_id IS NOT NULL AND NEW.plantation_id IS NULL THEN
        RAISE EXCEPTION 'Un gasto por lote debe indicar también la plantación.' USING ERRCODE = 'P0092';
    END IF;

    IF NEW.plantation_id IS NOT NULL THEN
        SELECT p.id_company, p.is_active INTO v_parent FROM public.agri_plantations p WHERE p.id = NEW.plantation_id;
        IF NOT FOUND OR v_parent.id_company IS DISTINCT FROM NEW.id_company THEN
            RAISE EXCEPTION 'La plantación no existe o no pertenece a la empresa activa.' USING ERRCODE = 'P0080';
        END IF;
        IF NOT v_parent.is_active THEN
            RAISE EXCEPTION 'La plantación está inactiva: no se le pueden registrar gastos.' USING ERRCODE = 'P0081';
        END IF;
    END IF;

    IF NEW.lot_id IS NOT NULL THEN
        SELECT l.id_company, l.plantation_id, l.is_active INTO v_parent FROM public.agri_lots l WHERE l.id = NEW.lot_id;
        IF NOT FOUND OR v_parent.id_company IS DISTINCT FROM NEW.id_company THEN
            RAISE EXCEPTION 'El lote no existe o no pertenece a la empresa activa.' USING ERRCODE = 'P0080';
        END IF;
        IF v_parent.plantation_id IS DISTINCT FROM NEW.plantation_id THEN
            RAISE EXCEPTION 'El lote no pertenece a la plantación indicada.' USING ERRCODE = 'P0080';
        END IF;
        IF NOT v_parent.is_active THEN
            RAISE EXCEPTION 'El lote está inactivo: no se le pueden registrar gastos.' USING ERRCODE = 'P0081';
        END IF;
    END IF;

    SELECT c.id_company, c.is_active INTO v_parent FROM public.agri_expense_categories c WHERE c.id = NEW.category_id;
    IF NOT FOUND OR v_parent.id_company IS DISTINCT FROM NEW.id_company THEN
        RAISE EXCEPTION 'La categoría no existe o no pertenece a la empresa activa.' USING ERRCODE = 'P0080';
    END IF;
    IF NOT v_parent.is_active THEN
        RAISE EXCEPTION 'La categoría está dada de baja.' USING ERRCODE = 'P0092';
    END IF;

    IF NEW.unit_code IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.agri_unit_catalog u WHERE u.unit_code = NEW.unit_code AND u.is_active) THEN
        RAISE EXCEPTION 'La unidad de medida no existe o está dada de baja.' USING ERRCODE = 'P0092';
    END IF;

    IF NEW.expense_date > public.fn_agri_today_cdmx() THEN
        RAISE EXCEPTION 'La fecha del gasto no puede ser futura.' USING ERRCODE = 'P0083';
    END IF;
    RETURN NEW;
END;
$$;

-- Triggers (created once; CREATE OR REPLACE FUNCTION above keeps them current on re-run). The seeding
-- trigger is (re-)enabled explicitly: 081_rollback.sql disables it instead of dropping it.
DO $$
DECLARE
    t record;
BEGIN
    FOR t IN
        SELECT * FROM (VALUES
            ('trg_agri_plantations_seed_expense_categories', 'agri_plantations',        'AFTER INSERT',              'ROW',       'fn_agri_plantation_seed_expense_categories'),
            ('trg_agri_expense_categories_guard',            'agri_expense_categories', 'BEFORE INSERT OR UPDATE',   'ROW',       'fn_agri_expense_category_guard'),
            ('trg_agri_expense_categories_updated_at',       'agri_expense_categories', 'BEFORE UPDATE',             'ROW',       'fn_agri_set_updated_at'),
            ('trg_agri_expenses_guard',                      'agri_expenses',           'BEFORE INSERT OR UPDATE OR DELETE', 'ROW', 'fn_agri_expense_guard'),
            ('trg_agri_expenses_no_truncate',                'agri_expenses',           'BEFORE TRUNCATE',           'STATEMENT', 'fn_agri_expense_guard')
        ) AS v(tgname, tbl, timing, level, fn)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger
                        WHERE tgname = t.tgname AND tgrelid = ('public.' || t.tbl)::regclass) THEN
            EXECUTE format('CREATE TRIGGER %I %s ON public.%I FOR EACH %s EXECUTE FUNCTION public.%I()',
                           t.tgname, t.timing, t.tbl, t.level, t.fn);
        END IF;
    END LOOP;
END $$;
ALTER TABLE public.agri_plantations ENABLE TRIGGER trg_agri_plantations_seed_expense_categories;

-- Initial categories for the companies that already have a plantation (only those: a company without a
-- plantation receives them with its first one).
DO $$
DECLARE
    r record;
    v_n integer;
BEGIN
    FOR r IN SELECT DISTINCT id_company FROM public.agri_plantations ORDER BY id_company LOOP
        v_n := public.fn_agri_seed_expense_categories(r.id_company);
        RAISE NOTICE '081: company % -> % categories seeded', r.id_company, v_n;
    END LOOP;
END $$;

-- 7) Procedures -----------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_agri_record_expense(
    p_tenant_id      integer,
    p_plantation_id  uuid,
    p_lot_id         uuid,
    p_category_id    uuid,
    p_expense_date   date,
    p_amount         numeric,
    p_quantity       numeric,
    p_unit_code      varchar,
    p_supplier_name  varchar,
    p_description    text,
    p_is_invoiced    boolean,
    p_invoice_folio  varchar,
    p_actor_email    varchar
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    c_max_amount   constant numeric := 9999999999.99;
    c_max_quantity constant numeric := 999999999.999;
    v_role         text := public.fn_agri_actor_role(p_tenant_id, p_actor_email);
    v_actor        text := lower(btrim(coalesce(p_actor_email, '')));
    v_date         date := coalesce(p_expense_date, public.fn_agri_today_cdmx());
    v_unit         text := NULLIF(upper(btrim(coalesce(p_unit_code, ''))), '');
    v_folio        text := NULLIF(btrim(coalesce(p_invoice_folio, '')), '');
    v_invoiced     boolean := coalesce(p_is_invoiced, false);
    v_plantation   uuid := p_plantation_id;
    v_lot          record;
    v_id           uuid;
BEGIN
    -- Field operation: the foreman (EDITOR) captures expenses (event authorization matrix); CUSTOMER cannot.
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'OWNER', 'EDITOR') THEN
        RAISE EXCEPTION 'Tu rol en la empresa no permite registrar gastos.' USING ERRCODE = 'P0084';
    END IF;
    IF public.fn_company_business_domain(p_tenant_id) IS DISTINCT FROM 'PALM' THEN
        RAISE EXCEPTION 'La empresa activa no es de palma: los gastos agrícolas solo se registran en empresas de palma.'
            USING ERRCODE = 'P0093';
    END IF;

    IF p_category_id IS NULL THEN
        RAISE EXCEPTION 'La categoría del gasto es obligatoria.' USING ERRCODE = 'P0092';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > c_max_amount OR p_amount <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'El monto debe ser mayor que 0, con máximo 2 decimales.' USING ERRCODE = 'P0092';
    END IF;
    IF (p_quantity IS NULL) <> (v_unit IS NULL) THEN
        RAISE EXCEPTION 'La cantidad y la unidad de medida van juntas: captura ambas o ninguna.' USING ERRCODE = 'P0092';
    END IF;
    IF p_quantity IS NOT NULL AND (p_quantity <= 0 OR p_quantity > c_max_quantity OR p_quantity <> round(p_quantity, 3)) THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que 0, con máximo 3 decimales.' USING ERRCODE = 'P0092';
    END IF;
    IF v_folio IS NOT NULL AND NOT v_invoiced THEN
        RAISE EXCEPTION 'El folio de factura solo se captura cuando el gasto está facturado.' USING ERRCODE = 'P0092';
    END IF;
    IF v_date > public.fn_agri_today_cdmx() THEN
        RAISE EXCEPTION 'La fecha del gasto no puede ser futura.' USING ERRCODE = 'P0083';
    END IF;

    -- Only the lot given: the expense goes to the lot's plantation. Both given: the guard checks they match.
    IF p_lot_id IS NOT NULL AND v_plantation IS NULL THEN
        SELECT l.plantation_id INTO v_lot FROM public.agri_lots l WHERE l.id = p_lot_id AND l.id_company = p_tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El lote no existe o no pertenece a la empresa activa.' USING ERRCODE = 'P0080';
        END IF;
        v_plantation := v_lot.plantation_id;
    END IF;

    -- trg_agri_expenses_guard validates company, parents, category, unit and date of the row.
    INSERT INTO public.agri_expenses
        (id_company, plantation_id, lot_id, category_id, expense_date, amount, quantity, unit_code,
         supplier_name, description, is_invoiced, invoice_folio, reported_by_email)
    VALUES
        (p_tenant_id, v_plantation, p_lot_id, p_category_id, v_date, p_amount, p_quantity, v_unit,
         NULLIF(btrim(coalesce(p_supplier_name, '')), ''), NULLIF(btrim(coalesce(p_description, '')), ''),
         v_invoiced, v_folio, v_actor)
    RETURNING id INTO v_id;

    -- No amounts in the answer: the EDITOR does not read amounts (only "Gasto registrado").
    RETURN jsonb_build_object('success', true, 'expense_id', v_id, 'expense_date', v_date,
                              'plantation_id', v_plantation, 'lot_id', p_lot_id);
END;
$$;
COMMENT ON FUNCTION public.sp_agri_record_expense(integer, uuid, uuid, uuid, date, numeric, numeric, varchar, varchar, text, boolean, varchar, varchar) IS
  'Records an agricultural expense (ADMIN/OWNER/EDITOR of a palm company); actor from the JWT. Errors: P0080, P0081, P0083, P0084, P0092, P0093.';

CREATE OR REPLACE FUNCTION public.sp_agri_void_expense(
    p_tenant_id    integer,
    p_expense_id   uuid,
    p_reason       text,
    p_actor_email  varchar
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_role     text := public.fn_agri_actor_role(p_tenant_id, p_actor_email);
    v_actor    text := lower(btrim(coalesce(p_actor_email, '')));
    v_reason   text := NULLIF(btrim(coalesce(p_reason, '')), '');
    v_expense  record;
BEGIN
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'OWNER') THEN
        RAISE EXCEPTION 'Solo un administrador de la empresa puede anular gastos.' USING ERRCODE = 'P0084';
    END IF;
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'El motivo de la anulación es obligatorio.' USING ERRCODE = 'P0091';
    END IF;

    SELECT id, is_void INTO v_expense
      FROM public.agri_expenses WHERE id = p_expense_id AND id_company = p_tenant_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El gasto no existe o no pertenece a la empresa activa.' USING ERRCODE = 'P0080';
    END IF;
    IF v_expense.is_void THEN
        RAISE EXCEPTION 'El gasto ya estaba anulado.' USING ERRCODE = 'P0091';
    END IF;

    PERFORM set_config('app.agri_expense_void', 'on', true);
    UPDATE public.agri_expenses
       SET is_void = true, void_reason = v_reason, voided_by_email = v_actor, voided_at = public.fn_agri_utc_now()
     WHERE id = p_expense_id;
    PERFORM set_config('app.agri_expense_void', '', true);

    RETURN jsonb_build_object('success', true, 'expense_id', p_expense_id);
END;
$$;
COMMENT ON FUNCTION public.sp_agri_void_expense(integer, uuid, text, varchar) IS
  'Voids an agricultural expense with a reason (ADMIN/OWNER); the only allowed change of an expense. Errors: P0080, P0084, P0091.';

-- Totals of any filter combination for the balance screen and the dashboard card (ADMIN/OWNER). Voided
-- expenses are excluded. Defaults: current month (America/Mexico_City), grain MONTH. by_period lists every
-- period of the range, with zeros, oldest first; WEEK periods are ISO weeks (Monday).
CREATE OR REPLACE FUNCTION public.sp_agri_expense_balance(
    p_tenant_id      integer,
    p_date_from      date,
    p_date_to        date,
    p_grain          varchar,
    p_plantation_id  uuid,
    p_lot_id         uuid,
    p_category_id    uuid,
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
    v_step          interval;
    v_lot           record;
    v_result        jsonb;
BEGIN
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'OWNER') THEN
        RAISE EXCEPTION 'Solo un administrador de la empresa puede consultar el balance de gastos.' USING ERRCODE = 'P0084';
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

    -- Filters must belong to the company (never says who owns them).
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
    IF p_category_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.agri_expense_categories WHERE id = p_category_id AND id_company = p_tenant_id) THEN
        RAISE EXCEPTION 'La categoría no existe o no pertenece a la empresa activa.' USING ERRCODE = 'P0080';
    END IF;

    v_step := CASE v_grain WHEN 'DAY' THEN interval '1 day' WHEN 'WEEK' THEN interval '1 week'
                           WHEN 'MONTH' THEN interval '1 month' ELSE interval '1 year' END;

    WITH f AS (
        SELECT e.*, date_trunc(lower(v_grain), e.expense_date::timestamp)::date AS period_start
          FROM public.agri_expenses e
         WHERE e.id_company = p_tenant_id
           AND NOT e.is_void
           AND e.expense_date BETWEEN v_from AND v_to
           AND (p_plantation_id IS NULL OR e.plantation_id = p_plantation_id)
           AND (p_lot_id IS NULL OR e.lot_id = p_lot_id)
           AND (p_category_id IS NULL OR e.category_id = p_category_id)
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
        'total_amount',   (SELECT coalesce(sum(amount), 0) FROM f),
        'expense_count',  (SELECT count(*) FROM f),
        'general_amount', (SELECT coalesce(sum(amount), 0) FROM f WHERE plantation_id IS NULL),
        'by_period', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'period_start', p.period_start, 'period_end', p.period_end,
                       'total_amount', coalesce(x.total, 0), 'expense_count', coalesce(x.n, 0))
                   ORDER BY p.period_start), '[]'::jsonb)
              FROM periods p
              LEFT JOIN (SELECT period_start, sum(amount) AS total, count(*) AS n FROM f GROUP BY 1) x
                ON x.period_start = p.period_start),
        'by_category', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'category_id', c.id, 'category_code', c.category_code, 'category_name', c.category_name,
                       'total_amount', x.total, 'expense_count', x.n)
                   ORDER BY x.total DESC, c.sort_order), '[]'::jsonb)
              FROM (SELECT category_id, sum(amount) AS total, count(*) AS n FROM f GROUP BY 1) x
              JOIN public.agri_expense_categories c ON c.id = x.category_id AND c.id_company = p_tenant_id),
        'by_plantation', (
            -- plantation_id NULL = general expenses of the company.
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'plantation_id', x.plantation_id, 'plantation_code', p.plantation_code,
                       'plantation_name', p.plantation_name, 'total_amount', x.total, 'expense_count', x.n)
                   ORDER BY x.total DESC), '[]'::jsonb)
              FROM (SELECT plantation_id, sum(amount) AS total, count(*) AS n FROM f GROUP BY 1) x
              LEFT JOIN public.agri_plantations p ON p.id = x.plantation_id AND p.id_company = p_tenant_id),
        'by_lot', (
            -- Only expenses assigned to a lot; plantation-level and general expenses are not split by lot.
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'lot_id', x.lot_id, 'lot_code', l.lot_code, 'lot_name', l.lot_name,
                       'plantation_id', l.plantation_id, 'total_amount', x.total, 'expense_count', x.n)
                   ORDER BY x.total DESC), '[]'::jsonb)
              FROM (SELECT lot_id, sum(amount) AS total, count(*) AS n FROM f WHERE lot_id IS NOT NULL GROUP BY 1) x
              JOIN public.agri_lots l ON l.id = x.lot_id AND l.id_company = p_tenant_id)
    ) INTO v_result;

    RETURN v_result;
END;
$$;
COMMENT ON FUNCTION public.sp_agri_expense_balance(integer, date, date, varchar, uuid, uuid, uuid, varchar) IS
  'Expense totals of a company for a range and filters (ADMIN/OWNER), voided excluded: total, general, by period / category / plantation / lot. Errors: P0080, P0084, P0092.';

-- 8) Views (id_company and created_at are required by the gateway) ------------------------------------------

CREATE OR REPLACE VIEW public.vw_agri_expense_list AS
SELECT
    e.id,
    e.id_company,
    e.plantation_id,
    p.plantation_code,
    p.plantation_name,
    e.lot_id,
    l.lot_code,
    l.lot_name,
    e.category_id,
    c.category_code,
    c.category_name,
    e.expense_date,
    e.amount,
    e.quantity,
    e.unit_code,
    u.unit_name,
    e.supplier_name,
    e.description,
    e.is_invoiced,
    e.invoice_folio,
    e.receipt_url,
    e.reported_by_email,
    e.is_void,
    e.void_reason,
    e.voided_by_email,
    e.voided_at,
    e.created_at
FROM public.agri_expenses e
JOIN public.agri_expense_categories c ON c.id = e.category_id AND c.id_company = e.id_company
LEFT JOIN public.agri_plantations p ON p.id = e.plantation_id AND p.id_company = e.id_company
LEFT JOIN public.agri_lots l ON l.id = e.lot_id AND l.id_company = e.id_company
LEFT JOIN public.agri_unit_catalog u ON u.unit_code = e.unit_code;

-- One row per grain (DAY / WEEK ISO / MONTH / YEAR) x period x plantation x lot x category, voided excluded.
-- plantation_id NULL = general expense; lot_id NULL = plantation-level (or general) expense.
-- expense_date is already the business date in America/Mexico_City. created_at = latest capture of the group.
CREATE OR REPLACE VIEW public.vw_agri_expense_summary AS
SELECT
    md5(concat_ws('|', e.id_company, g.grain, g.period_start, e.plantation_id, e.lot_id, e.category_id)) AS id,
    e.id_company,
    g.grain,
    g.period_start,
    g.period_end,
    e.plantation_id,
    p.plantation_code,
    p.plantation_name,
    e.lot_id,
    l.lot_code,
    l.lot_name,
    e.category_id,
    c.category_code,
    c.category_name,
    sum(e.amount)        AS total_amount,
    count(*)::integer    AS expense_count,
    max(e.created_at)    AS created_at
FROM public.agri_expenses e
CROSS JOIN LATERAL (VALUES
    ('DAY',   e.expense_date,                                e.expense_date),
    ('WEEK',  date_trunc('week',  e.expense_date::timestamp)::date, (date_trunc('week',  e.expense_date::timestamp) + interval '6 days')::date),
    ('MONTH', date_trunc('month', e.expense_date::timestamp)::date, (date_trunc('month', e.expense_date::timestamp) + interval '1 month' - interval '1 day')::date),
    ('YEAR',  date_trunc('year',  e.expense_date::timestamp)::date, (date_trunc('year',  e.expense_date::timestamp) + interval '1 year' - interval '1 day')::date)
) AS g(grain, period_start, period_end)
JOIN public.agri_expense_categories c ON c.id = e.category_id AND c.id_company = e.id_company
LEFT JOIN public.agri_plantations p ON p.id = e.plantation_id AND p.id_company = e.id_company
LEFT JOIN public.agri_lots l ON l.id = e.lot_id AND l.id_company = e.id_company
WHERE NOT e.is_void
GROUP BY e.id_company, g.grain, g.period_start, g.period_end, e.plantation_id, p.plantation_code, p.plantation_name,
         e.lot_id, l.lot_code, l.lot_name, e.category_id, c.category_code, c.category_name;

-- 9) crud_models (upsert; no model has `id` in allowed_fields, none has DELETE) ----------------------------

INSERT INTO crud_models (model_name, table_name, primary_key, allowed_fields, default_filter, schema_json,
                         allowed_ops, hooks, allowed_roles_select, allowed_roles_insert, allowed_roles_update,
                         allowed_roles_delete, joins, is_global, sp_requires_tenant)
VALUES
  -- Global and read-only: grows only through migrations.
  ('agri_unit_catalog', 'agri_unit_catalog', 'id',
   '["unit_code","unit_name","sort_order","is_active"]', NULL, '{}',
   '{SELECT,GETONE,GETALL}', '{"pre":[],"post":[]}',
   'ADMIN,OWNER,EDITOR,CUSTOMER', 'NONE', 'NONE', 'NONE', '[]', true, true),
  -- EDITOR reads the catalog to capture; only ADMIN / OWNER maintain it.
  ('agri_expense_categories', 'agri_expense_categories', 'id',
   '["id_company","category_code","category_name","sort_order","is_active"]', NULL, '{}',
   '{SELECT,GETONE,GETALL,INSERT,UPDATE}', '{"pre":[],"post":[]}',
   'ADMIN,OWNER,EDITOR', 'ADMIN,OWNER', 'ADMIN,OWNER', 'NONE', '[]', false, true),
  -- Amounts: read by ADMIN / OWNER only. Writes only through the procedures below.
  ('agri_expenses', 'vw_agri_expense_list', 'id',
   '["id_company","plantation_id","lot_id","category_id","expense_date","unit_code","is_invoiced","is_void"]', NULL, '{}',
   '{SELECT,GETONE,GETALL}', '{"pre":[],"post":[]}',
   'ADMIN,OWNER', 'NONE', 'NONE', 'NONE', '[]', false, true),
  ('agri_expense_summary', 'vw_agri_expense_summary', 'id',
   '["id_company","grain","period_start","plantation_id","lot_id","category_id"]', NULL, '{}',
   '{SELECT,GETONE,GETALL}', '{"pre":[],"post":[]}',
   'ADMIN,OWNER', 'NONE', 'NONE', 'NONE', '[]', false, true),
  ('agri_record_expense', 'sp_agri_record_expense', 'category_id',
   '["plantation_id","lot_id","category_id","expense_date","amount","quantity","unit_code","supplier_name","description","is_invoiced","invoice_folio","actor_email"]',
   NULL, '{}', '{INSERT}', '{"pre":[],"post":[]}',
   'NONE', 'ADMIN,OWNER,EDITOR', 'NONE', 'NONE', '[]', false, true),
  ('agri_void_expense', 'sp_agri_void_expense', 'expense_id',
   '["expense_id","reason","actor_email"]',
   NULL, '{}', '{INSERT}', '{"pre":[],"post":[]}',
   'NONE', 'ADMIN,OWNER', 'NONE', 'NONE', '[]', false, true),
  -- A read, but call_sp is validated as INSERT by the gateway.
  ('agri_expense_balance', 'sp_agri_expense_balance', 'date_from',
   '["date_from","date_to","grain","plantation_id","lot_id","category_id","actor_email"]',
   NULL, '{}', '{INSERT}', '{"pre":[],"post":[]}',
   'NONE', 'ADMIN,OWNER', 'NONE', 'NONE', '[]', false, true)
ON CONFLICT (model_name) DO UPDATE SET
    table_name = EXCLUDED.table_name, primary_key = EXCLUDED.primary_key,
    allowed_fields = EXCLUDED.allowed_fields, default_filter = EXCLUDED.default_filter,
    schema_json = EXCLUDED.schema_json, allowed_ops = EXCLUDED.allowed_ops, hooks = EXCLUDED.hooks,
    allowed_roles_select = EXCLUDED.allowed_roles_select, allowed_roles_insert = EXCLUDED.allowed_roles_insert,
    allowed_roles_update = EXCLUDED.allowed_roles_update, allowed_roles_delete = EXCLUDED.allowed_roles_delete,
    joins = EXCLUDED.joins, is_global = EXCLUDED.is_global, sp_requires_tenant = EXCLUDED.sp_requires_tenant;

-- 10) Checks ---------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_models text[] := ARRAY['agri_unit_catalog', 'agri_expense_categories', 'agri_expenses', 'agri_expense_summary',
                             'agri_record_expense', 'agri_void_expense', 'agri_expense_balance'];
    v_n integer;
BEGIN
    SELECT count(*) INTO v_n FROM pg_class
     WHERE relnamespace = 'public'::regnamespace
       AND relname IN ('agri_unit_catalog', 'agri_expense_categories', 'agri_expenses',
                       'vw_agri_expense_list', 'vw_agri_expense_summary');
    IF v_n <> 5 THEN RAISE EXCEPTION '081: expected 3 tables + 2 views, found %', v_n; END IF;

    SELECT count(*) INTO v_n FROM pg_trigger
     WHERE NOT tgisinternal AND tgenabled <> 'D'
       AND tgname IN ('trg_agri_plantations_seed_expense_categories', 'trg_agri_expense_categories_guard',
                      'trg_agri_expense_categories_updated_at', 'trg_agri_expenses_guard', 'trg_agri_expenses_no_truncate');
    IF v_n <> 5 THEN RAISE EXCEPTION '081: expected 5 enabled triggers, found %', v_n; END IF;

    SELECT count(*) INTO v_n FROM agri_unit_catalog
     WHERE unit_code IN ('KG', 'TON', 'L', 'PZA', 'BULTO', 'JORNAL', 'HA', 'VIAJE', 'SERVICIO');
    IF v_n <> 9 THEN RAISE EXCEPTION '081: unit seed incomplete (%)', v_n; END IF;

    IF EXISTS (SELECT 1 FROM (SELECT DISTINCT id_company FROM agri_plantations) p
                WHERE NOT EXISTS (SELECT 1 FROM agri_expense_categories c WHERE c.id_company = p.id_company)) THEN
        RAISE EXCEPTION '081: a company with a plantation has no expense categories';
    END IF;

    SELECT count(*) INTO v_n FROM crud_models WHERE model_name = ANY (v_models) AND cardinality(allowed_ops) > 0;
    IF v_n <> 7 THEN RAISE EXCEPTION '081: expected 7 enabled models, found %', v_n; END IF;

    IF EXISTS (SELECT 1 FROM crud_models WHERE model_name = ANY (v_models)
                AND (allowed_fields ? 'id' OR 'DELETE' = ANY (allowed_ops))) THEN
        RAISE EXCEPTION '081: a model exposes id in allowed_fields or allows DELETE';
    END IF;
    RAISE NOTICE '081: OK';
END $$;

\if :{?embedded}
\echo '*** 081 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 081 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
