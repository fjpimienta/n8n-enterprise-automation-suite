-- H001_tests.sql: tests for H001_hotel_test_tenant.sql and H001_rollback.sql. Run ONLY against a throwaway database that has the hotel structure, the sp_access_*
-- functions and synthetic data. It refuses to run on a real database (guard below). One transaction at REPEATABLE READ; ends in ROLLBACK.
-- Run from this folder:  psql -X -v ON_ERROR_STOP=1 [-v owner_email=<account that exists in the throwaway database>] -f H001_tests.sql
\set ON_ERROR_STOP on
\if :{?owner_email}
\else
\set owner_email owner@example.invalid
\endif
\set test_password SandboxPass1
\set embedded on
\set apply false
\set rehearse false
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- Guard: refuse to run on a real database --------------------------------------------------------------------------------------
CREATE FUNCTION pg_temp.is_real_db(p_db text, p_max_bookings bigint) RETURNS boolean LANGUAGE sql AS $f$
  SELECT p_db = 'hosting3m_db' OR (SELECT count(*) FROM hotel_bookings WHERE id_company = 1) > p_max_bookings $f$;
DO $$ BEGIN
  IF pg_temp.is_real_db(current_database(), 100) THEN
    RAISE EXCEPTION 'REFUSING TO RUN: this looks like a real database (name hosting3m_db or company 1 has more than 100 bookings). Use a throwaway database.';
  END IF;
  -- unit test of the guard itself
  IF NOT pg_temp.is_real_db('hosting3m_db', 100) OR NOT pg_temp.is_real_db('any', 0) OR pg_temp.is_real_db('any', 100) THEN RAISE EXCEPTION 'FAIL T-1: guard logic'; END IF;
  RAISE NOTICE 'PASS T-1: guard accepts this throwaway database; refuses the production name and a database with more than 100 bookings in company 1';
END $$;

-- Helpers and the "before" picture ------------------------------------------------------------------------------------
CREATE FUNCTION pg_temp.fp(p_excl integer) RETURNS text LANGUAGE sql AS $f$
  SELECT md5(coalesce(string_agg(x, '#' ORDER BY x), '')) FROM (
    SELECT 'room|'||r::text AS x FROM hotel_rooms r WHERE r.id_company IS DISTINCT FROM p_excl
    UNION ALL SELECT 'guest|'||g::text FROM hotel_guests g WHERE g.id_company IS DISTINCT FROM p_excl
    UNION ALL SELECT 'booking|'||b::text FROM hotel_bookings b WHERE b.id_company IS DISTINCT FROM p_excl
    UNION ALL SELECT 'ticket|'||t::text FROM hotel_maintenance_tickets t WHERE t.id_company IS DISTINCT FROM p_excl
    UNION ALL SELECT 'inspection|'||i::text FROM hotel_room_inspections i WHERE i.id_company IS DISTINCT FROM p_excl
    UNION ALL SELECT 'member|'||uc::text FROM user_companies uc WHERE uc.id_company IS DISTINCT FROM p_excl
    UNION ALL SELECT 'company|'||c::text FROM companys c WHERE c.id_company IS DISTINCT FROM p_excl
  ) q $f$;
CREATE TEMP TABLE t_state AS
  SELECT pg_temp.fp(NULL) AS fp_before, (SELECT last_value FROM companys_id_company_seq) AS seq_before, (SELECT count(*) FROM companys) AS companies_before;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM companys WHERE company_name = '[TEST] Hotel Demo') THEN RAISE EXCEPTION 'TEST SETUP: the test company already exists; use a fresh throwaway database'; END IF;
END $$;

-- T0: a dry run writes nothing (not even a sequence value) ----------------------------------------------------------------
\i H001_hotel_test_tenant.sql
DO $$ BEGIN
  IF (SELECT count(*) FROM companys) <> (SELECT companies_before FROM t_state) OR (SELECT last_value FROM companys_id_company_seq) <> (SELECT seq_before FROM t_state)
     OR pg_temp.fp(NULL) <> (SELECT fp_before FROM t_state) THEN RAISE EXCEPTION 'FAIL T0: the dry run changed something'; END IF;
  RAISE NOTICE 'PASS T0: dry run wrote nothing (rows, fingerprint and sequence unchanged)';
