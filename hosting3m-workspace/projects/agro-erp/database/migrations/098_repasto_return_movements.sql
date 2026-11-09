-- 098_repasto_return_movements.sql
-- Grazing ("repasto") movements with expected return, tracked per animal.
-- Adds: cattle_movement_events.purpose / expected_return_date, cattle_movement_event_animals.return_status / returned_at,
-- a partial unique index (one OPEN loan per animal), guard triggers, sp_return_movement, vw_livestock_out_on_loan,
-- and a two-point rejection inside sp_solicitar_venta_orden (rebuilt from the LIVE definition, not from a repo file).
-- No existing row is modified. return_status stays NULL for historical rows (NULL = not tracked).
-- Rollback: 098_rollback.sql. Verification: 098_state_check.sql. Tests: 098_tests.sql.
--
-- ERRCODE series (checked with grep over database/migrations; P0098-P0100 were free):
--   P0098  animal is out on an open loan: it cannot be sold, finalized or removed by data cleanup (trigger on cattle_livestock)
--   P0099  sp_return_movement validation failures (actor, role, tenant, event, animals, date)
--   P0100  inconsistent loan row: the animal is in a terminal status (VENDIDO, BAJA_MORTANDAD, BAJA_DEPURACION_DATOS or
--          FINALIZADO, the same four statuses the sale procedures treat as not sellable), or it is not in the event's
--          origin production unit. Closing a row (RETURNED / DIED_AWAY / CANCELLED) is never blocked.
--
-- DEPENDENCY: sp_return_movement is revoked from PUBLIC and no GRANT is issued; it relies on n8n_user being a PostgreSQL
-- superuser (see the suite CLAUDE.md). If that role ever stops being a superuser, add an explicit GRANT EXECUTE.
-- DEPENDENCY: the guards live in the database; real isolation still depends on every caller passing the verified tenant.
-- NOTE: returned_at of a DIED_AWAY row is the moment the death was recorded (now()); the date of death lives in mortality_events.
--
-- Usage: psql -v ON_ERROR_STOP=1 -f 098_repasto_return_movements.sql            (dry run: ROLLBACK)
--        psql -v ON_ERROR_STOP=1 -v apply=true -f 098_repasto_return_movements.sql   (COMMIT)
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- ---------------------------------------------------------------------------------------------
-- NOTE: the inserted SQL must not use identifiers that the function declares as PL/pgSQL variables (r, e, v_*): an alias
-- named like a variable raises 'record "e" has no field "id"' at run time, which a dry run cannot see (098_tests.sql does).
-- 0. Preconditions. Nothing is changed before the anchor pre-flight at the end of this section passes.
--    pg_temp.fn_098_patch_sale_order() is a session-local helper (it disappears with the session). It takes the LIVE
--    definition of sp_solicitar_venta_orden and returns the patched text; it raises if the function is not the 097 (FIFO)
--    version or if any anchor does not appear exactly once. Anchors are exact text of the live definition, so a different
--    pg_get_functiondef formatting (PG 15.4 vs 16) makes the pre-flight fail instead of patching blindly.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.fn_098_patch_sale_order(p_def text) RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE
    -- Loan check blocks (validation phase, then re-check under row lock)
    a1  constant text := E'     WHERE error IS NULL AND estatus IN (''VENDIDO'', ''BAJA_MORTANDAD'', ''BAJA_DEPURACION_DATOS'', ''FINALIZADO'');\n';
    a2  constant text := E'       AND l.current_status IN (''VENDIDO'', ''BAJA_MORTANDAD'', ''BAJA_DEPURACION_DATOS'', ''FINALIZADO'');\n    UPDATE tmp_sale_order_items t\n       SET error = ''El animal seleccionado FIFO';
    add_txt constant text :=
