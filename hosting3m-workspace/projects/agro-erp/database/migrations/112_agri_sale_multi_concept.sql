-- 112_agri_sale_multi_concept.sql
-- Palm sales from a CFDI voucher: one sale per voucher may carry several concepts (for example one per weighing ticket) and the concept unit may be
-- kilograms (KGM) or tonnes (TNE). Database layer only: no n8n, no frontend, no cfdi-service change, no crud_models change.
-- REQUIRES 104 and 105 (agri_sale_invoices, sp_agri_register_sale, vw_agri_sale_list, vw_agri_sale_ui_list). Aborts if missing.
--
-- What changes
--   agri_sale_invoices      two additive columns: concept_count (smallint, default 1) and ticket_detail (jsonb, NULL). Existing rows are not updated
--                           (the table guard forbids it): they keep concept_count = 1 and ticket_detail NULL. One new BEFORE INSERT trigger checks the
--                           detail against the row (kilograms, amounts, tickets).
--   sp_agri_register_sale   same signature (integer, text, jsonb, text, text, text), same privileges and attributes, replaced in place.
--   vw_agri_sale_list, vw_agri_sale_ui_list   two columns appended at the end (concept_count, ticket_detail). For rows without a stored detail the
--                           view builds a one-element detail from the existing columns, so every consumer can read the detail of every sale.
--   Nothing else is altered: no table is dropped, the void procedure, the balance procedure and vw_agri_sale_summary are untouched.
--
-- Voucher rules (jsonb produced by cfdi-service with the sale profile; reason codes are answers, never exceptions)
--   Concepts          1 to 10 (CONCEPT_COUNT otherwise). All concepts must have the same ClaveProdServ (PRODUCT_KEY_MIXED) and the same ClaveUnidad
--                     (UNIT_MIXED); the unit must be KGM or TNE (UNIT otherwise). Quantity and unit price are positive decimals with up to 6 decimals.
--   Tonnes            TNE is converted to kilograms with exact numeric arithmetic (x 1000); the stored quantity is always in kilograms and unit_code stays
--                     KGM. The original unit, quantity and unit price are kept in ticket_detail.
--   Quantity          the sum of the kilograms of all concepts (stored in agri_sale_invoices.quantity, below 10^12).
--   Amounts           totals come from the voucher as issued. Per concept: |round(kilograms x price per kilogram x 100) - concept amount| <= 1 cent
--                     (AMOUNTS_MISMATCH_CONCEPT). Voucher level: |sum of concept amounts - subtotal| <= (n - 1) cents for n concepts, because each concept
--                     amount is rounded to cents on its own while the voucher subtotal is rounded once: exact for one concept (AMOUNTS_MISMATCH_CONCEPT, as
--                     before), 1 cent for two, 2 cents for three (AMOUNTS_MISMATCH_SUBTOTAL). subtotal - discount + taxes = total stays exact to the cent.
--   Price per kilogram informational: for one KGM concept the voucher unit price (as before); otherwise round(subtotal / kilograms, 6), before taxes.
--   Tickets           a ticket reference "(ticket N)" is read from each concept description. It is OPTIONAL: a concept without exactly one recognizable
--                     reference gets no ticket and the sale is stored with ticket_warning = true (the sale is not refused). The same ticket twice inside one
--                     voucher is refused (TICKET_DUPLICATE). ticket_ref holds the first ticket of the voucher; ticket_detail holds all of them.
--   Idempotency       unchanged: one ACTIVE row per (company, voucher uuid); a second load answers ALREADY_REGISTERED.
-- Answer 'summary' keeps its keys and adds concept_count, tickets and source_unit.
--
-- DRIFT GUARD: sp_agri_register_sale is replaced only if its live text is the one of the repository (md5 of pg_get_functiondef, constants below) or already the
-- 112 text (re-running replaces it with the same text). If production differs, the migration aborts instead of overwriting something unknown.
-- Rollback: 112_rollback.sql (restores the exact 104 procedure; nothing is dropped). State: 112_state_check.sql. Tests: 112_tests.sql.
-- Usage:   psql -X -v ON_ERROR_STOP=1 -f 112_agri_sale_multi_concept.sql                (dry run: ROLLBACK)
--          psql -X -v ON_ERROR_STOP=1 -v apply=true -f 112_agri_sale_multi_concept.sql  (COMMIT)

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
    v_md5   text;
    v_cols  text;
    c_base_list text := 'id,id_company,uuid,cfdi_folio,issued_at,sale_date,buyer_name,buyer_rfc,quantity,unit_code,unit_price,subtotal_amount,discount_amount,total_amount,payment_form,payment_method,ticket_ref,ticket_warning,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,sat_status,is_test,status,void_reason,voided_by_email,voided_at,registered_by_email,created_at';
    c_base_ui   text := 'id,id_company,folio,sale_date,buyer_name,quantity,unit_code,unit_price,total_amount,payment_method,ticket_ref,ticket_warning,plantation_id,plantation_code,plantation_name,lot_id,lot_code,lot_name,status,void_reason,voided_at,is_test,created_at';
