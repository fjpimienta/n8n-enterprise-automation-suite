-- 083_qa_palm_chat_seed_local.sql — QA data for the palm chat agent tests. LOCAL ONLY. Company 10 only
-- ("Plantación de Pruebas", the palm test tenant; NEVER company 7, a real client).
-- Creates: rows 1-5 (22 planting positions each) in lot L-01 and a second lot L-02 "Catazaja Alto" with rows 1-3
-- (20 positions), in plantation PLM-01. Everything is tagged metadata.qa_seed = '083' so 083_qa_palm_chat_seed_rollback.sql
-- can find it. In production the owner creates equivalent data from the web (see 083_RUNBOOK.md, step 0).
--
--   psql -v ON_ERROR_STOP=1 -f 083_qa_palm_chat_seed_local.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 083_qa_palm_chat_seed_local.sql  -> commit
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
DO $$
DECLARE
    v_plantation uuid; v_l1 uuid; v_l2 uuid;
BEGIN
    IF fn_company_business_domain(10) IS DISTINCT FROM 'PALM' OR (SELECT company_name FROM companys WHERE id_company = 10) <> 'Plantación de Pruebas' THEN
        RAISE EXCEPTION 'ABORT: company 10 is not the palm QA tenant here.';
    END IF;
    SELECT p.id, l.id INTO v_plantation, v_l1 FROM agri_plantations p JOIN agri_lots l ON l.plantation_id = p.id AND l.id_company = p.id_company
     WHERE p.id_company = 10 AND p.plantation_code = 'PLM-01' AND l.lot_code = 'L-01' AND l.is_active;
    IF v_l1 IS NULL THEN RAISE EXCEPTION 'ABORT: PLM-01 / L-01 not found in company 10.'; END IF;
    IF EXISTS (SELECT 1 FROM agri_rows WHERE lot_id = v_l1) OR EXISTS (SELECT 1 FROM agri_lots WHERE plantation_id = v_plantation AND lot_code = 'L-02') THEN
        RAISE EXCEPTION 'ABORT: the seed was already applied (rows or L-02 exist).';
    END IF;
    INSERT INTO agri_lots (id_company, plantation_id, lot_code, lot_name, area_ha, metadata)
    VALUES (10, v_plantation, 'L-02', 'Catazaja Alto', 8, '{"qa_seed":"083"}') RETURNING id INTO v_l2;
    PERFORM sp_agri_bulk_create_rows(10, v_l1, 1, 5, 22, 'fjpimienta@gmail.com');
    PERFORM sp_agri_bulk_create_rows(10, v_l2, 1, 3, 20, 'fjpimienta@gmail.com');
    UPDATE agri_rows SET metadata = metadata || '{"qa_seed":"083"}' WHERE lot_id IN (v_l1, v_l2);
    RAISE NOTICE 'seeded: L-01 rows=%, L-02 rows=%', (SELECT count(*) FROM agri_rows WHERE lot_id = v_l1), (SELECT count(*) FROM agri_rows WHERE lot_id = v_l2);
END $$;
\if :apply
COMMIT;
\echo '*** QA seed COMMITTED ***'
\else
ROLLBACK;
\echo '*** QA seed DRY RUN ***'
\endif
