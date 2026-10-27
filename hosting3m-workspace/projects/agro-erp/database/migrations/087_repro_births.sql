-- 087_repro_births.sql
-- Reproduction tracking, phase 4a: births (checked registration, possible duplicates, blocks, historical births).
--
-- REQUIRES 084 and 085 (fn_repro_ctx / fn_repro_txt / fn_repro_date, fn_repro_today, fn_repro_resolve_animal,
-- fn_repro_member_role, fn_trg_empadre_append_only). It aborts when they are missing, and it aborts when the live body of
-- sp_register_birth_event (13 parameters) is not the one verified in production on 2026-10-28 (md5 below): production
-- procedures have been edited by hand before, so a replacement is never written over an unknown body.
--
-- What it changes (everything else is untouched):
--   * sp_register_birth_event (SAME 13-parameter signature, CREATE OR REPLACE; it is the only overload in production)
--       - when p_reported_by_email is given, the user must be an ACTIVE member of p_id_company (P0001, fail closed);
--         a NULL e-mail keeps the LEGACY path (the gateway model 'nacimiento' calls it without one; 089 disables that model)
--       - exact-retry detection (company, dam, date, calf sex and birth weight IS NOT DISTINCT FROM, created within the last
--         5 minutes) answers {success:true, duplicate_skipped:true} instead of inserting a second calf
--       - stores the reporter in the new birth_events.reported_by_email
--       - after the birth it links the dam's single plausible service when migration 088 is applied (otherwise skipped)
--       - the orphan-calf behaviour (dam not found / ambiguous => calf registered without a dam + warning) is NOT changed
--   * birth_events gets a nullable reported_by_email (additive, no default, no backfill).
-- New objects: repro_births_config, repro_historical_births (+ voids), helpers fn_repro_is_member, fn_repro_birth_dam,
--   fn_repro_birth_exact_retry, fn_repro_birth_window_matches, fn_repro_birth_check_line, fn_repro_births_batch_validate,
--   fn_repro_births_cfg, and the tools
--   sp_repro_register_birth            -> register_birth_checked          (single; dam ambiguity, possible_duplicate, force)
--   sp_repro_births_batch_preview      -> births_batch_preview            (pure read)
--   sp_repro_births_batch_register     -> births_batch_register           (all-or-nothing, re-validates, at most 50 lines)
--   sp_repro_register_historical_birth -> register_historical_birth       (no calf, no status change, idempotent)
--   sp_repro_void_historical_birth     -> void_historical_birth
--   sp_repro_list_historical_births    -> list_historical_births          (needed to find an id to void)
--   sp_repro_births_get_config         -> get_births_config               (read)
--   sp_repro_births_set_config         -> NOT an agent tool; ADMIN only
--
-- Rules (agreed with the owner, 2026-10-28):
--   * possible_duplicate: a second birth of the same dam within possible_duplicate_days (per company, default 240) answers
--     possible_duplicate with the existing birth and inserts nothing, unless the caller passes force (only the NEW function).
--     Historical births count when their precision is DAY or MONTH (MONTH by range overlap); YEAR rows never trigger it;
--     voided rows never count. force also bypasses the 5-minute retry detection (twins with identical data).
--   * The dam is given by id or by identifier (RFID first, then numero_fuego); several matches => ambiguous + candidates.
--   * Every id of a lot / production unit / paddock must belong to the company. Dates use the Mexico City day (not future,
--     at most 365 days back for a registered birth; historical births have no lower bound).
--   * One writer: sp_repro_register_birth and the block register call the legacy sp_register_birth_event for the writes.
--
-- Fail-closed (fn_repro_ctx from 084): non-member, bad tenant, blank e-mail and palm company RAISE (P0001 / P0094).
-- Error codes: P0095 append-only table, P0096 cross-company reference (both from 085).
-- Rollback: 087_rollback.sql (restores the ORIGINAL body of sp_register_birth_event, answers 'disabled' in the new tools;
--           drops nothing). State: 087_state_check.sql. Tests: 087_tests.sql.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 087_repro_births.sql                 -> dry run (rolled back)
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 087_repro_births.sql   -> commit
-- 087_tests.sql includes this file with `embedded` set.

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- 0) Preconditions --------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_oid  oid := to_regprocedure('public.sp_register_birth_event(integer,character varying,character varying,uuid,character varying,character varying,date,uuid,uuid,uuid,numeric,text,character varying)');
    v_n    integer;
BEGIN
    IF to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 084 is not applied here (fn_repro_ctx missing).';
    END IF;
    IF to_regprocedure('public.fn_repro_resolve_animal(integer,text)') IS NULL OR to_regprocedure('public.fn_trg_empadre_append_only()') IS NULL
       OR to_regprocedure('public.fn_repro_today()') IS NULL OR to_regprocedure('public.fn_repro_member_role(integer,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 085 is not applied here (its helpers are missing).';
    END IF;
    IF to_regclass('public.birth_events') IS NULL OR to_regclass('public.cattle_livestock') IS NULL OR to_regclass('public.cattle_weight_logs') IS NULL
       OR to_regclass('public.production_units') IS NULL OR to_regclass('public.production_unit_lots') IS NULL
       OR to_regclass('public.production_unit_paddocks') IS NULL OR to_regclass('public.companys') IS NULL THEN
        RAISE EXCEPTION 'ABORT: birth_events / cattle_livestock / cattle_weight_logs / production_units / lots / paddocks are missing.';
    END IF;
    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_register_birth_event with 13 parameters not found.';
    END IF;
    IF md5(pg_get_functiondef(v_oid)) <> '8eaf6f52716165a6bc59f8f4a6a7ce4a'
       AND (SELECT prosrc FROM pg_proc WHERE oid = v_oid) NOT LIKE '%087:legacy-birth-v1%' THEN
        RAISE EXCEPTION 'ABORT: the live sp_register_birth_event is not the verified production body (md5 %). STOP and compare it before replacing it.',
            md5(pg_get_functiondef(v_oid));
    END IF;
    SELECT count(*) INTO v_n FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'sp_register_birth_event';
    RAISE NOTICE '087: sp_register_birth_event overloads in this database: % (production has only the 13-parameter one; other overloads are never touched)', v_n;
END $$;

-- 1) Additive column ------------------------------------------------------------------------------------------

ALTER TABLE public.birth_events ADD COLUMN IF NOT EXISTS reported_by_email character varying(255);
COMMENT ON COLUMN public.birth_events.reported_by_email IS '087: e-mail of the reporter when the birth came through a path that knows it (nullable, no backfill).';

-- 2) Tables ---------------------------------------------------------------------------------------------------
-- No ON DELETE CASCADE: nothing in this feature is ever deleted by a cascade.

