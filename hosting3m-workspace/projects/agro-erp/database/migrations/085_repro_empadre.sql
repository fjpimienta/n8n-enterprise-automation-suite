-- 085_repro_empadre.sql
-- Reproduction tracking, phase 2: empadre (breeding-group entry) for heifers, and the list of open cows.
--
-- REQUIRES 084 (fn_repro_ctx, fn_repro_txt/int/date, vw_animal_effective_birth). It aborts if 084 is not applied.
--
-- What it adds (all in public; nothing existing is altered, replaced or dropped):
--   tables     repro_empadre_config   one row per company at most (id_company PK); no row = defaults (15 months / 300 kg)
--              repro_empadre_entries  APPEND-ONLY empadre entries (id_company on every row)
--              repro_empadre_voids    APPEND-ONLY, one void per entry (UNIQUE entry_id), reason required
--   triggers   append-only guards (UPDATE / DELETE / TRUNCATE raise P0095) and tenant guards (P0096) on the two
--              append-only tables, as defence in depth on top of the procedures
--   helpers    fn_repro_today, fn_repro_member_role, fn_repro_empadre_cfg, fn_repro_resolve_animal,
--              fn_repro_empadre_eval, fn_repro_empadre_check_item   (internal: no access control of their own)
--   tools      sp_repro_empadre_get_config            -> get_empadre_config            (read, any active member)
--              sp_repro_empadre_set_config            -> NOT an agent tool; ADMIN only, by procedure
--              sp_repro_list_heifers_eligible_for_empadre -> list_heifers_eligible_for_empadre (read)
--              sp_repro_log_empadre_entry             -> log_empadre_entry             (write, any active member)
--              sp_repro_log_empadre_entry_batch       -> log_empadre_entry_batch       (write, all-or-nothing)
--              sp_void_empadre_entry                  -> void_empadre_entry            (write, reason required)
--              sp_repro_list_empadre_entries          -> list_empadre_entries          (read; needed to find an entry to void)
--              sp_repro_list_open_cows                -> list_open_cows                (read)
--
-- NOT touched: sp_void_event (its fingerprint must stay identical: the empadre void is its own procedure),
-- sp_register_birth_event, sp_log_breeding_event, sp_log_palpation_event, crud_models, the gateway, any existing data.
-- This migration writes no rows (no per-company seed): a company without a config row simply uses the defaults.
--
-- Rules (agreed with the owner):
--   * Heifer scope: BOVINO females with category NOVILLONA or BECERRA (BECERRA carries category_possibly_outdated; the
--     category is NEVER changed automatically), not PREÑADA, not sold / dead / finished / purged, not already in an
--     active empadre. Eligible when age >= min_age_months OR a valid weight >= min_weight_kg.
--       - age comes from vw_animal_effective_birth (month precision). A legacy year-only age counts with its MINIMUM
--         possible age (assumed born in December of that year) and is shown with age_precision = YEAR_ONLY.
--       - a weight is valid only when current_weight_kg > 0; its date is the last cattle_weight_logs.log_date
--         (weight_stale when older than weight_stale_days or when there is no weigh-in date). A stale weight still
--         counts, flagged.
--       - trigger: EDAD | PESO | AMBAS. SIN_DATOS = no usable age and no valid weight. There is no
--         REQUIERE_REVISION_FISICA bucket.
--   * "Active empadre" = a non-voided entry whose entry_date is within empadre_window_days (default 90) of today.
--     (The owner asked for "not already in an active empadre" but no exit event exists yet; the window is the
--     assumption that closes an entry. It is a per-company setting and is flagged for review.)
--   * Logging never blocks on the thresholds: a heifer below 15 months / 300 kg is recorded and a warning is stored
--     with the entry and returned. It does block on: unknown / ambiguous animal, not a bovine female, sold / dead,
--     PREÑADA, bull that is not a TORO / BECERRO_TORETE of the same company, an already-active empadre with other data.
--   * Retries are idempotent: the same heifer + same entry_date + same bull returns duplicate_skipped with the
--     existing entry (also after the 5-minute mark, and independent of the notes).
--   * Entry dates use the Mexico City calendar day (the database runs in UTC): default = today there, never in the
--     future, at most 365 days back.
--   * Ambiguity: numero_fuego is not unique. An identifier is resolved first by RFID (unique), then by numero_fuego;
--     several matches answer status 'ambiguous' with the candidates and nothing is written.
--
-- Fail-closed (fn_repro_ctx from 084): the tenant must be a plain integer, the user an ACTIVE member of that ACTIVE
-- company and the company must not be a palm company (P0094). Anything else RAISES P0001: a user of A never gets rows
-- or a status for B. set_config additionally needs the ADMIN role (answers 'forbidden').
-- The 5 phase-1 tools, the parser and the view are not modified.
--
-- Error codes: P0095 append-only table, P0096 cross-company reference.
-- Rollback: 085_rollback.sql (no DROP / DELETE: the 8 tools answer 'disabled'; tables and rows are kept).
-- State:    085_state_check.sql -v expect=before|applied|rolled_back (read-only).
-- Tests:    085_tests.sql (LOCAL / throwaway database, everything rolled back).
--
-- Usage (dry run is the default when apply is not given):
--   psql -v ON_ERROR_STOP=1 -f 085_repro_empadre.sql                 -> dry run (rolled back)
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 085_repro_empadre.sql   -> commit
-- 085_tests.sql includes this file with `embedded` set (the tests own the transaction and roll it back).

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
BEGIN
    IF to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL
       OR to_regclass('public.vw_animal_effective_birth') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 084 is not applied here (fn_repro_ctx / vw_animal_effective_birth missing).';
    END IF;
    IF to_regclass('public.companys') IS NULL OR to_regclass('public.cattle_livestock') IS NULL
       OR to_regclass('public.cattle_breeding_events') IS NULL OR to_regclass('public.event_voids') IS NULL
       OR to_regclass('public.cattle_health_logs') IS NULL OR to_regclass('public.cattle_weight_logs') IS NULL THEN
        RAISE EXCEPTION 'ABORT: companys / cattle_livestock / cattle_breeding_events / event_voids / cattle_health_logs / cattle_weight_logs are missing.';
    END IF;
    IF to_regprocedure('public.fn_reject_palm_company(integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: fn_reject_palm_company not found (migration 082 is not applied here).';
    END IF;
END $$;

-- 1) Tables ---------------------------------------------------------------------------------------------------
-- No ON DELETE CASCADE anywhere: nothing in this feature is ever deleted by a cascade.

