-- 083 ROLLBACK. No DROP / DELETE: the 8 chat tool functions keep their names and signatures (the n8n palm agent still
-- calls them) but their bodies become a constant answer {"status":"disabled", ...}, so the agent keeps running and tells
-- the user the assistant is off, and nothing is read or written. The helpers (fn_agri_chat_*) are left in place:
-- they are harmless and are replaced by a re-apply. Re-applying 083 restores the tools.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 083_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 083_rollback.sql  -> commit
-- Then: 083_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.sp_agri_chat_catalog(text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_agri_chat_catalog not found - 083 was never applied here.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.sp_agri_chat_catalog(
    p_tenant_id text,
    p_actor_email text
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$ SELECT '{"status":"disabled","message":"El asistente de palma está desactivado temporalmente."}'::jsonb $$;
COMMENT ON FUNCTION public.sp_agri_chat_catalog(text,text) IS
  'ROLLED BACK (083_rollback.sql): always answers disabled. Re-apply 083 to restore.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_structure(
    p_tenant_id text,
    p_actor_email text,
    p_plantation text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$ SELECT '{"status":"disabled","message":"El asistente de palma está desactivado temporalmente."}'::jsonb $$;
COMMENT ON FUNCTION public.sp_agri_chat_structure(text,text,text) IS
  'ROLLED BACK (083_rollback.sql): always answers disabled. Re-apply 083 to restore.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_lot_summary(
    p_tenant_id text,
    p_actor_email text,
    p_lot text,
    p_plantation text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$ SELECT '{"status":"disabled","message":"El asistente de palma está desactivado temporalmente."}'::jsonb $$;
COMMENT ON FUNCTION public.sp_agri_chat_lot_summary(text,text,text,text) IS
  'ROLLED BACK (083_rollback.sql): always answers disabled. Re-apply 083 to restore.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_record_expense(
    p_tenant_id text,
    p_actor_email text,
    p_category_code text,
    p_amount text,
    p_expense_date text,
    p_plantation text,
    p_lot text,
    p_quantity text,
    p_unit_code text,
    p_supplier_name text,
    p_description text,
    p_is_invoiced text,
    p_invoice_folio text,
    p_confirmed text,
    p_force_duplicate text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$ SELECT '{"status":"disabled","message":"El asistente de palma está desactivado temporalmente."}'::jsonb $$;
COMMENT ON FUNCTION public.sp_agri_chat_record_expense(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text) IS
  'ROLLED BACK (083_rollback.sql): always answers disabled. Re-apply 083 to restore.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_void_expense(
    p_tenant_id text,
    p_actor_email text,
    p_expense_ref text,
    p_reason text,
    p_confirmed text
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$ SELECT '{"status":"disabled","message":"El asistente de palma está desactivado temporalmente."}'::jsonb $$;
COMMENT ON FUNCTION public.sp_agri_chat_void_expense(text,text,text,text,text) IS
  'ROLLED BACK (083_rollback.sql): always answers disabled. Re-apply 083 to restore.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_recent_expenses(
    p_tenant_id text,
    p_actor_email text,
    p_limit text DEFAULT NULL,
    p_date_from text DEFAULT NULL,
    p_category_code text DEFAULT NULL,
    p_lot text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$ SELECT '{"status":"disabled","message":"El asistente de palma está desactivado temporalmente."}'::jsonb $$;
COMMENT ON FUNCTION public.sp_agri_chat_recent_expenses(text,text,text,text,text,text) IS
  'ROLLED BACK (083_rollback.sql): always answers disabled. Re-apply 083 to restore.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_expense_balance(
    p_tenant_id text,
    p_actor_email text,
    p_period text DEFAULT NULL,
    p_date_from text DEFAULT NULL,
    p_date_to text DEFAULT NULL,
    p_plantation text DEFAULT NULL,
    p_lot text DEFAULT NULL,
    p_category_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$ SELECT '{"status":"disabled","message":"El asistente de palma está desactivado temporalmente."}'::jsonb $$;
COMMENT ON FUNCTION public.sp_agri_chat_expense_balance(text,text,text,text,text,text,text,text) IS
  'ROLLED BACK (083_rollback.sql): always answers disabled. Re-apply 083 to restore.';

CREATE OR REPLACE FUNCTION public.sp_agri_chat_record_row_census(
    p_tenant_id text,
    p_actor_email text,
    p_lot text,
    p_plantation text,
    p_row_number text,
    p_alive_plants text,
    p_reason text,
    p_census_date text,
    p_notes text,
    p_confirmed text
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
AS $$ SELECT '{"status":"disabled","message":"El asistente de palma está desactivado temporalmente."}'::jsonb $$;
COMMENT ON FUNCTION public.sp_agri_chat_record_row_census(text,text,text,text,text,text,text,text,text,text) IS
  'ROLLED BACK (083_rollback.sql): always answers disabled. Re-apply 083 to restore.';

SELECT public.sp_agri_chat_structure('10', 'fjpimienta@gmail.com')->>'status' AS tool_answer_after_rollback;

\if :apply
COMMIT;
\echo '*** 083 ROLLBACK COMMITTED - verify with 083_state_check.sql -v expect=rolled_back ***'
\else
ROLLBACK;
\echo '*** 083 ROLLBACK DRY RUN: nothing changed ***'
\endif