CREATE TABLE IF NOT EXISTS public.repro_births_config (
    id_company              integer PRIMARY KEY REFERENCES public.companys (id_company),
    possible_duplicate_days integer NOT NULL DEFAULT 240
                            CONSTRAINT ck_births_cfg_days CHECK (possible_duplicate_days BETWEEN 30 AND 730),
    updated_by_email        text,
    updated_at              timestamptz NOT NULL DEFAULT now(),
    created_at              timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.repro_historical_births (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company       integer NOT NULL REFERENCES public.companys (id_company),
    dam_id           uuid    NOT NULL REFERENCES public.cattle_livestock (id),
    -- the first day of the period for MONTH / YEAR precision
    birth_date       date    NOT NULL,
    date_precision   text    NOT NULL CONSTRAINT ck_hist_birth_precision CHECK (date_precision IN ('DAY', 'MONTH', 'YEAR')),
    calf_sex         text    CONSTRAINT ck_hist_birth_sex CHECK (calf_sex IN ('MACHO', 'HEMBRA')),
    litter_position  smallint NOT NULL DEFAULT 1 CONSTRAINT ck_hist_birth_litter CHECK (litter_position BETWEEN 1 AND 4),
    source           text    NOT NULL DEFAULT 'HISTORICAL_NOTEBOOK'
                             CONSTRAINT ck_hist_birth_source CHECK (source IN ('HISTORICAL_NOTEBOOK', 'HISTORICAL_SPREADSHEET', 'HISTORICAL_OTHER')),
    notes            text,
    entered_by_email text    NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hist_birth_period_start CHECK (
        (date_precision = 'DAY') OR (date_precision = 'MONTH' AND extract(day FROM birth_date) = 1)
        OR (date_precision = 'YEAR' AND extract(day FROM birth_date) = 1 AND extract(month FROM birth_date) = 1))
);
CREATE INDEX IF NOT EXISTS idx_hist_births_dam ON public.repro_historical_births (id_company, dam_id, birth_date);

CREATE TABLE IF NOT EXISTS public.repro_historical_birth_voids (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company           integer NOT NULL REFERENCES public.companys (id_company),
    historical_birth_id  uuid    NOT NULL UNIQUE REFERENCES public.repro_historical_births (id),
    reason               text    NOT NULL CONSTRAINT ck_hist_void_reason CHECK (length(btrim(reason)) >= 3),
    voided_by_email      text    NOT NULL,
    voided_at            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.repro_births_config IS '087: per-company window (days) of the possible_duplicate check for births; no row = 240. Edited only by sp_repro_births_set_config (ADMIN). Not in crud_models.';
COMMENT ON TABLE public.repro_historical_births IS '087: append-only historical births (P0095 on UPDATE / DELETE / TRUNCATE). Creates no calf and changes no status. Not in crud_models.';
COMMENT ON TABLE public.repro_historical_birth_voids IS '087: append-only voids of historical births, one per birth, reason required. Not in crud_models.';

-- 3) Triggers -------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_trg_hist_birth_tenant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.cattle_livestock l WHERE l.id = NEW.dam_id AND l.tenant_id = NEW.id_company) THEN
        RAISE EXCEPTION 'La madre no pertenece a la empresa del parto historico.' USING ERRCODE = 'P0096';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_trg_hist_birth_void_tenant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.repro_historical_births h WHERE h.id = NEW.historical_birth_id AND h.id_company = NEW.id_company) THEN
        RAISE EXCEPTION 'El parto historico no pertenece a la empresa de la anulacion.' USING ERRCODE = 'P0096';
    END IF;
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    t record;
BEGIN
    FOR t IN
        SELECT * FROM (VALUES
            ('trg_hist_births_append_only',  'repro_historical_births',      'BEFORE UPDATE OR DELETE', 'FOR EACH ROW',       'fn_trg_empadre_append_only'),
            ('trg_hist_births_no_truncate',  'repro_historical_births',      'BEFORE TRUNCATE',         'FOR EACH STATEMENT', 'fn_trg_empadre_append_only'),
            ('trg_hist_births_tenant',       'repro_historical_births',      'BEFORE INSERT',           'FOR EACH ROW',       'fn_trg_hist_birth_tenant'),
            ('trg_hist_voids_append_only',   'repro_historical_birth_voids', 'BEFORE UPDATE OR DELETE', 'FOR EACH ROW',       'fn_trg_empadre_append_only'),
            ('trg_hist_voids_no_truncate',   'repro_historical_birth_voids', 'BEFORE TRUNCATE',         'FOR EACH STATEMENT', 'fn_trg_empadre_append_only'),
            ('trg_hist_voids_tenant',        'repro_historical_birth_voids', 'BEFORE INSERT',           'FOR EACH ROW',       'fn_trg_hist_birth_void_tenant')
        ) AS v (trg, tbl, timing, scope, fn)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger g
                        WHERE g.tgname = t.trg AND g.tgrelid = format('public.%I', t.tbl)::regclass AND NOT g.tgisinternal) THEN
            EXECUTE format('CREATE TRIGGER %I %s ON public.%I %s EXECUTE FUNCTION public.%I()', t.trg, t.timing, t.tbl, t.scope, t.fn);
        END IF;
    END LOOP;
END $$;

-- 4) Helpers (internal: no access control of their own; the callers run fn_repro_ctx first) --------------------

-- True when the e-mail belongs to an ACTIVE member of an ACTIVE company (case-insensitive).
CREATE OR REPLACE FUNCTION public.fn_repro_is_member(p_tenant integer, p_email text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM public.user_companies uc
          JOIN public.users u    ON lower(u.email) = lower(uc.email)
          JOIN public.companys c ON c.id_company = uc.id_company
         WHERE uc.id_company = p_tenant AND uc.is_active IS TRUE AND c.is_active IS TRUE
           AND lower(u.email) = lower(btrim(coalesce(p_email, ''))))
$$;

CREATE OR REPLACE FUNCTION public.fn_repro_births_cfg(p_tenant integer)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce((SELECT c.possible_duplicate_days FROM public.repro_births_config c WHERE c.id_company = p_tenant), 240)
$$;

-- Resolves the dam of a birth inside ONE company: by id, else by identifier (RFID first, then numero_fuego).
--   {status: ok, dam_id, dam:{...}} | not_found | ambiguous (+candidates) | invalid
CREATE OR REPLACE FUNCTION public.fn_repro_birth_dam(p_tenant integer, p_dam_id text, p_ident text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    r    jsonb;
    v_id uuid;
    a    record;
BEGIN
    IF public.fn_repro_txt(p_dam_id) IS NOT NULL THEN
        IF public.fn_repro_txt(p_dam_id) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'DAM_ID_BAD', 'message', 'dam_id no es un UUID valido.');
        END IF;
        v_id := public.fn_repro_txt(p_dam_id)::uuid;
    ELSIF public.fn_repro_txt(p_ident) IS NOT NULL THEN
        r := public.fn_repro_resolve_animal(p_tenant, p_ident);
        IF r->>'status' = 'ambiguous' THEN
            RETURN jsonb_build_object('status', 'ambiguous', 'code', 'DAM_AMBIGUOUS', 'which', 'dam',
                'message', 'Hay varios animales con ese identificador; elige la madre por su arete SINIIGA o por su id.',
                'candidates', r->'candidates');
        ELSIF r->>'status' <> 'ok' THEN
            RETURN jsonb_build_object('status', 'not_found', 'code', 'DAM_NOT_FOUND', 'which', 'dam',
                'message', 'No se encontro la madre ' || public.fn_repro_txt(p_ident) || ' en esta empresa.');
        END IF;
        v_id := (r->>'livestock_id')::uuid;
    ELSE
        RETURN jsonb_build_object('status', 'invalid', 'code', 'DAM_MISSING', 'message', 'Falta identificar a la madre.');
    END IF;

    SELECT l.id, l.rfid_siniiga, l.electronic_rfid, l.numero_fuego, l.category, l.current_status, l.species
      INTO a
      FROM public.cattle_livestock l WHERE l.id = v_id AND l.tenant_id = p_tenant;
    IF a.id IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found', 'code', 'DAM_NOT_FOUND', 'which', 'dam',
                                  'message', 'La madre indicada no existe en esta empresa.');
    END IF;
    RETURN jsonb_build_object('status', 'ok', 'dam_id', a.id,
        'dam', jsonb_build_object('livestock_id', a.id, 'rfid_siniiga', a.rfid_siniiga, 'electronic_rfid', a.electronic_rfid,
                                  'numero_fuego', a.numero_fuego, 'category', a.category, 'current_status', a.current_status,
                                  'species', a.species));
END;
$$;