BEGIN
    IF to_regclass('public.agri_sale_invoices') IS NULL
       OR to_regprocedure('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)') IS NULL
       OR to_regclass('public.vw_agri_sale_list') IS NULL THEN
        RAISE EXCEPTION 'ABORT 112: migration 104 must be applied first.';
    END IF;
    IF to_regclass('public.vw_agri_sale_ui_list') IS NULL THEN
        RAISE EXCEPTION 'ABORT 112: migration 105 (vw_agri_sale_ui_list) must be applied first.';
    END IF;
    v_md5 := md5(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure));
    IF v_md5 NOT IN ('425229fb6036884d5c5dcd7527d7c674', '83a5d0a7bad97dcfe1372aa4db961d49') THEN
        RAISE EXCEPTION 'ABORT 112 (drift): sp_agri_register_sale is not the repository 104 text nor the 112 text (md5 %). Nothing was changed.', v_md5;
    END IF;
    SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_cols
      FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_list';
    IF v_cols NOT IN (c_base_list, c_base_list || ',concept_count,ticket_detail') THEN
        RAISE EXCEPTION 'ABORT 112 (drift): unexpected columns in vw_agri_sale_list: %', v_cols;
    END IF;
    SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_cols
      FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vw_agri_sale_ui_list';
    IF v_cols NOT IN (c_base_ui, c_base_ui || ',concept_count,ticket_detail') THEN
        RAISE EXCEPTION 'ABORT 112 (drift): unexpected columns in vw_agri_sale_ui_list: %', v_cols;
    END IF;
END $$;

-- 1) Additive columns and constraints ----------------------------------------------------------------------

ALTER TABLE public.agri_sale_invoices ADD COLUMN IF NOT EXISTS concept_count smallint NOT NULL DEFAULT 1;
ALTER TABLE public.agri_sale_invoices ADD COLUMN IF NOT EXISTS ticket_detail jsonb;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_agri_sale_invoices_concept_count' AND conrelid = 'public.agri_sale_invoices'::regclass) THEN
        ALTER TABLE public.agri_sale_invoices ADD CONSTRAINT ck_agri_sale_invoices_concept_count CHECK (concept_count BETWEEN 1 AND 10);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_agri_sale_invoices_ticket_detail' AND conrelid = 'public.agri_sale_invoices'::regclass) THEN
        ALTER TABLE public.agri_sale_invoices ADD CONSTRAINT ck_agri_sale_invoices_ticket_detail
            CHECK (ticket_detail IS NULL OR (jsonb_typeof(ticket_detail) = 'array' AND jsonb_array_length(ticket_detail) = concept_count));
    END IF;
END $$;
COMMENT ON COLUMN public.agri_sale_invoices.concept_count IS
  '112: number of concepts of the voucher (1 to 10). Rows registered before 112 keep 1.';
COMMENT ON COLUMN public.agri_sale_invoices.ticket_detail IS
  '112: informational detail per concept, in voucher order: n, ticket (or null), unit (KGM or TNE), qty (as in the voucher), kg, unit_price (per voucher unit), amount_cents. NULL for rows registered before 112 (the views build it from the row columns).';

-- 2) Insert guard for the detail (defence in depth; the procedure already validated everything) ------------------
-- An element without kg or without amount_cents counts as invalid (it is not ignored in the sums). Privileges follow the other trigger functions of
-- 104 (no explicit GRANT or REVOKE; a function that returns trigger cannot be called as a procedure); 112_tests.sql compares owner, ACL and attributes.

CREATE OR REPLACE FUNCTION public.fn_trg_agri_sale_invoices_detail_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_n      integer;
    v_kg     numeric;
    v_cents  bigint;
    v_tix    integer;
    v_dist   integer;
    v_bad    integer;
