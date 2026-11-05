-- 098_rollback.sql
-- Reverts 098 without DROP or DELETE:
--   * sp_solicitar_venta_orden: the two loan blocks and the two FIFO exclusions are removed by exact inverse text replacement, so the function
--     returns byte-for-byte to the definition it had before 098 (verify with md5(pg_get_functiondef) taken BEFORE the
--     apply in the SAME environment; never compare across PG 15 and PG 16).
--   * guard triggers: disabled (ALTER TABLE ... DISABLE TRIGGER); their functions stay.
--   * sp_return_movement: replaced by a stub that answers {"status":"disabled"}.
--   * vw_livestock_out_on_loan: replaced by the same column list with no rows.
--   * columns, CHECKs and the partial unique index stay (unused). Loan rows are NOT modified: re-applying 098 restores
--     the protection with the same state. Pass -v cancel_open=true to mark every OPEN row as CANCELLED instead.
-- While this rollback is in effect, animals with OPEN rows are NOT protected against sale. The script prints how many.
-- Usage: psql -v ON_ERROR_STOP=1 -f 098_rollback.sql            (dry run: ROLLBACK)
--        psql -v ON_ERROR_STOP=1 -v apply=true -f 098_rollback.sql   (COMMIT)
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?cancel_open}
\else
\set cancel_open false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

DO $$
DECLARE
    c_sig   constant text := 'public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)';
    v_def   text;
    v_new   text;
    add_txt constant text :=
E'    -- 098: animals out on loan (open grazing movement) cannot be sold\n'
'    UPDATE tmp_sale_order_items t\n'
'       SET error = ''Animal fuera en repasto (guía '' || coalesce(m.reemo_folio, ''s/n'') || '', retorno esperado ''\n'
'                   || coalesce(m.expected_return_date::text, ''s/f'') || ''): no se puede vender''\n'
'      FROM (SELECT ea.cattle_livestock_id, ev.id_company, ev.reemo_folio, ev.expected_return_date\n'
'              FROM cattle_movement_event_animals ea\n'
'              JOIN cattle_movement_events ev ON ev.id = ea.event_id\n'
'             WHERE ea.return_status = ''OPEN'') m\n'
'     WHERE t.error IS NULL AND t.livestock_id = m.cattle_livestock_id AND t.id_company = m.id_company;\n';
    ins_f constant text :=
E'               -- 098: FIFO skips animals out on loan\n'
'               AND NOT EXISTS (SELECT 1 FROM cattle_movement_event_animals ea\n'
'                                WHERE ea.cattle_livestock_id = l.id AND ea.return_status = ''OPEN'')\n';
    n int;
    nf int;
    v_open int;
BEGIN
    v_def := pg_get_functiondef(c_sig::regprocedure);
    n  := (length(v_def) - length(replace(v_def, add_txt, ''))) / length(add_txt);
    nf := (length(v_def) - length(replace(v_def, ins_f, ''))) / length(ins_f);
    IF n = 0 AND nf = 0 THEN
        RAISE NOTICE '098 rollback: sp_solicitar_venta_orden has no 098 text; nothing to restore.';
    ELSIF n = 2 AND nf = 2 THEN
        v_new := replace(replace(v_def, add_txt, ''), ins_f, '');
        IF v_new LIKE '%-- 098:%' THEN
            RAISE EXCEPTION 'ABORT: residual 098 text after removing the blocks.';
        END IF;
        EXECUTE v_new;
        RAISE NOTICE '098 rollback: sp_solicitar_venta_orden restored (md5 now %)', md5(pg_get_functiondef(c_sig::regprocedure));
    ELSE
        RAISE EXCEPTION 'ABORT: expected 0 or 2 loan blocks and 0 or 2 FIFO exclusions, found % and %. The function was edited by hand; restore it from a backup.', n, nf;
    END IF;

    IF to_regclass('public.cattle_movement_event_animals') IS NOT NULL
       AND EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'cattle_movement_event_animals' AND column_name = 'return_status') THEN
        SELECT count(*) INTO v_open FROM public.cattle_movement_event_animals WHERE return_status = 'OPEN';
        RAISE NOTICE '098 rollback: % OPEN loan row(s) lose their sale protection.', v_open;
    END IF;
END $$;