-- Birth already registered in the last 5 minutes with the same company, dam, date, calf sex and birth weight
-- (IS NOT DISTINCT FROM: both NULL counts as equal). NULL when none. Skipped while app.repro_force_birth = 'on'.
CREATE OR REPLACE FUNCTION public.fn_repro_birth_exact_retry(p_tenant integer, p_dam uuid, p_date date, p_sex text, p_weight numeric)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT be.id
      FROM public.birth_events be
     WHERE coalesce(current_setting('app.repro_force_birth', true), '') <> 'on'
       AND be.id_company = p_tenant AND be.dam_id = p_dam AND be.birth_date = p_date AND be.calf_sex = p_sex
       AND be.created_at > (now() - interval '5 minutes')::timestamp
       AND (SELECT w.weight_kg FROM public.cattle_weight_logs w
             WHERE w.livestock_id = be.calf_id AND w.source_device = 'BIRTH_EVENT'
             ORDER BY w.log_date, w.id LIMIT 1) IS NOT DISTINCT FROM p_weight
     ORDER BY be.created_at
     LIMIT 1
$$;

-- Births of the dam (registered ones, and historical ones with DAY / MONTH precision that are not voided) whose date is
-- within p_window days of p_date. YEAR rows are too coarse and never count.
CREATE OR REPLACE FUNCTION public.fn_repro_birth_window_matches(p_tenant integer, p_dam uuid, p_date date, p_window integer)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(jsonb_agg(m.j ORDER BY m.d, m.k), '[]'::jsonb)
      FROM (
        SELECT be.birth_date AS d, be.id::text AS k,
               jsonb_build_object('source', 'BIRTH', 'id', be.id, 'birth_date', be.birth_date, 'date_precision', 'DAY',
                                  'calf_id', be.calf_id, 'calf_sex', be.calf_sex) AS j
          FROM public.birth_events be
         WHERE be.id_company = p_tenant AND be.dam_id = p_dam
           AND be.birth_date BETWEEN p_date - p_window AND p_date + p_window
        UNION ALL
        SELECT h.birth_date, h.id::text,
               jsonb_build_object('source', 'HISTORICAL', 'id', h.id, 'birth_date', h.birth_date, 'date_precision', h.date_precision,
                                  'calf_sex', h.calf_sex, 'litter_position', h.litter_position)
          FROM public.repro_historical_births h
         WHERE h.id_company = p_tenant AND h.dam_id = p_dam AND h.date_precision IN ('DAY', 'MONTH')
           AND NOT EXISTS (SELECT 1 FROM public.repro_historical_birth_voids v WHERE v.historical_birth_id = h.id AND v.id_company = p_tenant)
           AND h.birth_date <= p_date + p_window
           AND CASE WHEN h.date_precision = 'MONTH' THEN (h.birth_date + interval '1 month')::date - 1 ELSE h.birth_date END >= p_date - p_window
      ) m
$$;

-- Validates ONE birth line for ONE company and resolves everything needed to register it. Writes nothing.
-- p_line keys: dam_identifier | dam_id, calf_sex, birth_date, birth_weight_kg, lot_id, production_unit_id, paddock_id, species, notes.
-- status: ok | duplicate_skipped | possible_duplicate | not_found | ambiguous | invalid
CREATE OR REPLACE FUNCTION public.fn_repro_birth_check_line(p_tenant integer, p_line jsonb, p_default_date date, p_force boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_today   date := public.fn_repro_today();
    v_species text := upper(coalesce(public.fn_repro_txt(p_line->>'species'), 'BOVINO'));
    v_sex     text := upper(coalesce(public.fn_repro_txt(p_line->>'calf_sex'), ''));
    v_date    date;
    v_wtxt    text := public.fn_repro_txt(p_line->>'birth_weight_kg');
    v_w       numeric;
    v_lot     uuid;
    v_pu      uuid;
    v_pad     uuid;
    v_txt     text;
    d         jsonb;
    v_dam     uuid;
    v_dam_j   jsonb;
    v_window  integer;
    v_dups    jsonb;
    v_retry   uuid;
    v_uuid_re constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
BEGIN
    IF v_species NOT IN ('BOVINO', 'BORREGO', 'BUFALO', 'EQUIDO') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_SPECIES', 'message', 'La especie debe ser BOVINO, BORREGO, BUFALO o EQUIDO.');
    END IF;
    IF v_sex IN ('M') THEN v_sex := 'MACHO'; ELSIF v_sex IN ('H') THEN v_sex := 'HEMBRA'; END IF;
    IF v_sex NOT IN ('MACHO', 'HEMBRA') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_SEX', 'message', 'El sexo de la cria debe ser MACHO o HEMBRA.');
    END IF;

    v_txt := public.fn_repro_txt(p_line->>'birth_date');
    IF v_txt IS NULL THEN
        v_date := coalesce(p_default_date, v_today);
    ELSE
        v_date := public.fn_repro_date(v_txt);
        IF v_date IS NULL THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'La fecha debe tener el formato AAAA-MM-DD.');
        END IF;
    END IF;
    IF v_date > v_today THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'La fecha del parto no puede ser futura.');
    ELSIF v_date < v_today - 365 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE',
            'message', 'La fecha del parto tiene mas de un ano de antiguedad; usa el registro de partos historicos.');
    END IF;

    IF v_wtxt IS NOT NULL THEN
        IF v_wtxt !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_WEIGHT', 'message', 'El peso al nacer debe ser un numero en kg (sin comas, maximo 2 decimales).');
        END IF;
        v_w := v_wtxt::numeric;
        IF v_w <= 0 OR v_w > 150 THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_WEIGHT', 'message', 'El peso al nacer debe estar entre 0 y 150 kg.');
        END IF;
    END IF;

    -- every id must belong to the company (the legacy procedure validates only the lot)
    v_txt := public.fn_repro_txt(p_line->>'lot_id');
    IF v_txt IS NOT NULL THEN
        IF v_txt !~* v_uuid_re OR NOT EXISTS (SELECT 1 FROM public.production_unit_lots x WHERE x.id = v_txt::uuid AND x.id_company = p_tenant) THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'LOT_NOT_FOUND', 'message', 'El lote indicado no existe en esta empresa.');
        END IF;
        v_lot := v_txt::uuid;
    END IF;
    v_txt := public.fn_repro_txt(p_line->>'production_unit_id');
    IF v_txt IS NOT NULL THEN
        IF v_txt !~* v_uuid_re OR NOT EXISTS (SELECT 1 FROM public.production_units x WHERE x.id = v_txt::uuid AND x.id_company = p_tenant) THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'UPP_NOT_FOUND', 'message', 'La UPP indicada no existe en esta empresa.');
        END IF;
        v_pu := v_txt::uuid;
    END IF;
    v_txt := public.fn_repro_txt(p_line->>'paddock_id');
    IF v_txt IS NOT NULL THEN
        IF v_txt !~* v_uuid_re OR NOT EXISTS (SELECT 1 FROM public.production_unit_paddocks x WHERE x.id = v_txt::uuid AND x.id_company = p_tenant) THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'PADDOCK_NOT_FOUND', 'message', 'El potrero indicado no existe en esta empresa.');
        END IF;
        v_pad := v_txt::uuid;
    END IF;

    -- the dam (a BORREGO flock may be registered without one, as the legacy procedure allows)
    IF v_species <> 'BORREGO' OR public.fn_repro_txt(p_line->>'dam_id') IS NOT NULL OR public.fn_repro_txt(p_line->>'dam_identifier') IS NOT NULL THEN
        d := public.fn_repro_birth_dam(p_tenant, p_line->>'dam_id', p_line->>'dam_identifier');
        IF d->>'status' <> 'ok' THEN
            RETURN d;
        END IF;
        v_dam := (d->>'dam_id')::uuid;
        v_dam_j := d->'dam';
        IF v_dam_j->>'current_status' IN ('VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS') THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'DAM_NOT_ACTIVE', 'dam', v_dam_j,
                'message', 'La madre tiene estatus ' || (v_dam_j->>'current_status') || ' y ya no forma parte del hato activo; un parto de una madre dada de baja se registra como parto historico.');
        END IF;
        IF v_dam_j->>'species' IS NOT NULL AND v_dam_j->>'species' <> v_species THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'DAM_SPECIES', 'dam', v_dam_j,
                'message', 'La especie de la madre (' || (v_dam_j->>'species') || ') no coincide con la de la cria (' || v_species || ').');
        END IF;
        IF v_species = 'BOVINO' AND v_dam_j->>'category' NOT IN ('VACA', 'NOVILLONA', 'BECERRA') THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'DAM_NOT_FEMALE', 'dam', v_dam_j,
                'message', 'La madre debe ser una hembra bovina (VACA, NOVILLONA o BECERRA); tiene categoria ' || (v_dam_j->>'category') || '.');
        END IF;
    END IF;

    IF v_dam IS NOT NULL AND NOT coalesce(p_force, false) THEN
        v_retry := public.fn_repro_birth_exact_retry(p_tenant, v_dam, v_date, v_sex, v_w);
        IF v_retry IS NOT NULL THEN
            RETURN jsonb_build_object('status', 'duplicate_skipped', 'code', 'DUPLICATE', 'dam_id', v_dam, 'dam', v_dam_j,
                'birth_date', v_date, 'existing_birth_event_id', v_retry,
                'message', 'Este parto ya estaba registrado hace unos minutos; no se duplico.');
        END IF;
        v_window := public.fn_repro_births_cfg(p_tenant);
        v_dups := public.fn_repro_birth_window_matches(p_tenant, v_dam, v_date, v_window);
        IF jsonb_array_length(v_dups) > 0 THEN
            RETURN jsonb_build_object('status', 'possible_duplicate', 'code', 'POSSIBLE_DUPLICATE', 'dam_id', v_dam, 'dam', v_dam_j,
                'birth_date', v_date, 'window_days', v_window, 'existing', v_dups,
                'message', 'La madre ya tiene un parto dentro de ' || v_window || ' dias de esa fecha. No se registro nada; si es un gemelo o un parto distinto, confirma y repite con force.');
        END IF;
    END IF;

    RETURN jsonb_build_object('status', 'ok', 'species', v_species, 'calf_sex', v_sex, 'birth_date', v_date,
        'birth_weight_kg', v_w, 'dam_id', v_dam, 'dam', v_dam_j, 'lot_id', v_lot, 'production_unit_id', v_pu,
        'paddock_id', v_pad, 'notes', public.fn_repro_txt(p_line->>'notes'));