CREATE TABLE IF NOT EXISTS public.repro_empadre_config (
    id_company          integer PRIMARY KEY REFERENCES public.companys (id_company),
    min_age_months      integer       NOT NULL DEFAULT 15  CONSTRAINT ck_empadre_cfg_age    CHECK (min_age_months BETWEEN 1 AND 120),
    min_weight_kg       numeric(7,1)  NOT NULL DEFAULT 300 CONSTRAINT ck_empadre_cfg_weight CHECK (min_weight_kg > 0 AND min_weight_kg <= 2000),
    weight_stale_days   integer       NOT NULL DEFAULT 60  CONSTRAINT ck_empadre_cfg_stale  CHECK (weight_stale_days BETWEEN 1 AND 730),
    empadre_window_days integer       NOT NULL DEFAULT 90  CONSTRAINT ck_empadre_cfg_window CHECK (empadre_window_days BETWEEN 1 AND 365),
    -- Phase 2b (weekly alert) is spec only: the flag exists but cannot be turned on until that phase replaces this check.
    notify_enabled      boolean       NOT NULL DEFAULT false CONSTRAINT ck_empadre_cfg_notify_off CHECK (notify_enabled = false),
    updated_by_email    text,
    updated_at          timestamptz   NOT NULL DEFAULT now(),
    created_at          timestamptz   NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.repro_empadre_entries (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company           integer NOT NULL REFERENCES public.companys (id_company),
    heifer_id            uuid    NOT NULL REFERENCES public.cattle_livestock (id),
    bull_id              uuid    REFERENCES public.cattle_livestock (id),
    entry_date           date    NOT NULL,
    method               text    CONSTRAINT ck_empadre_entry_method CHECK (method IN ('MONTA_NATURAL', 'INSEMINACION_ARTIFICIAL')),
    category_at_entry    text    NOT NULL,
    eligibility_trigger  text    NOT NULL CONSTRAINT ck_empadre_entry_trigger
                                 CHECK (eligibility_trigger IN ('EDAD', 'PESO', 'AMBAS', 'NINGUNO', 'SIN_DATOS', 'NO_APLICA')),
    warning_code         text,
    warning              text,
    criteria             jsonb   NOT NULL DEFAULT '{}'::jsonb,
    notes                text,
    registered_by_email  text    NOT NULL,
    batch_id             uuid,
    created_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_empadre_entries_heifer  ON public.repro_empadre_entries (id_company, heifer_id, entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_empadre_entries_company ON public.repro_empadre_entries (id_company, entry_date DESC);

CREATE TABLE IF NOT EXISTS public.repro_empadre_voids (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company       integer NOT NULL REFERENCES public.companys (id_company),
    entry_id         uuid    NOT NULL UNIQUE REFERENCES public.repro_empadre_entries (id),
    reason           text    NOT NULL CONSTRAINT ck_empadre_void_reason CHECK (length(btrim(reason)) >= 3),
    voided_by_email  text    NOT NULL,
    voided_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_empadre_voids_company ON public.repro_empadre_voids (id_company);

COMMENT ON TABLE public.repro_empadre_config  IS '085: per-company empadre thresholds. No row = defaults (15 months, 300 kg). Edited only by sp_repro_empadre_set_config (ADMIN). Not in crud_models.';
COMMENT ON TABLE public.repro_empadre_entries IS '085: append-only empadre entries (P0095 on UPDATE / DELETE / TRUNCATE). Written only by sp_repro_log_empadre_entry[_batch]. Not in crud_models.';
COMMENT ON TABLE public.repro_empadre_voids   IS '085: append-only voids of empadre entries, one per entry, reason required. Written only by sp_void_empadre_entry. Not in crud_models.';

-- 2) Triggers -------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_trg_empadre_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'La tabla % es de solo insercion (no se modifica ni se borra).', TG_TABLE_NAME USING ERRCODE = 'P0095';
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_trg_empadre_entry_tenant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.cattle_livestock l WHERE l.id = NEW.heifer_id AND l.tenant_id = NEW.id_company) THEN
        RAISE EXCEPTION 'La hembra no pertenece a la empresa de la entrada.' USING ERRCODE = 'P0096';
    END IF;
    IF NEW.bull_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.cattle_livestock l WHERE l.id = NEW.bull_id AND l.tenant_id = NEW.id_company) THEN
        RAISE EXCEPTION 'El toro no pertenece a la empresa de la entrada.' USING ERRCODE = 'P0096';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_trg_empadre_void_tenant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.repro_empadre_entries e WHERE e.id = NEW.entry_id AND e.id_company = NEW.id_company) THEN
        RAISE EXCEPTION 'La entrada de empadre no pertenece a la empresa de la anulacion.' USING ERRCODE = 'P0096';
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
            ('trg_empadre_entries_append_only', 'repro_empadre_entries', 'BEFORE UPDATE OR DELETE', 'FOR EACH ROW',       'fn_trg_empadre_append_only'),
            ('trg_empadre_entries_no_truncate', 'repro_empadre_entries', 'BEFORE TRUNCATE',         'FOR EACH STATEMENT', 'fn_trg_empadre_append_only'),
            ('trg_empadre_entries_tenant',      'repro_empadre_entries', 'BEFORE INSERT',           'FOR EACH ROW',       'fn_trg_empadre_entry_tenant'),
            ('trg_empadre_voids_append_only',   'repro_empadre_voids',   'BEFORE UPDATE OR DELETE', 'FOR EACH ROW',       'fn_trg_empadre_append_only'),
            ('trg_empadre_voids_no_truncate',   'repro_empadre_voids',   'BEFORE TRUNCATE',         'FOR EACH STATEMENT', 'fn_trg_empadre_append_only'),
            ('trg_empadre_voids_tenant',        'repro_empadre_voids',   'BEFORE INSERT',           'FOR EACH ROW',       'fn_trg_empadre_void_tenant')
        ) AS v (trg, tbl, timing, scope, fn)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger g
                        WHERE g.tgname = t.trg AND g.tgrelid = format('public.%I', t.tbl)::regclass AND NOT g.tgisinternal) THEN
            EXECUTE format('CREATE TRIGGER %I %s ON public.%I %s EXECUTE FUNCTION public.%I()', t.trg, t.timing, t.tbl, t.scope, t.fn);
        END IF;
    END LOOP;
END $$;

-- 3) Helpers (internal) ---------------------------------------------------------------------------------------

-- Calendar day in Mexico City (the database runs in UTC: current_date is the wrong day after 18:00 there).
CREATE OR REPLACE FUNCTION public.fn_repro_today()
RETURNS date
LANGUAGE sql
STABLE
AS $$
    SELECT (now() AT TIME ZONE 'America/Mexico_City')::date
$$;

