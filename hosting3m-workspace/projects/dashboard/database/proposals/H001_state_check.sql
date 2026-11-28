-- H001_state_check.sql: READ ONLY. Reports the state of the hotel test tenant and a fingerprint of every row that is NOT the test tenant's.
-- The fingerprint (md5 over the non-test rows of the hotel tables) must not change across apply and rollback: write it down before and compare after.
-- Usage: psql -X -v ON_ERROR_STOP=1 -v expect=before|applied|rolled_back -f H001_state_check.sql
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';
WITH tenant AS (
    SELECT id_company, is_active FROM companys WHERE company_name = '[TEST] Hotel Demo' AND metadata->>'qa_tenant' = 'true' ORDER BY id_company LIMIT 1
), fp AS (
    SELECT md5(coalesce(string_agg(x, '#' ORDER BY x), '')) AS non_test_fingerprint FROM (
        SELECT 'room|' || r::text AS x FROM hotel_rooms r WHERE r.id_company IS DISTINCT FROM (SELECT id_company FROM tenant)
        UNION ALL SELECT 'guest|' || g::text FROM hotel_guests g WHERE g.id_company IS DISTINCT FROM (SELECT id_company FROM tenant)
        UNION ALL SELECT 'booking|' || b::text FROM hotel_bookings b WHERE b.id_company IS DISTINCT FROM (SELECT id_company FROM tenant)
        UNION ALL SELECT 'ticket|' || t::text FROM hotel_maintenance_tickets t WHERE t.id_company IS DISTINCT FROM (SELECT id_company FROM tenant)
        UNION ALL SELECT 'inspection|' || i::text FROM hotel_room_inspections i WHERE i.id_company IS DISTINCT FROM (SELECT id_company FROM tenant)
    ) q
)
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM tenant) THEN 'before'
            WHEN (SELECT is_active FROM tenant) THEN 'applied' ELSE 'rolled_back' END AS state,
       coalesce((SELECT id_company::text FROM tenant), 'none') AS test_company,
       (SELECT non_test_fingerprint FROM fp) AS non_test_fingerprint,
       (SELECT count(*) FROM hotel_rooms r WHERE r.id_company = (SELECT id_company FROM tenant)) AS rooms,
       (SELECT count(*) FROM hotel_bookings b WHERE b.id_company = (SELECT id_company FROM tenant)) AS bookings,
       (SELECT count(*) FROM hotel_maintenance_tickets t WHERE t.id_company = (SELECT id_company FROM tenant) AND t.status IS DISTINCT FROM 'DELETED') AS open_or_resolved_tickets
\gset
\echo state=:state test_company=:test_company fingerprint=:non_test_fingerprint rooms=:rooms bookings=:bookings tickets=:open_or_resolved_tickets
\if :{?expect}
SELECT (:'state' = :'expect') AS state_matches_expectation \gset
\if :state_matches_expectation
\echo STATE OK: :expect
\else
\echo STATE MISMATCH: expected :expect, found :state
\endif
\endif
ROLLBACK;
