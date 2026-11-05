-- 098_state_check.sql: READ-ONLY.
-- psql -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back [-v expect_md5_orden=<md5>] -f 098_state_check.sql
--
-- * DATA FINGERPRINTS must be identical in all three states (098 changes structure, triggers, functions and a view only;
--   it never writes a row). They use only columns that exist before 098.
-- * expect_md5_orden is the md5(pg_get_functiondef) of sp_solicitar_venta_orden taken BEFORE the apply IN THE SAME
--   ENVIRONMENT (take it with this script, expect=before). When given, expect=before and expect=rolled_back require an
--   exact match. Never compare md5 values between environments: PG 15.4 (production) and PG 16 (local) can format
--   pg_get_functiondef differently, so each environment records its own "before" value.
-- * Run it in production before the apply (expect=before), after the apply (expect=applied) and after a rollback
--   (expect=rolled_back). Save the three outputs in the runbook record.
\set ON_ERROR_STOP on
\if :{?expect_md5_orden}
\else
\set expect_md5_orden ''
\endif
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t098.expect', :'expect', false) AS expect,
       set_config('t098.md5', :'expect_md5_orden', false) AS expect_md5_orden;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version;

\echo === DATA FINGERPRINTS (identical at every step)
SELECT 'cattle_livestock_data' AS fingerprint,
       md5(string_agg(concat_ws('|', id::text, tenant_id::text, current_status, coalesce(species, '~'), coalesce(rfid_siniiga, '~'),
                                coalesce(production_unit_id::text, '~'), coalesce(lot_id::text, '~'), coalesce(upp_origen, '~')), '#' ORDER BY id)) AS md5
  FROM cattle_livestock
UNION ALL SELECT 'cattle_movement_events_data',
       coalesce(md5(string_agg(concat_ws('|', id::text, id_company::text, coalesce(production_unit_origin_id::text, '~'),
                                         coalesce(external_destination_id::text, '~'), coalesce(reemo_folio, '~'), movement_date::text, status), '#' ORDER BY id)), 'empty')
  FROM cattle_movement_events
UNION ALL SELECT 'cattle_movement_event_animals_data',
       coalesce(md5(string_agg(concat_ws('|', id::text, event_id::text, cattle_livestock_id::text, coalesce(fire_number_snapshot, '~')), '#' ORDER BY id)), 'empty')
  FROM cattle_movement_event_animals
UNION ALL SELECT 'pending_authorizations_data', coalesce(md5(string_agg(concat_ws('|', id::text, estado, coalesce(livestock_id::text, '~')), '#' ORDER BY id)), 'empty') FROM pending_authorizations
UNION ALL SELECT 'historico_movimientos_count', count(*)::text FROM historico_movimientos
UNION ALL SELECT 'external_destinations_count', count(*)::text FROM external_destinations
UNION ALL SELECT 'crud_models', md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c;

\echo === FUNCTION DEFINITIONS (these differ by design between before and applied)
SELECT 'orden_def' AS fingerprint,
       md5(pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure)) AS md5;
SELECT 'sal5_def' AS fingerprint, md5(pg_get_functiondef('public.sp_procesar_salida_ganado(character varying,integer,character varying,character varying,uuid)'::regprocedure)) AS md5
UNION ALL SELECT 'sal4_def', md5(pg_get_functiondef('public.sp_procesar_salida_ganado(character varying,integer,character varying,character varying)'::regprocedure))
UNION ALL SELECT 'sal1_def', md5(pg_get_functiondef('public.sp_procesar_salida_ganado(character varying)'::regprocedure))
UNION ALL SELECT 'baja_def', md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' ORDER BY p.oid::regprocedure::text)) FROM pg_proc p WHERE p.proname = 'sp_procesar_baja_mortandad' AND p.pronamespace = 'public'::regnamespace;
-- sp_procesar_salida_ganado (3 overloads) and sp_procesar_baja_mortandad must NOT change: 098 never touches them.

\echo === 098 OBJECTS
SELECT 'columns' AS item,
       (SELECT string_agg(table_name || '.' || column_name, ', ' ORDER BY table_name, column_name)
          FROM information_schema.columns
         WHERE table_schema = 'public'
           AND ((table_name = 'cattle_movement_events' AND column_name IN ('purpose', 'expected_return_date'))
             OR (table_name = 'cattle_movement_event_animals' AND column_name IN ('return_status', 'returned_at')))) AS present
