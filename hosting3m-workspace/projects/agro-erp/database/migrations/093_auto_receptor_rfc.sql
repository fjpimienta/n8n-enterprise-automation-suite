-- 093_auto_receptor_rfc.sql
-- An ADMIN/OWNER confirming an invoice whose receiver RFC is not yet registered for the company registers that RFC automatically.
-- REQUIRES 091 and 092. Only sp_expense_invoice_register is replaced (same signature); no table, column, trigger or other function changes.
-- Rules: (1) only ADMIN/OWNER; an EDITOR still gets rfc_not_registered. (2) preview says so (rfc_new, rfc_new_notice, company_rfcs) and writes nothing.
--        (3) the RFC row is inserted only on confirm, in the same sub-transaction as the expense (a duplicate rolls both back). (4) qa_skip_sat stays false,
--        so the SAT must answer VIGENTE. (5) a deactivated RFC is NEVER reactivated automatically. (6) tenant context and role checks are unchanged (fail-closed).
-- Rollback: 093_rollback.sql (restores the exact 091 function). State: 093_state_check.sql. Tests: 093_tests.sql.
-- Usage:   psql -v ON_ERROR_STOP=1 -f 093_auto_receptor_rfc.sql (dry run) | ... -v apply=true -f ... (commit)

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
    IF to_regprocedure('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_expense_invoice_confirm(text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migrations 091 and 092 must be applied first.';
    END IF;
    IF pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure) LIKE '%''disabled''%' THEN
        RAISE EXCEPTION 'ABORT: 091 is rolled back (register is disabled).';
    END IF;
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
    v_tax_active boolean;
    v_rfc_new   boolean := false;
    v_others    text[];
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

    SELECT t.qa_skip_sat, t.is_active INTO v_skip, v_tax_active FROM public.company_tax_ids t
     WHERE t.id_company = v_co AND t.rfc = v_receptor;
    IF NOT FOUND THEN
        -- 093: an ADMIN/OWNER may register a new receiver RFC by confirming the invoice (created only inside the confirm transaction below).
        IF v_role NOT IN ('ADMIN', 'OWNER') THEN
            RETURN jsonb_build_object('status', 'rfc_not_registered',
                'message', 'El RFC receptor de la factura no esta registrado para esta empresa. Un ADMIN debe registrarlo o confirmar esta factura.');
        END IF;
        v_rfc_new := true;
        v_skip := false;
        SELECT array_agg(t.rfc ORDER BY t.rfc) INTO v_others FROM public.company_tax_ids t WHERE t.id_company = v_co AND t.is_active IS TRUE;
    ELSIF v_tax_active IS NOT TRUE THEN
        RETURN jsonb_build_object('status', 'rfc_not_registered',
            'message', 'El RFC receptor de la factura esta desactivado para esta empresa. Un ADMIN debe reactivarlo.');
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
            'taxes_transferred', v_tr::numeric / 100, 'taxes_withheld', v_ret::numeric / 100, 'sat_status', v_sat)
            || CASE WHEN v_rfc_new THEN jsonb_build_object('rfc_new', true, 'company_rfcs', to_jsonb(coalesce(v_others, ARRAY[]::text[])),
                   'rfc_new_notice', 'El RFC receptor ' || v_receptor || ' no esta registrado en esta empresa; se registrara como RFC de la empresa al confirmar.')
               ELSE '{}'::jsonb END;
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
        IF v_rfc_new THEN
            INSERT INTO public.company_tax_ids (id_company, rfc, label, is_active, qa_skip_sat, created_by_email)
            VALUES (v_co, v_receptor, left('AUTO factura ' || v_serie || v_folio, 100), true, false, v_email)
            ON CONFLICT (id_company, rfc) DO NOTHING;
        END IF;
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
        'amount', v_total::numeric / 100, 'sat_status', v_sat)
        || CASE WHEN v_rfc_new THEN jsonb_build_object('rfc_registered', v_receptor) ELSE '{}'::jsonb END;
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 093 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 093 rolled back ***'
\endif
\endif
