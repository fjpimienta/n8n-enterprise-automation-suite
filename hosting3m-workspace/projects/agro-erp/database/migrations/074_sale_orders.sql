-- 074_sale_orders.sql
-- Sale orders ("orden de venta"): one request, sent by chat / WhatsApp, for a group of animals that may live in
-- several UPPs and even in several companies of the requester.
--
-- Business rules (set by the project owner, 2026-10-16):
--   * ANY active member of a company may request the sale of animals of the companies they belong to,
--     whatever the UPP or lot. Only an ADMIN of the animal's company may approve (unchanged: sp_resolver_autorizacion).
--   * One order groups the animals of one sale. Each animal carries the transit guide of its UPP of origin
--     (one guide per UPP group); the guide is mandatory for every animal of an order.
--   * The order is split into one pending authorization per animal, created in the animal's own company, all
--     linked by sale_order_id. Each company only ever sees and approves its own part.
--   * All-or-nothing: if any animal fails validation, nothing is created.
--   * Notifications are sent once per order and company (workflow V6/Notificación de Autorizaciones Pendientes).
--
-- Objects:
--   sale_orders                          (new)   order header, cross-company, NOT exposed through the CRUD gateway
--   pending_authorizations.sale_order_id (new)   nullable FK; single-animal requests keep working unchanged
--   sp_solicitar_venta_orden(...)        (new)   preview (p_preview = true, read-only) or create the order
--   crud_models 'pending_authorizations' allowed_fields += sale_order_id (backed up first)
--
-- Usage:
--   psql -v ON_ERROR_STOP=1 -v apply=false -f 074_sale_orders.sql   -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true  -f 074_sale_orders.sql   -> commit

\set ON_ERROR_STOP on
BEGIN;

-- 0) Backup of the crud_models row this migration changes
CREATE TABLE IF NOT EXISTS crud_models_backup_20261016_074 AS
SELECT m.*, now() AS backed_up_at FROM crud_models m WHERE m.model_name = 'pending_authorizations';

-- 1) Order header
CREATE TABLE IF NOT EXISTS public.sale_orders (
    id                  uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number        bigint       GENERATED ALWAYS AS IDENTITY UNIQUE,
    order_code          text         GENERATED ALWAYS AS ('OV-' || lpad(order_number::text, 6, '0')) STORED,
    requested_by_email  varchar(255) NOT NULL,
    fecha_evento        date,
    channel             varchar(20)  NOT NULL DEFAULT 'AGENTE',
    created_at          timestamp    NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.sale_orders IS
  'Sale order header (one per chat/WhatsApp sale request). Cross-company: never exposed through the CRUD gateway; each company sees only its own pending_authorizations rows.';

-- 2) Link from each pending authorization to its order
ALTER TABLE public.pending_authorizations
    ADD COLUMN IF NOT EXISTS sale_order_id uuid REFERENCES public.sale_orders(id);
CREATE INDEX IF NOT EXISTS idx_pending_auth_sale_order ON public.pending_authorizations (sale_order_id);