UNION ALL SELECT 'constraints',
       (SELECT string_agg(conname, ', ' ORDER BY conname) FROM pg_constraint
         WHERE conname IN ('chk_movement_purpose', 'chk_movement_repasto_requires_return', 'chk_movement_animal_return_status', 'chk_movement_animal_returned_at'))
UNION ALL SELECT 'index', (SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_movement_animal_one_open')
UNION ALL SELECT 'triggers (name:enabled O=on D=off)',
       (SELECT string_agg(tgname || ':' || tgenabled::text, ', ' ORDER BY tgname) FROM pg_trigger
         WHERE NOT tgisinternal AND tgname IN ('trg_block_out_on_loan_status', 'trg_close_loan_on_death', 'trg_guard_movement_animal_open'))
UNION ALL SELECT 'functions', (SELECT string_agg(proname, ', ' ORDER BY proname) FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace AND proname IN ('sp_return_movement', 'trg_guard_movement_animal_open', 'trg_block_out_on_loan_status', 'trg_close_loan_on_death'))
UNION ALL SELECT 'view', to_regclass('public.vw_livestock_out_on_loan')::text
UNION ALL SELECT 'sp_return_movement_def', md5(pg_get_functiondef(to_regprocedure('public.sp_return_movement(uuid,uuid[],date,character varying)')));

\echo === OPEN LOANS (information)
DO $$
DECLARE
    v_open int;
    v_tracked int;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_movement_event_animals' AND column_name = 'return_status') THEN
        EXECUTE 'SELECT count(*) FILTER (WHERE return_status = ''OPEN''), count(*) FILTER (WHERE return_status IS NOT NULL) FROM public.cattle_movement_event_animals'
            INTO v_open, v_tracked;
        RAISE NOTICE 'loan rows: % OPEN, % tracked in total', v_open, v_tracked;
    ELSE
        RAISE NOTICE 'loan rows: columns not present (098 not applied)';
    END IF;
END $$;

DO $$
DECLARE
    e text := current_setting('t098.expect');
    v_want_md5 text := current_setting('t098.md5');
    v_def text := pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure);
    v_loan int := (length(v_def) - length(replace(v_def, '-- 098: animals out on loan', ''))) / length('-- 098: animals out on loan');
    v_fifo int := (length(v_def) - length(replace(v_def, '-- 098: FIFO skips animals out on loan', ''))) / length('-- 098: FIFO skips animals out on loan');
    v_cols int;
    v_enabled int;
    v_disabled int;
    v_return_def text;
    -- The rollback replaces the view by one with the same columns and WHERE false; the real view never ends that way.
    v_view_tail  text := right(rtrim(coalesce(pg_get_viewdef(to_regclass('public.vw_livestock_out_on_loan')), ''), E' \n;'), 11);
    v_view_def   text := coalesce(pg_get_viewdef(to_regclass('public.vw_livestock_out_on_loan')), '');