E'    -- 098: animals out on loan (open grazing movement) cannot be sold\n'
'    UPDATE tmp_sale_order_items t\n'
'       SET error = ''Animal fuera en repasto (guía '' || coalesce(m.reemo_folio, ''s/n'') || '', retorno esperado ''\n'
'                   || coalesce(m.expected_return_date::text, ''s/f'') || ''): no se puede vender''\n'
'      FROM (SELECT ea.cattle_livestock_id, ev.id_company, ev.reemo_folio, ev.expected_return_date\n'
'              FROM cattle_movement_event_animals ea\n'
'              JOIN cattle_movement_events ev ON ev.id = ea.event_id\n'
'             WHERE ea.return_status = ''OPEN'') m\n'
'     WHERE t.error IS NULL AND t.livestock_id = m.cattle_livestock_id AND t.id_company = m.id_company;\n';
    -- FIFO selection: the availability count and the selection query must skip animals on an open loan
    f1  constant text := E'               AND NOT EXISTS (SELECT 1 FROM pending_authorizations pa\n                                WHERE pa.livestock_id = l.id AND pa.estado = ''PENDIENTE'');\n\n            IF v_avail < v_qty THEN';
    f2  constant text := E'               AND NOT EXISTS (SELECT 1 FROM pending_authorizations pa\n                                WHERE pa.livestock_id = l.id AND pa.estado = ''PENDIENTE'')\n             ORDER BY l.created_at ASC, l.id ASC\n             LIMIT v_qty;';
    ins_f constant text :=
E'               -- 098: FIFO skips animals out on loan\n'
'               AND NOT EXISTS (SELECT 1 FROM cattle_movement_event_animals ea\n'
'                                WHERE ea.cattle_livestock_id = l.id AND ea.return_status = ''OPEN'')\n';
    v   text := p_def;
    n1 int; n2 int; nf1 int; nf2 int;
BEGIN
    IF v NOT LIKE '%FIFO_SIN_IDENTIFICADOR%' THEN
        RAISE EXCEPTION 'ABORT: the live sp_solicitar_venta_orden is not the 097 (FIFO) version; do not patch it blindly.';
    END IF;
    IF v LIKE '%-- 098:%' THEN
        RAISE EXCEPTION 'ABORT: sp_solicitar_venta_orden already contains 098 text.';
    END IF;
    n1  := (length(v) - length(replace(v, a1, ''))) / length(a1);
    n2  := (length(v) - length(replace(v, a2, ''))) / length(a2);
    nf1 := (length(v) - length(replace(v, f1, ''))) / length(f1);
    nf2 := (length(v) - length(replace(v, f2, ''))) / length(f2);
    IF n1 <> 1 OR n2 <> 1 OR nf1 <> 1 OR nf2 <> 1 THEN
        RAISE EXCEPTION 'ABORT: anchors do not match the live definition exactly once (loan1=%, loan2=%, fifo_count=%, fifo_select=%). Rebuild this migration from the live definition.',
            n1, n2, nf1, nf2;
    END IF;
    v := replace(v, a1, a1 || add_txt);
    v := replace(v, a2, E'       AND l.current_status IN (''VENDIDO'', ''BAJA_MORTANDAD'', ''BAJA_DEPURACION_DATOS'', ''FINALIZADO'');\n'
                        || add_txt
                        || E'    UPDATE tmp_sale_order_items t\n       SET error = ''El animal seleccionado FIFO');
    v := replace(v, f1, ins_f || f1);
    v := replace(v, f2, ins_f || f2);
    RETURN v;
END;
$fn$;

DO $$
DECLARE
    v_def text;
    v_loan int;
    v_fifo int;
BEGIN
    IF to_regclass('public.cattle_movement_events') IS NULL
       OR to_regclass('public.cattle_movement_event_animals') IS NULL
       OR to_regclass('public.cattle_livestock') IS NULL
       OR to_regclass('public.external_destinations') IS NULL
       OR to_regclass('public.production_units') IS NULL
       OR to_regclass('public.user_companies') IS NULL THEN
        RAISE EXCEPTION 'ABORT: a table required by 098 is missing.';
    END IF;
    IF to_regprocedure('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_solicitar_venta_orden not found.';
    END IF;
    v_def := pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure);
    -- The live function must be the 097 version (FIFO) and either unpatched or completely patched (re-run).
    IF v_def NOT LIKE '%FIFO_SIN_IDENTIFICADOR%' THEN
        RAISE EXCEPTION 'ABORT: the live sp_solicitar_venta_orden is not the 097 (FIFO) version; do not patch it blindly.';
    END IF;
    v_loan := (length(v_def) - length(replace(v_def, '-- 098: animals out on loan', ''))) / length('-- 098: animals out on loan');
    v_fifo := (length(v_def) - length(replace(v_def, '-- 098: FIFO skips animals out on loan', ''))) / length('-- 098: FIFO skips animals out on loan');
    IF (v_loan, v_fifo) NOT IN ((0, 0), (2, 2)) THEN
        RAISE EXCEPTION 'ABORT: sp_solicitar_venta_orden is partially patched by 098 (loan=%, fifo=%); restore it with 098_rollback.sql first.', v_loan, v_fifo;
    END IF;
    -- Pre-flight: when unpatched, prove that every anchor matches exactly once BEFORE anything is changed.
    IF v_loan = 0 THEN
        PERFORM pg_temp.fn_098_patch_sale_order(v_def);
        RAISE NOTICE '098 pre-flight: all 4 anchors match the live definition (live md5 %)', md5(v_def);
    ELSE
        RAISE NOTICE '098 pre-flight: sp_solicitar_venta_orden already patched (re-run); it will be left as is.';
    END IF;