END $$;

-- T0b: rehearsal runs the FULL apply path and leaves nothing; it consumes a sequence value. (The ROLLBACK statement of a standalone run is checked in the runbook run.)
SAVEPOINT r1;
\set rehearse true
\i H001_hotel_test_tenant.sql
SELECT (SELECT count(*) FROM hotel_rooms WHERE room_number LIKE 'T-%') AS rehearsal_rooms_inside \gset
\set rehearse false
ROLLBACK TO SAVEPOINT r1;
SELECT set_config('h001t.rr', :'rehearsal_rooms_inside', false) AS rooms_inside;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM companys WHERE company_name = '[TEST] Hotel Demo') OR pg_temp.fp(NULL) <> (SELECT fp_before FROM t_state) THEN RAISE EXCEPTION 'FAIL T0b: the rehearsal left data behind'; END IF;
  IF (SELECT last_value FROM companys_id_company_seq) <= (SELECT seq_before FROM t_state) THEN RAISE EXCEPTION 'FAIL T0b: the rehearsal did not consume a sequence value (not a full apply path)'; END IF;
  RAISE NOTICE 'PASS T0b: rehearsal ran the full apply path (% rooms existed inside), left nothing behind, and consumed a sequence value', current_setting('h001t.rr');
  IF current_setting('h001t.rr')::int <> 12 THEN RAISE EXCEPTION 'FAIL T0b: the rehearsal did not create the 12 rooms inside the transaction'; END IF;
END $$;

-- T0c: apply and rehearse together abort
\set ON_ERROR_STOP off
SAVEPOINT r2;
\set apply true
\set rehearse true
\i H001_hotel_test_tenant.sql
\set e_both :ERROR
\set apply false
\set rehearse false
ROLLBACK TO SAVEPOINT r2;
\set ON_ERROR_STOP on
\if :e_both
DO $$ BEGIN RAISE NOTICE 'PASS T0c: apply=true together with rehearse=true aborts'; END $$;
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL T0c: apply and rehearse together were accepted'; END $$;
\endif

-- T0d: the in-transaction fingerprint check catches a change made by the script's own writes (simulated hidden trigger on the guests table)
\set ON_ERROR_STOP off
SAVEPOINT r3;
CREATE FUNCTION public.h001_test_hidden_change() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN UPDATE hotel_guests SET notes = 'changed by a hidden trigger' WHERE id_company = 1; RETURN NEW; END $f$;
CREATE TRIGGER h001_test_hidden_change AFTER INSERT ON hotel_guests FOR EACH ROW EXECUTE FUNCTION public.h001_test_hidden_change();
\set rehearse true
\i H001_hotel_test_tenant.sql
\set e_fp :ERROR
\set rehearse false
ROLLBACK TO SAVEPOINT r3;
\set ON_ERROR_STOP on
\if :e_fp
DO $$ BEGIN RAISE NOTICE 'PASS T0d: a change outside the test tenant makes the run abort (fingerprint check)'; END $$;
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL T0d: the fingerprint check did not detect the change'; END $$;
\endif