BEGIN
    IF NEW.ticket_detail IS NULL THEN
        IF NEW.concept_count <> 1 THEN
            RAISE EXCEPTION 'A sale with several concepts needs its detail.' USING ERRCODE = 'P0110';
        END IF;
        RETURN NEW;
    END IF;
    BEGIN
        v_n := jsonb_array_length(NEW.ticket_detail);
        SELECT coalesce(sum((d ->> 'kg')::numeric), 0), coalesce(sum((d ->> 'amount_cents')::bigint), 0),
               count(*) FILTER (WHERE nullif(d ->> 'ticket', '') IS NOT NULL),
               count(DISTINCT upper(nullif(d ->> 'ticket', ''))),
               count(*) FILTER (WHERE jsonb_typeof(d) <> 'object' OR (d ->> 'kg') IS NULL OR (d ->> 'amount_cents') IS NULL
                                 OR coalesce(d ->> 'unit', '') NOT IN ('KGM', 'TNE') OR (d ->> 'kg')::numeric <= 0
                                 OR (d ->> 'amount_cents')::bigint < 0)
          INTO v_kg, v_cents, v_tix, v_dist, v_bad
          FROM jsonb_array_elements(NEW.ticket_detail) d;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR invalid_parameter_value THEN
        RAISE EXCEPTION 'The sale detail is not valid.' USING ERRCODE = 'P0110';
    END;
    IF v_n <> NEW.concept_count OR v_bad > 0 OR v_kg <> NEW.quantity OR abs(v_cents - NEW.subtotal_cents) > NEW.concept_count - 1 OR v_tix <> v_dist THEN
        RAISE EXCEPTION 'The sale detail does not match the sale.' USING ERRCODE = 'P0110';
    END IF;
    RETURN NEW;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_agri_sale_invoices_detail_guard' AND tgrelid = 'public.agri_sale_invoices'::regclass) THEN
        CREATE TRIGGER trg_agri_sale_invoices_detail_guard BEFORE INSERT ON public.agri_sale_invoices
            FOR EACH ROW EXECUTE FUNCTION public.fn_trg_agri_sale_invoices_detail_guard();
    END IF;
END $$;