-- Upper-cased role of an ACTIVE member, NULL otherwise. Call it only after fn_repro_ctx.
CREATE OR REPLACE FUNCTION public.fn_repro_member_role(p_tenant integer, p_email text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT upper(uc.role)
      FROM public.user_companies uc
     WHERE uc.id_company = p_tenant AND uc.is_active IS TRUE AND lower(uc.email) = lower(public.fn_repro_txt(p_email))
     ORDER BY uc.role
     LIMIT 1
$$;

-- Effective thresholds of a company: its row, or the defaults when it has none.
CREATE OR REPLACE FUNCTION public.fn_repro_empadre_cfg(p_tenant integer)
RETURNS TABLE (min_age_months integer, min_weight_kg numeric, weight_stale_days integer, empadre_window_days integer,
               notify_enabled boolean, is_default boolean, updated_by_email text, updated_at timestamptz)
LANGUAGE plpgsql
STABLE
AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT c.min_age_months, c.min_weight_kg, c.weight_stale_days, c.empadre_window_days, c.notify_enabled, false,
           c.updated_by_email, c.updated_at
      FROM public.repro_empadre_config c WHERE c.id_company = p_tenant;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 15, 300::numeric, 60, 90, false, true, NULL::text, NULL::timestamptz;
    END IF;
END;
$$;

-- Resolves an identifier inside ONE company: RFID (electronic or SINIIGA, unique) first, then numero_fuego (not unique).
--   {status: ok, livestock_id} | {status: not_found} | {status: missing} | {status: ambiguous, candidates: [...]}
-- Never picks one of several matches.
CREATE OR REPLACE FUNCTION public.fn_repro_resolve_animal(p_tenant integer, p_ident text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ident text := public.fn_repro_txt(p_ident);
    v_tier  integer;
    v_n     integer;
    v_id    uuid;
    v_c     jsonb;
BEGIN
    IF v_ident IS NULL THEN
        RETURN jsonb_build_object('status', 'missing');
    END IF;
    FOR v_tier IN 1..2 LOOP
        SELECT count(*), (array_agg(l.id ORDER BY l.id))[1],
               coalesce(jsonb_agg(jsonb_build_object('livestock_id', l.id, 'rfid_siniiga', l.rfid_siniiga,
                                                     'numero_fuego', l.numero_fuego, 'electronic_rfid', l.electronic_rfid,
                                                     'category', l.category, 'current_status', l.current_status)
                                  ORDER BY l.id) FILTER (WHERE l.id IS NOT NULL), '[]'::jsonb)
          INTO v_n, v_id, v_c
          FROM public.cattle_livestock l
         WHERE l.tenant_id = p_tenant
           AND ((v_tier = 1 AND (l.electronic_rfid = v_ident OR l.rfid_siniiga = v_ident))
             OR (v_tier = 2 AND l.numero_fuego = v_ident));
        IF v_n = 1 THEN
            RETURN jsonb_build_object('status', 'ok', 'livestock_id', v_id);
        ELSIF v_n > 1 THEN
            RETURN jsonb_build_object('status', 'ambiguous', 'candidates', v_c);
        END IF;
    END LOOP;
    RETURN jsonb_build_object('status', 'not_found');
END;
$$;

-- Eligibility facts of every BOVINO female (NOVILLONA, BECERRA, VACA) of ONE company, or of a single animal (p_only).
-- INTERNAL: no access control; the callers are the tools below, after fn_repro_ctx. Every table is filtered by p_tenant.
CREATE OR REPLACE FUNCTION public.fn_repro_empadre_eval(p_tenant integer, p_only uuid DEFAULT NULL)
RETURNS TABLE (
    livestock_id uuid, rfid_siniiga text, electronic_rfid text, numero_fuego text, category text, current_status text,
    age_months integer, age_months_min integer, age_precision text, age_source text, date_quality text,
    weight_kg numeric, weight_date date, weight_stale boolean, meets_age boolean, meets_weight boolean,
    eligibility_trigger text, category_possibly_outdated boolean, active_entry_id uuid, active_entry_date date,
    min_age_months integer, min_weight_kg numeric
)
LANGUAGE plpgsql
STABLE
AS $$
#variable_conflict use_column
DECLARE
    cfg     record;
    v_today date := public.fn_repro_today();
BEGIN
    SELECT * INTO cfg FROM public.fn_repro_empadre_cfg(p_tenant);
    RETURN QUERY
    WITH x AS (
        SELECT l.id AS lid, l.rfid_siniiga::text AS rs, l.electronic_rfid::text AS er, l.numero_fuego::text AS nf,
               l.category::text AS cat, l.current_status::text AS st,
               eb.age_months AS am, eb.age_months_min AS amin, eb.age_precision AS ap, eb.age_source AS asrc,
               eb.date_quality AS dq,
               CASE WHEN l.current_weight_kg > 0 THEN l.current_weight_kg END AS w,
               wl.wdate AS wd,
               ae.id AS aeid, ae.entry_date AS aedate,
               CASE WHEN eb.age_precision = 'MONTH'     THEN eb.age_months     >= cfg.min_age_months
                    WHEN eb.age_precision = 'YEAR_ONLY' THEN eb.age_months_min >= cfg.min_age_months
                    ELSE false END AS m_age
          FROM public.cattle_livestock l
          LEFT JOIN public.vw_animal_effective_birth eb ON eb.livestock_id = l.id AND eb.tenant_id = p_tenant
          LEFT JOIN LATERAL (SELECT max(w.log_date)::date AS wdate
                               FROM public.cattle_weight_logs w WHERE w.livestock_id = l.id) wl ON true
          LEFT JOIN LATERAL (SELECT e.id, e.entry_date
                               FROM public.repro_empadre_entries e
                              WHERE e.id_company = p_tenant AND e.heifer_id = l.id
                                AND e.entry_date >= v_today - cfg.empadre_window_days
                                AND NOT EXISTS (SELECT 1 FROM public.repro_empadre_voids v
                                                 WHERE v.entry_id = e.id AND v.id_company = p_tenant)
                              ORDER BY e.entry_date DESC, e.created_at DESC LIMIT 1) ae ON true
         WHERE l.tenant_id = p_tenant
           AND l.species = 'BOVINO'
           AND l.category IN ('NOVILLONA', 'BECERRA', 'VACA')
           AND (p_only IS NULL OR l.id = p_only)
    )
    SELECT x.lid, x.rs, x.er, x.nf, x.cat, x.st,
           x.am, x.amin, x.ap, x.asrc, x.dq,
           x.w, x.wd,
           (x.w IS NOT NULL AND (x.wd IS NULL OR x.wd < v_today - cfg.weight_stale_days)),
           x.m_age,
           (x.w IS NOT NULL AND x.w >= cfg.min_weight_kg),
           CASE WHEN x.cat = 'VACA' THEN 'NO_APLICA'
                WHEN x.m_age AND x.w >= cfg.min_weight_kg THEN 'AMBAS'
                WHEN x.m_age THEN 'EDAD'
                WHEN x.w >= cfg.min_weight_kg THEN 'PESO'
                WHEN x.ap IS NULL AND x.w IS NULL THEN 'SIN_DATOS'
                ELSE 'NINGUNO' END,
           (x.cat = 'BECERRA'),
           x.aeid, x.aedate,
           cfg.min_age_months, cfg.min_weight_kg
      FROM x;
END;
$$;

-- Validates ONE empadre item for ONE company and builds everything needed to insert it. Writes nothing.
-- status: ok | duplicate_skipped | not_found | ambiguous | invalid
CREATE OR REPLACE FUNCTION public.fn_repro_empadre_check_item(
    p_tenant integer, p_heifer text, p_bull text, p_method text, p_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    r        jsonb;
    v_hid    uuid;
    v_bid    uuid;
    v_cat    text;
    v_sp     text;
    v_st     text;
    v_bcat   text;
    v_bsp    text;
    v_bst    text;
    v_method text := upper(public.fn_repro_txt(p_method));
    ev       record;
    v_dup    uuid;
    v_wcode  text;
    v_wmsg   text;
    v_crit   jsonb;
    v_terminal text[] := ARRAY['VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS'];
BEGIN
    -- heifer
    r := public.fn_repro_resolve_animal(p_tenant, p_heifer);
    IF r->>'status' = 'missing' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'HEIFER_MISSING', 'message', 'Falta el identificador de la hembra.');
    ELSIF r->>'status' = 'not_found' THEN
        RETURN jsonb_build_object('status', 'not_found', 'code', 'HEIFER_NOT_FOUND', 'which', 'heifer',
                                  'message', 'No se encontro la hembra ' || public.fn_repro_txt(p_heifer) || ' en esta empresa.');
    ELSIF r->>'status' = 'ambiguous' THEN
        RETURN jsonb_build_object('status', 'ambiguous', 'code', 'HEIFER_AMBIGUOUS', 'which', 'heifer',
                                  'message', 'Hay varios animales con ese identificador; elige uno por su arete SINIIGA.',
                                  'candidates', r->'candidates');
    END IF;
    v_hid := (r->>'livestock_id')::uuid;

    -- bull (optional)
    IF public.fn_repro_txt(p_bull) IS NOT NULL THEN
        r := public.fn_repro_resolve_animal(p_tenant, p_bull);
        IF r->>'status' = 'not_found' THEN
            RETURN jsonb_build_object('status', 'not_found', 'code', 'BULL_NOT_FOUND', 'which', 'bull',
                                      'message', 'No se encontro el toro ' || public.fn_repro_txt(p_bull) || ' en esta empresa.');
        ELSIF r->>'status' = 'ambiguous' THEN
            RETURN jsonb_build_object('status', 'ambiguous', 'code', 'BULL_AMBIGUOUS', 'which', 'bull',
                                      'message', 'Hay varios animales con el identificador del toro; elige uno por su arete SINIIGA.',
                                      'candidates', r->'candidates');
        END IF;
        v_bid := (r->>'livestock_id')::uuid;
    END IF;

    -- idempotent retry: same heifer, same day, same bull (or both without bull), not voided
    SELECT e.id INTO v_dup
      FROM public.repro_empadre_entries e
     WHERE e.id_company = p_tenant AND e.heifer_id = v_hid AND e.entry_date = p_date
       AND e.bull_id IS NOT DISTINCT FROM v_bid
       AND NOT EXISTS (SELECT 1 FROM public.repro_empadre_voids v WHERE v.entry_id = e.id AND v.id_company = p_tenant)
     ORDER BY e.created_at LIMIT 1;
    IF v_dup IS NOT NULL THEN
        RETURN jsonb_build_object('status', 'duplicate_skipped', 'code', 'DUPLICATE', 'heifer_id', v_hid, 'bull_id', v_bid,
                                  'existing_entry_id', v_dup, 'message', 'Esta entrada ya estaba registrada; no se duplico.');
    END IF;

    -- heifer must be a bovine female still in the herd and not pregnant
    SELECT l.category, l.species, l.current_status INTO v_cat, v_sp, v_st
      FROM public.cattle_livestock l WHERE l.id = v_hid AND l.tenant_id = p_tenant;
    IF v_sp IS DISTINCT FROM 'BOVINO' OR v_cat NOT IN ('NOVILLONA', 'BECERRA', 'VACA') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'NOT_FEMALE_BOVINE', 'heifer_id', v_hid,
                                  'message', 'El animal no es una hembra bovina (NOVILLONA, BECERRA o VACA); su categoria es ' || coalesce(v_cat, '?') || '.');
    END IF;
    IF v_st = ANY (v_terminal) THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'NOT_ACTIVE', 'heifer_id', v_hid,
                                  'message', 'El animal ya no esta en el hato (estatus ' || v_st || ').');
    END IF;
    IF v_st = 'PREÑADA' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'PREGNANT', 'heifer_id', v_hid,
                                  'message', 'La hembra esta PREÑADA; no entra a empadre.');
    END IF;

    -- bull must be a breeding male of the same company
    IF v_bid IS NOT NULL THEN
        SELECT l.category, l.species, l.current_status INTO v_bcat, v_bsp, v_bst
          FROM public.cattle_livestock l WHERE l.id = v_bid AND l.tenant_id = p_tenant;
        IF v_bid = v_hid OR v_bsp IS DISTINCT FROM 'BOVINO' OR v_bcat NOT IN ('TORO', 'BECERRO_TORETE') THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'BULL_NOT_MALE', 'heifer_id', v_hid, 'bull_id', v_bid,
                                      'message', 'El animal indicado como toro no es un toro (TORO o BECERRO_TORETE); su categoria es ' || coalesce(v_bcat, '?') || '.');
        END IF;
        IF v_bst = ANY (v_terminal) THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'BULL_NOT_ACTIVE', 'heifer_id', v_hid, 'bull_id', v_bid,
                                      'message', 'El toro ya no esta en el hato (estatus ' || v_bst || ').');
        END IF;
    END IF;

    IF v_method IS NOT NULL AND v_method NOT IN ('MONTA_NATURAL', 'INSEMINACION_ARTIFICIAL') THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_METHOD', 'heifer_id', v_hid,
                                  'message', 'El metodo debe ser MONTA_NATURAL o INSEMINACION_ARTIFICIAL.');
    END IF;

    SELECT * INTO ev FROM public.fn_repro_empadre_eval(p_tenant, v_hid) e;
    IF ev.livestock_id IS NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'NOT_FEMALE_BOVINE', 'heifer_id', v_hid,
                                  'message', 'No se pudo evaluar a la hembra.');
    END IF;

    -- already in an active empadre with other data
    IF ev.active_entry_id IS NOT NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'ALREADY_IN_EMPADRE', 'heifer_id', v_hid,
                                  'existing_entry_id', ev.active_entry_id, 'existing_entry_date', ev.active_entry_date,
                                  'message', 'La hembra ya esta en un empadre activo desde ' || ev.active_entry_date
                                             || '. Anula esa entrada primero si hay que corregirla.');
    END IF;

    -- warning (never blocks)
    IF ev.category <> 'VACA' THEN
        IF ev.eligibility_trigger = 'SIN_DATOS' THEN
            v_wcode := 'NO_DATA';
            v_wmsg := 'No hay edad ni peso validos para comprobar los minimos (' || ev.min_age_months || ' meses o '
                      || trim_scale(ev.min_weight_kg)::text || ' kg). Se registra de todos modos.';
        ELSIF ev.eligibility_trigger = 'NINGUNO' THEN
            v_wcode := 'BELOW_THRESHOLDS';
            v_wmsg := 'La hembra no cumple los minimos (' || ev.min_age_months || ' meses o '
                      || trim_scale(ev.min_weight_kg)::text || ' kg): edad '
                      || coalesce(coalesce(ev.age_months, ev.age_months_min)::text || ' meses', 'desconocida') || ', peso '
                      || coalesce(ev.weight_kg::text || ' kg', 'sin dato') || '. Se registra de todos modos.';
        ELSIF ev.eligibility_trigger = 'PESO' AND ev.weight_stale THEN
            v_wcode := 'WEIGHT_STALE';
            v_wmsg := 'Cumple solo por peso y el peso es antiguo (' || coalesce(ev.weight_date::text, 'sin fecha de pesaje')
                      || '). Se registra de todos modos.';
        END IF;
    END IF;

    v_crit := jsonb_build_object(
        'min_age_months', ev.min_age_months, 'min_weight_kg', ev.min_weight_kg,
        'age_months', ev.age_months, 'age_months_min', ev.age_months_min, 'age_precision', ev.age_precision,
        'age_source', ev.age_source, 'weight_kg', ev.weight_kg, 'weight_date', ev.weight_date,
        'weight_stale', ev.weight_stale, 'meets_age', ev.meets_age, 'meets_weight', ev.meets_weight);

    RETURN jsonb_build_object('status', 'ok', 'heifer_id', v_hid, 'bull_id', v_bid, 'method', v_method, 'entry_date', p_date,
                              'category', ev.category, 'category_possibly_outdated', ev.category_possibly_outdated,
                              'eligibility_trigger', ev.eligibility_trigger,
                              'warning_code', v_wcode, 'warning', v_wmsg, 'criteria', v_crit);