-- T1: apply ---------------------------------------------------------------------------------------------------------------------
\set apply true
\i H001_hotel_test_tenant.sql
SELECT id_company AS co FROM companys WHERE company_name = '[TEST] Hotel Demo' \gset
SELECT set_config('h001t.co', :'co', false) AS co_set, set_config('h001t.pw', :'test_password', false) AS pw_set;
DO $$
DECLARE co integer := current_setting('h001t.co')::integer; m integer;
BEGIN
  IF co IS NULL OR co = 1 OR co <= (SELECT seq_before FROM t_state) THEN RAISE EXCEPTION 'FAIL T1: company id % is not a fresh sequence value', co; END IF;
  IF NOT EXISTS (SELECT 1 FROM companys WHERE id_company = co AND industry = 'Hotelera' AND metadata->>'qa_tenant' = 'true' AND is_active) THEN RAISE EXCEPTION 'FAIL T1: company shape'; END IF;
  RAISE NOTICE 'PASS T1: company % created from the sequence, flagged, industry Hotelera', co;

  -- T2: members and the end state. Synthetic ADMIN and EDITOR through sp_access_add_user; the owner scaffolding is deactivated with an audit row; an active synthetic ADMIN remains.
  SELECT count(*) INTO m FROM user_companies WHERE id_company = co AND is_active;
  IF m <> 2 THEN RAISE EXCEPTION 'FAIL T2: % active memberships (expected 2: the synthetic ADMIN and EDITOR)', m; END IF;
  IF (SELECT count(*) FROM user_companies WHERE id_company = co) <> 3 THEN RAISE EXCEPTION 'FAIL T2: the owner membership row should remain, inactive'; END IF;
  IF EXISTS (SELECT 1 FROM user_companies WHERE id_company = co AND email = 'owner@example.invalid' AND is_active) THEN RAISE EXCEPTION 'FAIL T2: the owner membership is still active'; END IF;
  IF NOT EXISTS (SELECT 1 FROM access_audit_log WHERE id_company = co AND target_email = 'owner@example.invalid' AND action = 'USER_DEACTIVATED') THEN RAISE EXCEPTION 'FAIL T2: no USER_DEACTIVATED audit row for the owner'; END IF;
  IF NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = co AND email = 'test.admin@example.invalid' AND role = 'ADMIN' AND is_active) THEN RAISE EXCEPTION 'FAIL T2: no active synthetic ADMIN'; END IF;
  IF (SELECT role FROM user_companies WHERE id_company = co AND email = 'test.editor@example.invalid') <> 'EDITOR' THEN RAISE EXCEPTION 'FAIL T2: editor role'; END IF;
  IF (SELECT count(*) FROM access_audit_log WHERE id_company = co AND action = 'USER_ADDED' AND new_value->>'created_account' = 'true'
       AND target_email IN ('test.admin@example.invalid','test.editor@example.invalid')) <> 2 THEN RAISE EXCEPTION 'FAIL T2: the synthetic members were not created through sp_access_add_user'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE email LIKE 'test.%@example.invalid' AND password IN (current_setting('h001t.pw'))) THEN RAISE EXCEPTION 'FAIL T2: a login value was stored in clear text'; END IF;
  IF EXISTS (SELECT 1 FROM user_companies WHERE email = 'owner@example.invalid' AND id_company <> co AND NOT is_active) THEN RAISE EXCEPTION 'FAIL T2: another membership of the owner was touched'; END IF;
  RAISE NOTICE 'PASS T2: 2 active synthetic members created only through sp_access_add_user; owner scaffolding deactivated with an audit row; an active synthetic ADMIN remains';

  -- T3: tenant column. No row of the test tenant has NULL or 1, and no marked row sits in another company.
  IF (SELECT count(*) FROM hotel_rooms WHERE id_company = co) <> 12 OR (SELECT count(*) FROM hotel_guests WHERE id_company = co) <> 6
     OR (SELECT count(*) FROM hotel_bookings WHERE id_company = co) <> 8 OR (SELECT count(*) FROM hotel_maintenance_tickets WHERE id_company = co) <> 4
     OR (SELECT count(*) FROM hotel_room_inspections WHERE id_company = co) <> 3 THEN RAISE EXCEPTION 'FAIL T3: row counts of the test tenant'; END IF;
  IF EXISTS (SELECT 1 FROM hotel_rooms WHERE room_number LIKE 'T-%' AND (id_company IS NULL OR id_company = 1 OR id_company <> co))
     OR EXISTS (SELECT 1 FROM hotel_guests WHERE (email LIKE 'test.guest%' OR doc_id LIKE 'TEST-%' OR phone LIKE 'TEST-PHONE-%') AND (id_company IS NULL OR id_company = 1 OR id_company <> co))
     OR EXISTS (SELECT 1 FROM hotel_bookings WHERE external_id LIKE 'TEST-B%' AND (id_company IS NULL OR id_company = 1 OR id_company <> co))
     OR EXISTS (SELECT 1 FROM hotel_maintenance_tickets WHERE description LIKE '[TEST]%' AND (id_company IS NULL OR id_company = 1 OR id_company <> co))
     OR EXISTS (SELECT 1 FROM hotel_room_inspections WHERE observaciones LIKE '[TEST]%' AND (id_company IS NULL OR id_company = 1 OR id_company <> co)) THEN RAISE EXCEPTION 'FAIL T3: NULL or 1 as id_company'; END IF;
  RAISE NOTICE 'PASS T3: every test row carries the test company id; none has NULL or 1';

  -- T4: globally UNIQUE columns use the reserved markers; phones are distinct invalid values
  IF EXISTS (SELECT 1 FROM hotel_rooms WHERE id_company = co AND room_number NOT LIKE 'T-%')
     OR EXISTS (SELECT 1 FROM hotel_guests WHERE id_company = co AND (email NOT LIKE '%@example.invalid' OR doc_id NOT LIKE 'TEST-%' OR phone NOT LIKE 'TEST-PHONE-%')) THEN RAISE EXCEPTION 'FAIL T4: markers'; END IF;
  IF (SELECT count(DISTINCT phone) FROM hotel_guests WHERE id_company = co) <> 6 THEN RAISE EXCEPTION 'FAIL T4: guest phones are not distinct'; END IF;
  RAISE NOTICE 'PASS T4: rooms "T-..", guests @example.invalid, TEST-.. doc ids and 6 distinct TEST-PHONE-.. phones';

  -- T5: no cross-tenant reference in either direction
  IF EXISTS (SELECT 1 FROM hotel_bookings b JOIN hotel_rooms r ON r.id = b.room_id WHERE (b.id_company = co) <> (r.id_company = co))
     OR EXISTS (SELECT 1 FROM hotel_bookings b JOIN hotel_guests g ON g.id = b.guest_id WHERE (b.id_company = co) <> (g.id_company = co))
     OR EXISTS (SELECT 1 FROM hotel_maintenance_tickets t JOIN hotel_rooms r ON r.id = t.room_id WHERE (t.id_company = co) <> (r.id_company = co))
     OR EXISTS (SELECT 1 FROM hotel_room_inspections i JOIN hotel_rooms r ON r.id = i.room_id WHERE (i.id_company = co) <> (r.id_company = co)) THEN
    RAISE EXCEPTION 'FAIL T5: a booking, ticket or inspection references a room or guest of another company'; END IF;
  RAISE NOTICE 'PASS T5: no booking, ticket or inspection of one company references a room or guest of another';

  -- T6: gateway-style scoping (what v5/CRUD adds: WHERE id_company = <company of the login>).
  IF (SELECT count(*) FROM hotel_rooms WHERE id_company = co) <> 12 OR (SELECT count(*) FROM hotel_rooms WHERE id_company = co AND room_number NOT LIKE 'T-%') <> 0
     OR (SELECT count(*) FROM hotel_rooms WHERE id_company = 1 AND room_number LIKE 'T-%') <> 0
     OR (SELECT count(*) FROM hotel_guests WHERE id_company = 1 AND email LIKE 'test.guest%') <> 0
     OR (SELECT count(*) FROM hotel_bookings WHERE id_company = 1 AND external_id LIKE 'TEST-B%') <> 0 THEN RAISE EXCEPTION 'FAIL T6: scoping'; END IF;
  RAISE NOTICE 'PASS T6: a query scoped to the test company sees only its rows, and company 1 sees none of them';

  -- T7: nothing outside the test tenant changed
  IF pg_temp.fp(co) <> (SELECT fp_before FROM t_state) THEN RAISE EXCEPTION 'FAIL T7: data outside the test tenant changed'; END IF;
  RAISE NOTICE 'PASS T7: fingerprint of everything outside the test tenant is unchanged';

  -- T7b: booking dates mirror live rows today: midnight UTC of the calendar day
  IF EXISTS (SELECT 1 FROM hotel_bookings WHERE id_company = co AND ((check_in AT TIME ZONE 'UTC')::time <> time '00:00' OR (check_out AT TIME ZONE 'UTC')::time <> time '00:00' OR check_out < check_in)) THEN
    RAISE EXCEPTION 'FAIL T7b: booking dates are not midnight UTC'; END IF;
  RAISE NOTICE 'PASS T7b: all test bookings use midnight UTC dates, like live rows';