-- 3) Registration procedure ---------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_agri_register_sale(
    p_tenant_id integer, p_actor_email text, p_parsed jsonb, p_sat_status text, p_original_path text, p_source_sha256 text
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    -- Oldest accepted voucher date, in days before today (America/Mexico_City). The owner may change this value.
    c_max_age_days constant integer := 365;
    c_max_concepts constant integer := 10;
    c_max_kg       constant numeric := 1000000000000;
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
    v_prods        text[] := '{}';
    v_units        text[] := '{}';
    v_qtys         text[] := '{}';
    v_prices       text[] := '{}';
    v_imps         text[] := '{}';
    v_descs        text[] := '{}';
    v_kgs          numeric[] := '{}';
    v_i            integer;
    v_factor       numeric := 1;
    v_sum_kg       numeric := 0;
    v_sum_imp      bigint := 0;
    v_product      text;
    v_qty          numeric;
    v_price        numeric;
    v_hash_in      text;
    v_sha          text := lower(btrim(coalesce(p_source_sha256, '')));
    v_path         text := btrim(coalesce(p_original_path, ''));
    v_sat_in       text := upper(btrim(coalesce(p_sat_status, '')));
    v_sat          text;
    v_today        date := public.fn_agri_today_cdmx();
    v_tk           text[];
    v_tickets      text[] := '{}';
    v_tickets_up   text[];
    v_ticket       text;
    v_ticket_warn  boolean := false;
    v_detail       jsonb := '[]'::jsonb;
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
        IF v_nconc BETWEEN 1 AND c_max_concepts THEN
            FOR v_i IN 0 .. v_nconc - 1 LOOP
                c := (j -> 'conceptos') -> v_i;
                v_prods  := array_append(v_prods,  c ->> 'claveProdServ');
                v_units  := array_append(v_units,  upper(c ->> 'claveUnidad'));
                v_qtys   := array_append(v_qtys,   c ->> 'cantidad');
                v_prices := array_append(v_prices, c ->> 'valorUnitario');
                v_imps   := array_append(v_imps,   c ->> 'importeCents');
                v_descs  := array_append(v_descs,  regexp_replace(coalesce(c ->> 'descripcion', ''), '[[:cntrl:]]', ' ', 'g'));
            END LOOP;
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
        ELSIF v_nconc IS NULL OR v_nconc < 1 OR v_nconc > c_max_concepts THEN v_reason := 'CONCEPT_COUNT';
        ELSIF EXISTS (SELECT 1 FROM unnest(v_prods) p WHERE p IS NULL OR p !~ '^[0-9]{8}$') THEN v_reason := 'PRODUCT_KEY';
        ELSIF (SELECT count(DISTINCT p) FROM unnest(v_prods) p) > 1 THEN v_reason := 'PRODUCT_KEY_MIXED';
        ELSIF EXISTS (SELECT 1 FROM unnest(v_units) u WHERE u IS NULL OR u NOT IN ('KGM', 'TNE')) THEN v_reason := 'UNIT';
        ELSIF (SELECT count(DISTINCT u) FROM unnest(v_units) u) > 1 THEN v_reason := 'UNIT_MIXED';
        ELSIF EXISTS (SELECT 1 FROM unnest(v_qtys) q WHERE q IS NULL OR q !~ c_qty)
              OR EXISTS (SELECT 1 FROM unnest(v_prices) q WHERE q IS NULL OR q !~ c_qty) THEN v_reason := 'QUANTITY';
        ELSIF EXISTS (SELECT 1 FROM unnest(v_imps) q WHERE q IS NULL OR q !~ '^[0-9]{1,13}$') THEN v_reason := 'CONCEPT_AMOUNT';
        END IF;
    END IF;
    IF v_reason IS NULL THEN
        -- Kilograms: tonnes are converted with exact numeric arithmetic (x 1000); all concepts share one unit here.
        v_factor := CASE WHEN v_units[1] = 'TNE' THEN 1000 ELSE 1 END;
        FOR v_i IN 1 .. v_nconc LOOP
            IF v_qtys[v_i]::numeric <= 0 OR v_prices[v_i]::numeric <= 0 THEN v_reason := 'QUANTITY'; EXIT; END IF;
            v_kgs := array_append(v_kgs, v_qtys[v_i]::numeric * v_factor);
            v_sum_kg := v_sum_kg + v_qtys[v_i]::numeric * v_factor;
            v_sum_imp := v_sum_imp + v_imps[v_i]::bigint;
        END LOOP;
    END IF;
    IF v_reason IS NULL THEN
        IF v_sum_kg >= c_max_kg THEN v_reason := 'QUANTITY';
        ELSIF v_sub IS NULL OR v_total IS NULL OR v_sub < 0 OR v_disc < 0 OR v_disc > v_sub OR v_total <= 0 OR v_total > 999999999999 THEN v_reason := 'AMOUNTS';
        ELSIF v_sub - v_disc + v_tr - v_ret <> v_total THEN v_reason := 'AMOUNTS_MISMATCH';
        END IF;
    END IF;
    IF v_reason IS NULL THEN
        -- Each concept: kilograms x price per kilogram against its own amount (one cent for issuer rounding).
        FOR v_i IN 1 .. v_nconc LOOP
            IF abs(round(v_kgs[v_i] * (v_prices[v_i]::numeric / v_factor) * 100) - v_imps[v_i]::bigint) > 1 THEN
                v_reason := 'AMOUNTS_MISMATCH_CONCEPT'; EXIT;
            END IF;
        END LOOP;
    END IF;
    IF v_reason IS NULL THEN
        -- The voucher subtotal against the sum of the concept amounts: at most (n - 1) cents, so exact for one concept.
        IF abs(v_sum_imp - v_sub) > v_nconc - 1 THEN
            v_reason := CASE WHEN v_nconc = 1 THEN 'AMOUNTS_MISMATCH_CONCEPT' ELSE 'AMOUNTS_MISMATCH_SUBTOTAL' END;
        END IF;
    END IF;
    IF v_reason IS NULL THEN
        v_qty := v_sum_kg;
        v_product := v_prods[1];
        v_price := CASE WHEN v_nconc = 1 AND v_units[1] = 'KGM' THEN v_prices[1]::numeric ELSE round(v_sub::numeric / 100 / v_sum_kg, 6) END;
        IF v_price <= 0 THEN v_reason := 'AMOUNTS';
        END IF;
    END IF;
    IF v_reason IS NULL THEN
        -- Ticket of each concept: exactly one recognizable reference, otherwise none (never a refusal). The same ticket twice is refused.
        FOR v_i IN 1 .. v_nconc LOOP
            SELECT array_agg(m[1]) INTO v_tk FROM regexp_matches(v_descs[v_i], c_ticket, 'gi') AS m;
            IF v_tk IS NOT NULL AND array_length(v_tk, 1) = 1 THEN
                v_tickets := array_append(v_tickets, v_tk[1]);
            ELSE
                v_tickets := array_append(v_tickets, NULL::text);
                v_ticket_warn := true;
            END IF;
        END LOOP;
        SELECT coalesce(array_agg(upper(t)), '{}') INTO v_tickets_up FROM unnest(v_tickets) t WHERE t IS NOT NULL;
        IF (SELECT count(DISTINCT t) FROM unnest(v_tickets_up) t) <> coalesce(array_length(v_tickets_up, 1), 0) THEN v_reason := 'TICKET_DUPLICATE';
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

    -- Ticket warning (a concept without a recognizable ticket) and the detail kept with the sale.
    IF v_ticket_warn THEN
        v_warnings := v_warnings || to_jsonb('ticket_missing_or_unrecognized'::text);
    END IF;
    SELECT t INTO v_ticket FROM unnest(v_tickets) WITH ORDINALITY AS u(t, n) WHERE t IS NOT NULL ORDER BY n LIMIT 1;
    FOR v_i IN 1 .. v_nconc LOOP
        v_detail := v_detail || jsonb_build_array(jsonb_build_object(
            'n', v_i, 'ticket', v_tickets[v_i], 'unit', v_units[v_i], 'qty', (v_qtys[v_i]::numeric)::text, 'kg', v_kgs[v_i]::text,
            'unit_price', (v_prices[v_i]::numeric)::text, 'amount_cents', v_imps[v_i]::bigint));
    END LOOP;

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

    -- A ticket of this voucher already present in another ACTIVE sale of the company (in its ticket_ref or in its detail).
    IF coalesce(array_length(v_tickets_up, 1), 0) > 0 AND EXISTS (
           SELECT 1 FROM public.agri_sale_invoices s
            WHERE s.id_company = p_tenant_id AND s.status = 'ACTIVE'
              AND (upper(s.ticket_ref) = ANY (v_tickets_up)
                   OR EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(s.ticket_detail, '[]'::jsonb)) d WHERE upper(d ->> 'ticket') = ANY (v_tickets_up)))) THEN
        v_warnings := v_warnings || to_jsonb('ticket_already_used'::text);
    END IF;

    BEGIN
        INSERT INTO public.agri_sale_invoices (id_company, uuid, emisor_rfc, emisor_name, receptor_rfc, buyer_name, serie, folio, issued_at, stamped_at,
                                               currency, subtotal_cents, discount_cents, total_cents, taxes, payment_form, payment_method,
                                               product_key, unit_code, quantity, unit_price, ticket_ref, ticket_warning,
                                               concept_count, ticket_detail,
                                               source_sha256, original_path, sat_status, registered_by_email)
        VALUES (p_tenant_id, v_uuid, v_emisor, v_emisor_nm, v_receptor, v_buyer, v_serie, v_folio, v_issued, v_stamped,
                'MXN', v_sub, v_disc, v_total, v_taxes, v_forma, 'PUE',
                v_product, 'KGM', v_qty, v_price, v_ticket, v_ticket_warn,
                v_nconc, v_detail,
                v_sha, v_path, v_sat, v_actor)
        RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        RETURN public.fn_agri_sale_reject(p_tenant_id, v_actor, 'DUPLICATE', 'DUPLICATE_UUID', 'No se pudo registrar la factura.');
    END;

    PERFORM public.fn_agri_sale_audit(p_tenant_id, v_id, 'REGISTER', 'OK', v_actor);
    RETURN jsonb_build_object('status', 'OK', 'sale_id', v_id, 'warnings', v_warnings,
        'summary', jsonb_build_object('folio', coalesce(v_serie, '') || coalesce(v_folio, ''), 'sale_date', v_issued::date,
            'buyer_name', v_buyer, 'total_amount', round(v_total::numeric / 100, 2), 'quantity_kg', v_qty, 'unit_price', v_price,
            'ticket_ref', v_ticket, 'sat_status', v_sat,
            'concept_count', v_nconc, 'tickets', to_jsonb(array_remove(v_tickets, NULL)), 'source_unit', v_units[1]));
