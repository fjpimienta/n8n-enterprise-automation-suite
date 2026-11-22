-- 110_expense_invoice_role_gate.sql
-- Expense registration only accepts vouchers RECEIVED by the company: a voucher issued by the company is refused with a clear message.
-- SQL only: no n8n, no frontend, no cfdi-service change, no table, no data. Exactly two functions are replaced, with their current signatures and attributes
-- (plain plpgsql VOLATILE, no SECURITY DEFINER, same privileges as before):
--   sp_expense_invoice_register  (091, replaced in 093)  role gate, then the 093 flow unchanged
--   sp_company_tax_id_set        (091)                   refuses the generic SAT constants
-- REQUIRES 091, 092, 093 and 109 (fn_classify_cfdi_role_detail, not the rollback stub). Aborts if missing.
--
-- Role gate (after the membership / role check and the parsing of the voucher, before the receiver RFC is looked up), in preview and in confirm:
--   the company is the one fn_repro_ctx resolved from the session, never a client value; the classifier is 109's fn_classify_cfdi_role_detail.
--   EXPENSE                      -> continue exactly as before
--   UNKNOWN / NEITHER            -> continue exactly as before (neither RFC is registered: the 093 preview-and-confirm / EDITOR rejection applies)
--   SALE                         -> {status: not_an_expense, code: ROLE_SALE, message}      nothing written, no RFC created
--   AMBIGUOUS                    -> {status: not_an_expense, code: ROLE_AMBIGUOUS, message} nothing written
--   anything else (UNKNOWN with another reason, NULL, an exception of the classifier, the 109 rollback stub)
--                                -> {status: not_an_expense, code: ROLE_UNAVAILABLE, message} (fail closed: never falls through to registration)
-- The messages are fixed text: no RFC, UUID, name or amount is echoed. sp_expense_invoice_preview / _confirm pass an unknown status through unchanged and
-- mark the draft as consumed only for recorded / duplicate, so a not_an_expense answer leaves the draft usable and writes nothing.
-- Generic RFCs: XAXX010101000 and XEXX010101000 are never registered as a company RFC, neither by sp_company_tax_id_set nor by the 093 auto-register branch
-- (status rfc_generic). A row of that kind that already exists keeps working and may be deactivated, never reactivated.
--
-- DRIFT GUARD: each function is replaced only if its live text is the one of the repository chain (md5 of pg_get_functiondef, constants below) or already the 110 text
-- (re-running is a no-op). If production differs, the migration aborts instead of overwriting something unknown. How the constants were obtained: 110_RUNBOOK.md.
--
-- ORDER WITH 109: rolling back 109 while 110 is applied makes registration refuse everything (ROLE_UNAVAILABLE). Roll back 110 first.
-- Rollback: 110_rollback.sql (restores the exact 091 / 093 bodies; no DROP). State: 110_state_check.sql. Tests: 110_tests.sql, 110_mutation_check.sh.
-- Usage:   psql -X -v ON_ERROR_STOP=1 -f 110_expense_invoice_role_gate.sql                (dry run: ROLLBACK)
--          psql -X -v ON_ERROR_STOP=1 -v apply=true -f 110_expense_invoice_role_gate.sql  (COMMIT)

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
    v_reg text;
    v_tax text;