BEGIN
    IF e NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back';
    END IF;
    IF v_def NOT LIKE '%FIFO_SIN_IDENTIFICADOR%' THEN
        RAISE EXCEPTION 'STATE FAIL: sp_solicitar_venta_orden is not the 097 (FIFO) version';
    END IF;
    SELECT count(*) INTO v_cols FROM information_schema.columns
     WHERE table_schema = 'public' AND ((table_name = 'cattle_movement_events' AND column_name IN ('purpose', 'expected_return_date'))
        OR (table_name = 'cattle_movement_event_animals' AND column_name IN ('return_status', 'returned_at')));
    SELECT count(*) FILTER (WHERE tgenabled = 'O'), count(*) FILTER (WHERE tgenabled = 'D') INTO v_enabled, v_disabled
      FROM pg_trigger WHERE NOT tgisinternal AND tgname IN ('trg_block_out_on_loan_status', 'trg_close_loan_on_death', 'trg_guard_movement_animal_open');

    IF e = 'before' THEN
        IF v_cols <> 0 OR v_enabled + v_disabled <> 0 OR to_regclass('public.vw_livestock_out_on_loan') IS NOT NULL
           OR to_regprocedure('public.sp_return_movement(uuid,uuid[],date,character varying)') IS NOT NULL THEN
            RAISE EXCEPTION 'STATE FAIL (before): 098 objects already exist (columns=%, triggers=%)', v_cols, v_enabled + v_disabled;
        END IF;
        IF v_loan <> 0 OR v_fifo <> 0 THEN
            RAISE EXCEPTION 'STATE FAIL (before): sp_solicitar_venta_orden already has 098 text';
        END IF;
    ELSIF e = 'applied' THEN
        IF v_cols <> 4 THEN RAISE EXCEPTION 'STATE FAIL (applied): expected 4 new columns, found %', v_cols; END IF;
        IF (SELECT count(*) FROM pg_constraint WHERE conname IN ('chk_movement_purpose', 'chk_movement_repasto_requires_return',
               'chk_movement_animal_return_status', 'chk_movement_animal_returned_at')) <> 4 THEN
            RAISE EXCEPTION 'STATE FAIL (applied): a CHECK constraint is missing';
        END IF;
        IF to_regclass('public.uq_movement_animal_one_open') IS NULL THEN RAISE EXCEPTION 'STATE FAIL (applied): partial unique index missing'; END IF;
        IF v_enabled <> 3 OR v_disabled <> 0 THEN
            RAISE EXCEPTION 'STATE FAIL (applied): the 3 triggers must be enabled (enabled=%, disabled=%)', v_enabled, v_disabled;
        END IF;
        IF v_loan <> 2 OR v_fifo <> 2 THEN
            RAISE EXCEPTION 'STATE FAIL (applied): expected 2 loan blocks and 2 FIFO exclusions in sp_solicitar_venta_orden, found % and %', v_loan, v_fifo;
        END IF;
        v_return_def := pg_get_functiondef('public.sp_return_movement(uuid,uuid[],date,character varying)'::regprocedure);
        IF v_return_def LIKE '%098 rolled back%' OR v_return_def NOT LIKE '%P0099%' THEN
            RAISE EXCEPTION 'STATE FAIL (applied): sp_return_movement is the rollback stub or incomplete';
        END IF;
        IF v_view_tail = 'WHERE false' THEN
            RAISE EXCEPTION 'STATE FAIL (applied): vw_livestock_out_on_loan is the empty rollback view (ends in WHERE false)';
        END IF;
        IF v_view_def NOT LIKE '%CLOSED%' THEN
            RAISE EXCEPTION 'STATE FAIL (applied): vw_livestock_out_on_loan is missing the CLOSED event_state';
        END IF;
    ELSE -- rolled_back
        IF v_loan <> 0 OR v_fifo <> 0 THEN
            RAISE EXCEPTION 'STATE FAIL (rolled_back): sp_solicitar_venta_orden still has 098 text';
        END IF;
        IF v_enabled <> 0 OR v_disabled <> 3 THEN
            RAISE EXCEPTION 'STATE FAIL (rolled_back): the 3 triggers must exist and be disabled (enabled=%, disabled=%)', v_enabled, v_disabled;
        END IF;
        IF pg_get_functiondef('public.sp_return_movement(uuid,uuid[],date,character varying)'::regprocedure) NOT LIKE '%098 rolled back%' THEN
            RAISE EXCEPTION 'STATE FAIL (rolled_back): sp_return_movement is not the disabled stub';
        END IF;
        IF v_view_tail <> 'WHERE false' THEN
            RAISE EXCEPTION 'STATE FAIL (rolled_back): vw_livestock_out_on_loan is not the empty rollback view';
        END IF;
    END IF;

    IF e IN ('before', 'rolled_back') AND v_want_md5 <> '' THEN
        IF md5(v_def) <> v_want_md5 THEN
            RAISE EXCEPTION 'STATE FAIL (%): sp_solicitar_venta_orden md5 expected %, found %', e, v_want_md5, md5(v_def);
        END IF;
        RAISE NOTICE 'sp_solicitar_venta_orden md5 matches the recorded pre-098 value';
    ELSIF e IN ('before', 'rolled_back') THEN
        RAISE NOTICE 'No expect_md5_orden given: record md5(orden_def) above as the pre-098 value of THIS environment.';
    END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
