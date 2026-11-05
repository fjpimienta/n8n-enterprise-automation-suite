-- 098_seed_repasto_prototipo.sql
-- PROTOTYPE data for the grazing-loan feature (migration 098). Test company ONLY.
--
-- SCOPE (read before running): this script writes rows for company id 3 ("Rancho El Palomar", the suite's test tenant) and
-- reads/creates nothing else. It never touches Santa Lucia (company 8), San Jose, La Pita or Maceo (company 5), any real UPP
-- or any real animal. The only production unit it uses is the fictitious UPP 99-999-9999-999 of company 3.
--   * 31 FICTITIOUS animals: rfid_siniiga = '99' || right(real_tag, 8). The real tag lives in metadata.real_rfid_siniiga
--     (rfid_siniiga is UNIQUE across the whole database, so the real tags cannot be loaded into company 3).
--     metadata.source = 'PROTOTIPO_REPASTO'. Weight stays NULL. birth_date is ESTIMATED (movement date minus the declared
--     months) and flagged as such in metadata.
--   * 1 external destination (third-party UPP 07-068-0171-001, Moises Guichard, Pichucalco, Chiapas).
--   * 3 grazing movements, one per transit guide (7139728, 7139729, PRUEBA-3A-GUIA), each with a REEMO_TRANSIT_GUIDE
--     certificate marked as a test record, and 31 loan rows (return_status = 'OPEN').
-- The fictitious return is NOT here: see 098_seed_return_demo.sql.
-- The REAL load of the 31 animals and the sharecropping (aparceria) model are OUT OF SCOPE.
--
-- Idempotent: every row is looked up before it is created, so a second run changes nothing.
-- Production safety: the script ABORTS if company 3 does not exist, unless -v allow_create_company=true is given, and that
-- flag is meant for a throw-away LOCAL copy only. It also aborts if migration 098 is not applied.
--
-- Usage: psql -v ON_ERROR_STOP=1 -f 098_seed_repasto_prototipo.sql                        (dry run: ROLLBACK)
--        psql -v ON_ERROR_STOP=1 -v apply=true -f 098_seed_repasto_prototipo.sql           (COMMIT)
--        LOCAL only, empty copy:  add -v allow_create_company=true
-- Header variables (override with -v name=value):
--   business_model        default CRIA  -- PENDING CONFIRMATION WITH THE OWNER; allowed: CRIA | ENGORDA | REPRODUCCION
--   movement_date         default 2026-10-14   (date of the three guides)
--   expected_return_date  default 2026-12-14
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?allow_create_company}
\else
\set allow_create_company false
\endif
\if :{?business_model}
\else
\set business_model CRIA
\endif
\if :{?movement_date}
\else
\set movement_date 2026-10-14
\endif
\if :{?expected_return_date}
\else
\set expected_return_date 2026-12-14
\endif
\if :{?embedded}
\else
BEGIN;
\endif

SELECT set_config('seed098.allow_create_company', :'allow_create_company', true) AS allow_create_company,
       set_config('seed098.business_model', :'business_model', true)             AS business_model,
       set_config('seed098.movement_date', :'movement_date', true)               AS movement_date,
       set_config('seed098.expected_return_date', :'expected_return_date', true) AS expected_return_date;

DO $seed$
DECLARE
    c_company    constant int  := 3;
    c_upp_code   constant text := '99-999-9999-999';
    c_source     constant text := 'PROTOTIPO_REPASTO';
    v_allow      boolean := current_setting('seed098.allow_create_company')::boolean;
    v_model      text    := current_setting('seed098.business_model');
    v_move       date    := current_setting('seed098.movement_date')::date;
    v_expected   date    := current_setting('seed098.expected_return_date')::date;
    v_name       text;
    v_active     boolean;
    v_unit       uuid;
    v_unit_status text;
    v_dest       uuid;
    v_ev         uuid;
    v_guide      text;
    v_new_animals int := 0;
    v_new_events  int := 0;
    v_new_rows    int := 0;
    v_new_certs   int := 0;
    v_total       int;
    r             record;
