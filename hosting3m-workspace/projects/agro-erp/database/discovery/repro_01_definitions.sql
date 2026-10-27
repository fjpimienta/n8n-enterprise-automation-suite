-- repro_01_definitions.sql  (READ-ONLY)
-- Phase 0 discovery for the reproduction-tracking work: dumps the REAL definitions of the objects
-- whose bodies are not versioned in this repo (CLAUDE.md rule 7: schema.sql is stale).
--
-- Run (LOCAL first, then the server) and send back the .txt:
--   psql -v ON_ERROR_STOP=1 -X -d hosting3m_db -f repro_01_definitions.sql > /root/repro_01_definitions.txt 2>&1
--
-- Only SELECT / catalog reads. No tenant data is returned (definitions and counts only), so no tenant
-- variable is needed. Do not run inside a read-write transaction block that you later COMMIT.
\set ON_ERROR_STOP on
SET default_transaction_read_only = on;

\echo '=== A. Columns of the reproduction tables ==='
SELECT table_name, ordinal_position, column_name, data_type, character_maximum_length, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('birth_events','cattle_breeding_events','breeding_events','cattle_health_logs',
                     'cattle_weight_logs','event_voids','cattle_livestock','user_companies')
ORDER BY table_name, ordinal_position;

\echo '=== B. Constraints (CHECK / FK / UNIQUE / PK) ==='
SELECT conrelid::regclass AS table_name, conname, contype, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN (
  SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('birth_events','cattle_breeding_events','breeding_events','cattle_health_logs',
                      'cattle_weight_logs','event_voids','cattle_livestock'))
ORDER BY 1, 3, 2;

\echo '=== C. Indexes ==='
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('birth_events','cattle_breeding_events','cattle_health_logs','cattle_weight_logs',
                    'event_voids','cattle_livestock')
ORDER BY 1, 2;

\echo '=== D. Triggers on those tables (weight sync, brand inheritance, guards) ==='
SELECT event_object_table AS table_name, trigger_name, action_timing, event_manipulation, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN ('birth_events','cattle_breeding_events','cattle_health_logs',
                             'cattle_weight_logs','event_voids','cattle_livestock')
ORDER BY 1, 2;

\echo '=== E. Function bodies (every overload) ==='
SELECT p.oid::regprocedure AS signature, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('sp_register_birth_event','sp_log_breeding_event','sp_log_palpation_event',
                    'sp_void_event','update_current_weight','fn_reject_palm_company',
                    'fn_apply_birth_brand_inheritance','fn_inherit_brand_from_mother',
                    'fn_flag_duplicate_fire_numbers')
ORDER BY p.proname, p.oid;

\echo '=== F. How is PALPACION stored? (shape of the JSON, no animal ids, no tenant data) ==='
SELECT event_type, count(*) AS rows,
       (SELECT jsonb_agg(DISTINCT k) FROM (
          SELECT jsonb_object_keys(medicines_json) k FROM cattle_health_logs h2
          WHERE h2.event_type = 'PALPACION' AND jsonb_typeof(h2.medicines_json) = 'object'
          LIMIT 200) s) AS medicines_json_keys
FROM cattle_health_logs
WHERE event_type = 'PALPACION'
GROUP BY event_type;

\echo '=== G. Category values currently in use and CHECK definition ==='
SELECT category, species, count(*) FROM cattle_livestock GROUP BY 1, 2 ORDER BY 2, 1;
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'cattle_livestock_category_check';
SELECT * FROM cattle_lifestage_catalog ORDER BY especie, edad_min_meses;

\echo '=== H. crud_models rows for the reproduction objects (permissions) ==='
SELECT model_name, table_name, allowed_roles_select, allowed_roles_insert, allowed_roles_update, allowed_roles_delete
FROM crud_models
WHERE table_name IN ('birth_events','cattle_breeding_events','cattle_health_logs','cattle_weight_logs','event_voids')
   OR model_name IN ('birth_events','cattle_breeding_events','cattle_health_logs','cattle_weight_logs');

\echo '=== I. Next free migration number (should be > 083) ==='
\echo 'Compare against: ls hosting3m-workspace/projects/agro-erp/database/migrations | sort | tail'