END $$;

-- ---------------------------------------------------------------------------------------------
-- 1. cattle_movement_events: purpose + expected return date (event state is NOT stored here)
-- ---------------------------------------------------------------------------------------------
ALTER TABLE public.cattle_movement_events
    ADD COLUMN IF NOT EXISTS purpose text,
    ADD COLUMN IF NOT EXISTS expected_return_date date;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_movement_purpose'
                    AND conrelid = 'public.cattle_movement_events'::regclass) THEN
        ALTER TABLE public.cattle_movement_events
            ADD CONSTRAINT chk_movement_purpose CHECK (purpose IS NULL OR purpose IN ('REPASTO'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_movement_repasto_requires_return'
                    AND conrelid = 'public.cattle_movement_events'::regclass) THEN
        ALTER TABLE public.cattle_movement_events
            ADD CONSTRAINT chk_movement_repasto_requires_return
            CHECK (purpose IS DISTINCT FROM 'REPASTO' OR expected_return_date IS NOT NULL);
    END IF;
END $$;

COMMENT ON COLUMN public.cattle_movement_events.purpose IS
  '098: movement purpose. REPASTO = animals leave to a third-party UPP and are expected back. NULL = ordinary movement.';
COMMENT ON COLUMN public.cattle_movement_events.expected_return_date IS
  '098: expected return date. Required when purpose = REPASTO. The loan state is derived per animal (see vw_livestock_out_on_loan).';

-- ---------------------------------------------------------------------------------------------
-- 2. cattle_movement_event_animals: per-animal loan state (nullable, no default)
-- ---------------------------------------------------------------------------------------------
ALTER TABLE public.cattle_movement_event_animals
    ADD COLUMN IF NOT EXISTS return_status text,
    ADD COLUMN IF NOT EXISTS returned_at timestamptz;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_movement_animal_return_status'
                    AND conrelid = 'public.cattle_movement_event_animals'::regclass) THEN
        ALTER TABLE public.cattle_movement_event_animals
            ADD CONSTRAINT chk_movement_animal_return_status
            CHECK (return_status IS NULL OR return_status IN ('OPEN', 'RETURNED', 'CANCELLED', 'DIED_AWAY'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_movement_animal_returned_at'
                    AND conrelid = 'public.cattle_movement_event_animals'::regclass) THEN
        ALTER TABLE public.cattle_movement_event_animals
            ADD CONSTRAINT chk_movement_animal_returned_at
            CHECK ((return_status IS DISTINCT FROM 'OPEN' OR returned_at IS NULL)
               AND (return_status IS DISTINCT FROM 'RETURNED' OR returned_at IS NOT NULL));
    END IF;
END $$;

-- One animal cannot be in two open loans.
CREATE UNIQUE INDEX IF NOT EXISTS uq_movement_animal_one_open
    ON public.cattle_movement_event_animals (cattle_livestock_id)
    WHERE return_status = 'OPEN';

COMMENT ON COLUMN public.cattle_movement_event_animals.return_status IS
  '098: NULL = not tracked (historical rows). OPEN = animal is out and expected back. RETURNED / CANCELLED / DIED_AWAY close the row (history is kept). Only the seed and sp_return_movement write OPEN.';
COMMENT ON COLUMN public.cattle_movement_event_animals.returned_at IS
  '098: close timestamp. Required for RETURNED, must be NULL while OPEN. For DIED_AWAY it is the moment the death was recorded.';

-- ---------------------------------------------------------------------------------------------
-- 3. Guard: a loan row can only be OPENED for a live animal that sits in the event's origin production unit.
--    Fires on INSERT, and on UPDATE only when the row becomes OPEN (OLD <> 'OPEN' and NEW = 'OPEN').
--    Closing a row (RETURNED / DIED_AWAY / CANCELLED) is never blocked, even for an animal already sold or dead.
--
--    LOCK ORDER (sale vs. new loan on the same animal; READ COMMITTED):
--      * this guard takes FOR SHARE on the cattle_livestock row, then reads the event (no lock on the event);
--      * trg_block_out_on_loan_status runs inside an UPDATE of that same cattle_livestock row, so the row is already locked
--        by the UPDATE, and it only READS cattle_movement_event_animals (no lock on it).
--      Both paths therefore lock cattle_livestock first and never lock event_animals rows in the opposite order, so they
--      cannot deadlock. If the sale commits first, the guard re-reads the new status and rejects with P0100; if the loan
--      is inserted first, the sale UPDATE waits for the share lock, then its trigger (fresh statement snapshot) sees the
--      committed OPEN row and rejects with P0098. sp_return_movement locks the event row, then event_animals; the death
--      trigger updates event_animals while holding the livestock row; neither locks livestock after event_animals.
--      This reasoning is documented, not covered by a concurrent-session test (tests run in one session with ROLLBACK).
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_guard_movement_animal_open()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_status text;
    v_unit   uuid;
    v_origin uuid;
BEGIN
    IF NEW.return_status IS DISTINCT FROM 'OPEN' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.return_status IS NOT DISTINCT FROM 'OPEN' THEN
        RETURN NEW;
    END IF;

    SELECT l.current_status, l.production_unit_id INTO v_status, v_unit
      FROM cattle_livestock l WHERE l.id = NEW.cattle_livestock_id
       FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan row rejected: animal % does not exist', NEW.cattle_livestock_id USING ERRCODE = 'P0100';
    END IF;
    IF v_status IN ('VENDIDO', 'BAJA_MORTANDAD', 'BAJA_DEPURACION_DATOS', 'FINALIZADO') THEN
        RAISE EXCEPTION 'Loan row rejected: animal % has status % and cannot go out on loan', NEW.cattle_livestock_id, v_status
            USING ERRCODE = 'P0100';
    END IF;

    SELECT e.production_unit_origin_id INTO v_origin FROM cattle_movement_events e WHERE e.id = NEW.event_id;
    IF v_origin IS NULL OR v_unit IS DISTINCT FROM v_origin THEN
        RAISE EXCEPTION 'Loan row rejected: animal % is not in the origin production unit of event %', NEW.cattle_livestock_id, NEW.event_id
            USING ERRCODE = 'P0100';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_movement_animal_open ON public.cattle_movement_event_animals;
CREATE TRIGGER trg_guard_movement_animal_open
    BEFORE INSERT OR UPDATE OF return_status ON public.cattle_movement_event_animals
    FOR EACH ROW EXECUTE FUNCTION public.trg_guard_movement_animal_open();

-- ---------------------------------------------------------------------------------------------
-- 4. cattle_livestock: an animal on an open loan cannot be sold / finalized / depurated;
--    a death while out closes the loan row as DIED_AWAY (sp_procesar_baja_mortandad is not touched).
--    The block is keyed by the animal primary key and is NOT filtered by tenant on purpose. This is fail-closed: a tenant
--    filter could only make the guard skip a row, never block more, so a tenant mismatch (bad data, wrong context) must
--    not be able to let a sale through. The animal id is a uuid, unique across tenants.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_block_out_on_loan_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_folio text;
    v_ret   date;
BEGIN
    SELECT e.reemo_folio, e.expected_return_date INTO v_folio, v_ret
      FROM cattle_movement_event_animals ea
      JOIN cattle_movement_events e ON e.id = ea.event_id
     WHERE ea.cattle_livestock_id = NEW.id AND ea.return_status = 'OPEN'
     LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'Animal % is out on loan (guide %, expected return %): it cannot move to status %',
            NEW.id, coalesce(v_folio, 'n/a'), coalesce(v_ret::text, 'n/a'), NEW.current_status
            USING ERRCODE = 'P0098';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_close_loan_on_death()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE cattle_movement_event_animals
       SET return_status = 'DIED_AWAY', returned_at = now()
     WHERE cattle_livestock_id = NEW.id AND return_status = 'OPEN';
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_out_on_loan_status ON public.cattle_livestock;
CREATE TRIGGER trg_block_out_on_loan_status
    BEFORE UPDATE OF current_status ON public.cattle_livestock
    FOR EACH ROW
    WHEN (NEW.current_status IN ('VENDIDO', 'FINALIZADO', 'BAJA_DEPURACION_DATOS')
          AND NEW.current_status IS DISTINCT FROM OLD.current_status)
    EXECUTE FUNCTION public.trg_block_out_on_loan_status();

DROP TRIGGER IF EXISTS trg_close_loan_on_death ON public.cattle_livestock;
CREATE TRIGGER trg_close_loan_on_death
    AFTER UPDATE OF current_status ON public.cattle_livestock
    FOR EACH ROW
    WHEN (NEW.current_status = 'BAJA_MORTANDAD' AND NEW.current_status IS DISTINCT FROM OLD.current_status)
    EXECUTE FUNCTION public.trg_close_loan_on_death();

-- ---------------------------------------------------------------------------------------------
-- 5. sp_return_movement: close the loan per animal (partial or total). History is kept; nothing is deleted
--    and cattle_livestock is never modified (production_unit_id, lot_id and upp_origen stay as they were).
--    p_actor_email MUST come from the verified session, never from model-supplied input.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sp_return_movement(
    p_event_id    uuid,
    p_animals     uuid[],
    p_return_date date,
    p_actor_email character varying)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_email      text := lower(btrim(coalesce(p_actor_email, '')));
    v_today      date := (now() AT TIME ZONE 'America/Mexico_City')::date;
    v_date       date;
    v_event      cattle_movement_events%ROWTYPE;
    v_role       text;
    v_targets    uuid[];
    v_unknown    int;
    v_closed     int;
    v_prev_closed int;
    v_open_left  int;
    v_any_returned boolean;
BEGIN
    IF v_email = '' THEN
        RAISE EXCEPTION 'sp_return_movement: the actor email is required' USING ERRCODE = 'P0099';
    END IF;
    IF p_event_id IS NULL THEN
        RAISE EXCEPTION 'sp_return_movement: the movement event is required' USING ERRCODE = 'P0099';
    END IF;

    SELECT * INTO v_event FROM cattle_movement_events WHERE id = p_event_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'sp_return_movement: movement not found' USING ERRCODE = 'P0099';
    END IF;
    IF v_event.purpose IS DISTINCT FROM 'REPASTO' THEN
        RAISE EXCEPTION 'sp_return_movement: the movement is not a grazing loan' USING ERRCODE = 'P0099';
    END IF;

    -- Role is resolved INSIDE the event's company; same message for "no membership" and "wrong role" (no probing).
    SELECT upper(uc.role) INTO v_role
      FROM user_companies uc
      JOIN users u    ON lower(u.email) = lower(uc.email)
      JOIN companys c ON c.id_company = uc.id_company
     WHERE uc.id_company = v_event.id_company AND lower(uc.email) = v_email
       AND uc.is_active IS TRUE AND u.is_active IS TRUE AND c.is_active IS TRUE
     LIMIT 1;
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'OWNER') THEN
        RAISE EXCEPTION 'sp_return_movement: only an ADMIN or OWNER of the company can register a return' USING ERRCODE = 'P0099';
    END IF;

    v_date := coalesce(p_return_date, v_today);
    IF v_date > v_today THEN
        RAISE EXCEPTION 'sp_return_movement: the return date (%) cannot be in the future', v_date USING ERRCODE = 'P0099';
    END IF;
    IF v_date < v_event.movement_date THEN
        RAISE EXCEPTION 'sp_return_movement: the return date (%) is before the departure (%)', v_date, v_event.movement_date
            USING ERRCODE = 'P0099';
    END IF;

    IF p_animals IS NOT NULL AND cardinality(p_animals) = 0 THEN
        RAISE EXCEPTION 'sp_return_movement: empty animal list; use NULL to return every open animal' USING ERRCODE = 'P0099';
    END IF;
    IF p_animals IS NULL THEN
        SELECT coalesce(array_agg(ea.cattle_livestock_id), '{}') INTO v_targets
          FROM cattle_movement_event_animals ea
         WHERE ea.event_id = p_event_id AND ea.return_status = 'OPEN';
    ELSE
        SELECT count(*) INTO v_unknown
          FROM unnest(p_animals) a(id)
         WHERE NOT EXISTS (SELECT 1 FROM cattle_movement_event_animals ea
                            WHERE ea.event_id = p_event_id AND ea.cattle_livestock_id = a.id);
        IF v_unknown > 0 THEN
            RAISE EXCEPTION 'sp_return_movement: % animal(s) do not belong to this movement', v_unknown USING ERRCODE = 'P0099';
        END IF;
        SELECT coalesce(array_agg(DISTINCT a.id), '{}') INTO v_targets FROM unnest(p_animals) a(id);
    END IF;

    UPDATE cattle_movement_event_animals ea
       SET return_status = 'RETURNED',
           returned_at   = (v_date::timestamp + interval '12 hours') AT TIME ZONE 'America/Mexico_City'
     WHERE ea.event_id = p_event_id AND ea.cattle_livestock_id = ANY (v_targets) AND ea.return_status = 'OPEN';
    GET DIAGNOSTICS v_closed = ROW_COUNT;

    SELECT count(*) INTO v_prev_closed
      FROM cattle_movement_event_animals ea
     WHERE ea.event_id = p_event_id AND ea.cattle_livestock_id = ANY (v_targets) AND ea.return_status IS DISTINCT FROM 'OPEN';
    v_prev_closed := v_prev_closed - v_closed;

    SELECT count(*) FILTER (WHERE ea.return_status = 'OPEN'),
           coalesce(bool_or(ea.return_status = 'RETURNED'), false)
      INTO v_open_left, v_any_returned
      FROM cattle_movement_event_animals ea WHERE ea.event_id = p_event_id;

    RETURN jsonb_build_object(
        'status', 'ok',
        'event_id', p_event_id,
        'returned', v_closed,
        'already_closed', v_prev_closed,
        'still_open', v_open_left,
        'event_state', CASE WHEN v_open_left > 0 THEN 'OPEN' WHEN v_any_returned THEN 'RETURNED' ELSE 'CLOSED' END,
        'return_date', v_date);
