-- 070_regularize_tenant6_direct_sales_20261003.sql
-- One-off data fix (tenant 6 only). Six direct sales made on 2026-10-03 (transit guides 14287 / 14288)
-- were requested on 2026-10-08 22:09 CDMX, blocked by the TB/Brucellosis check and then expired.
-- The company authorized them outside the system. This script records them as approved with a
-- sanitary exception, using the same dispatcher as the panel (sp_procesar_venta_autorizada), so the
-- animal status, lot history and historico_movimientos are written exactly as a normal approval.
--
-- Usage (psql variables):
--   -v autorizador='<email of the tenant-6 ADMIN who authorized>'
--   -v apply=false   -> dry run, everything is rolled back
--   -v apply=true    -> commit
-- Fail-closed: any check that does not hold raises and aborts the whole transaction.

\set ON_ERROR_STOP on

BEGIN;

SELECT set_config('app.autorizador', :'autorizador', true);

-- 1) Row-level backups of everything this script touches
CREATE TABLE pending_authorizations_bkp_20261010_t6 AS
SELECT * FROM pending_authorizations
WHERE id IN ('e3fbe591-7a74-4db7-807c-db929ae2cb73', 'f5f925b3-bfd4-4da5-a04a-d7c1069e1ebf',
             'f92af1f2-60ce-42f7-9174-a879c3646f0c', 'f9080a56-7aab-4fcc-9184-0f554763bbec',
             'c60ee7f2-15b2-4bee-9bbd-700dddcf44aa', 'f17b9ff0-a441-4fd4-aa6a-c6efdd3d6494');

CREATE TABLE cattle_livestock_bkp_20261010_t6 AS
SELECT l.* FROM cattle_livestock l
JOIN pending_authorizations_bkp_20261010_t6 b ON b.livestock_id = l.id;

-- 2) Regularize
DO $$
DECLARE
    v_admin  text := current_setting('app.autorizador');
    r        record;
    v_res    jsonb;
    v_notas  text;
    n        integer := 0;
BEGIN
    IF NOT public.fn_is_active_company_admin(v_admin, 6) THEN
        RAISE EXCEPTION 'El autorizador % no es ADMIN activo de la empresa 6', v_admin;
    END IF;

    FOR r IN
        SELECT pa.*
          FROM pending_authorizations pa
         WHERE pa.id IN (SELECT id FROM pending_authorizations_bkp_20261010_t6)
           AND pa.id_company = 6
           AND pa.tipo_evento = 'VENTA'
           AND pa.estado = 'EXPIRADO'
         ORDER BY pa.fecha_solicitud
           FOR UPDATE
    LOOP
        v_notas := format(
            'Venta directa realizada el %s, guía %s. Pruebas TB/BR no requeridas para esta operación. '
            'Regularización manual del %s (solicitud vencida el 09/10) aplicada por fjpimienta@gmail.com '
            'con autorización de %s.',
            to_char((r.payload->>'fecha_evento')::date, 'DD/MM/YYYY'),
            COALESCE(NULLIF(r.payload->>'guia_transito', ''), 'N/D'),
            to_char(now() AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY'),
            v_admin);

        v_res := public.sp_procesar_venta_autorizada(
            p_livestock_id         := r.livestock_id,
            p_tenant_id            := 6,
            p_excepcion_sanitaria  := true,
            p_autorizado_por_email := v_admin,
            p_notas                := v_notas,
            p_fecha_evento         := (r.payload->>'fecha_evento')::date);

        IF COALESCE(v_res->>'success', 'false') <> 'true' THEN
            RAISE EXCEPTION 'Arete % no procesado: %', r.payload->>'rfid_siniiga', v_res;
        END IF;

        UPDATE pending_authorizations
           SET estado             = 'APROBADO',
               resuelto_por_email = v_admin,
               fecha_resolucion   = now(),
               notas_resolucion   = '[EXCEPCION SANITARIA] [REGULARIZACION MANUAL] ' || v_notas
         WHERE id = r.id;

        n := n + 1;
        RAISE NOTICE 'OK % (guía %)', r.payload->>'rfid_siniiga', r.payload->>'guia_transito';
    END LOOP;

    IF n <> 6 THEN
        RAISE EXCEPTION 'Se esperaban 6 solicitudes EXPIRADO, se procesaron %', n;
    END IF;
END $$;

-- 3) Verification
SELECT pa.payload->>'rfid_siniiga' AS arete, pa.payload->>'guia_transito' AS guia,
       pa.estado, l.current_status, l.lot_id IS NULL AS sin_lote
FROM pending_authorizations pa
JOIN cattle_livestock l ON l.id = pa.livestock_id
WHERE pa.id IN (SELECT id FROM pending_authorizations_bkp_20261010_t6)
ORDER BY 1;

SELECT count(*) AS movimientos_venta_hoy
FROM historico_movimientos
WHERE tenant_id = 6 AND tipo_movimiento = 'VENTA'
  AND livestock_id IN (SELECT livestock_id FROM pending_authorizations_bkp_20261010_t6);

\if :apply
COMMIT;
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