END $$;
COMMENT ON FUNCTION public.sp_agri_register_sale(integer, text, jsonb, text, text, text) IS
  'Registers a palm sale from a parsed CFDI (direct load). ADMIN of a palm company only; issuer RFC from the platform-managed list; amounts only from the voucher; 1 to 10 concepts in KGM or TNE (kilograms stored); optional ticket per concept; idempotent per company; answers a status, never raises for expected cases.';

-- 4) Views: two columns appended at the end ----------------------------------------------------------------

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
    s.created_at,
    s.concept_count,
    coalesce(s.ticket_detail, jsonb_build_array(jsonb_build_object(
        'n', 1, 'ticket', s.ticket_ref, 'unit', 'KGM', 'qty', s.quantity::text, 'kg', s.quantity::text,
        'unit_price', s.unit_price::text, 'amount_cents', s.subtotal_cents))) AS ticket_detail
FROM public.agri_sale_invoices s
LEFT JOIN public.agri_plantations p ON p.id = s.plantation_id AND p.id_company = s.id_company
LEFT JOIN public.agri_lots l ON l.id = s.lot_id AND l.id_company = s.id_company;
COMMENT ON VIEW public.vw_agri_sale_list IS '104: sale list of a company, voided sales included with their status (ADMIN only; amounts). 112: concept_count and ticket_detail appended.';