END;
$$;

-- Validates a JSON array of birth lines. Returns {err, lines:[{index, ...check_line, }], bad:<count>}; err is set (and lines
-- empty) when the whole input is unusable. A repeated dam inside the batch is a possible_duplicate (twins: single tool + force).
CREATE OR REPLACE FUNCTION public.fn_repro_births_batch_validate(p_tenant integer, p_items text, p_default_date text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_arr     jsonb;
    v_def     date;
    e         jsonb;
    i         integer := 0;
    c         jsonb;
    v_lines   jsonb := '[]'::jsonb;
    v_seen    uuid[] := ARRAY[]::uuid[];
    v_bad     integer := 0;
    v_dam     uuid;
BEGIN
    IF public.fn_repro_txt(p_default_date) IS NOT NULL THEN
        v_def := public.fn_repro_date(p_default_date);
        IF v_def IS NULL THEN
            RETURN jsonb_build_object('err', jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'La fecha comun debe tener el formato AAAA-MM-DD.'));
        END IF;
    END IF;
    BEGIN
        v_arr := public.fn_repro_txt(p_items)::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_arr := NULL;
    END;
    IF v_arr IS NULL OR jsonb_typeof(v_arr) <> 'array' OR jsonb_array_length(v_arr) = 0 THEN
        RETURN jsonb_build_object('err', jsonb_build_object('status', 'invalid', 'code', 'BAD_ITEMS',
            'message', 'items debe ser un arreglo JSON no vacio de objetos con la madre y el sexo de la cria.'));
    END IF;
    IF jsonb_array_length(v_arr) > 50 THEN
        RETURN jsonb_build_object('err', jsonb_build_object('status', 'invalid', 'code', 'TOO_MANY_ITEMS', 'message', 'Maximo 50 partos por bloque.'));
    END IF;

    FOR e IN SELECT x FROM jsonb_array_elements(v_arr) AS t(x) LOOP
        i := i + 1;
        IF jsonb_typeof(e) <> 'object' THEN
            c := jsonb_build_object('status', 'invalid', 'code', 'ITEM_INCOMPLETE', 'message', 'Cada renglon debe ser un objeto.');
        ELSE
            c := public.fn_repro_birth_check_line(p_tenant, e, v_def, false);
        END IF;
        v_dam := NULLIF(c->>'dam_id', '')::uuid;
        IF c->>'status' IN ('ok', 'duplicate_skipped') AND v_dam IS NOT NULL THEN
            IF v_dam = ANY (v_seen) THEN
                c := c || jsonb_build_object('status', 'possible_duplicate', 'code', 'DUPLICATE_IN_BATCH',
                    'message', 'La misma madre aparece mas de una vez en el bloque; registra los gemelos aparte con force.');
            ELSE
                v_seen := v_seen || v_dam;
            END IF;
        END IF;
        IF c->>'status' NOT IN ('ok', 'duplicate_skipped') THEN v_bad := v_bad + 1; END IF;
        v_lines := v_lines || (jsonb_build_object('index', i) || c);
    END LOOP;
    RETURN jsonb_build_object('err', NULL, 'lines', v_lines, 'bad', v_bad);
END;
$$;

-- 5) Tools ----------------------------------------------------------------------------------------------------
-- Every parameter is text (n8n convention). Expected conditions are answers (status); membership / palm failures raise.

