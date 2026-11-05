-- 098_seed_return_demo.sql
-- FICTITIOUS return of the prototype animals created by 098_seed_repasto_prototipo.sql. Test company 3 ONLY.
--
-- Why a direct UPDATE and not sp_return_movement: the demo return date (2026-12-10) is in the future, and
-- sp_return_movement rejects future dates on purpose. This script is NOT the way to register a real return.
-- It only touches loan rows that belong to an event of company 3 whose animals carry metadata.source = 'PROTOTIPO_REPASTO'.
-- It ABORTS if any targeted row belongs to another company. Nothing is deleted; the animals keep production_unit_id, lot_id
-- and upp_origen. Each returned animal gets metadata.demo_return = {fictitious: true, ...} so the data cannot be mistaken
-- for a real return.
--
-- Usage: psql -v ON_ERROR_STOP=1 -f 098_seed_return_demo.sql                              (dry run: ROLLBACK)
--        psql -v ON_ERROR_STOP=1 -v apply=true -f 098_seed_return_demo.sql                 (COMMIT)
-- Header variables:
--   return_date   default 2026-12-10   (fictitious)
--   guide         optional: return only the animals of that guide (e.g. -v guide=7139728) to demonstrate a PARTIAL return
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?return_date}
\else
\set return_date 2026-12-10
\endif
\if :{?guide}
\else
\set guide ''
\endif
\if :{?embedded}
\else
BEGIN;
\endif

SELECT set_config('demo098.return_date', :'return_date', true) AS return_date, set_config('demo098.guide', :'guide', true) AS guide;

DO $demo$
DECLARE
    c_company constant int  := 3;
    c_source  constant text := 'PROTOTIPO_REPASTO';
    v_date    date := current_setting('demo098.return_date')::date;
    v_guide   text := nullif(current_setting('demo098.guide'), '');
    v_targets int;
    v_foreign int;
    v_done    int;
    v_open_left int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                    AND table_name = 'cattle_movement_event_animals' AND column_name = 'return_status') THEN
        RAISE EXCEPTION 'ABORT: migration 098 is not applied in this database.';
    END IF;

    -- Targets: OPEN rows of prototype animals (optionally one guide).
    DROP TABLE IF EXISTS pg_temp.demo098_rows;
    CREATE TEMP TABLE demo098_rows ON COMMIT DROP AS
    SELECT ea.id AS row_id, ea.cattle_livestock_id, e.id_company AS event_company, l.tenant_id AS animal_company, e.movement_date, e.reemo_folio
      FROM public.cattle_movement_event_animals ea
      JOIN public.cattle_movement_events e ON e.id = ea.event_id
      JOIN public.cattle_livestock l       ON l.id = ea.cattle_livestock_id
     WHERE ea.return_status = 'OPEN'
       AND l.metadata->>'source' = c_source
       AND (v_guide IS NULL OR e.reemo_folio = v_guide);
    SELECT count(*), count(*) FILTER (WHERE event_company <> c_company OR animal_company <> c_company)
      INTO v_targets, v_foreign FROM demo098_rows;
    IF v_foreign > 0 THEN
        RAISE EXCEPTION 'ABORT: % targeted row(s) belong to a company other than 3. This demo only touches the test company.', v_foreign;
    END IF;
    IF v_targets = 0 THEN
        RAISE EXCEPTION 'ABORT: no OPEN prototype rows found%', coalesce(' for guide ' || v_guide, '');
    END IF;
    IF EXISTS (SELECT 1 FROM demo098_rows WHERE v_date < movement_date) THEN
        RAISE EXCEPTION 'ABORT: the demo return date % is before the departure', v_date;
    END IF;

    UPDATE public.cattle_movement_event_animals ea
       SET return_status = 'RETURNED',
           returned_at   = (v_date::timestamp + interval '12 hours') AT TIME ZONE 'America/Mexico_City'
      FROM demo098_rows t
     WHERE ea.id = t.row_id AND ea.return_status = 'OPEN';
    GET DIAGNOSTICS v_done = ROW_COUNT;

    UPDATE public.cattle_livestock l
       SET metadata = l.metadata || jsonb_build_object('demo_return', jsonb_build_object(
               'fictitious', true, 'return_date', v_date, 'source', c_source, 'register_with', 'direct UPDATE (098_seed_return_demo.sql), not sp_return_movement'))
      FROM demo098_rows t
     WHERE l.id = t.cattle_livestock_id AND l.tenant_id = c_company;

    SELECT count(*) INTO v_open_left FROM public.vw_livestock_out_on_loan v
     WHERE v.id_company = c_company AND v.is_out_on_loan
       AND v.cattle_livestock_id IN (SELECT id FROM public.cattle_livestock WHERE tenant_id = c_company AND metadata->>'source' = c_source);
    RAISE NOTICE 'demo 098: % row(s) marked RETURNED on % (fictitious); % prototype animal(s) still OPEN', v_done, v_date, v_open_left;
END $demo$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 098 DEMO RETURN COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 098 demo return rolled back ***'
\endif
\endif
