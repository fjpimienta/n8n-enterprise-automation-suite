-- H001_hotel_test_tenant.sql  (PROPOSAL: not applied anywhere)
-- Creates a synthetic hotel test tenant: company "[TEST] Hotel Demo" (industry "Hotelera", flagged metadata.qa_tenant = true), memberships, rooms,
-- guests, bookings, maintenance tickets and room inspections. Everything is invented. No real hotel data is read or copied.
--
-- Safety
--   * Dry run is the default and writes NOTHING (not even a sequence value): it checks the preconditions and reports what it would do.
--   * The company id comes from the table sequence; it is never chosen by this file. Every INSERT sets id_company explicitly to that id and never relies on a column DEFAULT.
--   * The seed aborts if a company with the same name exists without the QA flag, if a test marker (room "T-..", guest e-mail "@example.invalid" or doc_id "TEST-..")
--     already belongs to another company, or if the test company was deactivated by H001_rollback.sql (re-seeding a deactivated tenant is not supported).
--   * Idempotent: each row is found by a natural key and left alone when it exists. Dates are relative to the run date (America/Mexico_City); arrival 15:00, departure 12:00.
--   * Members: the owner account (an EXISTING account, passed as owner_email) gets a direct ADMIN membership with an audit row, because sp_access_add_user requires an
--     active ADMIN of the target company as actor and a new company has none (same bootstrap as 080_qa_palm_tenant_seed.sql). The synthetic ADMIN and EDITOR are created ONLY
--     through sp_access_add_user.
-- Rollback: H001_rollback.sql (soft deactivation only). State: H001_state_check.sql. Tests: H001_tests.sql (ends in ROLLBACK).
-- Usage (never put the password in a file; a throwaway value is fine for a non-shared environment):
--   psql -X -v ON_ERROR_STOP=1 -v owner_email=<EXISTING_ACCOUNT> -v test_password=<PASSWORD_8+_CHARS> -f H001_hotel_test_tenant.sql               (dry run)
--   psql -X -v ON_ERROR_STOP=1 -v owner_email=... -v test_password=... -v apply=true -f H001_hotel_test_tenant.sql                                (commit)
\if :{?embedded}
\else
\set ON_ERROR_STOP on
\endif
\if :{?apply}
\else
\set apply false
\endif
\if :{?owner_email}
\else
\echo 'ABORT: pass -v owner_email=<an existing account>'
\quit
\endif
\if :{?test_password}
\else
\echo 'ABORT: pass -v test_password=<at least 8 characters>'
\quit
\endif
\if :{?embedded}
\else
BEGIN;
\endif
SET LOCAL lock_timeout = '5s';
SELECT set_config('h001.apply', :'apply', true) AS apply,
       set_config('h001.owner', :'owner_email', true) IS NOT NULL AS owner_set,
       set_config('h001.pw', :'test_password', true) IS NOT NULL AS password_set;

DO $$
DECLARE
    c_name     constant text := '[TEST] Hotel Demo';
    c_industry constant text := 'Hotelera';
    c_admin    constant text := 'test.admin@example.invalid';
    c_editor   constant text := 'test.editor@example.invalid';
    v_apply    boolean := current_setting('h001.apply')::boolean;
    v_owner    text    := lower(btrim(current_setting('h001.owner')));
    v_pw       text    := current_setting('h001.pw');
    v_today    date    := (now() AT TIME ZONE 'America/Mexico_City')::date;
    v_co       integer;
    v_active   boolean;
    v_max      integer;
    t          text;
    r          record;