-- 3) Order procedure
CREATE OR REPLACE FUNCTION public.sp_solicitar_venta_orden(
    p_items                jsonb,
    p_solicitado_por_email varchar,
    p_fecha_evento         date    DEFAULT NULL,
    p_preview              boolean DEFAULT true,
    p_channel              varchar DEFAULT 'AGENTE'
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_email      text := lower(btrim(coalesce(p_solicitado_por_email, '')));
    v_today_cdmx date := (now() AT TIME ZONE 'America/Mexico_City')::date;
    v_fecha      date := coalesce(p_fecha_evento, (now() AT TIME ZONE 'America/Mexico_City')::date);
    v_companies  int[];
    v_errors     int;
    v_order      sale_orders%ROWTYPE;
    v_res        jsonb;
    r            record;
    v_n          int;
    v_animal     cattle_livestock%ROWTYPE;
BEGIN
    -- Requester: active user with at least one active membership
    IF v_email = '' THEN
        RAISE EXCEPTION 'Se requiere el email de quien solicita la venta' USING ERRCODE = 'P0007';
    END IF;
    SELECT array_agg(DISTINCT uc.id_company) INTO v_companies
      FROM user_companies uc JOIN users u ON lower(u.email) = lower(uc.email)
     WHERE lower(uc.email) = v_email AND uc.is_active AND u.is_active;
    IF v_companies IS NULL THEN
        RAISE EXCEPTION 'El usuario no pertenece a ninguna empresa activa' USING ERRCODE = 'P0031';
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La orden debe incluir al menos un animal' USING ERRCODE = 'P0032';
    END IF;
    IF jsonb_array_length(p_items) > 300 THEN
        RAISE EXCEPTION 'La orden no puede tener más de 300 animales' USING ERRCODE = 'P0032';
    END IF;
    IF v_fecha > v_today_cdmx THEN
        RAISE EXCEPTION 'La fecha de venta (%) no puede ser futura', v_fecha USING ERRCODE = 'P0033';
    END IF;

    -- Validation of every item (no writes)
    IF to_regclass('pg_temp.tmp_sale_order_items') IS NULL THEN
        CREATE TEMP TABLE tmp_sale_order_items (
            pos int, identificador text, guia text, livestock_id uuid, id_company int, empresa text,
            upp text, lote text, arete text, numero_fuego text, categoria text, estatus text, error text
        ) ON COMMIT DROP;
    END IF;
    TRUNCATE tmp_sale_order_items;

    INSERT INTO tmp_sale_order_items (pos, identificador, guia)
    SELECT e.ord, nullif(btrim(e.val->>'identificador'), ''), left(nullif(btrim(e.val->>'guia_transito'), ''), 40)
      FROM jsonb_array_elements(p_items) WITH ORDINALITY AS e(val, ord);

    UPDATE tmp_sale_order_items SET error = 'Falta el identificador del animal' WHERE identificador IS NULL;
    UPDATE tmp_sale_order_items SET error = 'Falta la guía de tránsito'          WHERE error IS NULL AND guia IS NULL;
    UPDATE tmp_sale_order_items t SET error = 'Identificador repetido en la orden'
     WHERE error IS NULL AND (SELECT count(*) FROM tmp_sale_order_items x WHERE x.identificador = t.identificador) > 1;

    -- Resolve each identifier ONLY inside the requester's companies
    FOR r IN SELECT * FROM tmp_sale_order_items WHERE error IS NULL ORDER BY pos LOOP
        SELECT count(*) INTO v_n
          FROM cattle_livestock l
         WHERE l.tenant_id = ANY (v_companies)
           AND (l.rfid_siniiga = r.identificador OR l.electronic_rfid = r.identificador
                OR l.numero_fuego = r.identificador);
        IF v_n = 0 THEN
            UPDATE tmp_sale_order_items SET error = 'No existe en tus empresas' WHERE pos = r.pos;
        ELSIF v_n > 1 THEN
            UPDATE tmp_sale_order_items
               SET error = 'Identificador ambiguo (' || v_n || ' animales); usa el arete SINIIGA' WHERE pos = r.pos;
        ELSE
            SELECT * INTO v_animal
              FROM cattle_livestock l
             WHERE l.tenant_id = ANY (v_companies)
               AND (l.rfid_siniiga = r.identificador OR l.electronic_rfid = r.identificador
                    OR l.numero_fuego = r.identificador);
            UPDATE tmp_sale_order_items
               SET livestock_id = v_animal.id, id_company = v_animal.tenant_id, arete = v_animal.rfid_siniiga,
                   numero_fuego = v_animal.numero_fuego, categoria = v_animal.category, estatus = v_animal.current_status
             WHERE pos = r.pos;
        END IF;
    END LOOP;

    UPDATE tmp_sale_order_items
       SET error = 'Estatus ' || estatus || ': no se puede vender'
     WHERE error IS NULL AND estatus IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO');
    UPDATE tmp_sale_order_items t
       SET error = 'Ya tiene una solicitud pendiente'
     WHERE error IS NULL AND EXISTS (SELECT 1 FROM pending_authorizations pa
                                      WHERE pa.livestock_id = t.livestock_id AND pa.estado = 'PENDIENTE');
    UPDATE tmp_sale_order_items t
       SET empresa = c.company_name
      FROM companys c WHERE c.id_company = t.id_company;
    UPDATE tmp_sale_order_items t
       SET upp  = (SELECT pu.ranch_name FROM cattle_livestock l JOIN production_units pu ON pu.id = l.production_unit_id
                    WHERE l.id = t.livestock_id),
           lote = (SELECT lt.lot_name FROM cattle_livestock l JOIN production_unit_lots lt ON lt.id = l.lot_id
                    WHERE l.id = t.livestock_id)
     WHERE t.livestock_id IS NOT NULL;

    SELECT count(*) INTO v_errors FROM tmp_sale_order_items WHERE error IS NOT NULL;

    v_res := jsonb_build_object(
        'fecha_evento', v_fecha,
        'total', (SELECT count(*) FROM tmp_sale_order_items),
        'validos', (SELECT count(*) FROM tmp_sale_order_items WHERE error IS NULL),
        'errores', coalesce((SELECT jsonb_agg(jsonb_build_object('identificador', identificador, 'error', error) ORDER BY pos)
                               FROM tmp_sale_order_items WHERE error IS NOT NULL), '[]'::jsonb),
        'grupos', coalesce((SELECT jsonb_agg(g ORDER BY g->>'empresa', g->>'guia_transito')
                              FROM (SELECT jsonb_build_object(
                                             'empresa', empresa, 'upp', upp, 'guia_transito', guia,
                                             'cantidad', count(*),
                                             'por_categoria', (SELECT jsonb_object_agg(categoria, n) FROM (
                                                 SELECT x.categoria, count(*) n FROM tmp_sale_order_items x
                                                  WHERE x.error IS NULL AND x.empresa = i.empresa
                                                    AND x.upp IS NOT DISTINCT FROM i.upp AND x.guia = i.guia
                                                  GROUP BY 1) s),
                                             'aretes', jsonb_agg(coalesce(arete, numero_fuego, identificador) ORDER BY pos)) AS g
                                      FROM tmp_sale_order_items i WHERE error IS NULL
                                     GROUP BY empresa, upp, guia) q), '[]'::jsonb));

    IF p_preview THEN
        RETURN v_res || jsonb_build_object('success', v_errors = 0, 'preview', true);
    END IF;

    IF v_errors > 0 THEN
        RAISE EXCEPTION 'La orden no se registró: % animal(es) con error: %', v_errors,
            (SELECT string_agg(identificador || ' (' || error || ')', '; ' ORDER BY pos)
               FROM tmp_sale_order_items WHERE error IS NOT NULL)
            USING ERRCODE = 'P0034';
    END IF;

    -- Create the order and one pending authorization per animal, in the animal's own company
    INSERT INTO sale_orders (requested_by_email, fecha_evento, channel)
    VALUES (v_email, v_fecha, coalesce(nullif(btrim(p_channel), ''), 'AGENTE'))
    RETURNING * INTO v_order;

    INSERT INTO pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email, sale_order_id)
    SELECT t.id_company, t.livestock_id, 'VENTA',
           jsonb_strip_nulls(jsonb_build_object(
               'fecha_evento', to_char(v_fecha, 'YYYY-MM-DD'),
               'guia_transito', t.guia,
               'orden_venta', v_order.order_code,
               'rfid_siniiga', t.arete,
               'numero_fuego', t.numero_fuego,
               'electronic_rfid', (SELECT electronic_rfid FROM cattle_livestock WHERE id = t.livestock_id),
               -- Order-level counts only (no identities from other companies): lets each company's panel
               -- know the order also has animals it cannot see.
               'orden_total_animales', (SELECT count(*) FROM tmp_sale_order_items),
               'orden_total_empresas', (SELECT count(DISTINCT id_company) FROM tmp_sale_order_items))),
           v_email, v_order.id
      FROM tmp_sale_order_items t
     ORDER BY t.pos;

    RETURN v_res || jsonb_build_object(
        'success', true, 'preview', false,
        'order_id', v_order.id, 'orden_venta', v_order.order_code,
        'solicitudes', (SELECT count(*) FROM pending_authorizations WHERE sale_order_id = v_order.id));
