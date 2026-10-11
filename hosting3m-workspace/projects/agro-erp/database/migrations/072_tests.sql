-- 072_tests.sql — functional checks for migration 072 (tenant 3 test company). Everything is rolled back.
-- Uses animal 9999000003 (must be ACTIVO with no PENDIENTE request) and requester fjpimienta@gmail.com.
BEGIN;

DO $$
DECLARE
    v_user    text := 'fjpimienta@gmail.com';
    v_animal  uuid;
    v_req     uuid;
    v_today_0030_utc     timestamp;   -- today 00:30 CDMX, as naive UTC
    v_yesterday_2330_utc timestamp;   -- yesterday 23:30 CDMX, as naive UTC
BEGIN
    SELECT id INTO v_animal FROM cattle_livestock WHERE tenant_id = 3 AND rfid_siniiga = '9999000003' AND current_status = 'ACTIVO';
    IF v_animal IS NULL THEN RAISE EXCEPTION 'precondition: 9999000003 must be ACTIVO in tenant 3'; END IF;

    v_today_0030_utc     := ((date_trunc('day', now() AT TIME ZONE 'America/Mexico_City') + interval '30 minutes')
                             AT TIME ZONE 'America/Mexico_City') AT TIME ZONE 'UTC';
    v_yesterday_2330_utc := v_today_0030_utc - interval '1 hour';

    -- T1: request made today 00:30 CDMX can still be cancelled (valid until 23:59 CDMX)
    INSERT INTO pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email, fecha_solicitud)
    VALUES (3, v_animal, 'VENTA', '{"guia_transito":"T072-1"}', v_user, v_today_0030_utc) RETURNING id INTO v_req;
    PERFORM sp_cancelar_autorizacion(v_req, 3, v_user, 'Prueba 072');
    RAISE NOTICE 'T1 %: today-00:30 CDMX request cancelled',
        CASE WHEN (SELECT estado FROM pending_authorizations WHERE id = v_req) = 'CANCELADO' THEN 'OK' ELSE 'FAIL' END;

    -- T2: request made yesterday 23:30 CDMX is expired (P0012), message shows the CDMX date
    INSERT INTO pending_authorizations (id_company, livestock_id, tipo_evento, payload, solicitado_por_email, fecha_solicitud)
    VALUES (3, v_animal, 'VENTA', '{"guia_transito":"T072-2"}', v_user, v_yesterday_2330_utc) RETURNING id INTO v_req;
    BEGIN
        PERFORM sp_cancelar_autorizacion(v_req, 3, v_user, 'Prueba 072');
        RAISE NOTICE 'T2 FAIL: yesterday-23:30 CDMX request was cancelled';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T2 % (%): %', CASE WHEN SQLSTATE = 'P0012' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;

    -- T3: the resolver applies the same rule (rejection of the expired request -> P0012)
    BEGIN
        PERFORM sp_resolver_autorizacion(v_req, 'RECHAZADO', v_user, 'Prueba 072');
        RAISE NOTICE 'T3 FAIL: expired request was rejected';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'T3 % (%): %', CASE WHEN SQLSTATE = 'P0012' THEN 'OK' ELSE 'FAIL' END, SQLSTATE, SQLERRM;
    END;
END $$;

ROLLBACK;
