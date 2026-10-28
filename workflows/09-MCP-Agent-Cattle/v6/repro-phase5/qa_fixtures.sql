-- qa_fixtures.sql — QA fixtures for the reproduction agent tools. COMPANY 3 ("Rancho El Palomar", the test company) ONLY.
--
-- ##########################################################################################################################
-- #  UNTESTED. Nobody has run this file. Run it FIRST on LOCAL (dry run, then apply), read the output, and only then on        #
-- #  production. It writes ONLY to company 3. It aborts if company 3 is not "Rancho El Palomar", and it never mentions tenant 5.#
-- #  THERE IS NO CLEANUP SCRIPT, ON PURPOSE: company 3 is in production and births, empadre entries and historical births are   #
-- #  append-only. The QA events (births, calves, palpations, empadre entries, services) REMAIN as residue in the test company.  #
-- #  Every fixture row carries a QA marker: tags 9999<run>NNNNN (the 99 prefix is no real INEGI state), fire numbers QA5R<run>-..#
-- ##########################################################################################################################
--
-- What it creates in company 3 (all inside ONE transaction; dry run by default):
--   * 2 production units (QA5R<run> UPP Norte / UPP Sur) and 4 lots: "QA5R<run> Lote Maternidad" (Norte), "QA5R<run> Lote Repetido" (in BOTH
--     UPPs, to test a name repeated across production units), "QA5R<run> Lote Sur" (Sur);
--   * 38 animals (dams, a synthetic S/N pair, a PREÑADA stale-calving cow, palpation animals, bulls, heifers ...); see the output table.
--     The two S/N animals share a fire number and carry rfid_siniiga = 'S/N-<numero_fuego>-<n>' (the real pattern of the local data:
--     rfid_siniiga is NOT NULL and UNIQUE, so a NULL tag is impossible). Checked by reading the repo: cattle_livestock_rfid_siniiga_key and
--     cattle_livestock_electronic_rfid_key are the only unique constraints (numero_fuego may repeat on purpose: vw_duplicate_fire_numbers);
--     trg_cattle_livestock_identifier_history is AFTER UPDATE only, so inserting writes no history row (the weight trigger later UPDATEs
--     current_weight_kg, which changes no identifier and so also writes none);
--   * a few fixture palpations / weights written directly, the way the 2023 bulk load did (Spanish JSON keys);
--   * the uterine-code mapping of company 3 (UNE, UTCL1-3, NR, RP, NO APTO, UTC2) with source 'QA5_FIXTURE' and confirmed_by
--     'qa5 (fixture, no confirmation)' — so the palpation dialogs behave like company 5. Existing rows are never overwritten.
-- Requires migrations 084 - 088 and 090 applied (it checks). Nothing in this file has been run against any database. The INSERT shapes are the ones the migration tests run on the throwaway
-- database; running them against company 3 of production is what is UNTESTED.
--
-- Usage (dry run is the default; each run number 1-9 creates a NEW set of fixtures; the tags of run N are 9999N#####):
--   psql -v ON_ERROR_STOP=1 -v run=1 -f qa_fixtures.sql                 -> dry run (rolled back; prints the table of identifiers)
--   psql -v ON_ERROR_STOP=1 -v run=1 -v apply=true -f qa_fixtures.sql   -> commit
-- The QA documents (REPRO_QA_SCRIPT.md) use run 1. For another run replace the 5th digit of every tag and the "R1" in names with the run.

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?run}
\else
\set run 1
\endif

BEGIN;
SELECT set_config('qa5.run', :'run', true);

DO $$
DECLARE
    v_run  integer := current_setting('qa5.run')::integer;
    v_co   integer := 3;                 -- the test company; this file has no other company anywhere
    v_name text;