END;
$$;

COMMENT ON FUNCTION public.sp_solicitar_venta_orden(jsonb, varchar, date, boolean, varchar) IS
  'Sale order across the requester''s companies. p_items = [{"identificador": "...", "guia_transito": "..."}]. '
  'p_preview=true validates and groups without writing; p_preview=false creates the order (all-or-nothing).';

-- 4) Let the panel read / filter by the order
UPDATE crud_models
   SET allowed_fields = allowed_fields || '["sale_order_id"]'::jsonb
 WHERE model_name = 'pending_authorizations'
   AND NOT (allowed_fields ? 'sale_order_id');

-- 5) Checks
DO $$
BEGIN
    IF to_regclass('public.sale_orders') IS NULL THEN RAISE EXCEPTION '074: sale_orders missing'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name = 'pending_authorizations' AND column_name = 'sale_order_id') THEN
        RAISE EXCEPTION '074: pending_authorizations.sale_order_id missing';
    END IF;
    IF NOT (SELECT allowed_fields ? 'sale_order_id' FROM crud_models WHERE model_name = 'pending_authorizations') THEN
        RAISE EXCEPTION '074: crud_models not updated';
    END IF;
    RAISE NOTICE '074: OK';
END $$;

\if :apply
COMMIT;
\echo '*** 074 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
