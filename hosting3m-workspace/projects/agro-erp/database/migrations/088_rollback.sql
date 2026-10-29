-- 088 ROLLBACK. No DROP / DELETE / TRUNCATE.
--   * sp_log_breeding_event and sp_void_event get their ORIGINAL production bodies back (md5 2c1ff0adf25284e069ebf46ddc3108f8 and
--     c81f6faec5e61a28eca5d24b0f62a61c, verified before 088 was written), with the same signatures: they are existing procedures,
--     so they are restored, not disabled.
--   * sp_repro_get_dam_history keeps its name and signature but answers {"status":"disabled", ...}.
-- LEFT IN PLACE on purpose: cattle_breeding_events.birth_event_id with the links already made, its guard trigger and index, and
-- the helpers fn_repro_gestation_bounds / fn_repro_link_birth_service (migration 087's sp_register_birth_event keeps calling the
-- linker; unlink nothing - a link is a fact about a birth). After this rollback the "linked service cannot be voided" rule of
-- sp_void_event is gone (the original body does not know it); the guard trigger still blocks any other change of a service row.
-- Re-applying 088 restores the new bodies and keeps the links.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 088_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 088_rollback.sql  -> commit
-- Then: 088_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_repro_get_dam_history(text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_repro_get_dam_history not found - 088 was never applied here.';
    END IF;
END $$;

-- the original production bodies
CREATE OR REPLACE FUNCTION public.sp_log_breeding_event(p_animal_identifier character varying, p_tenant_id integer, p_breeding_date date DEFAULT CURRENT_DATE, p_method character varying DEFAULT 'MONTA_NATURAL'::character varying, p_sire_identifier character varying DEFAULT NULL::character varying, p_semen_batch character varying DEFAULT NULL::character varying, p_registered_by_email character varying DEFAULT NULL::character varying, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_livestock_id    uuid;
    v_current_status  character varying(50);
    v_species         character varying(50);
    v_match_count     integer;
    v_gestation_days  integer;
    v_estimated_due   date;
    v_breeding_event_id uuid;
BEGIN
    IF p_method NOT IN ('MONTA_NATURAL', 'INSEMINACION_ARTIFICIAL') THEN
        RAISE EXCEPTION 'method debe ser MONTA_NATURAL o INSEMINACION_ARTIFICIAL' USING ERRCODE = 'P0009';
    END IF;

    SELECT count(*) INTO v_match_count
      FROM public.cattle_livestock
     WHERE tenant_id = p_tenant_id
       AND (electronic_rfid = p_animal_identifier
            OR rfid_siniiga = p_animal_identifier
            OR numero_fuego = p_animal_identifier);

    IF v_match_count = 0 THEN
        RAISE EXCEPTION 'Ningún animal coincide con el identificador "%" (tenant %)', p_animal_identifier, p_tenant_id
            USING ERRCODE = 'P0002';
    ELSIF v_match_count > 1 THEN
        RAISE EXCEPTION 'Identificador ambiguo: % animales coinciden con "%"', v_match_count, p_animal_identifier
            USING ERRCODE = 'P0004';
    END IF;

    SELECT id, current_status, species
      INTO v_livestock_id, v_current_status, v_species
      FROM public.cattle_livestock
     WHERE tenant_id = p_tenant_id
       AND (electronic_rfid = p_animal_identifier
            OR rfid_siniiga = p_animal_identifier
            OR numero_fuego = p_animal_identifier);

    IF v_current_status IN ('VENDIDO', 'BAJA_MORTANDAD') THEN
        RAISE EXCEPTION 'El animal ya fue procesado (estatus actual: %), no puede registrarse un servicio', v_current_status
            USING ERRCODE = 'P0001';
    END IF;

    v_gestation_days := CASE v_species
        WHEN 'BOVINO'  THEN 283
        WHEN 'EQUINO'  THEN 340
        WHEN 'OVINO'   THEN 152
        WHEN 'CAPRINO' THEN 150
        WHEN 'PORCINO' THEN 114
        ELSE NULL
    END;

    IF v_gestation_days IS NOT NULL THEN
        v_estimated_due := p_breeding_date + v_gestation_days;
    END IF;

    INSERT INTO public.cattle_breeding_events
        (livestock_id, tenant_id, breeding_date, method, sire_identifier, semen_batch,
         estimated_due_date, registered_by_email, notes)
    VALUES
        (v_livestock_id, p_tenant_id, p_breeding_date, p_method, p_sire_identifier, p_semen_batch,
         v_estimated_due, p_registered_by_email, p_notes)
    RETURNING id INTO v_breeding_event_id;

    RETURN jsonb_build_object(
        'success', true,
        'breeding_event_id', v_breeding_event_id,
        'livestock_id', v_livestock_id,
        'breeding_date', p_breeding_date,
        'method', p_method,
        'estimated_due_date', v_estimated_due
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.sp_void_event(p_event_table character varying, p_event_id uuid, p_tenant_id integer, p_voided_by_email character varying, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_allowed_tables  text[] := ARRAY['cattle_breeding_events','cattle_deworming_events','cattle_castration_events'];
    v_exists          boolean;
    v_already_voided  boolean;
    v_void_id         uuid;
BEGIN
    -- Fail-closed: solo tablas explícitamente habilitadas, nunca un nombre arbitrario
    IF NOT (p_event_table = ANY(v_allowed_tables)) THEN
        RAISE EXCEPTION 'event_table "%" no está habilitada para anulación. Tablas permitidas: %', p_event_table, v_allowed_tables
            USING ERRCODE = 'P0016';
    END IF;

    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1 AND tenant_id = $2)', p_event_table)
      INTO v_exists
      USING p_event_id, p_tenant_id;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'El evento % no existe en % para la empresa %', p_event_id, p_event_table, p_tenant_id
            USING ERRCODE = 'P0002';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.event_voids
         WHERE event_table = p_event_table AND event_id = p_event_id
    ) INTO v_already_voided;

    IF v_already_voided THEN
        RAISE EXCEPTION 'El evento % en % ya fue anulado previamente', p_event_id, p_event_table
            USING ERRCODE = 'P0017';
    END IF;

    INSERT INTO public.event_voids (tenant_id, event_table, event_id, voided_by_email, voided_reason)
    VALUES (p_tenant_id, p_event_table, p_event_id, p_voided_by_email, p_reason)
    RETURNING id INTO v_void_id;

    RETURN jsonb_build_object(
        'success', true,
        'void_id', v_void_id,
        'event_table', p_event_table,
        'event_id', p_event_id,
        'voided_at', now()
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.sp_repro_get_dam_history(
    p_tenant_id text, p_user_email text, p_dam_identifier text DEFAULT NULL, p_dam_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'El historial reproductivo de la hembra esta desactivado temporalmente (088 revertida).')
$$;

DO $$
DECLARE
    v1 text := md5(pg_get_functiondef(to_regprocedure('public.sp_log_breeding_event(character varying,integer,date,character varying,character varying,character varying,character varying,text)')));
    v2 text := md5(pg_get_functiondef(to_regprocedure('public.sp_void_event(character varying,uuid,integer,character varying,text)')));
BEGIN
    IF v1 <> '2c1ff0adf25284e069ebf46ddc3108f8' THEN
        RAISE WARNING '088 rollback: the restored sp_log_breeding_event has md5 % (expected 2c1ff0adf25284e069ebf46ddc3108f8)', v1;
    END IF;
    IF v2 <> 'c81f6faec5e61a28eca5d24b0f62a61c' THEN
        RAISE WARNING '088 rollback: the restored sp_void_event has md5 % (expected c81f6faec5e61a28eca5d24b0f62a61c)', v2;
    END IF;
    IF public.sp_repro_get_dam_history('0', 'nobody@example.test')->>'status' IS DISTINCT FROM 'disabled' THEN
        RAISE EXCEPTION '088 rollback: the tool is not disabled';
    END IF;
    RAISE NOTICE '088 rollback: OK';
END $$;

\if :apply
COMMIT;
\echo '*** 088 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
