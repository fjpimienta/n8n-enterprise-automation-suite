-- H001_rollback.sql  (PROPOSAL: not applied anywhere)
-- Soft deactivation of the hotel test tenant created by H001_hotel_test_tenant.sql. It only UPDATEs rows of that one company: no DROP, no DELETE, no TRUNCATE.
-- (user_companies cascades on company delete, so a company is never deleted.)
--   * company: is_active = false (the qa_tenant flag stays)
--   * memberships of the company still active: is_active = false, with a USER_DEACTIVATED audit row each
--   * the two synthetic accounts (@example.invalid): is_active = false, only when they have no other active membership
--   * rooms, guests, bookings: is_active = false; maintenance tickets: status = 'DELETED' (the model's own soft-delete value)
--   * room inspections have no is_active column and stay (they are only reachable through the deactivated company)
-- The company is found with the SAME criterion as the seed (lower(btrim(company_name)) and the qa_tenant flag). Runs in one transaction at REPEATABLE READ; the
-- fingerprint of everything outside the test tenant is compared before the first write and just before COMMIT, and the script aborts if it differs.
-- A deactivated tenant stays in place: room numbers, guest e-mails and doc ids are globally UNIQUE and remain taken, so re-seeding is not supported.
-- Backup first: see the runbook. Usage (owner_email through stdin, like the seed; it is only recorded as the actor of the audit rows):
--   { printf '%s\n' '\set owner_email <EXISTING_ACCOUNT>'; cat H001_rollback.sql; } | psql -X -v ON_ERROR_STOP=1 -f -        (dry run)
--   add '\set apply true' as another line for the real run.
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
\echo 'ABORT: set owner_email (the account recorded as actor in the audit log)'
\quit
\endif
\if :{?embedded}
\else
BEGIN ISOLATION LEVEL REPEATABLE READ;
\endif
SET LOCAL lock_timeout = '5s';
SELECT set_config('h001.apply', :'apply', true) AS apply, set_config('h001.owner', :'owner_email', true) IS NOT NULL AS owner_set;

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
    v_apply boolean := current_setting('h001.apply')::boolean;
    v_owner text    := lower(btrim(current_setting('h001.owner')));
    v_co    integer;
    v_fp0   text;
    v_n     integer;
    v_m     integer := 0;
    v_rooms integer; v_guests integer; v_bookings integer; v_tickets integer; v_users integer;
    r       record;
BEGIN
    IF current_setting('transaction_isolation') <> 'repeatable read' THEN
        RAISE EXCEPTION 'ABORT: the transaction must run at REPEATABLE READ (found %).', current_setting('transaction_isolation');
    END IF;
    SELECT id_company INTO v_co FROM companys
     WHERE lower(btrim(company_name)) = lower('[TEST] Hotel Demo') AND metadata->>'qa_tenant' = 'true' ORDER BY id_company LIMIT 1;
    IF v_co IS NULL THEN RAISE EXCEPTION 'ABORT: the flagged test company was not found.'; END IF;
    IF v_co = 1 THEN RAISE EXCEPTION 'ABORT: company 1 can never be deactivated by this script.'; END IF;
    IF NOT v_apply THEN
        RAISE NOTICE 'DRY RUN: would deactivate company %, % active memberships, % rooms, % guests, % bookings and mark % tickets DELETED.', v_co,
            (SELECT count(*) FROM user_companies WHERE id_company = v_co AND is_active IS TRUE),
            (SELECT count(*) FROM hotel_rooms WHERE id_company = v_co AND is_active IS TRUE),
            (SELECT count(*) FROM hotel_guests WHERE id_company = v_co AND is_active IS TRUE),
            (SELECT count(*) FROM hotel_bookings WHERE id_company = v_co AND is_active IS TRUE),
            (SELECT count(*) FROM hotel_maintenance_tickets WHERE id_company = v_co AND status IS DISTINCT FROM 'DELETED');
        RETURN;
    END IF;
    v_fp0 := pg_temp.h001_fp(v_co);

    FOR r IN SELECT email, role FROM user_companies WHERE id_company = v_co AND is_active IS TRUE LOOP
        UPDATE user_companies SET is_active = false WHERE id_company = v_co AND email = r.email;
        INSERT INTO access_audit_log (id_company, actor_email, target_email, action, old_value, new_value)
        VALUES (v_co, v_owner, r.email, 'USER_DEACTIVATED', jsonb_build_object('role', r.role, 'is_active', true),
                jsonb_build_object('role', r.role, 'is_active', false, 'source', 'H001 rollback'));
        v_m := v_m + 1;
    END LOOP;
    UPDATE users u SET is_active = false
     WHERE lower(u.email) IN ('test.admin@example.invalid', 'test.editor@example.invalid')
       AND NOT EXISTS (SELECT 1 FROM user_companies uc WHERE uc.email = u.email AND uc.is_active IS TRUE);
    GET DIAGNOSTICS v_users = ROW_COUNT;
    UPDATE hotel_rooms    SET is_active = false WHERE id_company = v_co AND is_active IS TRUE;  GET DIAGNOSTICS v_rooms = ROW_COUNT;
    UPDATE hotel_guests   SET is_active = false WHERE id_company = v_co AND is_active IS TRUE;  GET DIAGNOSTICS v_guests = ROW_COUNT;
    UPDATE hotel_bookings SET is_active = false WHERE id_company = v_co AND is_active IS TRUE;  GET DIAGNOSTICS v_bookings = ROW_COUNT;
    UPDATE hotel_maintenance_tickets SET status = 'DELETED' WHERE id_company = v_co AND status IS DISTINCT FROM 'DELETED';  GET DIAGNOSTICS v_tickets = ROW_COUNT;
    UPDATE companys SET is_active = false WHERE id_company = v_co AND is_active IS TRUE;  GET DIAGNOSTICS v_n = ROW_COUNT;

    IF pg_temp.h001_fp(v_co) IS DISTINCT FROM v_fp0 THEN
        RAISE EXCEPTION 'ABORT: data outside the test tenant changed during this transaction (fingerprint differs).';
    END IF;
    RAISE NOTICE 'H001 rollback, company %: company rows deactivated %, memberships deactivated %, synthetic accounts deactivated %, rooms %, guests %, bookings %, tickets marked DELETED %. Fingerprint outside the tenant unchanged.',
        v_co, v_n, v_m, v_users, v_rooms, v_guests, v_bookings, v_tickets;
END $$;

-- @@FINALIZE
\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** H001 ROLLBACK COMMITTED (soft deactivation) ***'
\else
ROLLBACK;
\echo '*** H001 ROLLBACK DRY RUN: nothing changed ***'
\endif
\endif
