-- 098_mutate.sql: used ONLY by 098_tests.sql when -v mutation=<M1..M6> is given (see 098_mutation_check.sh).
-- It breaks one protection inside the test transaction (which always ends in ROLLBACK) so that the matching test must fail.
\set ON_ERROR_STOP on
SELECT :'mutation' = 'M1' AS m1, :'mutation' = 'M2' AS m2, :'mutation' = 'M3' AS m3,
       :'mutation' = 'M4' AS m4, :'mutation' = 'M5' AS m5, :'mutation' = 'M6' AS m6 \gset
\echo MUTATION :mutation

-- M1: remove the sale trigger on cattle_livestock (expect C1 to fail)
\if :m1
DROP TRIGGER trg_block_out_on_loan_status ON public.cattle_livestock;
\endif

-- M2: remove the two loan blocks from sp_solicitar_venta_orden, keep the FIFO exclusion (expect C10 to fail)
\if :m2
DO $$
DECLARE
    c_sig constant text := 'public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)';
    v_def text := pg_get_functiondef(c_sig::regprocedure);
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
BEGIN
    IF position(add_txt IN v_def) = 0 THEN RAISE EXCEPTION 'M2: loan block not found'; END IF;
    EXECUTE replace(v_def, add_txt, '');
END $$;
\endif

-- M3: remove the partial unique index (expect B3 to fail)
\if :m3
DROP INDEX public.uq_movement_animal_one_open;
\endif

-- M4: neutralise the P0100 guard (expect B4 to fail)
\if :m4
CREATE OR REPLACE FUNCTION public.trg_guard_movement_animal_open() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN RETURN NEW; END $f$;
\endif

-- M5: remove the FIFO exclusion from sp_solicitar_venta_orden (expect D2 to fail)
\if :m5
DO $$
DECLARE
    c_sig constant text := 'public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)';
    v_def text := pg_get_functiondef(c_sig::regprocedure);
    ins_f constant text :=
E'               -- 098: FIFO skips animals out on loan\n'
'               AND NOT EXISTS (SELECT 1 FROM cattle_movement_event_animals ea\n'
'                                WHERE ea.cattle_livestock_id = l.id AND ea.return_status = ''OPEN'')\n';
BEGIN
    IF position(ins_f IN v_def) = 0 THEN RAISE EXCEPTION 'M5: FIFO exclusion not found'; END IF;
    EXECUTE replace(v_def, ins_f, '');
END $$;
\endif

-- M6: remove the DIED_AWAY trigger (expect F1 to fail)
\if :m6
DROP TRIGGER trg_close_loan_on_death ON public.cattle_livestock;
\endif
