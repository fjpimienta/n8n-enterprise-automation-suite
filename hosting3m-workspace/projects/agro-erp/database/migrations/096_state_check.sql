-- 096_state_check.sql: READ-ONLY. psql -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 096_state_check.sql
-- The data FINGERPRINT lines must be identical at every step (096 changes functions only). The *_def lines differ by design between before and applied.
-- Built from the production definitions of 2026-11-03:
-- before md5 sal4 = 6427feed3417359715696ca2eab57ab4
-- before md5 sal5 = 98f0ef956924a37e3fbacb1412112b52
-- before md5 venta = d8dc9660b81a7c5e56619ab8453771de
-- before md5 orden = d3c1fadef0b7d5e9c188acda08df85fb
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t096.expect', :'expect', false) AS expect;
\echo === DATA FINGERPRINTS
SELECT 'cattle_livestock_data' AS fingerprint,
       md5(string_agg(concat_ws('|', id::text, tenant_id::text, current_status, coalesce(species, '~'), coalesce(rfid_siniiga, '~')), '#' ORDER BY id)) AS md5
  FROM cattle_livestock
UNION ALL SELECT 'pending_authorizations_data', coalesce(md5(string_agg(concat_ws('|', id::text, estado, coalesce(livestock_id::text, '~')), '#' ORDER BY id)), 'empty') FROM pending_authorizations
UNION ALL SELECT 'historico_movimientos_count', count(*)::text FROM historico_movimientos
UNION ALL SELECT 'crud_models', md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c;
\echo === FUNCTION DEFINITIONS
SELECT 'helper_exists' AS fingerprint, (to_regprocedure('public.fn_species_requires_bovine_compliance(character varying)') IS NOT NULL)::text AS md5
UNION ALL
SELECT 'sal4_def' AS fingerprint, md5(pg_get_functiondef('public.sp_procesar_salida_ganado(character varying,integer,character varying,character varying)'::regprocedure)) AS md5
UNION ALL SELECT 'sal5_def' AS fingerprint, md5(pg_get_functiondef('public.sp_procesar_salida_ganado(character varying,integer,character varying,character varying,uuid)'::regprocedure)) AS md5
UNION ALL SELECT 'venta_def' AS fingerprint, md5(pg_get_functiondef('public.sp_procesar_venta_autorizada(uuid,integer,boolean,character varying,text,date)'::regprocedure)) AS md5
UNION ALL SELECT 'orden_def' AS fingerprint, md5(pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure)) AS md5;
\echo === SPECIES IN THE CURRENT HERD (not sold, not dead)
SELECT tenant_id, coalesce(species, '(NULL)') AS species, count(*)
  FROM cattle_livestock
 WHERE current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO')
 GROUP BY 1, 2 ORDER BY 1, 2;
DO $$
DECLARE
    e       text := current_setting('t096.expect');
    v_sig   text;
    v_uses  integer := 0;
    v_total integer := 0;
BEGIN
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN RAISE EXCEPTION 'expect must be before, applied or rolled_back'; END IF;
    FOREACH v_sig IN ARRAY ARRAY[
        'public.sp_procesar_salida_ganado(character varying,integer,character varying,character varying)',
        'public.sp_procesar_salida_ganado(character varying,integer,character varying,character varying,uuid)',
        'public.sp_procesar_venta_autorizada(uuid,integer,boolean,character varying,text,date)',
        'public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'
    ] LOOP
        v_total := v_total + 1;
        IF pg_get_functiondef(v_sig::regprocedure) LIKE '%fn_species_requires_bovine_compliance%' THEN v_uses := v_uses + 1; END IF;
    END LOOP;
    IF e IN ('before', 'rolled_back') AND v_uses <> 0 THEN RAISE EXCEPTION 'STATE FAIL: % function(s) already use the helper', v_uses; END IF;
    IF e = 'applied' AND (v_uses <> v_total OR to_regprocedure('public.fn_species_requires_bovine_compliance(character varying)') IS NULL) THEN
        RAISE EXCEPTION 'STATE FAIL: only % of % functions use the helper', v_uses, v_total;
    END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
ROLLBACK;
