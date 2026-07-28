-- Migration 024: Herd-free certificates + corrected exit validation.
--
-- Two defects in sp_procesar_salida_ganado, both found while mapping the SENASICA
-- regulatory framework (NOM-001-SAG/GAN-2015, NOM-031-ZOO-1995, NOM-041-ZOO-1995):
--
-- DEFECT 1 — Missing official ear tag check.
--   NOM-001 makes the SINIIGA tag applied at the origin UPP an indispensable requirement
--   for ANY movement or procedure. The routine validated TB/BR but never checked that the
--   animal actually carries an official tag, so it authorised exits that are illegal.
--   Production currently holds 21 animals (tenant 5) whose rfid_siniiga is a capture
--   placeholder of the form 'S/N-<numero_fuego>-<n>' — literally "sin número".
--
-- DEFECT 2 — The 60-day window was applied as a universal rule.
--   Those 60 days are the legal validity of a LOT TEST (prueba de lote): the dictamen a
--   third-party authorised vet issues after bleeding only the animals about to move.
--   A herd certified as TB/BR free (dictamen de hato libre, 12-24 months of validity)
--   moves animals WITHOUT lot tests, validating against the herd-free certificate number.
--   The routine therefore rejected legitimate exits from a certified herd.
--
-- SCOPE NOTE: this migration does NOT implement movement rules, zone sanitary status, or
-- the REEMO/CZM state machine. It only corrects the exit routine and adds the entity the
-- corrected rule needs.
--
-- FORMAT NOTE (deliberate omission): 188 animals carry 9-digit tags while 54 carry 10.
-- The SINIIGA bovine identifier is nominally 10 digits, so the 9-digit ones may be
-- truncated. That is NOT validated here: blocking 188 animals on an unconfirmed suspicion
-- would be worse than the gap it closes. Flagged for review, not enforced.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Herd-free certificates (dictamen de hato libre)
-- ---------------------------------------------------------------------------
-- Scoped to the PRODUCTION UNIT, not to the animal: the whole herd of a UPP is certified
-- as a unit. Append-only, same audit contract as compliance_certificates.
CREATE TABLE IF NOT EXISTS public.herd_free_certificates (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    id_company          integer NOT NULL,
    production_unit_id  uuid NOT NULL,

    disease             character varying(20) NOT NULL,
    folio               character varying(50) NOT NULL,
    issued_at           date NOT NULL,
    valid_until         date NOT NULL,
    issuing_authority   character varying(255),
    veterinarian_name   character varying(255),
    veterinarian_license character varying(100),

    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamp without time zone DEFAULT now(),

    CONSTRAINT herd_free_certificates_disease_check
        CHECK (disease IN ('TB', 'BR')),
    CONSTRAINT herd_free_certificates_dates_check
        CHECK (valid_until > issued_at),
    CONSTRAINT fk_herd_free_company
        FOREIGN KEY (id_company) REFERENCES public.companys(id_company) ON DELETE CASCADE,
    CONSTRAINT fk_herd_free_unit
        FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_herd_free_unit_disease_folio
    ON public.herd_free_certificates (production_unit_id, disease, folio);
CREATE INDEX IF NOT EXISTS idx_herd_free_unit_validity
    ON public.herd_free_certificates (production_unit_id, disease, valid_until DESC)
    WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_herd_free_company
    ON public.herd_free_certificates (id_company);

COMMENT ON TABLE public.herd_free_certificates IS
    'Dictamen de hato libre per production unit. One row per disease (TB / BR): a herd may be certified for one and not the other. While valid, animals from this unit move without lot tests.';
COMMENT ON COLUMN public.herd_free_certificates.disease IS
    'TB = tuberculosis (NOM-031-ZOO-1995), BR = brucelosis (NOM-041-ZOO-1995). Separate rows because the certificates are issued and expire independently.';

-- ---------------------------------------------------------------------------
-- 2. Official ear tag validator
-- ---------------------------------------------------------------------------
-- Conservative on purpose: rejects only what is certainly not an official tag.
-- Does NOT enforce digit count (see FORMAT NOTE in the header).
CREATE OR REPLACE FUNCTION public.fn_has_official_ear_tag(p_rfid_siniiga character varying)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_rfid_siniiga IS NOT NULL
       AND btrim(p_rfid_siniiga) <> ''
       AND upper(btrim(p_rfid_siniiga)) NOT LIKE 'S/N%'
       AND upper(btrim(p_rfid_siniiga)) NOT LIKE 'SN-%'
       AND btrim(p_rfid_siniiga) ~ '[0-9]';
$$;

COMMENT ON FUNCTION public.fn_has_official_ear_tag(character varying) IS
    'True when the value looks like a real SINIIGA tag rather than a capture placeholder. Deliberately does not validate length: 188 production records carry 9 digits and 54 carry 10, and which one is correct has not been confirmed.';

-- ---------------------------------------------------------------------------
-- 3. Herd-free coverage resolver
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_is_herd_free(
    p_production_unit_id uuid,
    p_disease character varying,
    p_reference_date date DEFAULT CURRENT_DATE
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM public.herd_free_certificates h
         WHERE h.production_unit_id = p_production_unit_id
           AND h.disease = p_disease
           AND h.is_active = true
           AND h.valid_until >= p_reference_date
    );
$$;

-- ---------------------------------------------------------------------------
-- 4. Corrected exit routine
-- ---------------------------------------------------------------------------
-- Signature and invocation are unchanged: SELECT sp_procesar_salida_ganado(rfid).
-- Hard errors (RAISE EXCEPTION) still mean "data problem"; business rejections still
-- return success:false so the n8n gateway can tell them apart.
CREATE OR REPLACE FUNCTION public.sp_procesar_salida_ganado(p_electronic_rfid character varying)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_livestock_id   uuid;
    v_tenant_id      integer;
    v_current_status character varying(50);
    v_upp_anterior   character varying(100);
    v_unit_id        uuid;
    v_rfid_siniiga   character varying(100);
    v_tb_test_date   date;
    v_br_test_date   date;
    v_dias_tb        integer;
    v_dias_br        integer;
    v_tb_free        boolean := false;
    v_br_free        boolean := false;
    v_motivo         text := '';
BEGIN
    SELECT id, tenant_id, current_status, upp_origen, production_unit_id,
           rfid_siniiga, tb_test_date, br_test_date
      INTO v_livestock_id, v_tenant_id, v_current_status, v_upp_anterior, v_unit_id,
           v_rfid_siniiga, v_tb_test_date, v_br_test_date
      FROM public.cattle_livestock
     WHERE electronic_rfid = p_electronic_rfid
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'RFID % no está registrado en el inventario', p_electronic_rfid
            USING ERRCODE = 'P0002';
    END IF;

    IF v_current_status = 'VENDIDO' THEN
        RAISE EXCEPTION 'El animal con RFID % ya fue procesado como VENDIDO', p_electronic_rfid
            USING ERRCODE = 'P0001';
    END IF;

    -- DEFECT 1 FIX: no official ear tag, no movement (NOM-001-SAG/GAN-2015).
    IF NOT public.fn_has_official_ear_tag(v_rfid_siniiga) THEN
        v_motivo := v_motivo ||
            'Sin arete oficial SINIIGA (valor actual: ' ||
            COALESCE(v_rfid_siniiga, 'ninguno') ||
            '). La NOM-001-SAG/GAN-2015 lo exige para cualquier movilización. ';
    END IF;

    -- DEFECT 2 FIX: the 60-day window is the validity of a LOT TEST. A unit with a
    -- current herd-free certificate is exempt from it.
    IF v_unit_id IS NOT NULL THEN
        v_tb_free := public.fn_is_herd_free(v_unit_id, 'TB');
        v_br_free := public.fn_is_herd_free(v_unit_id, 'BR');
    END IF;

    v_dias_tb := CASE WHEN v_tb_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_tb_test_date END;
    v_dias_br := CASE WHEN v_br_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_br_test_date END;

    IF NOT v_tb_free AND (v_tb_test_date IS NULL OR v_dias_tb > 60) THEN
        v_motivo := v_motivo || 'Prueba TB ' ||
            (CASE WHEN v_tb_test_date IS NULL THEN 'no registrada' ELSE 'vencida hace ' || v_dias_tb || ' días' END) ||
            ' y la unidad no cuenta con dictamen de hato libre vigente. ';
    END IF;

    IF NOT v_br_free AND (v_br_test_date IS NULL OR v_dias_br > 60) THEN
        v_motivo := v_motivo || 'Prueba Brucelosis ' ||
            (CASE WHEN v_br_test_date IS NULL THEN 'no registrada' ELSE 'vencida hace ' || v_dias_br || ' días' END) ||
            ' y la unidad no cuenta con dictamen de hato libre vigente. ';
    END IF;

    IF v_motivo <> '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'livestock_id', v_livestock_id,
            'electronic_rfid', p_electronic_rfid,
            'rfid_siniiga', v_rfid_siniiga,
            'current_status', v_current_status,
            'tb_herd_free', v_tb_free,
            'br_herd_free', v_br_free,
            'motivo', trim(v_motivo)
        );
    END IF;

    UPDATE public.cattle_livestock
       SET current_status     = 'VENDIDO',
           upp_origen         = NULL,
           production_unit_id = NULL
     WHERE id = v_livestock_id;

    INSERT INTO public.historico_movimientos
        (livestock_id, electronic_rfid, tenant_id, tipo_movimiento, upp_origen_anterior)
    VALUES
        (v_livestock_id, p_electronic_rfid, v_tenant_id, 'VENTA', v_upp_anterior);

    RETURN jsonb_build_object(
        'success', true,
        'livestock_id', v_livestock_id,
        'electronic_rfid', p_electronic_rfid,
        'current_status', 'VENDIDO',
        'tb_herd_free', v_tb_free,
        'br_herd_free', v_br_free
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Movement-readiness view (dashboard feed)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_livestock_movement_readiness AS
 SELECT cl.id                       AS livestock_id,
        cl.tenant_id                AS id_company,
        c.company_name,
        cl.production_unit_id,
        pu.ranch_name,
        pu.upp_code,
        cl.rfid_siniiga,
        cl.electronic_rfid,
        cl.numero_fuego,
        cl.category,
        cl.current_status,
        public.fn_has_official_ear_tag(cl.rfid_siniiga) AS has_official_tag,
        COALESCE(public.fn_is_herd_free(cl.production_unit_id, 'TB'), false) AS tb_herd_free,
        COALESCE(public.fn_is_herd_free(cl.production_unit_id, 'BR'), false) AS br_herd_free,
        cl.tb_test_date,
        cl.br_test_date,
        (cl.tb_test_date IS NOT NULL AND (CURRENT_DATE - cl.tb_test_date) <= 60) AS tb_lot_test_valid,
        (cl.br_test_date IS NOT NULL AND (CURRENT_DATE - cl.br_test_date) <= 60) AS br_lot_test_valid,
        (
            public.fn_has_official_ear_tag(cl.rfid_siniiga)
            AND (COALESCE(public.fn_is_herd_free(cl.production_unit_id, 'TB'), false)
                 OR (cl.tb_test_date IS NOT NULL AND (CURRENT_DATE - cl.tb_test_date) <= 60))
            AND (COALESCE(public.fn_is_herd_free(cl.production_unit_id, 'BR'), false)
                 OR (cl.br_test_date IS NOT NULL AND (CURRENT_DATE - cl.br_test_date) <= 60))
        ) AS is_movable,
        cl.created_at
   FROM public.cattle_livestock cl
   LEFT JOIN public.companys c ON c.id_company = cl.tenant_id
   LEFT JOIN public.production_units pu ON pu.id = cl.production_unit_id
  WHERE cl.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD');

COMMENT ON VIEW public.vw_livestock_movement_readiness IS
    'Per-animal movement eligibility. is_movable reflects only the rules verified so far (official tag + TB/BR coverage). It does NOT evaluate zone sanitary status, REEMO/CZM documents or destination type, which are not modelled yet.';

COMMIT;