END;
$$;

REVOKE ALL ON FUNCTION public.sp_return_movement(uuid, uuid[], date, character varying) FROM PUBLIC;

COMMENT ON FUNCTION public.sp_return_movement(uuid, uuid[], date, character varying) IS
  '098: closes grazing loan rows (RETURNED) per animal. p_animals NULL = every OPEN animal of the event; an empty array is rejected (P0099). Idempotent, supports partial returns. '
  'Requires ADMIN/OWNER of the event company. p_actor_email must come from the verified session, never from model-supplied input. '
  'Errors: P0099. Does not modify cattle_livestock.';

-- ---------------------------------------------------------------------------------------------
-- 6. View: animals tracked in grazing loans. Event state is DERIVED here: OPEN while any animal row is OPEN; else RETURNED
--    if at least one animal RETURNED; else CLOSED (every row CANCELLED or DIED_AWAY).
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.vw_livestock_out_on_loan AS
SELECT e.id_company,
       e.id                          AS event_id,
       e.reemo_folio,
       e.movement_date,
       e.expected_return_date,
       e.purpose,
       ea.id                         AS event_animal_id,
       ea.cattle_livestock_id,
       l.rfid_siniiga,
       l.numero_fuego,
       l.category,
       l.species,
       l.current_status,
       e.production_unit_origin_id,
       pu.ranch_name                 AS origin_upp_name,
       ed.name                       AS destination_name,
       ed.contact_info               AS destination_contact,
       ea.return_status,
       ea.returned_at,
       (ea.return_status = 'OPEN')   AS is_out_on_loan,
       CASE WHEN bool_or(ea.return_status = 'OPEN') OVER (PARTITION BY e.id) THEN 'OPEN'
            WHEN bool_or(ea.return_status = 'RETURNED') OVER (PARTITION BY e.id) THEN 'RETURNED'
            ELSE 'CLOSED' END AS event_state,
       (ea.return_status = 'OPEN' AND e.expected_return_date < (now() AT TIME ZONE 'America/Mexico_City')::date) AS is_overdue,
       ea.created_at
  FROM public.cattle_movement_event_animals ea
  JOIN public.cattle_movement_events e ON e.id = ea.event_id
  JOIN public.cattle_livestock l       ON l.id = ea.cattle_livestock_id
  LEFT JOIN public.production_units pu ON pu.id = e.production_unit_origin_id
  LEFT JOIN public.external_destinations ed ON ed.id = e.external_destination_id
 WHERE e.purpose = 'REPASTO' AND ea.return_status IS NOT NULL;