END;
$$;

-- Parses the entry date of a write tool. Returns NULL date and a message through p_err when it is not acceptable.
CREATE OR REPLACE FUNCTION public.fn_repro_empadre_date(p_text text, OUT p_date date, OUT p_err text)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF public.fn_repro_txt(p_text) IS NULL THEN
        p_date := public.fn_repro_today();
    ELSE
        p_date := public.fn_repro_date(p_text);
        IF p_date IS NULL THEN
            p_err := 'La fecha debe tener el formato AAAA-MM-DD.';
        ELSIF p_date > public.fn_repro_today() THEN
            p_date := NULL; p_err := 'La fecha de entrada no puede ser futura.';
        ELSIF p_date < public.fn_repro_today() - 365 THEN
            p_date := NULL; p_err := 'La fecha de entrada tiene mas de un ano de antiguedad.';
        END IF;
    END IF;
END;
$$;

-- 4) Tools ----------------------------------------------------------------------------------------------------
-- Every parameter is text (n8n convention). Expected conditions are answers (status); membership / palm failures raise.

-- 4.1 get_empadre_config
CREATE OR REPLACE FUNCTION public.sp_repro_empadre_get_config(p_tenant_id text, p_user_email text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    cfg      record;
BEGIN
    SELECT * INTO cfg FROM public.fn_repro_empadre_cfg(v_tenant);
    RETURN jsonb_build_object('status', 'ok', 'id_company', v_tenant,
        'min_age_months', cfg.min_age_months, 'min_weight_kg', cfg.min_weight_kg,
        'weight_stale_days', cfg.weight_stale_days, 'empadre_window_days', cfg.empadre_window_days,
        'notify_enabled', cfg.notify_enabled, 'is_default', cfg.is_default,
        'updated_by_email', cfg.updated_by_email, 'updated_at', cfg.updated_at);
END;
$$;

-- 4.2 set_config: ADMIN only. A NULL / empty parameter keeps the current value. notify_enabled cannot be changed here.
CREATE OR REPLACE FUNCTION public.sp_repro_empadre_set_config(
    p_tenant_id text, p_user_email text,
    p_min_age_months text DEFAULT NULL, p_min_weight_kg text DEFAULT NULL,
    p_weight_stale_days text DEFAULT NULL, p_empadre_window_days text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_age    integer := public.fn_repro_int(p_min_age_months);
    v_stale  integer := public.fn_repro_int(p_weight_stale_days);
    v_window integer := public.fn_repro_int(p_empadre_window_days);
    v_weight numeric;
    cfg      record;
BEGIN
    IF public.fn_repro_member_role(v_tenant, p_user_email) IS DISTINCT FROM 'ADMIN' THEN
        RETURN jsonb_build_object('status', 'forbidden', 'message', 'Solo un ADMIN de la empresa puede cambiar estos parametros.');
    END IF;
    IF public.fn_repro_txt(p_min_age_months) IS NULL AND public.fn_repro_txt(p_min_weight_kg) IS NULL
       AND public.fn_repro_txt(p_weight_stale_days) IS NULL AND public.fn_repro_txt(p_empadre_window_days) IS NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'No se indico ningun valor para cambiar.');
    END IF;
    IF public.fn_repro_txt(p_min_weight_kg) IS NOT NULL THEN
        IF public.fn_repro_txt(p_min_weight_kg) !~ '^[0-9]{1,4}(\.[0-9])?$' THEN
            RETURN jsonb_build_object('status', 'invalid', 'message', 'El peso minimo debe ser un numero (maximo un decimal, sin comas).');
        END IF;
        v_weight := public.fn_repro_txt(p_min_weight_kg)::numeric;
    END IF;
    IF (public.fn_repro_txt(p_min_age_months) IS NOT NULL AND (v_age IS NULL OR v_age NOT BETWEEN 1 AND 120))
       OR (v_weight IS NOT NULL AND (v_weight <= 0 OR v_weight > 2000))
       OR (public.fn_repro_txt(p_weight_stale_days) IS NOT NULL AND (v_stale IS NULL OR v_stale NOT BETWEEN 1 AND 730))
       OR (public.fn_repro_txt(p_empadre_window_days) IS NOT NULL AND (v_window IS NULL OR v_window NOT BETWEEN 1 AND 365)) THEN
        RETURN jsonb_build_object('status', 'invalid',
            'message', 'Rangos: edad 1-120 meses, peso mayor que 0 y hasta 2000 kg, dias de pesaje 1-730, dias de empadre 1-365.');
    END IF;

    SELECT * INTO cfg FROM public.fn_repro_empadre_cfg(v_tenant);
    INSERT INTO public.repro_empadre_config AS c
           (id_company, min_age_months, min_weight_kg, weight_stale_days, empadre_window_days, updated_by_email, updated_at)
    VALUES (v_tenant, coalesce(v_age, cfg.min_age_months), coalesce(v_weight, cfg.min_weight_kg),
            coalesce(v_stale, cfg.weight_stale_days), coalesce(v_window, cfg.empadre_window_days),
            lower(public.fn_repro_txt(p_user_email)), now())
    ON CONFLICT (id_company) DO UPDATE
       SET min_age_months      = coalesce(v_age, c.min_age_months),
           min_weight_kg       = coalesce(v_weight, c.min_weight_kg),
           weight_stale_days   = coalesce(v_stale, c.weight_stale_days),
           empadre_window_days = coalesce(v_window, c.empadre_window_days),
           updated_by_email    = lower(public.fn_repro_txt(p_user_email)),
           updated_at          = now()
     WHERE c.id_company = v_tenant;

    RETURN public.sp_repro_empadre_get_config(p_tenant_id, p_user_email) || jsonb_build_object('status', 'updated');
END;
$$;

-- 4.3 list_heifers_eligible_for_empadre
CREATE OR REPLACE FUNCTION public.sp_repro_list_heifers_eligible_for_empadre(
    p_tenant_id text, p_user_email text, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 50), 100);
    v_offset integer := coalesce(public.fn_repro_int(p_offset), 0);
    cfg      record;
    v_elig_total integer; v_nodata_total integer; v_below integer; v_in_empadre integer;
    v_elig jsonb; v_nodata jsonb;