BEGIN
    IF v_run NOT BETWEEN 1 AND 9 THEN RAISE EXCEPTION 'ABORT: run must be 1..9'; END IF;
    SELECT company_name INTO v_name FROM public.companys WHERE id_company = v_co AND is_active IS TRUE;
    IF v_name IS DISTINCT FROM 'Rancho El Palomar' THEN
        RAISE EXCEPTION 'ABORT: company 3 is "%" here, not "Rancho El Palomar". Not touching it.', v_name;
    END IF;
    IF coalesce(public.fn_company_business_domain(v_co), '') = 'PALM' THEN RAISE EXCEPTION 'ABORT: company 3 is a palm company'; END IF;
    IF to_regprocedure('public.sp_repro_register_birth(text,text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL
       OR to_regprocedure('public.sp_repro_get_dam_history(text,text,text,text)') IS NULL
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'repro_condition_codes' AND column_name = 'meaning') THEN
        RAISE EXCEPTION 'ABORT: migrations 084 - 088 and 090 must be applied here first.';
    END IF;
    -- rfid_siniiga is UNIQUE across ALL companies: check the whole table, not only company 3
    IF EXISTS (SELECT 1 FROM public.cattle_livestock WHERE (length(rfid_siniiga) = 10 AND rfid_siniiga >= '9999' || v_run || '00001' AND rfid_siniiga <= '9999' || v_run || '00099')
                                                           OR rfid_siniiga IN ('S/N-QA5R' || v_run || '-1450-1', 'S/N-QA5R' || v_run || '-1450-2')) THEN
        RAISE EXCEPTION 'ABORT: the fixtures of run % already exist in company 3. Use another -v run=N.', v_run;
    END IF;
END $$;

\echo === company 3 (must be the test company)
SELECT id_company, company_name, is_active FROM public.companys WHERE id_company = 3;

CREATE TEMP TABLE qa_fx (idx integer, k text, rfid text, fuego text, category text, status text, id uuid) ON COMMIT DROP;

DO $$
DECLARE
    v_run integer := current_setting('qa5.run')::integer;
    v_co  integer := 3;
    v_pu1 uuid;
    v_pu2 uuid;
    r     record;
    v_id  uuid;
    v_tag text;