COMMENT ON VIEW public.vw_livestock_out_on_loan IS
  '098: tracked grazing-loan rows (return_status not null). Filter by id_company in every consumer. event_state is derived, never stored.';

-- ---------------------------------------------------------------------------------------------
-- 7. sp_solicitar_venta_orden: reject animals on an open loan (validation phase and re-check under lock) and keep
--    FIFO selection from picking them (availability count and selection query).
--    The live definition is read with pg_get_functiondef and patched by exact text anchors (helper in section 0), so every
--    other line stays byte-identical to the live function. The error text becomes part of the P0034 summary (creation)
--    and of "errores" (preview). CREATE OR REPLACE keeps owner, ACL and comment; SECURITY, search_path/config, volatility
--    and the other properties are compared before and after, and the migration aborts if any differs.
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
    c_sig constant text := 'public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)';
    v_def text := pg_get_functiondef(c_sig::regprocedure);
    v_props_before text;
    v_props_after  text;
BEGIN
    IF v_def LIKE '%-- 098: animals out on loan%' THEN
        RAISE NOTICE '098: sp_solicitar_venta_orden already patched; skipping.';
        RETURN;
    END IF;
    SELECT concat_ws('|', prosecdef, proconfig::text, provolatile, proleakproof, proparallel, proisstrict, procost, prorows,
                     proacl::text, proowner::regrole::text, prokind, prorettype::regtype::text, proargnames::text,
                     coalesce(obj_description(oid, 'pg_proc'), ''))
      INTO v_props_before FROM pg_proc WHERE oid = c_sig::regprocedure;

    EXECUTE pg_temp.fn_098_patch_sale_order(v_def);

    SELECT concat_ws('|', prosecdef, proconfig::text, provolatile, proleakproof, proparallel, proisstrict, procost, prorows,
                     proacl::text, proowner::regrole::text, prokind, prorettype::regtype::text, proargnames::text,
                     coalesce(obj_description(oid, 'pg_proc'), ''))
      INTO v_props_after FROM pg_proc WHERE oid = c_sig::regprocedure;
    IF v_props_before IS DISTINCT FROM v_props_after THEN
        RAISE EXCEPTION 'ABORT: CREATE OR REPLACE changed function properties (before: %, after: %)', v_props_before, v_props_after;
    END IF;
    RAISE NOTICE '098: sp_solicitar_venta_orden patched. md5 before % / after %; properties unchanged (%)',
        md5(v_def), md5(pg_get_functiondef(c_sig::regprocedure)), v_props_after;
