-- 106_state_check.sql: READ-ONLY (BEGIN READ ONLY ... ROLLBACK).
-- psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f 106_state_check.sql
--
-- * 106 changes ONE column (allowed_fields) of TWO crud_models rows (hotel_rooms, hotel_maintenance_tickets). The fingerprints of every other
--   row, and of every column of those two rows other than allowed_fields, must be identical in all three states.
-- * Save the output of "before", "applied" and "rolled_back" in the runbook record and diff the FINGERPRINT blocks.
\set ON_ERROR_STOP on
\if :{?embedded}
\else
BEGIN READ ONLY;
\endif
SELECT set_config('t106.expect', :'expect', false) AS expect;

\echo === ENVIRONMENT
SELECT current_database() AS database, split_part(version(), ' ', 2) AS postgres_version,
       now() AT TIME ZONE 'America/Mexico_City' AS checked_at_cdmx;

\echo === FINGERPRINTS (identical at every step)
SELECT 'other_crud_models' AS fingerprint,
       coalesce(md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)), 'empty') AS md5
  FROM crud_models c WHERE c.model_name NOT IN ('hotel_rooms', 'hotel_maintenance_tickets')
UNION ALL SELECT 'other_crud_models_count', count(*)::text FROM crud_models WHERE model_name NOT IN ('hotel_rooms', 'hotel_maintenance_tickets')
UNION ALL SELECT 'two_rows_without_allowed_fields',
       coalesce(md5(string_agg((to_jsonb(c) - 'allowed_fields')::text, '|' ORDER BY c.model_name)), 'empty')
  FROM crud_models c WHERE c.model_name IN ('hotel_rooms', 'hotel_maintenance_tickets')
UNION ALL SELECT 'two_rows_count', count(*)::text FROM crud_models WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets');

\echo === THE TWO ROWS (information)
SELECT model_name, table_name, allowed_ops, allowed_roles_select, allowed_fields ? 'id_company' AS lists_id_company,
       jsonb_array_length(allowed_fields) AS n_allowed_fields, md5(allowed_fields::text) AS allowed_fields_md5
  FROM crud_models WHERE model_name IN ('hotel_rooms', 'hotel_maintenance_tickets') ORDER BY model_name;
SELECT to_regclass('public.crud_models_backup_20261112_106') AS backup_table;

\echo === TENANT COLUMN CHECK OF ALL MODELS (information)
SELECT coalesce(string_agg(DISTINCT m.model_name, ', ' ORDER BY m.model_name), '(none)') AS models_not_listing_their_tenant_column
  FROM crud_models m
  JOIN information_schema.columns c ON c.table_schema = 'public' AND c.table_name = m.table_name AND c.column_name IN ('id_company', 'tenant_id')
 WHERE NOT (m.allowed_fields ? c.column_name);

\echo === ASSERTIONS
DO $$
DECLARE
    v_expect text := current_setting('t106.expect');
    v_backup boolean := to_regclass('public.crud_models_backup_20261112_106') IS NOT NULL;
    t        text;
BEGIN
    IF v_expect NOT IN ('before', 'applied', 'rolled_back') THEN
        RAISE EXCEPTION 'expect must be before, applied or rolled_back (got %)', v_expect;
    END IF;
    FOREACH t IN ARRAY ARRAY['hotel_rooms', 'hotel_maintenance_tickets'] LOOP
        IF (SELECT count(*) FROM crud_models WHERE model_name = t AND table_name = t) <> 1 THEN
            RAISE EXCEPTION 'FAIL: the crud_models row % is missing or points elsewhere', t;
        END IF;
    END LOOP;

    IF v_expect = 'before' THEN
        IF v_backup THEN RAISE EXCEPTION 'FAIL: the backup table already exists before 106'; END IF;
        FOREACH t IN ARRAY ARRAY['hotel_rooms', 'hotel_maintenance_tickets'] LOOP
            IF (SELECT allowed_fields ? 'id_company' FROM crud_models WHERE model_name = t) THEN
                RAISE EXCEPTION 'FAIL: % already lists id_company before 106', t;
            END IF;
        END LOOP;
    ELSE
        IF NOT v_backup THEN RAISE EXCEPTION 'FAIL: the backup table is missing'; END IF;
        FOREACH t IN ARRAY ARRAY['hotel_rooms', 'hotel_maintenance_tickets'] LOOP
            IF NOT EXISTS (SELECT 1 FROM crud_models_backup_20261112_106 WHERE model_name = t) THEN
                RAISE EXCEPTION 'FAIL: the backup has no row for %', t;
            END IF;
            -- every column other than allowed_fields equals the backup, in both applied and rolled_back
            IF (SELECT to_jsonb(m) - 'allowed_fields' FROM crud_models m WHERE m.model_name = t)
               IS DISTINCT FROM (SELECT to_jsonb(b) - 'allowed_fields' - 'backed_up_at' FROM crud_models_backup_20261112_106 b WHERE b.model_name = t) THEN
                RAISE EXCEPTION 'FAIL: a column other than allowed_fields of % differs from the backup', t;
            END IF;
            IF v_expect = 'applied' THEN
                IF NOT (SELECT allowed_fields ? 'id_company' FROM crud_models WHERE model_name = t) THEN
                    RAISE EXCEPTION 'FAIL: % does not list id_company', t;
                END IF;
                IF (SELECT allowed_fields - 'id_company' FROM crud_models WHERE model_name = t)
                   IS DISTINCT FROM (SELECT allowed_fields - 'id_company' FROM crud_models_backup_20261112_106 WHERE model_name = t) THEN
                    RAISE EXCEPTION 'FAIL: the other allowed fields of % differ from the backup', t;
                END IF;
            ELSE
                IF (SELECT allowed_fields FROM crud_models WHERE model_name = t)
                   IS DISTINCT FROM (SELECT allowed_fields FROM crud_models_backup_20261112_106 WHERE model_name = t) THEN
                    RAISE EXCEPTION 'FAIL: allowed_fields of % is not the backup one after the rollback', t;
                END IF;
            END IF;
        END LOOP;
        IF (SELECT count(*) FROM crud_models_backup_20261112_106) <> 2 THEN
            RAISE EXCEPTION 'FAIL: the backup must hold exactly the two rows';
        END IF;
    END IF;
    RAISE NOTICE 'STATE OK: %', v_expect;
END $$;
\if :{?embedded}
\else
ROLLBACK;
\endif