BEGIN
    INSERT INTO public.production_units (id_company, upp_code, ranch_name) VALUES (v_co, '99-50' || v_run || '-0001-001', 'QA5R' || v_run || ' UPP Norte') RETURNING id INTO v_pu1;
    INSERT INTO public.production_units (id_company, upp_code, ranch_name) VALUES (v_co, '99-50' || v_run || '-0002-001', 'QA5R' || v_run || ' UPP Sur') RETURNING id INTO v_pu2;
    INSERT INTO public.production_unit_lots (id_company, production_unit_id, lot_name, tenure_type) VALUES
        (v_co, v_pu1, 'QA5R' || v_run || ' Lote Maternidad', 'PROPIO'),
        (v_co, v_pu1, 'QA5R' || v_run || ' Lote Repetido', 'PROPIO'),
        (v_co, v_pu2, 'QA5R' || v_run || ' Lote Repetido', 'PROPIO'),
        (v_co, v_pu2, 'QA5R' || v_run || ' Lote Sur', 'PROPIO');

    FOR r IN SELECT * FROM (VALUES
    (1, 'D1', 'VACA', 'PREÑADA', 'QA5R{r}-D1', NULL::text),
    (2, 'D2', 'VACA', 'ACTIVO', 'QA5R{r}-D2', NULL::text),
    (3, 'D3', 'VACA', 'ACTIVO', 'QA5R{r}-DUP', NULL::text),
    (4, 'D4', 'NOVILLONA', 'VACÍA', 'QA5R{r}-DUP', NULL::text),
    (5, 'SN1', 'VACA', 'ACTIVO', 'QA5R{r}-1450', 'S/N-QA5R{r}-1450-1'),
    (6, 'SN2', 'VACA', 'VACÍA', 'QA5R{r}-1450', 'S/N-QA5R{r}-1450-2'),
    (7, 'B1', 'VACA', 'ACTIVO', 'QA5R{r}-B1', NULL::text),
    (8, 'B2', 'VACA', 'ACTIVO', 'QA5R{r}-B2', NULL::text),
    (9, 'B3', 'VACA', 'ACTIVO', 'QA5R{r}-B3', NULL::text),
    (10, 'B4', 'VACA', 'ACTIVO', 'QA5R{r}-B4', NULL::text),
    (11, 'B5', 'VACA', 'ACTIVO', 'QA5R{r}-B5', NULL::text),
    (12, 'D11', 'VACA', 'PREÑADA', 'QA5R{r}-D11', NULL::text),
    (13, 'D12', 'VACA', 'VACÍA', 'QA5R{r}-D12', NULL::text),
    (14, 'D13', 'VACA', 'PREÑADA', 'QA5R{r}-D13', NULL::text),
    (15, 'P1', 'VACA', 'ACTIVO', 'QA5R{r}-P1', NULL::text),
    (16, 'P2', 'VACA', 'ACTIVO', 'QA5R{r}-P2', NULL::text),
    (17, 'P3', 'VACA', 'ACTIVO', 'QA5R{r}-P3', NULL::text),
    (18, 'P4', 'VACA', 'ACTIVO', 'QA5R{r}-P4', NULL::text),
    (19, 'P5', 'VACA', 'ACTIVO', 'QA5R{r}-P5', NULL::text),
    (20, 'P6', 'VACA', 'ACTIVO', 'QA5R{r}-P6', NULL::text),
    (21, 'P7', 'VACA', 'ACTIVO', 'QA5R{r}-P7', NULL::text),
    (22, 'P8', 'VACA', 'ACTIVO', 'QA5R{r}-P8', NULL::text),
    (23, 'H1', 'VACA', 'ACTIVO', 'QA5R{r}-H1', NULL::text),
    (24, 'H2', 'VACA', 'ACTIVO', 'QA5R{r}-H2', NULL::text),
    (25, 'S1', 'VACA', 'ACTIVO', 'QA5R{r}-S1', NULL::text),
    (26, 'S2', 'VACA', 'ACTIVO', 'QA5R{r}-S2', NULL::text),
    (27, 'T1', 'TORO', 'ACTIVO', 'QA5R{r}-T1', NULL::text),
    (28, 'T2', 'TORO', 'ACTIVO', 'QA5R{r}-TORODUP', NULL::text),
    (29, 'T3', 'TORO', 'ACTIVO', 'QA5R{r}-TORODUP', NULL::text),
    (30, 'E1', 'NOVILLONA', 'ACTIVO', 'QA5R{r}-E1', NULL::text),
    (31, 'E2', 'NOVILLONA', 'ACTIVO', 'QA5R{r}-E2', NULL::text),
    (32, 'E3', 'NOVILLONA', 'ACTIVO', 'QA5R{r}-E3', NULL::text),
    (33, 'E4', 'NOVILLONA', 'ACTIVO', 'QA5R{r}-E4', NULL::text),
    (34, 'E5', 'NOVILLONA', 'ACTIVO', 'QA5R{r}-E5', NULL::text),
    (35, 'O1', 'VACA', 'VACÍA', 'QA5R{r}-O1', NULL::text),
    (36, 'X1', 'VACA', 'ACTIVO', 'QA5R{r}-X1', NULL::text),
    (37, 'X2', 'VACA', 'ACTIVO', 'QA5R{r}-X2', NULL::text),
    (38, 'P9', 'VACA', 'ACTIVO', 'QA5R{r}-P9', NULL::text)
    ) AS a (idx, k, category, status, fuego, rfid_txt) ORDER BY idx LOOP
        -- rfid_siniiga is NOT NULL and globally UNIQUE: the numeric QA tag, or the real synthetic pattern 'S/N-<numero_fuego>-<n>' for the S/N animals
        v_tag := CASE WHEN r.rfid_txt IS NULL THEN '9999' || v_run || lpad(r.idx::text, 5, '0') ELSE replace(r.rfid_txt, '{r}', v_run::text) END;
        INSERT INTO public.cattle_livestock (tenant_id, rfid_siniiga, business_model, category, current_status, numero_fuego)
        VALUES (v_co, v_tag, 'CRIA', r.category, r.status, replace(r.fuego, '{r}', v_run::text))
        RETURNING id INTO v_id;
        INSERT INTO qa_fx VALUES (r.idx, r.k, v_tag, replace(r.fuego, '{r}', v_run::text), r.category, r.status, v_id);
    END LOOP;

    -- palpations written directly, as the 2023 bulk load did (Spanish keys); event_date = a number of days ago
    INSERT INTO public.cattle_health_logs (livestock_id, event_type, description, medicines_json, event_date)
    SELECT f.id, 'PALPACION', 'QA5 fixture', p.js::jsonb, now() - make_interval(days => p.d)
      FROM (VALUES ('D11', 400, '{"resultado":"PRENADA","dias_gestacion":"60","condicion_utero":"N/A"}'),
                   ('D12', 150, '{"resultado":"VACIA","condicion_utero":"MATRIZ OCUPADA"}'),
                   ('O1',  100, '{"resultado":"VACIA","condicion_utero":"UNE"}')) AS p (k, d, js)
      JOIN qa_fx f ON f.k = p.k;

    -- weights (the trigger update_current_weight sets current_weight_kg)
    INSERT INTO public.cattle_weight_logs (livestock_id, weight_kg, log_date, source_device)
    SELECT f.id, w.kg, now() - make_interval(days => w.d), 'QA5_FIXTURE'
      FROM (VALUES ('E1', 320, 5), ('E3', 310, 5), ('E4', 305, 5), ('E5', 306, 5)) AS w (k, kg, d)
      JOIN qa_fx f ON f.k = w.k;

    -- the uterine-code mapping of company 3 (never overwrites an existing row)
    INSERT INTO public.repro_condition_codes (id_company, code, repro_condition, meaning, source, confirmed_by, confirmed_at) VALUES
        (v_co, 'UNE',   'ESTATICA', NULL, 'QA5_FIXTURE', 'qa5 (fixture, no confirmation)', now()),
        (v_co, 'UTCL1', 'CICLANDO', NULL, 'QA5_FIXTURE', 'qa5 (fixture, no confirmation)', now()),
        (v_co, 'UTCL2', 'CICLANDO', NULL, 'QA5_FIXTURE', 'qa5 (fixture, no confirmation)', now()),
        (v_co, 'UTCL3', 'CICLANDO', NULL, 'QA5_FIXTURE', 'qa5 (fixture, no confirmation)', now()),
        (v_co, 'NR',      NULL, 'NOT_EXAMINED', 'QA5_FIXTURE', 'qa5 (fixture, no confirmation)', now()),
        (v_co, 'RP',      NULL, 'POSTPARTUM',   'QA5_FIXTURE', 'qa5 (fixture, no confirmation)', now()),
        (v_co, 'NO APTO', NULL, 'UNFIT',        'QA5_FIXTURE', 'qa5 (fixture, no confirmation)', now()),
        (v_co, 'UTC2',    NULL, NULL,           'QA5_FIXTURE pending', NULL, NULL)
    ON CONFLICT (id_company, code) DO NOTHING;
END $$;

\echo === FIXTURE TABLE (the identifiers the QA dialogs use; the S/N animals carry the synthetic tag S/N-<numero_fuego>-<n>)
SELECT idx, k AS key, rfid AS tag, fuego, category, status FROM qa_fx ORDER BY idx;
\echo === lots and production units created
SELECT pu.ranch_name AS upp, l.lot_name AS lote FROM public.production_units pu JOIN public.production_unit_lots l ON l.production_unit_id = pu.id
 WHERE pu.id_company = 3 AND pu.ranch_name LIKE 'QA5R' || current_setting('qa5.run') || '%' ORDER BY 1, 2;
\echo === other companies untouched by this file: nothing to check (it has no other company id)
\echo === rows created in company 3
SELECT (SELECT count(*) FROM qa_fx) AS animals,
       (SELECT count(*) FROM public.production_units WHERE id_company = 3 AND ranch_name LIKE 'QA5R' || current_setting('qa5.run') || '%') AS production_units;

\if :apply
COMMIT;
\echo '*** qa_fixtures COMMITTED (company 3) ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