BEGIN
    IF to_regprocedure('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_company_tax_id_set(text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_expense_invoice_confirm(text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT 110: migrations 091, 092 and 093 must be applied first.';
    END IF;
    IF to_regprocedure('public.fn_classify_cfdi_role_detail(integer,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT 110: migration 109 (classifier) must be applied first.';
    END IF;
    IF (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.fn_classify_cfdi_role_detail(integer,text,text)')) LIKE '%''DISABLED''%' THEN
        RAISE EXCEPTION 'ABORT 110: the 109 classifier is rolled back (stub); applying the gate would make registration refuse every voucher.';
    END IF;
    v_reg := md5(pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure));
    v_tax := md5(pg_get_functiondef('public.sp_company_tax_id_set(text,text,text,text,text)'::regprocedure));
    IF v_reg NOT IN ('0612086a244911ac15c47a5405f7ac0b', 'acbeeb49f222d36de95f8db2be3cd4be') THEN
        RAISE EXCEPTION 'ABORT 110 (drift): sp_expense_invoice_register is not the repository 093 text (md5 %). Nothing was changed.', v_reg;
    END IF;
    IF v_tax NOT IN ('e89f615ed99bae63adb6d53554819789', 'f7cec648615c6741f166d9356f0530c9') THEN
        RAISE EXCEPTION 'ABORT 110 (drift): sp_company_tax_id_set is not the repository 091 text (md5 %). Nothing was changed.', v_tax;
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
    c_generic constant text[] := ARRAY['XAXX010101000', 'XEXX010101000'];
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
    -- 110: the generic SAT constants are never a company's own RFC. An existing row of that kind may still be deactivated, never created or reactivated.
    IF v_rfc = ANY (c_generic)
       AND (v_act OR NOT EXISTS (SELECT 1 FROM public.company_tax_ids t WHERE t.id_company = v_co AND t.rfc = v_rfc)) THEN
        RETURN jsonb_build_object('status', 'rfc_generic', 'message', 'El RFC genérico del SAT (público en general o extranjero) no puede registrarse como RFC de la empresa. No lo registré.');
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
    v_tax_active boolean;
    v_rfc_new   boolean := false;
    v_others    text[];
    v_desc      text;
    v_dup_date  date;
    v_dup_total bigint;
    v_exp_id    uuid;
    v_confirmed boolean := lower(btrim(coalesce(p_confirmed, 'false'))) = 'true';
    c_rfc       constant text := '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$';
    c_generic   constant text[] := ARRAY['XAXX010101000', 'XEXX010101000'];
    v_cls       jsonb;
    v_crole     text;
    v_creason   text;
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

    -- 110 role gate: this procedure only books vouchers RECEIVED by the company. The company is the one resolved from the session above.
    -- Any answer other than EXPENSE (or UNKNOWN / NEITHER, which keeps the 093 flow for a receiver that is not registered yet) refuses, writes nothing and never registers an RFC.
    BEGIN
        v_cls := public.fn_classify_cfdi_role_detail(v_co, v_emisor, v_receptor);
    EXCEPTION WHEN others THEN
        v_cls := NULL;
    END;
    v_crole := v_cls ->> 'role';
    v_creason := v_cls ->> 'reason';
    IF v_crole = 'EXPENSE' OR (v_crole = 'UNKNOWN' AND v_creason = 'NEITHER') THEN
        NULL;
    ELSIF v_crole = 'SALE' THEN
        RETURN jsonb_build_object('status', 'not_an_expense', 'code', 'ROLE_SALE', 'message', 'Esta factura parece una venta (tu empresa aparece como emisora), no un gasto. No la registré.');
    ELSIF v_crole = 'AMBIGUOUS' THEN
        RETURN jsonb_build_object('status', 'not_an_expense', 'code', 'ROLE_AMBIGUOUS', 'message', 'No puedo decidir si es compra o venta porque tu empresa aparece como emisora y receptora. No la registré.');
    ELSE
        RETURN jsonb_build_object('status', 'not_an_expense', 'code', 'ROLE_UNAVAILABLE', 'message', 'No pude clasificar la factura como gasto. No la registré; intenta de nuevo o avisa al administrador.');
    END IF;

    SELECT t.qa_skip_sat, t.is_active INTO v_skip, v_tax_active FROM public.company_tax_ids t
     WHERE t.id_company = v_co AND t.rfc = v_receptor;
    IF NOT FOUND THEN
        -- 093: an ADMIN/OWNER may register a new receiver RFC by confirming the invoice (created only inside the confirm transaction below).
        IF v_role NOT IN ('ADMIN', 'OWNER') THEN
            RETURN jsonb_build_object('status', 'rfc_not_registered',
                'message', 'El RFC receptor de la factura no esta registrado para esta empresa. Un ADMIN debe registrarlo o confirmar esta factura.');
        END IF;
        IF v_receptor = ANY (c_generic) THEN
            RETURN jsonb_build_object('status', 'rfc_generic', 'message', 'El RFC genérico del SAT (público en general o extranjero) no puede registrarse como RFC de la empresa. No lo registré.');
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

DO $$
BEGIN
    IF md5(pg_get_functiondef('public.sp_expense_invoice_register(text,text,text,text,text,text,text,text,text)'::regprocedure)) <> 'acbeeb49f222d36de95f8db2be3cd4be'
       OR md5(pg_get_functiondef('public.sp_company_tax_id_set(text,text,text,text,text)'::regprocedure)) <> 'f7cec648615c6741f166d9356f0530c9' THEN
        RAISE EXCEPTION '110: a function does not have the expected text after the change';
    END IF;
    RAISE NOTICE '110: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 110 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 110 rolled back ***'
\endif
\endif
