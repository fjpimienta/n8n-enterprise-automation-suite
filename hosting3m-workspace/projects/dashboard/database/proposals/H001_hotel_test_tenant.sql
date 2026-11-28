-- H001_hotel_test_tenant.sql  (PROPOSAL: not applied anywhere)
-- Creates a synthetic hotel test tenant inside the production database as an isolated company (like the agro QA tenants): company "[TEST] Hotel Demo"
-- (industry "Hotelera", flagged metadata.qa_tenant = true), two synthetic members, rooms, guests, bookings, maintenance tickets and room inspections.
-- Everything is invented. No real hotel data is read or copied. DATA ONLY: no table, column, function, trigger or workflow is created or changed.
--
-- Modes (psql variables)
--   (default)        DRY RUN: checks the preconditions, reports what it would do, writes NOTHING (not even a sequence value).
--   rehearse=true    REHEARSAL: runs the FULL apply path inside the transaction and ends in ROLLBACK. It CONSUMES a sequence value (sequences are not rolled back),
--                    so the real company id will skip one number. Cannot be combined with apply=true (the script aborts).
--   apply=true       APPLY: commits.
--
-- Safety
--   * Runs in ONE transaction at REPEATABLE READ. A fingerprint of everything that is NOT the test tenant is taken before the first write and compared just
--     before COMMIT; the script aborts if it differs. Under REPEATABLE READ this detects changes made BY THIS SCRIPT (for example a hidden trigger); it cannot
--     see other sessions' commits, which are outside the snapshot and irrelevant to the correctness of this script.
--   * The company id comes from the table sequence and is never chosen by this file. Every INSERT sets the company explicitly and never relies on a column DEFAULT.
--   * Aborts if a company with the same name exists without the QA flag, if a test marker (room "T-..", guest e-mail "test.guest..@example.invalid", doc_id "TEST-..",
--     phone "TEST-PHONE-..") already belongs to another company, or if the test company was deactivated by H001_rollback.sql (re-seeding is not supported).
--   * Idempotent: each row is found by a natural key and left alone when it exists.
--   * Members: the synthetic ADMIN and EDITOR are created ONLY through sp_access_add_user. That procedure needs an active ADMIN of the target company as actor and a
--     new company has none, so the owner account (an EXISTING account, owner_email) gets a TEMPORARY ADMIN membership of the test company (only when that company is
--     flagged qa_tenant) with an audit row. It is SCAFFOLDING: once the synthetic members exist it is deactivated (is_active = false, USER_DEACTIVATED audit row) and the
--     script verifies that an active synthetic ADMIN remains.
--   * Login value for the synthetic accounts: at least 16 characters (8 only in the embedded test harness, never on the production database).
--   * Booking dates mirror how live rows are stored today: midnight UTC of the calendar day (what the dashboard and the public booking flow produce). The
--     convention approved for AFTER the pending data migration is arrival 15:00 and departure 12:00 America/Mexico_City, i.e.
--       ((v_today + d) + time '15:00') AT TIME ZONE 'America/Mexico_City'   (arrival)    ((v_today + d) + time '12:00') AT TIME ZONE 'America/Mexico_City'  (departure)
--     Switch the two expressions in section 5 when that migration is done.
-- Rollback: H001_rollback.sql (soft deactivation only). State: H001_state_check.sql. Tests: H001_tests.sql (throwaway database only, ends in ROLLBACK).
-- Usage (see H001_RUNBOOK.md: owner_email and the login value are passed through stdin as \set lines, never as command-line arguments):
--   { printf '%s\n' '\set owner_email <EXISTING_ACCOUNT>' '\set test_password <16+ CHARACTERS>'; cat H001_hotel_test_tenant.sql; } | psql -X -v ON_ERROR_STOP=1 -f -
-- Add '\set rehearse true' or '\set apply true' as another line before the file for the rehearsal or the real run.
\if :{?embedded}
\else
\set ON_ERROR_STOP on
\endif
\if :{?apply}
\else
\set apply false
\endif
\if :{?rehearse}
\else
\set rehearse false
\endif
\if :{?owner_email}
\else
\echo 'ABORT: set owner_email (an existing account)'
\quit
\endif
\if :{?test_password}
\else
\echo 'ABORT: set test_password (at least 16 characters)'
\quit
\endif
\if :{?embedded}
\set h001_min_pw 8
\else
\set h001_min_pw 16
BEGIN ISOLATION LEVEL REPEATABLE READ;
\endif
SET LOCAL lock_timeout = '5s';
SELECT set_config('h001.apply', :'apply', true) AS apply, set_config('h001.rehearse', :'rehearse', true) AS rehearse,
       set_config('h001.owner', :'owner_email', true) IS NOT NULL AS owner_set, set_config('h001.pw', :'test_password', true) IS NOT NULL AS login_value_set,
       set_config('h001.min_pw', :'h001_min_pw', true) AS min_login_length;