BEGIN
    -- ---- guards -------------------------------------------------------------------------------------------------
    IF v_model NOT IN ('CRIA', 'ENGORDA', 'REPRODUCCION') THEN
        RAISE EXCEPTION 'ABORT: business_model % is not allowed', v_model;
    END IF;
    IF v_expected <= v_move THEN
        RAISE EXCEPTION 'ABORT: expected_return_date (%) must be after movement_date (%)', v_expected, v_move;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                    AND table_name = 'cattle_movement_event_animals' AND column_name = 'return_status')
       OR to_regclass('public.vw_livestock_out_on_loan') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 098 is not applied in this database.';
    END IF;

    SELECT company_name, is_active INTO v_name, v_active FROM public.companys WHERE id_company = c_company;
    IF NOT FOUND THEN
        IF v_allow THEN
            INSERT INTO public.companys (id_company, company_name) VALUES (c_company, 'Rancho El Palomar');
            RAISE NOTICE 'seed 098: company 3 created (LOCAL only, allow_create_company=true)';
            v_name := 'Rancho El Palomar'; v_active := true;
        ELSE
            RAISE EXCEPTION 'ABORT: company 3 (the test company) does not exist in this database. The seed never creates it unless -v allow_create_company=true is given (LOCAL copies only).';
        END IF;
    END IF;
    IF v_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ABORT: company 3 is inactive.';
    END IF;
    IF v_name NOT IN ('Rancho El Palomar', 'Pista de Hielo') THEN
        RAISE EXCEPTION 'ABORT: company 3 is named "%", not the known test company; refusing to write prototype data into it.', v_name;
    END IF;

    -- ---- fictitious UPP of company 3 -----------------------------------------------------------------------------
    SELECT id, registry_status INTO v_unit, v_unit_status FROM public.production_units
     WHERE id_company = c_company AND upp_code = c_upp_code;
    IF NOT FOUND THEN
        INSERT INTO public.production_units (id_company, upp_code, ranch_name)
        VALUES (c_company, c_upp_code, 'UPP Ficticia de Pruebas') RETURNING id INTO v_unit;
        RAISE NOTICE 'seed 098: fictitious UPP % created in company 3', c_upp_code;
    ELSIF v_unit_status IN ('BLOQUEADA', 'BAJA', 'SUSPENDIDA') THEN
        RAISE EXCEPTION 'ABORT: the fictitious UPP % has registry_status %', c_upp_code, v_unit_status;
    END IF;

    -- ---- third-party destination ----------------------------------------------------------------------------------
    SELECT id INTO v_dest FROM public.external_destinations
     WHERE id_company = c_company AND name = 'Moisés Guichard — UPP 07-068-0171-001 (Pichucalco, Chiapas)';
    IF NOT FOUND THEN
        INSERT INTO public.external_destinations (id_company, name, destination_type, normative_type, notes)
        VALUES (c_company, 'Moisés Guichard — UPP 07-068-0171-001 (Pichucalco, Chiapas)', 'THIRD_PARTY_RANCH', 'UPP',
                c_source || ': third-party UPP receiving animals for grazing (repasto); test record in the test company.')
        RETURNING id INTO v_dest;
    END IF;

    -- ---- animals (31) --------------------------------------------------------------------------------------------
    DROP TABLE IF EXISTS pg_temp.seed098_animals;
    CREATE TEMP TABLE seed098_animals (real_tag text, guide text, category text, sex text, months int) ON COMMIT DROP;
    INSERT INTO seed098_animals VALUES
        ('0724388351','7139728','BECERRA','HEMBRA',9),   ('0724388340','7139728','NOVILLONA','HEMBRA',14),
        ('0724388357','7139728','BECERRA','HEMBRA',11),  ('0724388383','7139728','BECERRA','HEMBRA',10),
        ('0724388327','7139728','BECERRA','HEMBRA',10),  ('0724388385','7139728','BECERRA','HEMBRA',11),
        ('0724388338','7139728','NOVILLONA','HEMBRA',13),('0724388374','7139728','NOVILLONA','HEMBRA',13),
        ('0724388369','7139728','BECERRA','HEMBRA',10),  ('0724388345','7139728','NOVILLONA','HEMBRA',14),
        ('0724388339','7139728','NOVILLONA','HEMBRA',13),('0724388344','7139728','BECERRA','HEMBRA',11),
        ('0719880159','7139728','TORO','MACHO',80),
        ('0724756886','7139729','BECERRA','HEMBRA',8),   ('0724756996','7139729','BECERRA','HEMBRA',9),
        ('0724756946','7139729','BECERRA','HEMBRA',9),   ('0724756916','7139729','BECERRA','HEMBRA',9),
        ('0724756865','7139729','BECERRA','HEMBRA',9),   ('0724756913','7139729','BECERRA','HEMBRA',8),
        ('0724756854','7139729','BECERRA','HEMBRA',8),   ('0724756923','7139729','BECERRA','HEMBRA',7),
        ('0724756845','7139729','BECERRA','HEMBRA',8),   ('0724756870','7139729','BECERRA','HEMBRA',8),
        ('0724756848','7139729','BECERRA','HEMBRA',8),   ('0724756953','7139729','BECERRA','HEMBRA',8),
        ('0724756892','7139729','BECERRA','HEMBRA',6),   ('0724756962','7139729','BECERRA','HEMBRA',8),
        ('0724757019','7139729','BECERRA','HEMBRA',8),   ('0724756914','7139729','BECERRA','HEMBRA',8),
        ('0724756937','7139729','BECERRA','HEMBRA',8),
        ('0724019839','PRUEBA-3A-GUIA','NOVILLONA','HEMBRA',13);

    -- Self-check of the fixture list: 31 rows, no duplicates, unique fictitious tags, the agreed distribution.
    SELECT count(*) INTO v_total FROM seed098_animals;
    IF v_total <> 31
       OR (SELECT count(DISTINCT real_tag) FROM seed098_animals) <> 31
       OR (SELECT count(DISTINCT '99' || right(real_tag, 8)) FROM seed098_animals) <> 31
       OR (SELECT count(*) FROM seed098_animals WHERE guide = '7139728' AND category = 'BECERRA') <> 7
       OR (SELECT count(*) FROM seed098_animals WHERE guide = '7139728' AND category = 'NOVILLONA') <> 5
       OR (SELECT count(*) FROM seed098_animals WHERE guide = '7139728' AND category = 'TORO') <> 1
       OR (SELECT count(*) FROM seed098_animals WHERE guide = '7139729' AND category = 'BECERRA') <> 17
       OR (SELECT count(*) FROM seed098_animals WHERE guide = 'PRUEBA-3A-GUIA' AND category = 'NOVILLONA') <> 1 THEN
        RAISE EXCEPTION 'ABORT: the fixture list is not the agreed 31 animals';
    END IF;
    IF EXISTS (SELECT 1 FROM seed098_animals a JOIN public.cattle_livestock l ON l.rfid_siniiga = '99' || right(a.real_tag, 8)
                WHERE l.tenant_id <> c_company) THEN
        RAISE EXCEPTION 'ABORT: a fictitious tag already belongs to another company';
    END IF;

    INSERT INTO public.cattle_livestock
        (tenant_id, rfid_siniiga, business_model, category, current_status, species, birth_date, current_weight_kg,
         production_unit_id, metadata)
    SELECT c_company, '99' || right(a.real_tag, 8), v_model, a.category, 'ACTIVO', 'BOVINO',
           (v_move - make_interval(months => a.months))::date, NULL, v_unit,
           jsonb_build_object(
               'source', c_source,
               'prototype', true,
               'real_rfid_siniiga', a.real_tag,
               'transit_guide', a.guide,
               'sex', a.sex,
               'declared_age_months', a.months,
               'birth_date_estimated', true,
               'note', 'Fictitious tag (99 + last 8 digits of the real tag). Real load is out of scope of migration 098.')
      FROM seed098_animals a
     WHERE NOT EXISTS (SELECT 1 FROM public.cattle_livestock l
                        WHERE l.tenant_id = c_company AND l.rfid_siniiga = '99' || right(a.real_tag, 8));
    GET DIAGNOSTICS v_new_animals = ROW_COUNT;

    -- ---- movements (one per guide), certificates, loan rows -----------------------------------------------------
    FOR v_guide IN SELECT DISTINCT guide FROM seed098_animals ORDER BY 1 LOOP
        SELECT id INTO v_ev FROM public.cattle_movement_events WHERE id_company = c_company AND reemo_folio = v_guide;
        IF NOT FOUND THEN
            INSERT INTO public.cattle_movement_events
                (id_company, production_unit_origin_id, external_destination_id, reemo_folio, movement_date, captured_by,
                 notes, purpose, expected_return_date)
            VALUES (c_company, v_unit, v_dest, v_guide, v_move, 'seed 098',
                    c_source || ': grazing (repasto) to the third-party UPP 07-068-0171-001. TEST RECORD in the test company; '
                    || CASE WHEN v_guide = 'PRUEBA-3A-GUIA' THEN 'the folio is a test marker, not a real guide.' ELSE 'the folio is the real guide number used to build the prototype.' END,
                    'REPASTO', v_expected)
            RETURNING id INTO v_ev;
            v_new_events := v_new_events + 1;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM public.compliance_certificates
                        WHERE id_company = c_company AND certificate_type = 'REEMO_TRANSIT_GUIDE' AND folio = v_guide) THEN
            INSERT INTO public.compliance_certificates (id_company, movement_event_id, certificate_type, folio, issued_at, notes)
            VALUES (c_company, v_ev, 'REEMO_TRANSIT_GUIDE', v_guide, v_move,
                    c_source || ': test certificate in the test company'
                    || CASE WHEN v_guide = 'PRUEBA-3A-GUIA' THEN ' (test folio).' ELSE '.' END);
            v_new_certs := v_new_certs + 1;
        END IF;

        INSERT INTO public.cattle_movement_event_animals (event_id, cattle_livestock_id, return_status)
        SELECT v_ev, l.id, 'OPEN'
          FROM seed098_animals a
          JOIN public.cattle_livestock l ON l.tenant_id = c_company AND l.rfid_siniiga = '99' || right(a.real_tag, 8)
         WHERE a.guide = v_guide
        ON CONFLICT (event_id, cattle_livestock_id) DO NOTHING;
        GET DIAGNOSTICS v_total = ROW_COUNT;
        v_new_rows := v_new_rows + v_total;
    END LOOP;

    -- ---- verification -------------------------------------------------------------------------------------------
    SELECT count(*) INTO v_total FROM public.vw_livestock_out_on_loan
     WHERE id_company = c_company AND is_out_on_loan
       AND cattle_livestock_id IN (SELECT id FROM public.cattle_livestock WHERE tenant_id = c_company AND metadata->>'source' = c_source);
    IF v_total <> 31 THEN
        RAISE EXCEPTION 'ABORT: expected 31 prototype animals OPEN in the loan view, found % (an earlier partial return?)', v_total;
    END IF;
    IF EXISTS (SELECT 1 FROM public.cattle_livestock WHERE metadata->>'source' = c_source AND tenant_id <> c_company) THEN
        RAISE EXCEPTION 'ABORT: prototype rows found outside company 3';
    END IF;
    RAISE NOTICE 'seed 098: created % animals, % movements, % certificates, % loan rows (31 OPEN in company 3)',
        v_new_animals, v_new_events, v_new_certs, v_new_rows;
END $seed$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 098 SEED (prototype) COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 098 seed rolled back ***'
\endif
\endif