END $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Self-check
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
    v_def text := pg_get_functiondef('public.sp_solicitar_venta_orden(jsonb,character varying,date,boolean,character varying)'::regprocedure);
BEGIN
    IF (length(v_def) - length(replace(v_def, '-- 098: animals out on loan', ''))) <> 2 * length('-- 098: animals out on loan')
       OR (length(v_def) - length(replace(v_def, '-- 098: FIFO skips animals out on loan', ''))) <> 2 * length('-- 098: FIFO skips animals out on loan') THEN
        RAISE EXCEPTION '098: sp_solicitar_venta_orden must contain the loan check twice and the FIFO exclusion twice';
    END IF;
    IF to_regprocedure('public.sp_return_movement(uuid,uuid[],date,character varying)') IS NULL
       OR to_regclass('public.vw_livestock_out_on_loan') IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_block_out_on_loan_status' AND NOT tgisinternal)
       OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_close_loan_on_death' AND NOT tgisinternal)
       OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_guard_movement_animal_open' AND NOT tgisinternal)
       OR to_regclass('public.uq_movement_animal_one_open') IS NULL THEN
        RAISE EXCEPTION '098: an object is missing after the migration';
    END IF;
    RAISE NOTICE '098: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '*** 098 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: 098 rolled back ***'
\endif
\endif