CREATE OR REPLACE FUNCTION pg_temp.h001_fp(p_co integer) RETURNS text LANGUAGE sql AS $f$
  SELECT md5(coalesce(string_agg(x, '#' ORDER BY x), '')) FROM (
    SELECT 'room|'||r::text AS x FROM hotel_rooms r WHERE r.id_company IS DISTINCT FROM p_co
    UNION ALL SELECT 'guest|'||g::text FROM hotel_guests g WHERE g.id_company IS DISTINCT FROM p_co
    UNION ALL SELECT 'booking|'||b::text FROM hotel_bookings b WHERE b.id_company IS DISTINCT FROM p_co
    UNION ALL SELECT 'ticket|'||t::text FROM hotel_maintenance_tickets t WHERE t.id_company IS DISTINCT FROM p_co
    UNION ALL SELECT 'inspection|'||i::text FROM hotel_room_inspections i WHERE i.id_company IS DISTINCT FROM p_co
    UNION ALL SELECT 'member|'||uc::text FROM user_companies uc WHERE uc.id_company IS DISTINCT FROM p_co
    UNION ALL SELECT 'company|'||c::text FROM companys c WHERE c.id_company IS DISTINCT FROM p_co
    UNION ALL SELECT 'user|'||u::text FROM users u WHERE u.email NOT LIKE 'test.%@example.invalid'
  ) q $f$;

DO $$
DECLARE
    c_name     constant text := '[TEST] Hotel Demo';
    c_industry constant text := 'Hotelera';
    c_admin    constant text := 'test.admin@example.invalid';
    c_editor   constant text := 'test.editor@example.invalid';
    v_apply    boolean := current_setting('h001.apply')::boolean;
    v_rehearse boolean := current_setting('h001.rehearse')::boolean;
    v_owner    text    := lower(btrim(current_setting('h001.owner')));
    v_pw       text    := current_setting('h001.pw');
    v_min_pw   integer := current_setting('h001.min_pw')::integer;
    v_today    date    := (now() AT TIME ZONE 'America/Mexico_City')::date;
    v_co       integer;
    v_active   boolean;
    v_max      integer;
    v_n        integer;
    t          text;
    r          record;