-- Disable the guards (IF EXISTS on the table is not available for triggers: check first).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_block_out_on_loan_status' AND NOT tgisinternal) THEN
        ALTER TABLE public.cattle_livestock DISABLE TRIGGER trg_block_out_on_loan_status;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_close_loan_on_death' AND NOT tgisinternal) THEN
        ALTER TABLE public.cattle_livestock DISABLE TRIGGER trg_close_loan_on_death;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_guard_movement_animal_open' AND NOT tgisinternal) THEN
        ALTER TABLE public.cattle_movement_event_animals DISABLE TRIGGER trg_guard_movement_animal_open;
    END IF;
END $$;

-- Optional: close the loans instead of leaving them OPEN.
-- trg_check_movement_animal_tenant (fires on UPDATE too) resolves the animal's tenant through production_unit_id and raises
-- when it is NULL. A row whose animal has no production unit therefore cannot be updated without touching that guard,
-- which this script never does: such rows are skipped, stay OPEN and are reported. With the guards disabled above they
-- protect nothing, so leaving them OPEN is harmless; close them by hand after fixing the animal's production unit.
\if :cancel_open
DO $$
DECLARE
    v_cancelled int;
    v_skipped   int;
BEGIN
    UPDATE public.cattle_movement_event_animals ea
       SET return_status = 'CANCELLED'
     WHERE ea.return_status = 'OPEN'
       AND EXISTS (SELECT 1 FROM public.cattle_livestock l
                     JOIN public.production_units pu ON pu.id = l.production_unit_id
                    WHERE l.id = ea.cattle_livestock_id);
    GET DIAGNOSTICS v_cancelled = ROW_COUNT;
    SELECT count(*) INTO v_skipped FROM public.cattle_movement_event_animals WHERE return_status = 'OPEN';
    RAISE NOTICE '098 rollback: % OPEN row(s) cancelled, % skipped (animal without production unit).', v_cancelled, v_skipped;
END $$;
\endif

-- Stub for the return procedure.
DO $$
BEGIN
    IF to_regprocedure('public.sp_return_movement(uuid,uuid[],date,character varying)') IS NOT NULL THEN
        CREATE OR REPLACE FUNCTION public.sp_return_movement(
            p_event_id uuid, p_animals uuid[], p_return_date date, p_actor_email character varying)
        RETURNS jsonb LANGUAGE sql AS $f$
            SELECT jsonb_build_object('status', 'disabled', 'message', 'sp_return_movement is disabled (098 rolled back)')
        $f$;
    END IF;
END $$;

-- Empty view with the same columns.
DO $$
BEGIN
    IF to_regclass('public.vw_livestock_out_on_loan') IS NOT NULL THEN
        CREATE OR REPLACE VIEW public.vw_livestock_out_on_loan AS
        SELECT e.id_company,
               e.id                          AS event_id,
               e.reemo_folio,
               e.movement_date,
               e.expected_return_date,
               e.purpose,
               ea.id                         AS event_animal_id,
               ea.cattle_livestock_id,
               l.rfid_siniiga,
               l.numero_fuego,
               l.category,
               l.species,
               l.current_status,
               e.production_unit_origin_id,
               pu.ranch_name                 AS origin_upp_name,
               ed.name                       AS destination_name,
               ed.contact_info               AS destination_contact,
               ea.return_status,
               ea.returned_at,
               (ea.return_status = 'OPEN')   AS is_out_on_loan,
               CASE WHEN bool_or(ea.return_status = 'OPEN') OVER (PARTITION BY e.id) THEN 'OPEN'
                    WHEN bool_or(ea.return_status = 'RETURNED') OVER (PARTITION BY e.id) THEN 'RETURNED'
                    ELSE 'CLOSED' END AS event_state,
               (ea.return_status = 'OPEN' AND e.expected_return_date < (now() AT TIME ZONE 'America/Mexico_City')::date) AS is_overdue,
               ea.created_at
          FROM public.cattle_movement_event_animals ea
          JOIN public.cattle_movement_events e ON e.id = ea.event_id
          JOIN public.cattle_livestock l       ON l.id = ea.cattle_livestock_id
          LEFT JOIN public.production_units pu ON pu.id = e.production_unit_origin_id
          LEFT JOIN public.external_destinations ed ON ed.id = e.external_destination_id
         WHERE false;
    END IF;
END $$;

DO $$
BEGIN
    IF pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure) LIKE '%-- 098:%' THEN
        RAISE EXCEPTION '098 rollback: sp_solicitar_venta_orden still contains 098 text';
    END IF;
    RAISE NOTICE '098 rollback: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 098 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 098 rollback rolled back ***'
\endif
\endif