CREATE OR REPLACE VIEW public.vw_agri_sale_ui_list AS
SELECT
    s.id,
    s.id_company,
    coalesce(s.serie, '') || coalesce(s.folio, '') AS folio,
    s.issued_at::date AS sale_date,
    s.buyer_name,
    s.quantity,
    s.unit_code,
    s.unit_price,
    s.total_cents::numeric / 100 AS total_amount,
    s.payment_method,
    s.ticket_ref,
    s.ticket_warning,
    s.plantation_id,
    p.plantation_code,
    p.plantation_name,
    s.lot_id,
    l.lot_code,
    l.lot_name,
    s.status,
    s.void_reason,
    s.voided_at,
    s.is_test,
    s.created_at,
    s.concept_count,
    coalesce(s.ticket_detail, jsonb_build_array(jsonb_build_object(
        'n', 1, 'ticket', s.ticket_ref, 'unit', 'KGM', 'qty', s.quantity::text, 'kg', s.quantity::text,
        'unit_price', s.unit_price::text, 'amount_cents', s.subtotal_cents))) AS ticket_detail
FROM public.agri_sale_invoices s
LEFT JOIN public.agri_plantations p ON p.id = s.plantation_id AND p.id_company = s.id_company
LEFT JOIN public.agri_lots l ON l.id = s.lot_id AND l.id_company = s.id_company;
COMMENT ON VIEW public.vw_agri_sale_ui_list IS
  '105: sales of the dashboard (voided sales included with their status). Reduced column set; id_company is filtered by the gateway (ADMIN-only read model agri_sales). 112: concept_count and ticket_detail appended.';

-- 5) Post-checks ---------------------------------------------------------------------------------------------

DO $$
BEGIN
    IF to_regprocedure('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)') IS NULL
       OR to_regprocedure('public.fn_trg_agri_sale_invoices_detail_guard()') IS NULL THEN
        RAISE EXCEPTION '112: procedures missing';
    END IF;
    IF (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'sp_agri_register_sale') <> 1 THEN
        RAISE EXCEPTION '112: sp_agri_register_sale must have exactly one signature';
    END IF;
    -- The live text must be exactly the one the runbook, the state check and the rollback know (so the dry run validates it before any COMMIT).
    IF md5(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure)) <> '83a5d0a7bad97dcfe1372aa4db961d49' THEN
        RAISE EXCEPTION '112: sp_agri_register_sale does not have the expected text (md5 %; PostgreSQL %)',
            md5(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure)), split_part(version(), ' ', 2);
    END IF;
    -- The 104 state check recognises the rollback stub by this word: the live procedure must not contain it.
    IF pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure) LIKE '%disabled%' THEN
        RAISE EXCEPTION '112: the procedure text must not contain the word used by the rollback stub of 104';
    END IF;
    IF (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'agri_sale_invoices'
           AND column_name IN ('concept_count', 'ticket_detail')) <> 2
       OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_agri_sale_invoices_detail_guard' AND tgrelid = 'public.agri_sale_invoices'::regclass AND NOT tgisinternal) THEN
        RAISE EXCEPTION '112: columns or trigger missing';
    END IF;
    RAISE NOTICE '112: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 112 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 112 rolled back ***'
\endif
\endif
