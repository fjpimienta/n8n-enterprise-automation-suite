-- 097_state_check.sql: READ-ONLY. psql -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 097_state_check.sql
-- The 097 migration changes only the function definition; compare data fingerprints before and after deployment.
-- before md5 orden (096) = d3c1fadef0b7d5e9c188acda08df85fb
-- applied md5 orden = TO BE FILLED AFTER REHEARSAL
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t097.expect', :'expect', false) AS expect;
\echo === DATA FINGERPRINTS
SELECT 'cattle_livestock_data' AS fingerprint,
       md5(string_agg(concat_ws('|', id::text, tenant_id::text, current_status, coalesce(species, '~'), coalesce(rfid_siniiga, '~')), '#' ORDER BY id)) AS md5
  FROM cattle_livestock
UNION ALL SELECT 'pending_authorizations_data', coalesce(md5(string_agg(concat_ws('|', id::text, estado, coalesce(livestock_id::text, '~')), '#' ORDER BY id)), 'empty') FROM pending_authorizations
UNION ALL SELECT 'historico_movimientos_count', count(*)::text FROM historico_movimientos
UNION ALL SELECT 'crud_models', md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c;
\echo === FUNCTION DEFINITION
SELECT 'orden_def' AS fingerprint,
       md5(pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure)) AS md5;
DO $$
DECLARE
    e text := current_setting('t097.expect');
    v_md5 text;
    v_after_md5 constant text := 'TO BE FILLED AFTER REHEARSAL';
    v_def text;
BEGIN
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back';
    END IF;
    v_def := pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure);
    v_md5 := md5(v_def);
    IF e IN ('before', 'rolled_back') AND v_md5 <> 'd3c1fadef0b7d5e9c188acda08df85fb' THEN
        RAISE EXCEPTION 'STATE FAIL: 096 function fingerprint expected, found %', v_md5;
    END IF;
    IF e = 'applied' THEN
        IF v_after_md5 !~ '^[0-9a-f]{32}$' THEN
            RAISE EXCEPTION 'STATE FAIL: applied fingerprint is pending rehearsal; replace TO BE FILLED AFTER REHEARSAL before deployment';
        END IF;
        IF v_md5 <> v_after_md5 THEN
            RAISE EXCEPTION 'STATE FAIL: applied function fingerprint expected %, found %', v_after_md5, v_md5;
        END IF;
        IF v_def NOT LIKE '%FIFO_SIN_IDENTIFICADOR%'
           OR v_def NOT LIKE '%seleccionados%'
           OR v_def NOT LIKE '%l.created_at ASC, l.id ASC%' THEN
            RAISE EXCEPTION 'STATE FAIL: applied function does not contain the FIFO selection behavior';
        END IF;
    END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
ROLLBACK;