BEGIN
    -- 0) Preconditions ------------------------------------------------------------------------------------------
    IF v_apply AND v_rehearse THEN RAISE EXCEPTION 'ABORT: apply=true and rehearse=true cannot be combined.'; END IF;
    IF current_setting('transaction_isolation') <> 'repeatable read' THEN
        RAISE EXCEPTION 'ABORT: the transaction must run at REPEATABLE READ (found %).', current_setting('transaction_isolation');
    END IF;
    IF v_min_pw < 16 AND current_database() = 'hosting3m_db' THEN
        RAISE EXCEPTION 'ABORT: the test-harness mode (embedded) is refused on the production database.';
    END IF;
    FOREACH t IN ARRAY ARRAY['companys','users','user_companies','access_audit_log','hotel_rooms','hotel_guests','hotel_bookings','hotel_maintenance_tickets','hotel_room_inspections'] LOOP
        IF to_regclass('public.' || t) IS NULL THEN RAISE EXCEPTION 'ABORT: table % not found (wrong database?).', t; END IF;
    END LOOP;
    IF to_regprocedure('public.sp_access_add_user(integer,character varying,character varying,character varying,character varying,character varying,text,character varying)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_access_add_user not found; members can only be created through it.';
    END IF;
    IF length(coalesce(v_pw, '')) < v_min_pw THEN RAISE EXCEPTION 'ABORT: the login value for the synthetic accounts must have at least % characters.', v_min_pw; END IF;
    IF v_owner IN (c_admin, c_editor) THEN RAISE EXCEPTION 'ABORT: owner_email cannot be one of the synthetic member accounts.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM users WHERE lower(email) = v_owner AND is_active IS NOT FALSE) THEN
        RAISE EXCEPTION 'ABORT: owner_email is not an existing active account.';
    END IF;
    IF EXISTS (SELECT 1 FROM companys WHERE lower(btrim(company_name)) = lower(c_name) AND coalesce(metadata->>'qa_tenant', 'false') <> 'true') THEN
        RAISE EXCEPTION 'ABORT: a company named "%" exists without metadata.qa_tenant = true. Not touching it.', c_name;
    END IF;

    SELECT id_company, is_active INTO v_co, v_active FROM companys
     WHERE lower(btrim(company_name)) = lower(c_name) AND metadata->>'qa_tenant' = 'true' ORDER BY id_company LIMIT 1;
    IF v_co IS NOT NULL AND v_active IS NOT TRUE THEN
        RAISE EXCEPTION 'ABORT: the test company % was deactivated (H001_rollback.sql); re-seeding it is not supported.', v_co;
    END IF;

    IF NOT v_apply AND NOT v_rehearse THEN
        RAISE NOTICE 'DRY RUN: nothing is written. Company: %. Would create: 2 synthetic members through sp_access_add_user (the owner gets a temporary ADMIN membership that is deactivated again), 12 rooms, 6 guests, 8 bookings, 4 tickets, 3 inspections.',
            CASE WHEN v_co IS NULL THEN 'would be created with the next sequence id' ELSE 'exists (id ' || v_co || '), existing rows are left alone' END;
        RETURN;
    END IF;
    -- From here on: apply or rehearsal (the same path). Fingerprint of everything outside the test tenant, before the first write.
    PERFORM set_config('h001.fp0', pg_temp.h001_fp(v_co), true);

    -- 1) Company (id from the sequence) -----------------------------------------------------------------------
    IF v_co IS NULL THEN
        SELECT coalesce(max(id_company), 0) INTO v_max FROM companys;
        INSERT INTO companys (company_name, industry, relation_type, is_active, notes, metadata)
        VALUES (c_name, c_industry, 'Pruebas', true,
                'TEST hotel tenant. Everything under this company is synthetic.',
                jsonb_build_object('qa_tenant', true, 'domain', 'HOTEL', 'created_by_script', 'H001_hotel_test_tenant.sql'))
        RETURNING id_company INTO v_co;
        IF v_co IS NULL OR v_co <= v_max OR v_co = 1 THEN
            RAISE EXCEPTION 'ABORT: the sequence returned id % (not above the current maximum %, or 1).', v_co, v_max;
        END IF;
        RAISE NOTICE 'Created test company id %.', v_co;
    END IF;

    -- 2) Members -----------------------------------------------------------------------------------------------
    -- Temporary scaffolding: the owner is an ADMIN of the test company only while the synthetic members are created, and only if the company is flagged.
    IF (NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = c_admin)
        OR NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = c_editor))
       AND NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = v_owner AND is_active IS TRUE AND upper(role) = 'ADMIN') THEN
        INSERT INTO user_companies (email, id_company, role, is_active)
        SELECT u.email, v_co, 'ADMIN', true FROM users u
         WHERE lower(u.email) = v_owner AND EXISTS (SELECT 1 FROM companys c WHERE c.id_company = v_co AND c.metadata->>'qa_tenant' = 'true')
        ON CONFLICT (email, id_company) DO UPDATE SET role = 'ADMIN', is_active = true;
        INSERT INTO access_audit_log (id_company, actor_email, is_platform_admin, target_email, action, new_value)
        VALUES (v_co, v_owner, true, v_owner, 'USER_ADDED', jsonb_build_object('role', 'ADMIN', 'is_active', true, 'source', 'H001 bootstrap (temporary)'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = c_admin) THEN
        PERFORM sp_access_add_user(v_co, c_admin, 'Test Admin', 'Demo', NULL, 'ADMIN', v_pw, v_owner);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = c_editor) THEN
        PERFORM sp_access_add_user(v_co, c_editor, 'Test Editor', 'Demo', NULL, 'EDITOR', v_pw, v_owner);
    END IF;
    -- End state: an active synthetic ADMIN must exist before the owner scaffolding is removed.
    IF NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = c_admin AND upper(role) = 'ADMIN' AND is_active IS TRUE) THEN
        RAISE EXCEPTION 'ABORT: no active synthetic ADMIN in company %; refusing to continue.', v_co;
    END IF;
    UPDATE user_companies SET is_active = false
     WHERE id_company = v_co AND lower(email) = v_owner AND is_active IS TRUE
       AND EXISTS (SELECT 1 FROM companys c WHERE c.id_company = v_co AND c.metadata->>'qa_tenant' = 'true');
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN
        INSERT INTO access_audit_log (id_company, actor_email, is_platform_admin, target_email, action, old_value, new_value)
        VALUES (v_co, v_owner, true, v_owner, 'USER_DEACTIVATED', jsonb_build_object('role', 'ADMIN', 'is_active', true),
                jsonb_build_object('role', 'ADMIN', 'is_active', false, 'source', 'H001 bootstrap removed'));
    END IF;

    -- 3) Rooms (room_number is globally UNIQUE: every test room starts with "T-") ---------------------------------
    IF EXISTS (SELECT 1 FROM hotel_rooms WHERE room_number LIKE 'T-%' AND id_company IS DISTINCT FROM v_co) THEN
        RAISE EXCEPTION 'ABORT: a room numbered "T-..." belongs to another company.';
    END IF;
    -- Scenarios covered by the room states: T-101/T-102 occupied (T-102 departs today); T-103 arrival today; T-106 dirty after check-out;
    -- T-109 in maintenance with a CRITICAL open ticket ("Bloqueada" on the maintenance board); T-110 is AVAILABLE with two PENDING tickets, the scenario
    -- "room with open faults that is not blocked" ("Con falla pendiente" on the maintenance board, the same room appears dirty on the housekeeping board);
    -- T-105 has a RESOLVED ticket (resolved tickets are not shown as open).
    FOR r IN SELECT * FROM (VALUES
        ('T-101','SENCILLA',600,'occupied','clean','Synthetic room'),    ('T-102','SENCILLA',600,'occupied','clean','Synthetic room'),
        ('T-103','DOBLE',900,'available','clean','Synthetic room'),      ('T-104','DOBLE',900,'available','clean','Synthetic room'),
        ('T-105','KING',1100,'available','clean','Synthetic room'),      ('T-106','KING',1100,'available','dirty','Synthetic room'),
        ('T-107','TRIPLE',1200,'available','clean','Synthetic room'),    ('T-108','TRIPLE',1200,'available','inspected','Synthetic room'),
        ('T-109','DOBLE',900,'maintenance','dirty','Synthetic room'),    ('T-110','SENCILLA',600,'available','dirty','Synthetic room'),
        ('T-111','DOBLE',900,'available','clean','Synthetic room'),      ('T-112','KING',1100,'available','clean','Synthetic room')
    ) AS x(num, typ, price, st, cl, descr) LOOP
        INSERT INTO hotel_rooms (room_number, type, status, price_night, description, cleaning_status, id_company, is_active)
        SELECT r.num, r.typ, r.st, r.price, r.descr, r.cl, v_co, true
         WHERE NOT EXISTS (SELECT 1 FROM hotel_rooms WHERE room_number = r.num);
    END LOOP;

    -- 4) Guests (email and doc_id are globally UNIQUE; the live prereservation function looks guests up by phone WITHOUT a company filter, so each test guest
    --    has its own invalid phone value that no real guest can have) ---------------------------------------------------
    IF EXISTS (SELECT 1 FROM hotel_guests WHERE (email LIKE 'test.guest%@example.invalid' OR doc_id LIKE 'TEST-%' OR phone LIKE 'TEST-PHONE-%')
                  AND id_company IS DISTINCT FROM v_co) THEN
        RAISE EXCEPTION 'ABORT: a test guest belongs to another company.';
    END IF;
    FOR r IN SELECT * FROM (VALUES
        ('Test Guest One','test.guest1@example.invalid','TEST-0001','TEST-PHONE-1'),   ('Test Guest Two','test.guest2@example.invalid','TEST-0002','TEST-PHONE-2'),
        ('Test Guest Three','test.guest3@example.invalid','TEST-0003','TEST-PHONE-3'), ('Test Guest Four','test.guest4@example.invalid','TEST-0004','TEST-PHONE-4'),
        ('Test Guest Five','test.guest5@example.invalid','TEST-0005','TEST-PHONE-5'),  ('Test Guest Six','test.guest6@example.invalid','TEST-0006','TEST-PHONE-6')
    ) AS x(nm, em, doc, ph) LOOP
        INSERT INTO hotel_guests (full_name, email, doc_id, phone, id_company, is_active)
        SELECT r.nm, r.em, r.doc, r.ph, v_co, true
         WHERE NOT EXISTS (SELECT 1 FROM hotel_guests WHERE email = r.em OR doc_id = r.doc);
    END LOOP;

    -- 5) Bookings (midnight UTC of the calendar day, like live rows today; one active check-in per room) ------------------
    INSERT INTO hotel_bookings (room_id, guest_id, check_in, check_out, status, total_amount, payment_status, amount_paid, source, external_id, id_company, is_active, notes)
    SELECT rm.id, g.id,
           (v_today + b.d_in)::timestamp  AT TIME ZONE 'UTC',
           (v_today + b.d_out)::timestamp AT TIME ZONE 'UTC',
           b.st, (b.d_out - b.d_in) * rm.price_night, b.pay, CASE WHEN b.pay = 'paid' THEN (b.d_out - b.d_in) * rm.price_night ELSE 0 END,
           'direct', b.ext, v_co, true, '[TEST] synthetic booking'
      FROM (VALUES
        ('TEST-B01','T-101','test.guest1@example.invalid','checked_in', -1,  2,'paid'),
        ('TEST-B02','T-102','test.guest2@example.invalid','checked_in', -2,  0,'pending'),
        ('TEST-B03','T-103','test.guest3@example.invalid','confirmed',   0,  2,'pending'),
        ('TEST-B04','T-104','test.guest4@example.invalid','confirmed',   3,  5,'paid'),
        ('TEST-B05','T-105','test.guest5@example.invalid','pending',     5,  7,'pending'),
        ('TEST-B06','T-106','test.guest6@example.invalid','checked_out',-3, -1,'paid'),
        ('TEST-B07','T-107','test.guest1@example.invalid','cancelled',   1,  3,'pending'),
        ('TEST-B08','T-108','test.guest2@example.invalid','checked_out',-12,-10,'paid')
      ) AS b(ext, room, guest, st, d_in, d_out, pay)
      JOIN hotel_rooms  rm ON rm.room_number = b.room AND rm.id_company = v_co
      JOIN hotel_guests g  ON g.email = b.guest       AND g.id_company  = v_co
     WHERE NOT EXISTS (SELECT 1 FROM hotel_bookings x WHERE x.id_company = v_co AND x.external_id = b.ext);

    -- 6) Maintenance tickets (open and resolved; priorities CRITICAL / NORMAL / LOW) --------------------------------
    INSERT INTO hotel_maintenance_tickets (room_id, issue_type, description, solution_details, status, priority, created_at, resolved_at, id_company)
    SELECT rm.id, k.issue, k.descr, k.sol, k.st, k.prio,
           now() AT TIME ZONE 'UTC' - make_interval(days => k.age),
           CASE WHEN k.st = 'RESOLVED' THEN now() AT TIME ZONE 'UTC' - make_interval(days => k.age - 1) END,
           v_co
      FROM (VALUES
        ('T-109','PLOMERIA','[TEST] Synthetic leak in the bathroom',NULL,'PENDING','CRITICAL',5),
        ('T-110','ELECTRICO','[TEST] Synthetic lamp does not turn on',NULL,'PENDING','NORMAL',1),
        ('T-110','MOBILIARIO','[TEST] Synthetic loose chair leg',NULL,'PENDING','LOW',4),
        ('T-105','AIRE_ACONDICIONADO','[TEST] Synthetic air conditioner noise','Synthetic filter cleaned','RESOLVED','NORMAL',8)
      ) AS k(room, issue, descr, sol, st, prio, age)
      JOIN hotel_rooms rm ON rm.room_number = k.room AND rm.id_company = v_co
     WHERE NOT EXISTS (SELECT 1 FROM hotel_maintenance_tickets x WHERE x.id_company = v_co AND x.description = k.descr);

    -- 7) Room inspections -----------------------------------------------------------------------------------------
    INSERT INTO hotel_room_inspections (room_id, inspection_date, checklist_data, observaciones, id_company)
    SELECT rm.id, v_today - k.ago, k.chk::jsonb, k.obs, v_co
      FROM (VALUES
        ('T-101', 0, '{"equipamiento":{"tv":true,"ac":true},"bano":{"toallas":true}}', '[TEST] all fine'),
        ('T-109', 1, '{"equipamiento":{"tv":true,"ac":false},"bano":{"toallas":false}}', '[TEST] synthetic findings'),
        ('T-106', 2, '{"equipamiento":{"tv":true,"ac":true},"bano":{"toallas":true}}', '[TEST] after check-out')
      ) AS k(room, ago, chk, obs)
      JOIN hotel_rooms rm ON rm.room_number = k.room AND rm.id_company = v_co
     WHERE NOT EXISTS (SELECT 1 FROM hotel_room_inspections x WHERE x.id_company = v_co AND x.room_id = rm.id AND x.inspection_date = v_today - k.ago);

    -- 8) Post-check: every marked row belongs to the test company, none has NULL or 1 ------------------------------
    IF EXISTS (SELECT 1 FROM hotel_rooms WHERE room_number LIKE 'T-%' AND id_company IS DISTINCT FROM v_co)
       OR EXISTS (SELECT 1 FROM hotel_guests WHERE email LIKE 'test.guest%@example.invalid' AND id_company IS DISTINCT FROM v_co)
       OR EXISTS (SELECT 1 FROM hotel_bookings WHERE external_id LIKE 'TEST-B%' AND id_company IS DISTINCT FROM v_co)
       OR EXISTS (SELECT 1 FROM hotel_maintenance_tickets WHERE description LIKE '[TEST]%' AND id_company IS DISTINCT FROM v_co)
       OR EXISTS (SELECT 1 FROM hotel_room_inspections WHERE observaciones LIKE '[TEST]%' AND id_company IS DISTINCT FROM v_co) THEN
        RAISE EXCEPTION 'H001: a marked row does not belong to the test company';
    END IF;
    PERFORM set_config('h001.co', v_co::text, true);
    RAISE NOTICE 'H001: OK (company %)%.', v_co, CASE WHEN v_rehearse THEN ' - REHEARSAL, will be rolled back' ELSE '' END;
