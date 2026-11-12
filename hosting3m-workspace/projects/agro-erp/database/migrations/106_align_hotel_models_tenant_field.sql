-- 106_align_hotel_models_tenant_field.sql
-- Aligns allowed_fields with the tenant column for two hotel models: hotel_rooms and hotel_maintenance_tickets. Both tables have an id_company
-- column; this migration lists "id_company" in the allowed_fields of their crud_models rows, as tenant-scoped models do.
-- Data only: no table, view, function, trigger or workflow is changed, and nothing else in the two rows changes (operations, roles, primary key,
-- default filter, joins, hooks and every other allowed field stay byte-identical). No visible behavior change for the hotel workflow.
--
-- Safety
--   * Preconditions abort unless both rows exist, point at the same-named tables and those tables have an id_company column.
--   * The two rows are copied first into crud_models_backup_20261112_106 (first run only: a re-apply after the rollback keeps the original).
--   * Idempotent: a row that already lists id_company is left alone. Exactly two rows can change; the post-check proves the rest of each row is equal to the backup.
-- Rollback: 106_rollback.sql restores allowed_fields of the two rows from the backup. State: 106_state_check.sql -v expect=before|applied|rolled_back (read-only).
-- Tests: 106_tests.sql. Static check: 106_static_check.sh.
-- Usage:   psql -X -v ON_ERROR_STOP=1 -f 106_align_hotel_models_tenant_field.sql                (dry run)
--          psql -X -v ON_ERROR_STOP=1 -v apply=true -f 106_align_hotel_models_tenant_field.sql  (commit)

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- 0) Preconditions ---------------------------------------------------------------------------------------

DO $$
DECLARE
    t text;
BEGIN
    IF to_regclass('public.crud_models') IS NULL THEN
        RAISE EXCEPTION 'ABORT: crud_models does not exist.';
    END IF;
    FOREACH t IN ARRAY ARRAY['hotel_rooms', 'hotel_maintenance_tickets'] LOOP
        IF (SELECT count(*) FROM public.crud_models WHERE model_name = t) <> 1 THEN
            RAISE EXCEPTION 'ABORT: the crud_models row % does not exist.', t;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.crud_models WHERE model_name = t AND table_name = t) THEN
            RAISE EXCEPTION 'ABORT: the model % does not point at the table %.', t, t;
        END IF;
        IF to_regclass('public.' || t) IS NULL
           OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                           WHERE table_schema = 'public' AND table_name = t AND column_name = 'id_company') THEN
            RAISE EXCEPTION 'ABORT: the table % does not exist or has no id_company column.', t;
        END IF;
        IF jsonb_typeof((SELECT allowed_fields FROM public.crud_models WHERE model_name = t)) <> 'array' THEN
            RAISE EXCEPTION 'ABORT: allowed_fields of % is not a JSON array.', t;
        END IF;
    END LOOP;
END $$;

-- 1) Backup of exactly those two rows (first run only) -----------------------------------------------------

CREATE TABLE IF NOT EXISTS crud_models_backup_20261112_106 AS
SELECT m.*, now() AS backed_up_at
  FROM crud_models m
 WHERE m.model_name IN ('hotel_rooms', 'hotel_maintenance_tickets');

-- 2) The change: list id_company in allowed_fields (idempotent; nothing else in the two rows) ---------------------

UPDATE crud_models
   SET allowed_fields = allowed_fields || '["id_company"]'::jsonb
 WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets')
   AND NOT (allowed_fields ? 'id_company');

-- 3) Post-check ------------------------------------------------------------------------------------------------

DO $$
BEGIN
    IF (SELECT count(*) FROM public.crud_models
         WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets') AND allowed_fields ? 'id_company') <> 2 THEN
        RAISE EXCEPTION '106: both rows must list id_company in allowed_fields';
    END IF;
    -- every column other than allowed_fields is equal to the backup
    IF EXISTS (SELECT 1 FROM public.crud_models m JOIN public.crud_models_backup_20261112_106 b ON b.model_name = m.model_name
                WHERE (to_jsonb(m) - 'allowed_fields') IS DISTINCT FROM (to_jsonb(b) - 'allowed_fields' - 'backed_up_at')) THEN
        RAISE EXCEPTION '106: a column other than allowed_fields differs from the backup';
    END IF;
    -- the other allowed fields are the backup ones, in the same order
    IF EXISTS (SELECT 1 FROM public.crud_models m JOIN public.crud_models_backup_20261112_106 b ON b.model_name = m.model_name
                WHERE (m.allowed_fields - 'id_company') IS DISTINCT FROM (b.allowed_fields - 'id_company')) THEN
        RAISE EXCEPTION '106: the other allowed fields differ from the backup';
    END IF;
    IF (SELECT count(*) FROM public.crud_models_backup_20261112_106) <> 2 THEN
        RAISE EXCEPTION '106: the backup must hold exactly the two rows';
    END IF;
    RAISE NOTICE '106: OK';
END $$;

SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_fields
  FROM crud_models WHERE model_name IN ('hotel_maintenance_tickets', 'hotel_rooms') ORDER BY model_name;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 106 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 106 rolled back ***'
\endif
\endif
