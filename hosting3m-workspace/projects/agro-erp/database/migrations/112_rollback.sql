-- 112 ROLLBACK. No DROP / DELETE / TRUNCATE. The registration procedure is replaced by the exact 104 text (one KGM concept per voucher), so a
-- caller that still sends several concepts or tonnes gets the same refusals as before 112 (CONCEPT_COUNT / UNIT) and nothing else changes.
-- Kept on purpose: the two columns, their constraints, the detail guard trigger (it accepts every row the 104 procedure writes), the two view columns
-- and every sale registered while 112 was applied (a multi-concept sale keeps its quantity, totals and detail; it can still be voided).
-- Re-applying 112_agri_sale_multi_concept.sql restores the new rules.
-- The text below is the one of 104_agri_sale_invoices.sql (checked by md5 in 112_state_check.sql).
--
-- Usage:   psql -X -v ON_ERROR_STOP=1 -f 112_rollback.sql                -> dry run
--          psql -X -v ON_ERROR_STOP=1 -v apply=true -f 112_rollback.sql  -> commit
-- Then: 112_state_check.sql -v expect=rolled_back

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
BEGIN
    IF to_regprocedure('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT 112 rollback: sp_agri_register_sale not found - 104 was never applied here.';
    END IF;
    IF md5(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure))
           NOT IN ('425229fb6036884d5c5dcd7527d7c674', '83a5d0a7bad97dcfe1372aa4db961d49') THEN
        RAISE EXCEPTION 'ABORT 112 rollback: the live procedure is neither the 112 text nor the 104 text (md5 %). Nothing was changed.',
            md5(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure));
    END IF;
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

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 112 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 112 rollback rolled back ***'
\endif
\endif