END $$;

-- T8: idempotency (a second apply changes nothing, including memberships and audit rows)
CREATE TEMP TABLE t_counts AS SELECT (SELECT count(*) FROM hotel_rooms) r, (SELECT count(*) FROM hotel_guests) g, (SELECT count(*) FROM hotel_bookings) b,
  (SELECT count(*) FROM hotel_maintenance_tickets) t, (SELECT count(*) FROM hotel_room_inspections) i, (SELECT count(*) FROM user_companies) m,
  (SELECT count(*) FROM user_companies WHERE is_active) ma, (SELECT count(*) FROM access_audit_log) a, (SELECT count(*) FROM companys) c;
\i H001_hotel_test_tenant.sql
DO $$ BEGIN
  IF (SELECT count(*) FROM hotel_rooms) <> (SELECT r FROM t_counts)
     OR (SELECT count(*) FROM hotel_guests) <> (SELECT g FROM t_counts) OR (SELECT count(*) FROM hotel_bookings) <> (SELECT b FROM t_counts)
     OR (SELECT count(*) FROM hotel_maintenance_tickets) <> (SELECT t FROM t_counts) OR (SELECT count(*) FROM hotel_room_inspections) <> (SELECT i FROM t_counts)
     OR (SELECT count(*) FROM user_companies) <> (SELECT m FROM t_counts) OR (SELECT count(*) FROM user_companies WHERE is_active) <> (SELECT ma FROM t_counts)
     OR (SELECT count(*) FROM access_audit_log) <> (SELECT a FROM t_counts) OR (SELECT count(*) FROM companys) <> (SELECT c FROM t_counts) THEN
    RAISE EXCEPTION 'FAIL T8: the second apply changed something'; END IF;
  RAISE NOTICE 'PASS T8: second apply is a no-op (no new rows, memberships, audit rows or companies; the owner stays inactive)';