CREATE OR REPLACE FUNCTION public.sp_repro_births_get_config(p_tenant_id text, p_user_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    c        record;
BEGIN
    SELECT * INTO c FROM public.repro_births_config WHERE id_company = v_tenant;
    RETURN jsonb_build_object('status', 'ok', 'id_company', v_tenant,
        'possible_duplicate_days', coalesce(c.possible_duplicate_days, 240), 'is_default', c.id_company IS NULL,
        'updated_by_email', c.updated_by_email, 'updated_at', c.updated_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_births_set_config(p_tenant_id text, p_user_email text, p_possible_duplicate_days text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_days   integer := public.fn_repro_int(p_possible_duplicate_days);
BEGIN
    IF public.fn_repro_member_role(v_tenant, p_user_email) IS DISTINCT FROM 'ADMIN' THEN
        RETURN jsonb_build_object('status', 'forbidden', 'message', 'Solo un ADMIN de la empresa puede cambiar este parametro.');
    END IF;
    IF v_days IS NULL OR v_days NOT BETWEEN 30 AND 730 THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Los dias deben ser un numero entre 30 y 730.');
    END IF;
    INSERT INTO public.repro_births_config AS c (id_company, possible_duplicate_days, updated_by_email, updated_at)
    VALUES (v_tenant, v_days, lower(public.fn_repro_txt(p_user_email)), now())
    ON CONFLICT (id_company) DO UPDATE
       SET possible_duplicate_days = excluded.possible_duplicate_days, updated_by_email = excluded.updated_by_email, updated_at = now()
     WHERE c.id_company = v_tenant;
    RETURN public.sp_repro_births_get_config(p_tenant_id, p_user_email) || jsonb_build_object('status', 'updated');
END;
$$;

-- register_birth_checked
CREATE OR REPLACE FUNCTION public.sp_repro_register_birth(
    p_tenant_id text, p_user_email text, p_calf_sex text,
    p_dam_identifier text DEFAULT NULL, p_dam_id text DEFAULT NULL, p_birth_date text DEFAULT NULL,
    p_birth_weight_kg text DEFAULT NULL, p_lot_id text DEFAULT NULL, p_production_unit_id text DEFAULT NULL,
    p_paddock_id text DEFAULT NULL, p_species text DEFAULT NULL, p_notes text DEFAULT NULL, p_force text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_email  text;
    v_force  boolean := lower(coalesce(public.fn_repro_txt(p_force), '')) IN ('true', 't', '1', 'si', 'sí', 'yes');
    v_line   jsonb;
    d        jsonb;
    c        jsonb;
    r        jsonb;
BEGIN
    SELECT u.email INTO v_email FROM public.users u WHERE lower(u.email) = lower(public.fn_repro_txt(p_user_email)) LIMIT 1;
    v_line := jsonb_strip_nulls(jsonb_build_object(
        'calf_sex', public.fn_repro_txt(p_calf_sex), 'dam_identifier', public.fn_repro_txt(p_dam_identifier), 'dam_id', public.fn_repro_txt(p_dam_id),
        'birth_date', public.fn_repro_txt(p_birth_date), 'birth_weight_kg', public.fn_repro_txt(p_birth_weight_kg),
        'lot_id', public.fn_repro_txt(p_lot_id), 'production_unit_id', public.fn_repro_txt(p_production_unit_id),
        'paddock_id', public.fn_repro_txt(p_paddock_id), 'species', public.fn_repro_txt(p_species), 'notes', public.fn_repro_txt(p_notes)));

    -- serialise concurrent registrations of the same dam
    d := public.fn_repro_birth_dam(v_tenant, p_dam_id, p_dam_identifier);
    IF d->>'status' = 'ok' THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('birth:' || v_tenant || ':' || (d->>'dam_id'), 0));
    END IF;

    c := public.fn_repro_birth_check_line(v_tenant, v_line, NULL, v_force);
    IF c->>'status' <> 'ok' THEN
        RETURN c || jsonb_build_object('written', 0);
    END IF;

    BEGIN
        PERFORM set_config('app.repro_force_birth', CASE WHEN v_force THEN 'on' ELSE 'off' END, true);
        r := public.sp_register_birth_event(
            v_tenant, c->>'calf_sex', c->>'species', NULLIF(c->>'dam_id', '')::uuid, NULL::varchar, NULL::varchar,
            (c->>'birth_date')::date, NULLIF(c->>'lot_id', '')::uuid, NULLIF(c->>'production_unit_id', '')::uuid,
            NULLIF(c->>'paddock_id', '')::uuid, NULLIF(c->>'birth_weight_kg', '')::numeric, c->>'notes', v_email);
        PERFORM set_config('app.repro_force_birth', 'off', true);
    EXCEPTION WHEN OTHERS THEN
        RAISE;   -- the sub-transaction rollback also restores the setting
    END;

    RETURN r || jsonb_build_object('status', CASE WHEN coalesce((r->>'duplicate_skipped')::boolean, false) THEN 'duplicate_skipped' ELSE 'recorded' END,
                                   'forced', v_force, 'written', 1, 'dam', c->'dam');
END;
$$;

-- births_batch_preview: pure read. Nothing is written, nothing is reserved.
CREATE OR REPLACE FUNCTION public.sp_repro_births_batch_preview(
    p_tenant_id text, p_user_email text, p_items text, p_default_date text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v        jsonb := public.fn_repro_births_batch_validate(v_tenant, p_items, p_default_date);
BEGIN
    IF v->'err' IS NOT NULL AND jsonb_typeof(v->'err') = 'object' THEN
        RETURN v->'err';
    END IF;
    RETURN jsonb_build_object('status', 'ok', 'max_lines', 50,
        'total', jsonb_array_length(v->'lines'), 'problems', (v->>'bad')::int,
        'can_register', (v->>'bad')::int = 0,
        'lines', v->'lines',
        'note', 'Esto es solo una vista previa: no se guardo nada. births_batch_register vuelve a validar todo por su cuenta. Resuelve con el usuario los renglones ambiguous / not_found / possible_duplicate antes de registrar.');
END;
$$;

-- births_batch_register: ALL OR NOTHING. Re-validates every line itself (it never trusts a previous preview).
CREATE OR REPLACE FUNCTION public.sp_repro_births_batch_register(
    p_tenant_id text, p_user_email text, p_items text, p_default_date text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant  integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_email   text;
    v         jsonb;
    v0        jsonb;
    ln        jsonb;
    v_lock    uuid;
    r         jsonb;
    v_results jsonb := '[]'::jsonb;
    v_written integer := 0;
    v_skipped integer := 0;
BEGIN
    SELECT u.email INTO v_email FROM public.users u WHERE lower(u.email) = lower(public.fn_repro_txt(p_user_email)) LIMIT 1;

    -- pass 1 finds the dams so they can be locked in a fixed order; pass 2 (after the locks) is the one that counts
    v0 := public.fn_repro_births_batch_validate(v_tenant, p_items, p_default_date);
    IF v0->'err' IS NOT NULL AND jsonb_typeof(v0->'err') = 'object' THEN
        RETURN v0->'err';
    END IF;
    FOR v_lock IN SELECT DISTINCT (l->>'dam_id')::uuid FROM jsonb_array_elements(v0->'lines') l WHERE NULLIF(l->>'dam_id', '') IS NOT NULL ORDER BY 1 LOOP
        PERFORM pg_advisory_xact_lock(hashtextextended('birth:' || v_tenant || ':' || v_lock::text, 0));
    END LOOP;
    v := public.fn_repro_births_batch_validate(v_tenant, p_items, p_default_date);

    IF (v->>'bad')::int > 0 THEN
        RETURN jsonb_build_object('status', 'rejected', 'written', 0, 'problems', (v->>'bad')::int, 'lines', v->'lines',
            'message', 'No se registro nada del bloque: hay renglones con problemas. Quita o corrige esos renglones y repite el bloque completo; un gemelo o un parto repetido se registra aparte con force.');
    END IF;

    PERFORM set_config('app.repro_force_birth', 'off', true);
    FOR ln IN SELECT l FROM jsonb_array_elements(v->'lines') AS t(l) ORDER BY (l->>'index')::int LOOP
        IF ln->>'status' = 'duplicate_skipped' THEN
            v_skipped := v_skipped + 1;
            v_results := v_results || (jsonb_build_object('index', (ln->>'index')::int) || jsonb_build_object('status', 'duplicate_skipped',
                          'existing_birth_event_id', ln->'existing_birth_event_id', 'dam_id', ln->'dam_id'));
            CONTINUE;
        END IF;
        r := public.sp_register_birth_event(
            v_tenant, ln->>'calf_sex', ln->>'species', NULLIF(ln->>'dam_id', '')::uuid, NULL::varchar, NULL::varchar,
            (ln->>'birth_date')::date, NULLIF(ln->>'lot_id', '')::uuid, NULLIF(ln->>'production_unit_id', '')::uuid,
            NULLIF(ln->>'paddock_id', '')::uuid, NULLIF(ln->>'birth_weight_kg', '')::numeric, ln->>'notes', v_email);
        v_written := v_written + 1;
        v_results := v_results || (jsonb_build_object('index', (ln->>'index')::int, 'status', 'recorded', 'dam', ln->'dam') || r);
    END LOOP;

    RETURN jsonb_build_object('status', 'recorded', 'written', v_written, 'duplicate_skipped', v_skipped, 'results', v_results);
END;
$$;

-- register_historical_birth: a historical birth creates NO calf, does NOT change the dam, is idempotent and voidable.
-- p_date accepts YYYY-MM-DD (DAY), YYYY-MM or YYYY-MM-DD (MONTH) and YYYY or YYYY-MM-DD (YEAR).
CREATE OR REPLACE FUNCTION public.sp_repro_register_historical_birth(
    p_tenant_id text, p_user_email text, p_dam_identifier text DEFAULT NULL, p_dam_id text DEFAULT NULL,
    p_birth_date text DEFAULT NULL, p_date_precision text DEFAULT NULL, p_calf_sex text DEFAULT NULL,
    p_litter_position text DEFAULT NULL, p_source text DEFAULT NULL, p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant  integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_email   text := lower(public.fn_repro_txt(p_user_email));
    v_today   date := public.fn_repro_today();
    v_prec    text := upper(coalesce(public.fn_repro_txt(p_date_precision), 'DAY'));
    v_txt     text := public.fn_repro_txt(p_birth_date);
    v_date    date;
    v_sex     text := upper(public.fn_repro_txt(p_calf_sex));
    v_lit     integer := coalesce(public.fn_repro_int(p_litter_position), 1);
    v_src     text := upper(coalesce(public.fn_repro_txt(p_source), 'HISTORICAL_NOTEBOOK'));
    d         jsonb;
    v_dam     uuid;
    v_dup     uuid;
    v_id      uuid;
    v_reg     jsonb;
BEGIN
    IF v_prec NOT IN ('DAY', 'MONTH', 'YEAR') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_PRECISION', 'message', 'La precision debe ser DAY, MONTH o YEAR.');
    END IF;
    IF v_txt IS NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'Falta la fecha del parto.');
    END IF;
    IF v_prec = 'DAY' THEN
        v_date := public.fn_repro_date(v_txt);
    ELSIF v_prec = 'MONTH' THEN
        v_date := CASE WHEN v_txt ~ '^[0-9]{4}-[0-9]{2}$' THEN public.fn_repro_date(v_txt || '-01')
                       ELSE date_trunc('month', public.fn_repro_date(v_txt))::date END;
    ELSE
        v_date := CASE WHEN v_txt ~ '^[0-9]{4}$' THEN public.fn_repro_date(v_txt || '-01-01')
                       ELSE date_trunc('year', public.fn_repro_date(v_txt))::date END;
    END IF;
    IF v_date IS NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'Fecha invalida para la precision indicada (AAAA-MM-DD, AAAA-MM o AAAA).');
    END IF;
    IF v_date > v_today THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'La fecha del parto no puede ser futura.');
    END IF;
    IF v_sex IN ('M') THEN v_sex := 'MACHO'; ELSIF v_sex IN ('H') THEN v_sex := 'HEMBRA'; END IF;
    IF v_sex IS NOT NULL AND v_sex NOT IN ('MACHO', 'HEMBRA') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_SEX', 'message', 'El sexo de la cria debe ser MACHO, HEMBRA o vacio.');
    END IF;
    IF v_lit NOT BETWEEN 1 AND 4 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_LITTER', 'message', 'La posicion en la camada debe ser de 1 a 4.');
    END IF;
    IF v_src NOT IN ('HISTORICAL_NOTEBOOK', 'HISTORICAL_SPREADSHEET', 'HISTORICAL_OTHER') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_SOURCE', 'message', 'La fuente debe ser HISTORICAL_NOTEBOOK, HISTORICAL_SPREADSHEET o HISTORICAL_OTHER.');
    END IF;

    d := public.fn_repro_birth_dam(v_tenant, p_dam_id, p_dam_identifier);   -- any status of the company is fine
    IF d->>'status' <> 'ok' THEN
        RETURN d;
    END IF;
    v_dam := (d->>'dam_id')::uuid;
    PERFORM pg_advisory_xact_lock(hashtextextended('histbirth:' || v_tenant || ':' || v_dam::text, 0));

    SELECT h.id INTO v_dup
      FROM public.repro_historical_births h
     WHERE h.id_company = v_tenant AND h.dam_id = v_dam AND h.birth_date = v_date AND h.date_precision = v_prec
       AND h.calf_sex IS NOT DISTINCT FROM v_sex AND h.litter_position = v_lit
       AND NOT EXISTS (SELECT 1 FROM public.repro_historical_birth_voids v WHERE v.historical_birth_id = h.id AND v.id_company = v_tenant)
     ORDER BY h.created_at LIMIT 1;
    IF v_dup IS NOT NULL THEN
        RETURN jsonb_build_object('status', 'duplicate_skipped', 'code', 'DUPLICATE', 'historical_birth_id', v_dup, 'dam', d->'dam',
                                  'message', 'Este parto historico ya estaba registrado; no se duplico.');
    END IF;

    INSERT INTO public.repro_historical_births
           (id_company, dam_id, birth_date, date_precision, calf_sex, litter_position, source, notes, entered_by_email)
    VALUES (v_tenant, v_dam, v_date, v_prec, v_sex, v_lit::smallint, v_src, public.fn_repro_txt(p_notes), v_email)
    RETURNING id INTO v_id;

    -- informational only: a REGISTERED birth of the same dam in the same period
    SELECT coalesce(jsonb_agg(jsonb_build_object('birth_event_id', be.id, 'birth_date', be.birth_date)), '[]'::jsonb) INTO v_reg
      FROM public.birth_events be
     WHERE be.id_company = v_tenant AND be.dam_id = v_dam
       AND be.birth_date BETWEEN v_date AND CASE v_prec WHEN 'DAY' THEN v_date WHEN 'MONTH' THEN (v_date + interval '1 month')::date - 1
                                                         ELSE (v_date + interval '1 year')::date - 1 END;

    RETURN jsonb_build_object('status', 'recorded', 'historical_birth_id', v_id, 'birth_date', v_date, 'date_precision', v_prec,
        'calf_sex', v_sex, 'litter_position', v_lit, 'dam', d->'dam',
        'overlaps_registered_births', v_reg,
        'message', 'Parto historico registrado. No se creo ninguna cria ni se cambio el estatus de la madre.');
END;
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_void_historical_birth(
    p_tenant_id text, p_user_email text, p_historical_birth_id text, p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_email  text := lower(public.fn_repro_txt(p_user_email));
    v_txt    text := public.fn_repro_txt(p_historical_birth_id);
    v_id     uuid;
    v_void   uuid;
BEGIN
    IF v_txt IS NULL OR v_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_ID', 'message', 'historical_birth_id debe ser un UUID.');
    END IF;
    IF public.fn_repro_txt(p_reason) IS NULL OR length(public.fn_repro_txt(p_reason)) < 3 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'REASON_REQUIRED', 'message', 'El motivo de la anulacion es obligatorio (minimo 3 caracteres).');
    END IF;
    v_id := v_txt::uuid;
    PERFORM pg_advisory_xact_lock(hashtextextended('histbirth-void:' || v_tenant || ':' || v_id::text, 0));
    IF NOT EXISTS (SELECT 1 FROM public.repro_historical_births h WHERE h.id = v_id AND h.id_company = v_tenant) THEN
        RETURN jsonb_build_object('status', 'not_found', 'message', 'No existe ese parto historico en esta empresa.');
    END IF;
    IF EXISTS (SELECT 1 FROM public.repro_historical_birth_voids v WHERE v.historical_birth_id = v_id AND v.id_company = v_tenant) THEN
        RETURN jsonb_build_object('status', 'already_voided', 'historical_birth_id', v_id, 'message', 'Ese parto historico ya estaba anulado.');
    END IF;
    INSERT INTO public.repro_historical_birth_voids (id_company, historical_birth_id, reason, voided_by_email)
    VALUES (v_tenant, v_id, public.fn_repro_txt(p_reason), v_email) RETURNING id INTO v_void;
    RETURN jsonb_build_object('status', 'voided', 'void_id', v_void, 'historical_birth_id', v_id,
                              'message', 'Parto historico anulado. No se cambio nada mas.');
END;
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_historical_births(
    p_tenant_id text, p_user_email text, p_dam_identifier text DEFAULT NULL, p_include_voided text DEFAULT NULL,
    p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 50), 100);
    v_offset integer := coalesce(public.fn_repro_int(p_offset), 0);
    v_incl   boolean := lower(coalesce(public.fn_repro_txt(p_include_voided), '')) IN ('true', 't', '1', 'si', 'yes');
    d        jsonb;
    v_dam    uuid;
    v_total  bigint;
    v_rows   jsonb;
BEGIN
    IF v_limit < 1 THEN v_limit := 50; END IF;
    IF public.fn_repro_txt(p_dam_identifier) IS NOT NULL THEN
        d := public.fn_repro_birth_dam(v_tenant, NULL, p_dam_identifier);
        IF d->>'status' <> 'ok' THEN RETURN d; END IF;
        v_dam := (d->>'dam_id')::uuid;
    END IF;
    SELECT count(*), coalesce(jsonb_agg(q.j ORDER BY q.d DESC, q.k) FILTER (WHERE q.rn > v_offset AND q.rn <= v_offset + v_limit), '[]'::jsonb)
      INTO v_total, v_rows
      FROM (
        SELECT h.birth_date AS d, h.id::text AS k, row_number() OVER (ORDER BY h.birth_date DESC, h.id::text) AS rn,
               jsonb_build_object('historical_birth_id', h.id, 'dam_id', h.dam_id, 'rfid_siniiga', l.rfid_siniiga, 'numero_fuego', l.numero_fuego,
                                  'dam_status', l.current_status, 'birth_date', h.birth_date, 'date_precision', h.date_precision,
                                  'calf_sex', h.calf_sex, 'litter_position', h.litter_position, 'source', h.source, 'notes', h.notes,
                                  'entered_by_email', h.entered_by_email, 'created_at', h.created_at,
                                  'voided', v.id IS NOT NULL, 'void_reason', v.reason) AS j
          FROM public.repro_historical_births h
          JOIN public.cattle_livestock l ON l.id = h.dam_id AND l.tenant_id = v_tenant
          LEFT JOIN public.repro_historical_birth_voids v ON v.historical_birth_id = h.id AND v.id_company = v_tenant
         WHERE h.id_company = v_tenant AND (v_dam IS NULL OR h.dam_id = v_dam) AND (v_incl OR v.id IS NULL)
      ) q;
    RETURN jsonb_build_object('status', 'ok', 'total', v_total, 'limit', v_limit, 'offset', v_offset,
                              'has_more', (v_offset + v_limit) < v_total, 'historical_births', v_rows);
END;
$$;

-- 6) The legacy procedure -------------------------------------------------------------------------------------
-- Same name, same 13 parameters and defaults: CREATE OR REPLACE, not a new overload. The body is the verified production
-- body (md5 8eaf6f52716165a6bc59f8f4a6a7ce4a) plus the 087 blocks marked "-- 087". 087_rollback.sql restores the original.

CREATE OR REPLACE FUNCTION public.sp_register_birth_event(p_id_company integer, p_calf_sex character varying, p_species character varying DEFAULT 'BOVINO'::character varying, p_dam_id uuid DEFAULT NULL::uuid, p_dam_ear_tag character varying DEFAULT NULL::character varying, p_dam_fire_number character varying DEFAULT NULL::character varying, p_birth_date date DEFAULT CURRENT_DATE, p_lot_id uuid DEFAULT NULL::uuid, p_production_unit_id uuid DEFAULT NULL::uuid, p_paddock_id uuid DEFAULT NULL::uuid, p_birth_weight_kg numeric DEFAULT NULL::numeric, p_notes text DEFAULT NULL::text, p_reported_by_email character varying DEFAULT NULL::character varying)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_event_id             uuid;
    v_calf_id              uuid;
    v_dam_id                uuid;
    v_dam_status             character varying(50);
    v_dam_production_unit    uuid;
    v_dam_lot_id              uuid;
    v_dam_paddock_id          uuid;
    v_dam_upp_origen          character varying(100);
    v_match_count             integer;
    v_dam_updated             boolean := false;
    v_category                 character varying(50);
    v_weight_log_id            uuid;
    v_explicit_lot_unit        uuid;
    v_final_lot_id              uuid;
    v_final_production_unit     uuid;
    v_dup_event                 uuid;
    v_dup_calf                  uuid;
    v_dup_cat                   character varying(50);
    v_link                      jsonb;
BEGIN
    -- 087:legacy-birth-v1 (marker used by the migration, its rollback and its state check)
    -- 087: the legacy NULL e-mail path is kept (gateway callers); when an e-mail IS given the reporter must be an
    -- ACTIVE member of the company (fail closed, same error as the other tools).
    IF p_reported_by_email IS NOT NULL THEN
        IF NOT public.fn_repro_is_member(p_id_company, p_reported_by_email) THEN
            RAISE EXCEPTION 'El usuario % no tiene acceso activo a la empresa %', p_reported_by_email, p_id_company
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF p_species <> 'BORREGO' AND p_dam_id IS NULL AND p_dam_ear_tag IS NULL AND p_dam_fire_number IS NULL THEN
        RAISE EXCEPTION 'Debe identificar a la madre por UUID, arete SINIIGA o número de fuego'
            USING ERRCODE = 'P0003';
    END IF;

    IF p_calf_sex NOT IN ('MACHO', 'HEMBRA') THEN
        RAISE EXCEPTION 'calf_sex debe ser MACHO o HEMBRA'
            USING ERRCODE = 'P0005';
    END IF;

    v_category := CASE p_species || '_' || p_calf_sex
        WHEN 'BOVINO_MACHO'  THEN 'BECERRO'
        WHEN 'BOVINO_HEMBRA' THEN 'BECERRA'
        WHEN 'BORREGO_MACHO'  THEN 'BORREGO'
        WHEN 'BORREGO_HEMBRA' THEN 'BORREGA'
        WHEN 'BUFALO_MACHO'  THEN 'BUCERRO'
        WHEN 'BUFALO_HEMBRA' THEN 'BUCERRA'
        WHEN 'EQUIDO_MACHO'  THEN 'POTRO'
        WHEN 'EQUIDO_HEMBRA' THEN 'POTRANCA'
        ELSE NULL
    END;

    IF v_category IS NULL THEN
        RAISE EXCEPTION 'No hay categoría configurada para especie % y sexo %', p_species, p_calf_sex
            USING ERRCODE = 'P0006';
    END IF;

    IF p_lot_id IS NOT NULL THEN
        SELECT production_unit_id INTO v_explicit_lot_unit
          FROM production_unit_lots
         WHERE id = p_lot_id AND id_company = p_id_company;

        IF v_explicit_lot_unit IS NULL THEN
            RAISE EXCEPTION 'El lote % no existe o no pertenece a la empresa %', p_lot_id, p_id_company
                USING ERRCODE = 'P0002';
        END IF;
    END IF;

    IF p_dam_id IS NOT NULL THEN
        SELECT id, current_status, production_unit_id, lot_id, paddock_id, upp_origen
          INTO v_dam_id, v_dam_status, v_dam_production_unit, v_dam_lot_id, v_dam_paddock_id, v_dam_upp_origen
          FROM cattle_livestock WHERE id = p_dam_id AND tenant_id = p_id_company;

        IF v_dam_id IS NULL THEN
            RAISE EXCEPTION 'La madre % no pertenece a la empresa %', p_dam_id, p_id_company
                USING ERRCODE = 'P0002';
        END IF;

    ELSIF p_dam_ear_tag IS NOT NULL THEN
        SELECT count(*) INTO v_match_count
          FROM cattle_livestock WHERE rfid_siniiga = p_dam_ear_tag AND tenant_id = p_id_company;

        IF v_match_count = 1 THEN
            SELECT id, current_status, production_unit_id, lot_id, paddock_id, upp_origen
              INTO v_dam_id, v_dam_status, v_dam_production_unit, v_dam_lot_id, v_dam_paddock_id, v_dam_upp_origen
              FROM cattle_livestock WHERE rfid_siniiga = p_dam_ear_tag AND tenant_id = p_id_company;
        END IF;

    ELSIF p_dam_fire_number IS NOT NULL THEN
        SELECT count(*) INTO v_match_count
          FROM cattle_livestock WHERE numero_fuego = p_dam_fire_number AND tenant_id = p_id_company;

        IF v_match_count = 1 THEN
            SELECT id, current_status, production_unit_id, lot_id, paddock_id, upp_origen
              INTO v_dam_id, v_dam_status, v_dam_production_unit, v_dam_lot_id, v_dam_paddock_id, v_dam_upp_origen
              FROM cattle_livestock WHERE numero_fuego = p_dam_fire_number AND tenant_id = p_id_company;
        END IF;
    END IF;

    -- 087: exact retry (company, dam, date, calf sex, birth weight IS NOT DISTINCT FROM; created within 5 minutes)
    IF v_dam_id IS NOT NULL THEN
        v_dup_event := public.fn_repro_birth_exact_retry(p_id_company, v_dam_id, p_birth_date, p_calf_sex, p_birth_weight_kg);
        IF v_dup_event IS NOT NULL THEN
            SELECT be.calf_id, cl.category INTO v_dup_calf, v_dup_cat
              FROM birth_events be LEFT JOIN cattle_livestock cl ON cl.id = be.calf_id
             WHERE be.id = v_dup_event;
            RETURN jsonb_build_object(
                'success', true,
                'duplicate_skipped', true,
                'birth_event_id', v_dup_event,
                'calf_id', v_dup_calf,
                'category', v_dup_cat,
                'dam_id_resolved', v_dam_id,
                'message', 'Este parto ya estaba registrado hace unos minutos; no se duplico.'
            );
        END IF;
    END IF;

    IF v_dam_id IS NOT NULL AND v_dam_status = 'PREÑADA' THEN
        UPDATE cattle_livestock SET current_status = 'VACÍA' WHERE id = v_dam_id;
        v_dam_updated := true;
    END IF;

    v_final_lot_id          := COALESCE(p_lot_id, v_dam_lot_id);
    v_final_production_unit := COALESCE(v_explicit_lot_unit, v_dam_production_unit, p_production_unit_id);

    INSERT INTO cattle_livestock (
        tenant_id, category, current_status, birth_date, species,
        mother_id, production_unit_id, lot_id, paddock_id, upp_origen,
        business_model
    ) VALUES (
        p_id_company, v_category, 'ACTIVO', p_birth_date, p_species,
        v_dam_id,
        v_final_production_unit,
        v_final_lot_id,
        COALESCE(v_dam_paddock_id, p_paddock_id),
        v_dam_upp_origen,
        'CRIA'
    ) RETURNING id INTO v_calf_id;

    IF p_birth_weight_kg IS NOT NULL THEN
        INSERT INTO cattle_weight_logs (livestock_id, weight_kg, log_date, source_device)
        VALUES (v_calf_id, p_birth_weight_kg, now(), 'BIRTH_EVENT')
        RETURNING id INTO v_weight_log_id;
    END IF;

    INSERT INTO birth_events (
        id_company, species, dam_id, dam_ear_tag, dam_fire_number,
        calf_sex, calf_id, birth_date, production_unit_id, paddock_id,
        source, notes, reported_by_email
    ) VALUES (
        p_id_company, p_species, v_dam_id, p_dam_ear_tag, p_dam_fire_number,
        p_calf_sex, v_calf_id, p_birth_date,
        v_final_production_unit,
        COALESCE(v_dam_paddock_id, p_paddock_id),
        'MOBILE_APP', p_notes, NULLIF(btrim(p_reported_by_email), '')
    ) RETURNING id INTO v_event_id;

    -- 087: link the dam's single plausible service to this birth (function created by migration 088; absent => skipped).
    -- A failure here never undoes the birth.
    IF v_dam_id IS NOT NULL AND to_regprocedure('public.fn_repro_link_birth_service(uuid,integer)') IS NOT NULL THEN
        BEGIN
            EXECUTE 'SELECT public.fn_repro_link_birth_service($1, $2)' INTO v_link USING v_event_id, p_id_company;
        EXCEPTION WHEN OTHERS THEN
            v_link := jsonb_build_object('status', 'error', 'message', SQLERRM);
        END;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'birth_event_id', v_event_id,
        'calf_id', v_calf_id,
        'duplicate_skipped', false,
        'service_link', v_link,
        'category', v_category,
        'dam_id_resolved', v_dam_id,
        'lot_id_resolved', v_final_lot_id,
        'production_unit_id_resolved', v_final_production_unit,
        'dam_status_updated_to_vacia', v_dam_updated,
        'dam_status_warning', CASE
            WHEN v_dam_id IS NULL AND p_species <> 'BORREGO' THEN 'No se pudo identificar a la madre sin ambigüedad; estatus no actualizado, revisar manualmente.'
            WHEN v_dam_id IS NOT NULL AND v_dam_status IS DISTINCT FROM 'PREÑADA' THEN 'La madre no estaba en estatus PREÑADA (estaba en ' || v_dam_status || '); estatus no modificado.'
            ELSE NULL
        END
    );
