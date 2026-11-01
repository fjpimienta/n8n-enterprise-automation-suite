-- 094_state_check.sql: READ-ONLY. psql -v ON_ERROR_STOP=1 -v expect=before|applied_094|applied_095 -f 094_state_check.sql
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT set_config('t094.expect', :'expect', false) AS expect;
\echo === FINGERPRINTS (rows must not change across steps)
SELECT 'tickets_rows' AS fingerprint, count(*)::text AS value FROM public.hotel_maintenance_tickets
UNION ALL SELECT 'tickets_data_md5', md5(string_agg(concat_ws('|', id::text, room_id::text, status, priority, created_at::text), '#' ORDER BY id)) FROM public.hotel_maintenance_tickets
UNION ALL SELECT 'crud_models_md5', md5(string_agg(row_to_json(c)::text, '|' ORDER BY c.model_name)) FROM crud_models c;
\echo === COLUMN
SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'hotel_maintenance_tickets' AND column_name = 'id_company';
DO $$
DECLARE r record;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='hotel_maintenance_tickets' AND column_name='id_company') THEN
        FOR r IN EXECUTE 'SELECT id_company, count(*) AS n FROM public.hotel_maintenance_tickets GROUP BY 1 ORDER BY 1' LOOP
            RAISE NOTICE 'tickets by company: % -> %', r.id_company, r.n;
        END LOOP;
    END IF;
END $$;
DO $$
DECLARE
    e text := current_setting('t094.expect');
    c record;
BEGIN
    IF e NOT IN ('before', 'applied_094', 'applied_095') THEN RAISE EXCEPTION 'expect must be before, applied_094 or applied_095'; END IF;
    SELECT is_nullable, column_default INTO c FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'hotel_maintenance_tickets' AND column_name = 'id_company';
    IF e = 'before' AND FOUND THEN RAISE EXCEPTION 'STATE FAIL: id_company exists'; END IF;
    IF e = 'applied_094' AND (NOT FOUND OR c.is_nullable <> 'NO' OR c.column_default IS DISTINCT FROM '1') THEN
        RAISE EXCEPTION 'STATE FAIL: expected id_company NOT NULL DEFAULT 1';
    END IF;
    IF e = 'applied_095' AND (NOT FOUND OR c.is_nullable <> 'NO' OR c.column_default IS NOT NULL) THEN
        RAISE EXCEPTION 'STATE FAIL: expected id_company NOT NULL without default';
    END IF;
    RAISE NOTICE 'STATE OK: %', e;
END $$;
ROLLBACK;