END $$;

-- T9: abort cases. Each one is attempted inside a savepoint and must make the seed fail.
\set ON_ERROR_STOP off
SAVEPOINT a1;
INSERT INTO companys (company_name, industry, metadata) VALUES ('[test] hotel demo ', 'x', '{}');
\i H001_hotel_test_tenant.sql
\set e1 :ERROR
ROLLBACK TO SAVEPOINT a1;
SAVEPOINT a2;
INSERT INTO hotel_rooms (room_number, type, price_night, id_company) VALUES ('T-999', 'DOBLE', 1, 1);
\i H001_hotel_test_tenant.sql
\set e2 :ERROR
ROLLBACK TO SAVEPOINT a2;
SAVEPOINT a3;
INSERT INTO hotel_guests (full_name, email, doc_id, id_company) VALUES ('x', 'test.guest9@example.invalid', 'TEST-9999', 1);
\i H001_hotel_test_tenant.sql
\set e3 :ERROR
ROLLBACK TO SAVEPOINT a3;
SAVEPOINT a3b;
INSERT INTO hotel_guests (full_name, email, doc_id, phone, id_company) VALUES ('x', 'real.looking@example.invalid', 'DOC-REAL', 'TEST-PHONE-9', 1);
\i H001_hotel_test_tenant.sql
\set e3b :ERROR
ROLLBACK TO SAVEPOINT a3b;
SAVEPOINT a4;
\set test_password short
\i H001_hotel_test_tenant.sql
\set e4 :ERROR
\set test_password SandboxPass1
ROLLBACK TO SAVEPOINT a4;
SAVEPOINT a5;
\set owner_email nobody@example.invalid
\i H001_hotel_test_tenant.sql
\set e5 :ERROR
\set owner_email owner@example.invalid
ROLLBACK TO SAVEPOINT a5;
\set ON_ERROR_STOP on
SELECT (:'e1' = 'true' AND :'e2' = 'true' AND :'e3' = 'true' AND :'e3b' = 'true' AND :'e4' = 'true' AND :'e5' = 'true') AS aborts_ok \gset
\if :aborts_ok
DO $$ BEGIN RAISE NOTICE 'PASS T9: the seed aborts on a same-name company without the flag, a T- room, a test guest or a TEST-PHONE phone in another company, a too-short login value and an unknown owner'; END $$;
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL T9: a guard did not abort the seed'; END $$;
\endif

