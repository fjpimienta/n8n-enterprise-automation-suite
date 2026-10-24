-- Rollback of 083_qa_palm_chat_seed.sql (LOCAL and production, company 10 only). Nothing is deleted: the tagged rows and the L-02 lot are
-- DEACTIVATED (is_active = false); the census history (append-only) and any expenses stay as evidence.
-- Rows of L-01 tagged qa_seed = '083' are deactivated too, so L-01 returns to "no active rows".
--   psql -v ON_ERROR_STOP=1 -f 083_qa_palm_chat_seed_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 083_qa_palm_chat_seed_rollback.sql  -> commit
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
DO $$ BEGIN
    IF (SELECT company_name FROM companys WHERE id_company = 10) <> 'Plantación de Pruebas' THEN RAISE EXCEPTION 'ABORT: company 10 is not the palm QA tenant here.'; END IF;
END $$;
UPDATE agri_rows SET is_active = false WHERE id_company = 10 AND metadata->>'qa_seed' = '083' AND is_active;
UPDATE agri_lots SET is_active = false WHERE id_company = 10 AND metadata->>'qa_seed' = '083' AND is_active;
SELECT (SELECT count(*) FROM agri_rows WHERE id_company = 10 AND metadata->>'qa_seed' = '083' AND is_active) AS active_seed_rows,
       (SELECT count(*) FROM agri_lots WHERE id_company = 10 AND metadata->>'qa_seed' = '083' AND is_active) AS active_seed_lots;
\if :apply
COMMIT;
\echo '*** QA seed ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** QA seed ROLLBACK DRY RUN ***'
\endif
