-- Migration 016: Replaces the free-text cattle_livestock.upp_origen with a real FK.
--
-- upp_origen is a VARCHAR(100) holding strings like 'UPP La Bendición'. It cannot be
-- joined, cannot be validated, and silently tolerates typos. production_unit_id fixes that.
--
-- upp_origen is NOT dropped: sp_procesar_salida_ganado and historico_movimientos snapshot
-- it, and the AI field agent writes to it. Both columns coexist; upp_origen becomes a
-- denormalized label kept for audit snapshots, production_unit_id becomes the join key.
BEGIN;

ALTER TABLE public.cattle_livestock
    ADD COLUMN IF NOT EXISTS production_unit_id uuid;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT IF EXISTS fk_livestock_production_unit;
ALTER TABLE public.cattle_livestock
    ADD CONSTRAINT fk_livestock_production_unit
    FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_livestock_production_unit
    ON public.cattle_livestock (production_unit_id);

COMMENT ON COLUMN public.cattle_livestock.production_unit_id IS
    'FK to production_units. Authoritative origin. upp_origen is retained as a denormalized label for audit snapshots only.';

-- Same-tenant guard: an animal may only point at a production unit of its own tenant.
-- Enforced by trigger because a composite FK would require a redundant UNIQUE on
-- production_units(id, id_company).
CREATE OR REPLACE FUNCTION public.fn_guard_livestock_production_unit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_unit_company integer;
BEGIN
    IF NEW.production_unit_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id_company INTO v_unit_company
      FROM public.production_units
     WHERE id = NEW.production_unit_id;

    IF v_unit_company IS NULL THEN
        RAISE EXCEPTION 'production_unit_id % does not exist', NEW.production_unit_id
            USING ERRCODE = 'P0002';
    END IF;

    -- Fail-closed: cross-tenant assignment is rejected, never silently coerced.
    IF v_unit_company <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Cross-tenant assignment rejected: production unit belongs to company %, animal to company %',
            v_unit_company, NEW.tenant_id
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_livestock_production_unit ON public.cattle_livestock;
CREATE TRIGGER trg_guard_livestock_production_unit
    BEFORE INSERT OR UPDATE OF production_unit_id, tenant_id
    ON public.cattle_livestock
    FOR EACH ROW EXECUTE FUNCTION public.fn_guard_livestock_production_unit();

-- Backfill by exact ranch label. Deliberately conservative: only unambiguous matches
-- (exactly one active unit for that tenant with that name) are linked. Anything else is
-- left NULL for manual review rather than guessed.
UPDATE public.cattle_livestock cl
   SET production_unit_id = pu.id
  FROM public.production_units pu
 WHERE cl.production_unit_id IS NULL
   AND cl.upp_origen IS NOT NULL
   AND pu.id_company = cl.tenant_id
   AND pu.is_active = true
   AND (
        btrim(lower(pu.ranch_name)) = btrim(lower(cl.upp_origen))
     OR btrim(lower(pu.ranch_name)) = btrim(lower(replace(cl.upp_origen, 'UPP ', '')))
   )
   AND (SELECT count(*) FROM public.production_units p2
         WHERE p2.id_company = cl.tenant_id AND p2.is_active = true) = 1;

-- sp_procesar_salida_ganado must clear the new FK too, otherwise a sold animal keeps
-- pointing at a unit it no longer occupies. Only the UPDATE statement changes; the
-- normative TB/BR ruleset from migration 002 is preserved verbatim.
CREATE OR REPLACE FUNCTION public.sp_procesar_salida_ganado(p_electronic_rfid character varying)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_livestock_id   uuid;
    v_tenant_id      integer;
    v_current_status character varying(50);
    v_upp_anterior   character varying(100);
    v_tb_test_date   date;
    v_br_test_date   date;
    v_dias_tb        integer;
    v_dias_br        integer;
    v_motivo         text := '';
BEGIN
    SELECT id, tenant_id, current_status, upp_origen, tb_test_date, br_test_date
      INTO v_livestock_id, v_tenant_id, v_current_status, v_upp_anterior, v_tb_test_date, v_br_test_date
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

    v_dias_tb := CASE WHEN v_tb_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_tb_test_date END;
    v_dias_br := CASE WHEN v_br_test_date IS NULL THEN NULL ELSE CURRENT_DATE - v_br_test_date END;

    IF v_tb_test_date IS NULL OR v_dias_tb > 60 THEN
        v_motivo := v_motivo || 'Prueba TB ' ||
            (CASE WHEN v_tb_test_date IS NULL THEN 'no registrada. ' ELSE 'vencida hace ' || v_dias_tb || ' días. ' END);
    END IF;

    IF v_br_test_date IS NULL OR v_dias_br > 60 THEN
        v_motivo := v_motivo || 'Prueba Brucelosis ' ||
            (CASE WHEN v_br_test_date IS NULL THEN 'no registrada. ' ELSE 'vencida hace ' || v_dias_br || ' días. ' END);
    END IF;

    IF v_motivo <> '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'livestock_id', v_livestock_id,
            'electronic_rfid', p_electronic_rfid,
            'current_status', v_current_status,
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
        'current_status', 'VENDIDO'
    );
END;
$$;

COMMIT;