BEGIN
    IF v_limit < 1 THEN v_limit := 50; END IF;
    SELECT * INTO cfg FROM public.fn_repro_empadre_cfg(v_tenant);

    WITH s AS (
        SELECT e.* FROM public.fn_repro_empadre_eval(v_tenant) e
         WHERE e.category IN ('NOVILLONA', 'BECERRA')
           AND e.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS', 'PREÑADA')
    )
    SELECT count(*) FILTER (WHERE s.active_entry_id IS NULL AND s.eligibility_trigger IN ('EDAD', 'PESO', 'AMBAS')),
           count(*) FILTER (WHERE s.active_entry_id IS NULL AND s.eligibility_trigger = 'SIN_DATOS'),
           count(*) FILTER (WHERE s.active_entry_id IS NULL AND s.eligibility_trigger = 'NINGUNO'),
           count(*) FILTER (WHERE s.active_entry_id IS NOT NULL)
      INTO v_elig_total, v_nodata_total, v_below, v_in_empadre
      FROM s;

    SELECT coalesce(jsonb_agg(j ORDER BY k1 DESC NULLS LAST, k2), '[]'::jsonb) INTO v_elig
      FROM (
        SELECT jsonb_build_object(
                 'livestock_id', e.livestock_id, 'rfid_siniiga', e.rfid_siniiga, 'numero_fuego', e.numero_fuego,
                 'electronic_rfid', e.electronic_rfid, 'category', e.category,
                 'category_possibly_outdated', e.category_possibly_outdated, 'current_status', e.current_status,
                 'eligibility_trigger', e.eligibility_trigger,
                 'age_months', e.age_months, 'age_months_min', e.age_months_min,
                 'age_precision', e.age_precision, 'age_source', e.age_source, 'date_quality', e.date_quality,
                 'weight_kg', e.weight_kg, 'weight_date', e.weight_date, 'weight_stale', e.weight_stale) AS j,
               coalesce(e.age_months, e.age_months_min) AS k1, e.livestock_id::text AS k2
          FROM public.fn_repro_empadre_eval(v_tenant) e
         WHERE e.category IN ('NOVILLONA', 'BECERRA')
           AND e.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS', 'PREÑADA')
           AND e.active_entry_id IS NULL AND e.eligibility_trigger IN ('EDAD', 'PESO', 'AMBAS')
         ORDER BY coalesce(e.age_months, e.age_months_min) DESC NULLS LAST, e.livestock_id::text
         LIMIT v_limit OFFSET v_offset
      ) q;

    SELECT coalesce(jsonb_agg(j ORDER BY k), '[]'::jsonb) INTO v_nodata
      FROM (
        SELECT jsonb_build_object(
                 'livestock_id', e.livestock_id, 'rfid_siniiga', e.rfid_siniiga, 'numero_fuego', e.numero_fuego,
                 'electronic_rfid', e.electronic_rfid, 'category', e.category,
                 'category_possibly_outdated', e.category_possibly_outdated, 'current_status', e.current_status) AS j,
               e.livestock_id::text AS k
          FROM public.fn_repro_empadre_eval(v_tenant) e
         WHERE e.category IN ('NOVILLONA', 'BECERRA')
           AND e.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS', 'PREÑADA')
           AND e.active_entry_id IS NULL AND e.eligibility_trigger = 'SIN_DATOS'
         ORDER BY e.livestock_id::text
         LIMIT v_limit OFFSET v_offset
      ) q;

    RETURN jsonb_build_object(
        'status', 'ok',
        'thresholds', jsonb_build_object('min_age_months', cfg.min_age_months, 'min_weight_kg', cfg.min_weight_kg,
                                         'weight_stale_days', cfg.weight_stale_days, 'is_default', cfg.is_default),
        'eligible_total', v_elig_total, 'no_data_total', v_nodata_total,
        'below_thresholds_total', v_below, 'already_in_empadre_total', v_in_empadre,
        'limit', v_limit, 'offset', v_offset,
        'has_more', (v_offset + v_limit) < greatest(v_elig_total, v_nodata_total),
        'eligible', v_elig,
        'sin_datos', v_nodata,
        'note', 'BECERRA puede estar desactualizada como categoria (category_possibly_outdated); la categoria no se cambia sola. Una edad de solo anio (YEAR_ONLY) cuenta con su minimo posible.');