END $$;

SELECT c.id_company, c.company_name, c.industry, c.metadata->>'qa_tenant' AS qa_tenant,
       (SELECT count(*) FROM user_companies uc WHERE uc.id_company = c.id_company AND uc.is_active) AS active_members,
       (SELECT count(*) FROM hotel_rooms WHERE id_company = c.id_company) AS rooms,
       (SELECT count(*) FROM hotel_guests WHERE id_company = c.id_company) AS guests,
       (SELECT count(*) FROM hotel_bookings WHERE id_company = c.id_company) AS bookings,
       (SELECT count(*) FROM hotel_maintenance_tickets WHERE id_company = c.id_company) AS tickets,
       (SELECT count(*) FROM hotel_room_inspections WHERE id_company = c.id_company) AS inspections
  FROM companys c WHERE c.metadata->>'qa_tenant' = 'true' AND c.company_name = '[TEST] Hotel Demo';

-- Just before COMMIT: the rows outside the test tenant must be byte-identical to the start of this transaction.
DO $$
DECLARE v_fp0 text := nullif(current_setting('h001.fp0', true), ''); v_co integer := nullif(current_setting('h001.co', true), '')::integer;
BEGIN
    IF v_fp0 IS NULL THEN RETURN; END IF;   -- dry run: nothing was written
    IF pg_temp.h001_fp(v_co) IS DISTINCT FROM v_fp0 THEN RAISE EXCEPTION 'ABORT: data outside the test tenant changed during this transaction (fingerprint differs).'; END IF;
    RAISE NOTICE 'H001: fingerprint of everything outside the test tenant is unchanged.';
    PERFORM set_config('h001.fp0', '', true);
END $$;

-- @@FINALIZE
\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** H001 COMMITTED ***'
\elif :rehearse
ROLLBACK;
\echo '*** H001 REHEARSAL: the full apply path ran and was rolled back; a sequence value was consumed ***'
\else
ROLLBACK;
\echo '*** H001 DRY RUN: rolled back, nothing changed ***'
\endif
\endif