END;
$function$;

-- 7) Sanity ---------------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY['fn_repro_is_member', 'fn_repro_births_cfg', 'fn_repro_birth_dam', 'fn_repro_birth_exact_retry',
                        'fn_repro_birth_window_matches', 'fn_repro_birth_check_line', 'fn_repro_births_batch_validate',
                        'fn_trg_hist_birth_tenant', 'fn_trg_hist_birth_void_tenant',
                        'sp_repro_births_get_config', 'sp_repro_births_set_config', 'sp_repro_register_birth',
                        'sp_repro_births_batch_preview', 'sp_repro_births_batch_register', 'sp_repro_register_historical_birth',
                        'sp_repro_void_historical_birth', 'sp_repro_list_historical_births']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '087: missing functions: %', v_missing;
    END IF;
    IF to_regclass('public.repro_births_config') IS NULL OR to_regclass('public.repro_historical_births') IS NULL
       OR to_regclass('public.repro_historical_birth_voids') IS NULL THEN
        RAISE EXCEPTION '087: tables missing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'birth_events' AND column_name = 'reported_by_email') THEN
        RAISE EXCEPTION '087: birth_events.reported_by_email missing';
    END IF;
    IF (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.sp_register_birth_event(integer,character varying,character varying,uuid,character varying,character varying,date,uuid,uuid,uuid,numeric,text,character varying)'))
       NOT LIKE '%087:legacy-birth-v1%' THEN
        RAISE EXCEPTION '087: the legacy procedure was not replaced';
    END IF;
    RAISE NOTICE '087: OK';
END $$;

\if :{?embedded}
\echo '*** 087 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 087 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