END;
$$;

-- 4.4 log_empadre_entry
CREATE OR REPLACE FUNCTION public.sp_repro_log_empadre_entry(
    p_tenant_id text, p_user_email text, p_heifer_identifier text,
    p_bull_identifier text DEFAULT NULL, p_entry_date text DEFAULT NULL, p_method text DEFAULT NULL, p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_email  text := lower(public.fn_repro_txt(p_user_email));
    d        record;
    r        jsonb;
    c        jsonb;
    v_id     uuid;
BEGIN
    SELECT * INTO d FROM public.fn_repro_empadre_date(p_entry_date);
    IF d.p_date IS NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', d.p_err);
    END IF;

    r := public.fn_repro_resolve_animal(v_tenant, p_heifer_identifier);
    IF r->>'status' = 'ok' THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('empadre:' || v_tenant || ':' || (r->>'livestock_id'), 0));
    END IF;

    c := public.fn_repro_empadre_check_item(v_tenant, p_heifer_identifier, p_bull_identifier, p_method, d.p_date);
    IF c->>'status' <> 'ok' THEN
        RETURN c;
    END IF;

    INSERT INTO public.repro_empadre_entries
           (id_company, heifer_id, bull_id, entry_date, method, category_at_entry, eligibility_trigger,
            warning_code, warning, criteria, notes, registered_by_email)
    VALUES (v_tenant, (c->>'heifer_id')::uuid, (c->>'bull_id')::uuid, d.p_date, c->>'method', c->>'category',
            c->>'eligibility_trigger', c->>'warning_code', c->>'warning', c->'criteria',
            public.fn_repro_txt(p_notes), v_email)
    RETURNING id INTO v_id;

    RETURN c || jsonb_build_object('status', 'recorded', 'entry_id', v_id,
                                   'message', CASE WHEN c->>'warning' IS NULL THEN 'Entrada a empadre registrada.'
                                                   ELSE 'Entrada a empadre registrada con advertencia.' END);
END;
$$;

-- 4.5 log_empadre_entry_batch: ALL OR NOTHING. p_items is a JSON array (text) of identifiers or of objects
-- {"heifer": "...", "bull": "...", "method": "...", "notes": "..."}; the common bull / method / date / notes apply to
-- every item that does not carry its own. At most 100 items.
CREATE OR REPLACE FUNCTION public.sp_repro_log_empadre_entry_batch(
    p_tenant_id text, p_user_email text, p_items text,
    p_entry_date text DEFAULT NULL, p_bull_identifier text DEFAULT NULL, p_method text DEFAULT NULL, p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant  integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_email   text := lower(public.fn_repro_txt(p_user_email));
    d         record;
    v_arr     jsonb;
    v_items   jsonb := '[]'::jsonb;
    e         jsonb;
    i         integer;
    r         jsonb;
    c         jsonb;
    v_locks   uuid[] := ARRAY[]::uuid[];
    v_lock    uuid;
    v_seen    uuid[] := ARRAY[]::uuid[];
    v_checks  jsonb := '[]'::jsonb;
    v_issues  jsonb := '[]'::jsonb;
    v_results jsonb := '[]'::jsonb;
    v_batch   uuid := gen_random_uuid();
    v_id      uuid;
    v_new     integer := 0;
    v_skipped integer := 0;
    v_warn    integer := 0;
    v_hid     uuid;
BEGIN
    SELECT * INTO d FROM public.fn_repro_empadre_date(p_entry_date);
    IF d.p_date IS NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', d.p_err);
    END IF;

    BEGIN
        v_arr := public.fn_repro_txt(p_items)::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_arr := NULL;
    END;
    IF v_arr IS NULL OR jsonb_typeof(v_arr) <> 'array' OR jsonb_array_length(v_arr) = 0 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_ITEMS',
                                  'message', 'items debe ser un arreglo JSON no vacio de identificadores.');
    END IF;
    IF jsonb_array_length(v_arr) > 100 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'TOO_MANY_ITEMS', 'message', 'Maximo 100 hembras por lote.');
    END IF;

    -- normalise
    i := 0;
    FOR e IN SELECT x FROM jsonb_array_elements(v_arr) AS t(x) LOOP
        i := i + 1;
        IF jsonb_typeof(e) = 'string' THEN
            v_items := v_items || jsonb_build_array(jsonb_build_object('i', i, 'heifer', e #>> '{}', 'bull', p_bull_identifier,
                                                                      'method', p_method, 'notes', p_notes));
        ELSIF jsonb_typeof(e) = 'object' THEN
            v_items := v_items || jsonb_build_array(jsonb_build_object(
                'i', i, 'heifer', coalesce(e->>'heifer', e->>'identifier'),
                'bull', coalesce(e->>'bull', p_bull_identifier), 'method', coalesce(e->>'method', p_method),
                'notes', coalesce(e->>'notes', p_notes)));
        ELSE
            RETURN jsonb_build_object('status', 'rejected', 'recorded', 0,
                'issues', jsonb_build_array(jsonb_build_object('index', i, 'status', 'invalid', 'code', 'BAD_ITEM',
                                                                'message', 'Cada elemento debe ser un identificador o un objeto.')));
        END IF;
    END LOOP;

    -- lock every resolvable heifer in a fixed order (no deadlock between two batches)
    FOR e IN SELECT x FROM jsonb_array_elements(v_items) AS t(x) LOOP
        r := public.fn_repro_resolve_animal(v_tenant, e->>'heifer');
        IF r->>'status' = 'ok' THEN
            v_locks := v_locks || (r->>'livestock_id')::uuid;
        END IF;
    END LOOP;
    FOR v_lock IN SELECT DISTINCT u FROM unnest(v_locks) AS u ORDER BY u LOOP
        PERFORM pg_advisory_xact_lock(hashtextextended('empadre:' || v_tenant || ':' || v_lock::text, 0));
    END LOOP;

    -- validate everything first: nothing has been written yet
    FOR e IN SELECT x FROM jsonb_array_elements(v_items) AS t(x) LOOP
        c := public.fn_repro_empadre_check_item(v_tenant, e->>'heifer', e->>'bull', e->>'method', d.p_date);
        c := c || jsonb_build_object('index', (e->>'i')::integer, 'heifer_identifier', e->>'heifer', 'notes', e->>'notes');
        v_hid := (c->>'heifer_id')::uuid;
        IF c->>'status' IN ('ok', 'duplicate_skipped') THEN
            IF v_hid = ANY (v_seen) THEN
                v_issues := v_issues || jsonb_build_array(jsonb_build_object(
                    'index', (e->>'i')::integer, 'heifer_identifier', e->>'heifer', 'status', 'invalid',
                    'code', 'DUPLICATE_IN_BATCH', 'message', 'La misma hembra aparece dos veces en el lote.'));
            END IF;
            v_seen := v_seen || v_hid;
        ELSE
            v_issues := v_issues || jsonb_build_array(c - 'criteria' || jsonb_build_object('heifer_identifier', e->>'heifer'));
        END IF;
        v_checks := v_checks || jsonb_build_array(c);
    END LOOP;

    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'rejected', 'recorded', 0, 'items', jsonb_array_length(v_items),
                                  'message', 'No se registro nada: corrige los renglones con problema y repite el lote completo.',
                                  'issues', v_issues);
    END IF;

    -- write (same transaction: any error rolls the whole batch back)
    FOR c IN SELECT x FROM jsonb_array_elements(v_checks) AS t(x) LOOP
        IF c->>'status' = 'duplicate_skipped' THEN
            v_skipped := v_skipped + 1;
            v_results := v_results || jsonb_build_array(jsonb_build_object(
                'index', (c->>'index')::integer, 'heifer_identifier', c->>'heifer_identifier', 'status', 'duplicate_skipped',
                'entry_id', c->>'existing_entry_id'));
        ELSE
            INSERT INTO public.repro_empadre_entries
                   (id_company, heifer_id, bull_id, entry_date, method, category_at_entry, eligibility_trigger,
                    warning_code, warning, criteria, notes, registered_by_email, batch_id)
            VALUES (v_tenant, (c->>'heifer_id')::uuid, (c->>'bull_id')::uuid, d.p_date, c->>'method', c->>'category',
                    c->>'eligibility_trigger', c->>'warning_code', c->>'warning', c->'criteria',
                    public.fn_repro_txt(c->>'notes'), v_email, v_batch)
            RETURNING id INTO v_id;
            v_new := v_new + 1;
            IF c->>'warning' IS NOT NULL THEN v_warn := v_warn + 1; END IF;
            v_results := v_results || jsonb_build_array(jsonb_build_object(
                'index', (c->>'index')::integer, 'heifer_identifier', c->>'heifer_identifier', 'status', 'recorded',
                'entry_id', v_id, 'eligibility_trigger', c->>'eligibility_trigger',
                'category_possibly_outdated', (c->>'category_possibly_outdated')::boolean,
                'warning_code', c->>'warning_code', 'warning', c->>'warning'));
        END IF;
    END LOOP;

    RETURN jsonb_build_object('status', CASE WHEN v_new > 0 THEN 'recorded' ELSE 'duplicate_skipped' END,
                              'batch_id', v_batch, 'entry_date', d.p_date, 'items', jsonb_array_length(v_items),
                              'recorded', v_new, 'skipped_duplicates', v_skipped, 'with_warning', v_warn,
                              'results', v_results);