-- T10: rollback. Dry run changes nothing; apply deactivates only the test tenant, deletes nothing, and the in-transaction fingerprint holds.
CREATE TEMP TABLE t_rows AS SELECT (SELECT count(*) FROM hotel_rooms) r, (SELECT count(*) FROM hotel_guests) g, (SELECT count(*) FROM hotel_bookings) b,
  (SELECT count(*) FROM hotel_maintenance_tickets) t, (SELECT count(*) FROM hotel_room_inspections) i, (SELECT count(*) FROM user_companies) m, (SELECT count(*) FROM companys) c, (SELECT count(*) FROM users) u;
\set apply false
\i H001_rollback.sql
DO $$ BEGIN IF NOT (SELECT is_active FROM companys WHERE company_name = '[TEST] Hotel Demo') THEN RAISE EXCEPTION 'FAIL T10: the rollback dry run changed the company'; END IF;
  RAISE NOTICE 'PASS T10a: rollback dry run changed nothing'; END $$;
\set apply true
\i H001_rollback.sql
DO $$
DECLARE co integer := current_setting('h001t.co')::integer;
BEGIN
  IF (SELECT row(r,g,b,t,i,m,c,u) FROM t_rows) IS DISTINCT FROM (SELECT row((SELECT count(*) FROM hotel_rooms),(SELECT count(*) FROM hotel_guests),(SELECT count(*) FROM hotel_bookings),
       (SELECT count(*) FROM hotel_maintenance_tickets),(SELECT count(*) FROM hotel_room_inspections),(SELECT count(*) FROM user_companies),(SELECT count(*) FROM companys),(SELECT count(*) FROM users))) THEN
    RAISE EXCEPTION 'FAIL T10: the rollback removed or added rows'; END IF;
  IF (SELECT is_active FROM companys WHERE id_company = co) OR EXISTS (SELECT 1 FROM user_companies WHERE id_company = co AND is_active)
     OR EXISTS (SELECT 1 FROM hotel_rooms WHERE id_company = co AND is_active) OR EXISTS (SELECT 1 FROM hotel_guests WHERE id_company = co AND is_active)
     OR EXISTS (SELECT 1 FROM hotel_bookings WHERE id_company = co AND is_active) OR EXISTS (SELECT 1 FROM hotel_maintenance_tickets WHERE id_company = co AND status <> 'DELETED')
     OR EXISTS (SELECT 1 FROM users WHERE email IN ('test.admin@example.invalid','test.editor@example.invalid') AND is_active) THEN RAISE EXCEPTION 'FAIL T10: something stayed active'; END IF;
  IF NOT (SELECT is_active FROM users WHERE email = 'owner@example.invalid') OR NOT EXISTS (SELECT 1 FROM user_companies WHERE email = 'owner@example.invalid' AND id_company = 1 AND is_active) THEN
    RAISE EXCEPTION 'FAIL T10: the owner account or its other memberships were touched'; END IF;
  IF pg_temp.fp(co) <> (SELECT fp_before FROM t_state) THEN RAISE EXCEPTION 'FAIL T10: data outside the test tenant changed'; END IF;
  RAISE NOTICE 'PASS T10b: rollback soft-deactivated only the test tenant, deleted no row, left company 1 and the owner account untouched';
END $$;

-- T11: a deactivated tenant is not re-seeded
\set ON_ERROR_STOP off
SAVEPOINT a6;
\i H001_hotel_test_tenant.sql
\set e6 :ERROR
ROLLBACK TO SAVEPOINT a6;
\set ON_ERROR_STOP on
SELECT (:'e6' = 'true') AS reseed_blocked \gset
\if :reseed_blocked
DO $$ BEGIN RAISE NOTICE 'PASS T11: re-seeding a deactivated tenant aborts'; END $$;
\else
DO $$ BEGIN RAISE EXCEPTION 'FAIL T11: re-seeding a deactivated tenant was allowed'; END $$;
\endif

ROLLBACK;
\echo '*** H001 tests finished; everything rolled back ***'