BEGIN
    -- 0) Preconditions ------------------------------------------------------------------------------------------
    FOREACH t IN ARRAY ARRAY['companys','users','user_companies','access_audit_log','hotel_rooms','hotel_guests','hotel_bookings','hotel_maintenance_tickets','hotel_room_inspections'] LOOP
        IF to_regclass('public.' || t) IS NULL THEN RAISE EXCEPTION 'ABORT: table % not found (wrong database?).', t; END IF;
    END LOOP;
    IF to_regprocedure('public.sp_access_add_user(integer,character varying,character varying,character varying,character varying,character varying,text,character varying)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_access_add_user not found; members can only be created through it.';
    END IF;
    IF length(coalesce(v_pw, '')) < 8 THEN RAISE EXCEPTION 'ABORT: test_password must have at least 8 characters.'; END IF;
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

    IF NOT v_apply THEN
        RAISE NOTICE 'DRY RUN: nothing is written. Company: %. Would create: 3 memberships (owner bootstrap + synthetic ADMIN + EDITOR via sp_access_add_user), 12 rooms, 6 guests, 8 bookings, 4 tickets, 3 inspections.',
            CASE WHEN v_co IS NULL THEN 'would be created with the next sequence id' ELSE 'exists (id ' || v_co || '), existing rows are left alone' END;
        RETURN;
    END IF;

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
    IF NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = v_owner AND is_active IS TRUE AND upper(role) = 'ADMIN') THEN
        INSERT INTO user_companies (email, id_company, role, is_active)
        SELECT u.email, v_co, 'ADMIN', true FROM users u WHERE lower(u.email) = v_owner
        ON CONFLICT (email, id_company) DO UPDATE SET role = 'ADMIN', is_active = true;
        INSERT INTO access_audit_log (id_company, actor_email, is_platform_admin, target_email, action, new_value)
        VALUES (v_co, v_owner, true, v_owner, 'USER_ADDED', jsonb_build_object('role', 'ADMIN', 'is_active', true, 'source', 'H001 bootstrap'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = c_admin) THEN
        PERFORM sp_access_add_user(v_co, c_admin, 'Test Admin', 'Demo', NULL, 'ADMIN', v_pw, v_owner);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM user_companies WHERE id_company = v_co AND lower(email) = c_editor) THEN
        PERFORM sp_access_add_user(v_co, c_editor, 'Test Editor', 'Demo', NULL, 'EDITOR', v_pw, v_owner);
    END IF;

    -- 3) Rooms (room_number is globally UNIQUE: every test room starts with "T-") ---------------------------------
    IF EXISTS (SELECT 1 FROM hotel_rooms WHERE room_number LIKE 'T-%' AND id_company IS DISTINCT FROM v_co) THEN
        RAISE EXCEPTION 'ABORT: a room numbered "T-..." belongs to another company.';
    END IF;
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

    -- 4) Guests (email and doc_id are globally UNIQUE: reserved ".invalid" domain and "TEST-" prefix) ---------------
    IF EXISTS (SELECT 1 FROM hotel_guests WHERE (email LIKE 'test.guest%@example.invalid' OR doc_id LIKE 'TEST-%')
                  AND id_company IS DISTINCT FROM v_co) THEN
        RAISE EXCEPTION 'ABORT: a test guest belongs to another company.';
    END IF;
    FOR r IN SELECT * FROM (VALUES
        ('Test Guest One','test.guest1@example.invalid','TEST-0001'),   ('Test Guest Two','test.guest2@example.invalid','TEST-0002'),
        ('Test Guest Three','test.guest3@example.invalid','TEST-0003'), ('Test Guest Four','test.guest4@example.invalid','TEST-0004'),
        ('Test Guest Five','test.guest5@example.invalid','TEST-0005'),  ('Test Guest Six','test.guest6@example.invalid','TEST-0006')
    ) AS x(nm, em, doc) LOOP
        INSERT INTO hotel_guests (full_name, email, doc_id, phone, id_company, is_active)
        SELECT r.nm, r.em, r.doc, '0000000000', v_co, true
         WHERE NOT EXISTS (SELECT 1 FROM hotel_guests WHERE email = r.em OR doc_id = r.doc);
    END LOOP;

    -- 5) Bookings (arrival 15:00 and departure 12:00, America/Mexico_City; one active check-in per room) ------------
    INSERT INTO hotel_bookings (room_id, guest_id, check_in, check_out, status, total_amount, payment_status, amount_paid, source, external_id, id_company, is_active, notes)
    SELECT rm.id, g.id,
           ((v_today + b.d_in) + time '15:00') AT TIME ZONE 'America/Mexico_City',
           ((v_today + b.d_out) + time '12:00') AT TIME ZONE 'America/Mexico_City',
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
    RAISE NOTICE 'H001: OK (company %).', v_co;
END $$;

SELECT c.id_company, c.company_name, c.industry, c.metadata->>'qa_tenant' AS qa_tenant,
       (SELECT count(*) FROM user_companies uc WHERE uc.id_company = c.id_company) AS memberships,
       (SELECT count(*) FROM hotel_rooms WHERE id_company = c.id_company) AS rooms,
       (SELECT count(*) FROM hotel_guests WHERE id_company = c.id_company) AS guests,
       (SELECT count(*) FROM hotel_bookings WHERE id_company = c.id_company) AS bookings,
       (SELECT count(*) FROM hotel_maintenance_tickets WHERE id_company = c.id_company) AS tickets,
       (SELECT count(*) FROM hotel_room_inspections WHERE id_company = c.id_company) AS inspections
  FROM companys c WHERE c.metadata->>'qa_tenant' = 'true' AND c.company_name = '[TEST] Hotel Demo';

-- @@FINALIZE
\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** H001 COMMITTED ***'
\else
ROLLBACK;
\echo '*** H001 DRY RUN: rolled back, nothing changed ***'
\endif
\endif