END;
$$;

-- 4.6 void_empadre_entry: dedicated procedure (sp_void_event is NOT modified). Any active member; reason required;
-- one void per entry; an entry of another company answers not_found (never says it exists).
CREATE OR REPLACE FUNCTION public.sp_void_empadre_entry(
    p_tenant_id text, p_user_email text, p_entry_id text, p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_email  text := lower(public.fn_repro_txt(p_user_email));
    v_reason text := public.fn_repro_txt(p_reason);
    v_entry  uuid;
    v_void   uuid;
    v_prev   record;
BEGIN
    IF v_reason IS NULL OR length(v_reason) < 3 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'REASON_REQUIRED', 'message', 'Se requiere el motivo de la anulacion.');
    END IF;
    IF public.fn_repro_txt(p_entry_id) IS NULL
       OR public.fn_repro_txt(p_entry_id) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_ENTRY_ID', 'message', 'El id de la entrada no es valido.');
    END IF;

    SELECT e.id INTO v_entry
      FROM public.repro_empadre_entries e
     WHERE e.id = public.fn_repro_txt(p_entry_id)::uuid AND e.id_company = v_tenant;
    IF v_entry IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found', 'message', 'No se encontro esa entrada de empadre en esta empresa.');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('empadre-void:' || v_entry::text, 0));
    INSERT INTO public.repro_empadre_voids (id_company, entry_id, reason, voided_by_email)
    VALUES (v_tenant, v_entry, v_reason, v_email)
    ON CONFLICT (entry_id) DO NOTHING
    RETURNING id INTO v_void;

    IF v_void IS NULL THEN
        SELECT v.voided_at, v.voided_by_email, v.reason INTO v_prev
          FROM public.repro_empadre_voids v WHERE v.entry_id = v_entry AND v.id_company = v_tenant;
        RETURN jsonb_build_object('status', 'already_voided', 'entry_id', v_entry, 'voided_at', v_prev.voided_at,
                                  'message', 'Esa entrada ya estaba anulada.');
    END IF;
    RETURN jsonb_build_object('status', 'voided', 'entry_id', v_entry, 'void_id', v_void, 'message', 'Entrada de empadre anulada.');
END;
$$;

-- 4.7 list_empadre_entries: entries of the company (optionally of one heifer), newest first, with their void state.
CREATE OR REPLACE FUNCTION public.sp_repro_list_empadre_entries(
    p_tenant_id text, p_user_email text, p_heifer_identifier text DEFAULT NULL,
    p_include_voided text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 50), 100);
    v_offset integer := coalesce(public.fn_repro_int(p_offset), 0);
    v_voided boolean := lower(coalesce(public.fn_repro_txt(p_include_voided), 'false')) IN ('true', 't', '1', 'si', 'yes');
    v_hid    uuid;
    r        jsonb;
    v_total  bigint;
    v_rows   jsonb;
BEGIN
    IF v_limit < 1 THEN v_limit := 50; END IF;
    IF public.fn_repro_txt(p_heifer_identifier) IS NOT NULL THEN
        r := public.fn_repro_resolve_animal(v_tenant, p_heifer_identifier);
        IF r->>'status' = 'not_found' THEN
            RETURN jsonb_build_object('status', 'not_found', 'message', 'No se encontro esa hembra en esta empresa.');
        ELSIF r->>'status' = 'ambiguous' THEN
            RETURN jsonb_build_object('status', 'ambiguous', 'candidates', r->'candidates',
                                      'message', 'Hay varios animales con ese identificador; elige uno por su arete SINIIGA.');
        END IF;
        v_hid := (r->>'livestock_id')::uuid;
    END IF;

    SELECT count(*) INTO v_total
      FROM public.repro_empadre_entries e
     WHERE e.id_company = v_tenant AND (v_hid IS NULL OR e.heifer_id = v_hid)
       AND (v_voided OR NOT EXISTS (SELECT 1 FROM public.repro_empadre_voids v WHERE v.entry_id = e.id AND v.id_company = v_tenant));

    SELECT coalesce(jsonb_agg(q.j ORDER BY q.entry_date DESC, q.created_at DESC, q.id), '[]'::jsonb) INTO v_rows
      FROM (
        SELECT e.id, e.entry_date, e.created_at,
               jsonb_build_object(
                 'entry_id', e.id, 'entry_date', e.entry_date, 'method', e.method,
                 'heifer', jsonb_build_object('livestock_id', h.id, 'rfid_siniiga', h.rfid_siniiga, 'numero_fuego', h.numero_fuego,
                                              'electronic_rfid', h.electronic_rfid, 'category_at_entry', e.category_at_entry),
                 'bull', CASE WHEN b.id IS NULL THEN NULL ELSE jsonb_build_object(
                                 'livestock_id', b.id, 'rfid_siniiga', b.rfid_siniiga, 'numero_fuego', b.numero_fuego) END,
                 'eligibility_trigger', e.eligibility_trigger, 'warning_code', e.warning_code, 'warning', e.warning,
                 'notes', e.notes, 'registered_by_email', e.registered_by_email,
                 'voided', v.id IS NOT NULL, 'void_reason', v.reason, 'voided_at', v.voided_at) AS j
          FROM public.repro_empadre_entries e
          LEFT JOIN public.cattle_livestock h ON h.id = e.heifer_id AND h.tenant_id = v_tenant
          LEFT JOIN public.cattle_livestock b ON b.id = e.bull_id   AND b.tenant_id = v_tenant
          LEFT JOIN public.repro_empadre_voids v ON v.entry_id = e.id AND v.id_company = v_tenant
         WHERE e.id_company = v_tenant AND (v_hid IS NULL OR e.heifer_id = v_hid) AND (v_voided OR v.id IS NULL)
         ORDER BY e.entry_date DESC, e.created_at DESC, e.id
         LIMIT v_limit OFFSET v_offset
      ) q;

    RETURN jsonb_build_object('status', 'ok', 'total', v_total, 'limit', v_limit, 'offset', v_offset,
                              'has_more', (v_offset + v_limit) < v_total, 'entries', v_rows);
