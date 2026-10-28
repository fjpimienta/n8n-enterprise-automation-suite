-- 087 ROLLBACK. No DROP / DELETE / TRUNCATE.
--   * sp_register_birth_event (13 parameters) gets its ORIGINAL production body back (md5 8eaf6f52716165a6bc59f8f4a6a7ce4a, verified
--     before 087 was written), with the same signature: it is an existing procedure, so it is restored, not disabled.
--   * the 8 new tool functions keep their names and signatures (the n8n tools still call them) but answer
--     {"status":"disabled", ...}: nothing is read, nothing is written.
-- LEFT IN PLACE on purpose: birth_events.reported_by_email (additive, with its values), repro_births_config,
-- repro_historical_births and repro_historical_birth_voids with all their rows and triggers (append-only records of what staff
-- reported), and the internal helpers. Re-applying 087 restores the tools and keeps the rows.
-- A birth already linked to a service by migration 088 stays linked (088 has its own rollback).
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 087_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 087_rollback.sql  -> commit
-- Then: 087_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_repro_register_birth(text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_repro_register_birth not found - 087 was never applied here.';
    END IF;
END $$;

-- the original production body of the legacy procedure
CREATE OR REPLACE FUNCTION public.sp_register_birth_event(p_id_company integer, p_calf_sex character varying, p_species character varying DEFAULT 'BOVINO'::character varying, p_dam_id uuid DEFAULT NULL::uuid, p_dam_ear_tag character varying DEFAULT NULL::character varying, p_dam_fire_number character varying DEFAULT NULL::character varying, p_birth_date date DEFAULT CURRENT_DATE, p_lot_id uuid DEFAULT NULL::uuid, p_production_unit_id uuid DEFAULT NULL::uuid, p_paddock_id uuid DEFAULT NULL::uuid, p_birth_weight_kg numeric DEFAULT NULL::numeric, p_notes text DEFAULT NULL::text, p_reported_by_email character varying DEFAULT NULL::character varying)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_event_id             uuid;
    v_calf_id              uuid;
    v_dam_id                uuid;
    v_dam_status             character varying(50);
    v_dam_production_unit    uuid;
    v_dam_lot_id              uuid;
    v_dam_paddock_id          uuid;
    v_dam_upp_origen          character varying(100);
    v_match_count             integer;
    v_dam_updated             boolean := false;
    v_category                 character varying(50);
    v_weight_log_id            uuid;
    v_explicit_lot_unit        uuid;
    v_final_lot_id              uuid;
    v_final_production_unit     uuid;
BEGIN
    IF p_species <> 'BORREGO' AND p_dam_id IS NULL AND p_dam_ear_tag IS NULL AND p_dam_fire_number IS NULL THEN
        RAISE EXCEPTION 'Debe identificar a la madre por UUID, arete SINIIGA o número de fuego'
            USING ERRCODE = 'P0003';
    END IF;

    IF p_calf_sex NOT IN ('MACHO', 'HEMBRA') THEN
        RAISE EXCEPTION 'calf_sex debe ser MACHO o HEMBRA'
            USING ERRCODE = 'P0005';
    END IF;

    v_category := CASE p_species || '_' || p_calf_sex
        WHEN 'BOVINO_MACHO'  THEN 'BECERRO'
        WHEN 'BOVINO_HEMBRA' THEN 'BECERRA'
        WHEN 'BORREGO_MACHO'  THEN 'BORREGO'
        WHEN 'BORREGO_HEMBRA' THEN 'BORREGA'
        WHEN 'BUFALO_MACHO'  THEN 'BUCERRO'
        WHEN 'BUFALO_HEMBRA' THEN 'BUCERRA'
        WHEN 'EQUIDO_MACHO'  THEN 'POTRO'
        WHEN 'EQUIDO_HEMBRA' THEN 'POTRANCA'
        ELSE NULL
    END;

    IF v_category IS NULL THEN
        RAISE EXCEPTION 'No hay categoría configurada para especie % y sexo %', p_species, p_calf_sex
            USING ERRCODE = 'P0006';
    END IF;

    IF p_lot_id IS NOT NULL THEN
        SELECT production_unit_id INTO v_explicit_lot_unit
          FROM production_unit_lots
         WHERE id = p_lot_id AND id_company = p_id_company;

        IF v_explicit_lot_unit IS NULL THEN
            RAISE EXCEPTION 'El lote % no existe o no pertenece a la empresa %', p_lot_id, p_id_company
                USING ERRCODE = 'P0002';
        END IF;
    END IF;

    IF p_dam_id IS NOT NULL THEN
        SELECT id, current_status, production_unit_id, lot_id, paddock_id, upp_origen
          INTO v_dam_id, v_dam_status, v_dam_production_unit, v_dam_lot_id, v_dam_paddock_id, v_dam_upp_origen
          FROM cattle_livestock WHERE id = p_dam_id AND tenant_id = p_id_company;

        IF v_dam_id IS NULL THEN
            RAISE EXCEPTION 'La madre % no pertenece a la empresa %', p_dam_id, p_id_company
                USING ERRCODE = 'P0002';
        END IF;

    ELSIF p_dam_ear_tag IS NOT NULL THEN
        SELECT count(*) INTO v_match_count
          FROM cattle_livestock WHERE rfid_siniiga = p_dam_ear_tag AND tenant_id = p_id_company;

        IF v_match_count = 1 THEN
            SELECT id, current_status, production_unit_id, lot_id, paddock_id, upp_origen
              INTO v_dam_id, v_dam_status, v_dam_production_unit, v_dam_lot_id, v_dam_paddock_id, v_dam_upp_origen
              FROM cattle_livestock WHERE rfid_siniiga = p_dam_ear_tag AND tenant_id = p_id_company;
        END IF;

    ELSIF p_dam_fire_number IS NOT NULL THEN
        SELECT count(*) INTO v_match_count
          FROM cattle_livestock WHERE numero_fuego = p_dam_fire_number AND tenant_id = p_id_company;

        IF v_match_count = 1 THEN
            SELECT id, current_status, production_unit_id, lot_id, paddock_id, upp_origen
              INTO v_dam_id, v_dam_status, v_dam_production_unit, v_dam_lot_id, v_dam_paddock_id, v_dam_upp_origen
              FROM cattle_livestock WHERE numero_fuego = p_dam_fire_number AND tenant_id = p_id_company;
        END IF;
    END IF;

    IF v_dam_id IS NOT NULL AND v_dam_status = 'PREÑADA' THEN
        UPDATE cattle_livestock SET current_status = 'VACÍA' WHERE id = v_dam_id;
        v_dam_updated := true;
    END IF;

    v_final_lot_id          := COALESCE(p_lot_id, v_dam_lot_id);
    v_final_production_unit := COALESCE(v_explicit_lot_unit, v_dam_production_unit, p_production_unit_id);

    INSERT INTO cattle_livestock (
        tenant_id, category, current_status, birth_date, species,
        mother_id, production_unit_id, lot_id, paddock_id, upp_origen,
        business_model
    ) VALUES (
        p_id_company, v_category, 'ACTIVO', p_birth_date, p_species,
        v_dam_id,
        v_final_production_unit,
        v_final_lot_id,
        COALESCE(v_dam_paddock_id, p_paddock_id),
        v_dam_upp_origen,
        'CRIA'
    ) RETURNING id INTO v_calf_id;

    IF p_birth_weight_kg IS NOT NULL THEN
        INSERT INTO cattle_weight_logs (livestock_id, weight_kg, log_date, source_device)
        VALUES (v_calf_id, p_birth_weight_kg, now(), 'BIRTH_EVENT')
        RETURNING id INTO v_weight_log_id;
    END IF;

    INSERT INTO birth_events (
        id_company, species, dam_id, dam_ear_tag, dam_fire_number,
        calf_sex, calf_id, birth_date, production_unit_id, paddock_id,
        source, notes
    ) VALUES (
        p_id_company, p_species, v_dam_id, p_dam_ear_tag, p_dam_fire_number,
        p_calf_sex, v_calf_id, p_birth_date,
        v_final_production_unit,
        COALESCE(v_dam_paddock_id, p_paddock_id),
        'MOBILE_APP', p_notes
    ) RETURNING id INTO v_event_id;

    RETURN jsonb_build_object(
        'success', true,
        'birth_event_id', v_event_id,
        'calf_id', v_calf_id,
        'category', v_category,
        'dam_id_resolved', v_dam_id,
        'lot_id_resolved', v_final_lot_id,
        'production_unit_id_resolved', v_final_production_unit,
        'dam_status_updated_to_vacia', v_dam_updated,
        'dam_status_warning', CASE
            WHEN v_dam_id IS NULL AND p_species <> 'BORREGO' THEN 'No se pudo identificar a la madre sin ambigüedad; estatus no actualizado, revisar manualmente.'
            WHEN v_dam_id IS NOT NULL AND v_dam_status IS DISTINCT FROM 'PREÑADA' THEN 'La madre no estaba en estatus PREÑADA (estaba en ' || v_dam_status || '); estatus no modificado.'
            ELSE NULL
        END
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.sp_repro_births_get_config(
    p_tenant_id text, p_user_email text
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos revisados estan desactivadas temporalmente (087 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_births_set_config(
    p_tenant_id text, p_user_email text, p_possible_duplicate_days text
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos revisados estan desactivadas temporalmente (087 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_register_birth(
    p_tenant_id text, p_user_email text, p_calf_sex text, p_dam_identifier text DEFAULT NULL, p_dam_id text DEFAULT NULL, p_birth_date text DEFAULT NULL, p_birth_weight_kg text DEFAULT NULL, p_lot_id text DEFAULT NULL, p_production_unit_id text DEFAULT NULL, p_paddock_id text DEFAULT NULL, p_species text DEFAULT NULL, p_notes text DEFAULT NULL, p_force text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos revisados estan desactivadas temporalmente (087 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_births_batch_preview(
    p_tenant_id text, p_user_email text, p_items text, p_default_date text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos revisados estan desactivadas temporalmente (087 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_births_batch_register(
    p_tenant_id text, p_user_email text, p_items text, p_default_date text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos revisados estan desactivadas temporalmente (087 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_register_historical_birth(
    p_tenant_id text, p_user_email text, p_dam_identifier text DEFAULT NULL, p_dam_id text DEFAULT NULL, p_birth_date text DEFAULT NULL, p_date_precision text DEFAULT NULL, p_calf_sex text DEFAULT NULL, p_litter_position text DEFAULT NULL, p_source text DEFAULT NULL, p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos revisados estan desactivadas temporalmente (087 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_void_historical_birth(
    p_tenant_id text, p_user_email text, p_historical_birth_id text, p_reason text
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos revisados estan desactivadas temporalmente (087 revertida).')
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_historical_births(
    p_tenant_id text, p_user_email text, p_dam_identifier text DEFAULT NULL, p_include_voided text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object('status', 'disabled',
                              'message', 'Las funciones de partos revisados estan desactivadas temporalmente (087 revertida).')
$$;

DO $$
DECLARE
    v_md5 text := md5(pg_get_functiondef(to_regprocedure('public.sp_register_birth_event(integer,character varying,character varying,uuid,character varying,character varying,date,uuid,uuid,uuid,numeric,text,character varying)')));
BEGIN
    IF v_md5 <> '8eaf6f52716165a6bc59f8f4a6a7ce4a' THEN
        RAISE WARNING '087 rollback: the restored sp_register_birth_event has md5 % (expected 8eaf6f52716165a6bc59f8f4a6a7ce4a): compare it before relying on it', v_md5;
    END IF;
    IF public.sp_repro_register_birth('0', 'nobody@example.test', 'MACHO')->>'status' IS DISTINCT FROM 'disabled'
       OR public.sp_repro_births_batch_preview('0', 'nobody@example.test', '[]')->>'status' IS DISTINCT FROM 'disabled' THEN
        RAISE EXCEPTION '087 rollback: a tool is not disabled';
    END IF;
    RAISE NOTICE '087 rollback: OK';
END $$;

\if :apply
COMMIT;
\echo '*** 087 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