END;
$$;

-- 4.8 list_open_cows: VACÍA females (VACA, NOVILLONA) with no non-voided breeding event in the last N days
-- (default 90). last_palpation_* read BOTH palpation key sets (result / resultado) and both spellings (VACIA / VACÍA).
-- Joined through cattle_livestock for the company (cattle_health_logs has no tenant column).
CREATE OR REPLACE FUNCTION public.sp_repro_list_open_cows(
    p_tenant_id text, p_user_email text, p_days text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_days   integer := coalesce(public.fn_repro_int(p_days), 90);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 50), 100);
    v_offset integer := coalesce(public.fn_repro_int(p_offset), 0);
    v_today  date := public.fn_repro_today();
    cfg      record;
    v_total  bigint;
    v_rows   jsonb;
BEGIN
    IF public.fn_repro_txt(p_days) IS NOT NULL AND (public.fn_repro_int(p_days) IS NULL OR v_days NOT BETWEEN 1 AND 730) THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Los dias deben ser un numero entre 1 y 730.');
    END IF;
    IF v_limit < 1 THEN v_limit := 50; END IF;
    SELECT * INTO cfg FROM public.fn_repro_empadre_cfg(v_tenant);

    WITH cows AS (
        SELECT l.id, l.rfid_siniiga, l.electronic_rfid, l.numero_fuego, l.category
          FROM public.cattle_livestock l
         WHERE l.tenant_id = v_tenant AND l.species = 'BOVINO'
           AND l.category IN ('VACA', 'NOVILLONA') AND l.current_status = 'VACÍA'
    ), svc AS (
        SELECT be.livestock_id, max(be.breeding_date) AS last_service
          FROM public.cattle_breeding_events be
         WHERE be.tenant_id = v_tenant
           AND NOT EXISTS (SELECT 1 FROM public.event_voids v
                            WHERE v.event_table = 'cattle_breeding_events' AND v.event_id = be.id AND v.tenant_id = v_tenant)
         GROUP BY be.livestock_id
    ), pal AS (
        SELECT DISTINCT ON (h.livestock_id) h.livestock_id, h.event_date::date AS pdate,
               coalesce(h.medicines_json->>'result', h.medicines_json->>'resultado') AS praw
          FROM public.cattle_health_logs h
          JOIN cows c ON c.id = h.livestock_id
         WHERE upper(translate(h.event_type, 'Óó', 'Oo')) = 'PALPACION'
         ORDER BY h.livestock_id, h.event_date DESC, h.created_at DESC
    ), o AS (
        SELECT c.id, c.rfid_siniiga, c.electronic_rfid, c.numero_fuego, c.category, s.last_service,
               p.pdate AS last_palpation_date,
               CASE upper(translate(btrim(p.praw), 'ÍíÑñ', 'IiNn'))
                    WHEN 'VACIA' THEN 'VACÍA' WHEN 'PRENADA' THEN 'PREÑADA' ELSE p.praw END AS last_palpation_result,
               EXISTS (SELECT 1 FROM public.repro_empadre_entries e
                        WHERE e.id_company = v_tenant AND e.heifer_id = c.id
                          AND e.entry_date >= v_today - cfg.empadre_window_days
                          AND NOT EXISTS (SELECT 1 FROM public.repro_empadre_voids v WHERE v.entry_id = e.id AND v.id_company = v_tenant)
               ) AS in_active_empadre
          FROM cows c
          LEFT JOIN svc s ON s.livestock_id = c.id
          LEFT JOIN pal p ON p.livestock_id = c.id
         WHERE s.last_service IS NULL OR s.last_service < v_today - v_days
    )
    SELECT (SELECT count(*) FROM o),
           coalesce((SELECT jsonb_agg(q.j ORDER BY q.k1 NULLS FIRST, q.k2)
                       FROM (SELECT jsonb_build_object(
                                      'livestock_id', t.id, 'rfid_siniiga', t.rfid_siniiga, 'numero_fuego', t.numero_fuego,
                                      'electronic_rfid', t.electronic_rfid, 'category', t.category,
                                      'last_service_date', t.last_service,
                                      'days_since_last_service', CASE WHEN t.last_service IS NULL THEN NULL ELSE v_today - t.last_service END,
                                      'last_palpation_date', t.last_palpation_date, 'last_palpation_result', t.last_palpation_result,
                                      'in_active_empadre', t.in_active_empadre) AS j,
                                    t.last_service AS k1, t.id::text AS k2
                               FROM o t
                              ORDER BY t.last_service NULLS FIRST, t.id::text
                              LIMIT v_limit OFFSET v_offset) q), '[]'::jsonb)
      INTO v_total, v_rows;

    RETURN jsonb_build_object('status', 'ok', 'days', v_days, 'total', v_total, 'limit', v_limit, 'offset', v_offset,
                              'has_more', (v_offset + v_limit) < v_total, 'cows', v_rows,
                              'note', 'Vacas con estatus VACÍA sin servicio en los ultimos ' || v_days
                                      || ' dias (nunca servidas primero). in_active_empadre indica si ya tienen una entrada de empadre vigente.');
END;
$$;

-- 5) Sanity ---------------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY['fn_repro_today', 'fn_repro_member_role', 'fn_repro_empadre_cfg', 'fn_repro_resolve_animal',
                        'fn_repro_empadre_eval', 'fn_repro_empadre_check_item', 'fn_repro_empadre_date',
                        'sp_repro_empadre_get_config', 'sp_repro_empadre_set_config',
                        'sp_repro_list_heifers_eligible_for_empadre', 'sp_repro_log_empadre_entry',
                        'sp_repro_log_empadre_entry_batch', 'sp_void_empadre_entry', 'sp_repro_list_empadre_entries',
                        'sp_repro_list_open_cows']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '085: missing functions: %', v_missing;
    END IF;
    IF to_regclass('public.repro_empadre_config') IS NULL OR to_regclass('public.repro_empadre_entries') IS NULL
       OR to_regclass('public.repro_empadre_voids') IS NULL THEN
        RAISE EXCEPTION '085: tables missing';
    END IF;
    RAISE NOTICE '085: OK';
END $$;

\if :{?embedded}
\echo '*** 085 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 085 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
