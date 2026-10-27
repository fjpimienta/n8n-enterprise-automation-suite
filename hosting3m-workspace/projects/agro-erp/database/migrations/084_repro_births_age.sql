-- 084_repro_births_age.sql
-- Reproduction tracking, phase 1: age derived from the burned number (numero_fuego) and read-only birth / identifier
-- quality tools for the cattle AI agent (Web Chat and WhatsApp, via v6/MCP Server Cattle).
--
-- This file adds ONLY functions, one type and one view. No table, no column, no trigger, no crud_models row, no change to
-- any existing procedure (sp_register_birth_event, sp_log_breeding_event, sp_log_palpation_event and sp_void_event are
-- untouched; they are phase 4). Nothing here writes data: every tool is STABLE.
--
-- Rules come from the client, not from data (tenant 5 has no YY-CC-M number and its birth_date is mostly a placeholder):
--   CURRENT  YY-CC-M   from 2025 on     (YY >= 25, month 1..12)      -> year 2000+YY, month, precision MONTH
--   LEGACY   YYCC      before 2025      (4 digits, YY 05..24)        -> year 2000+YY, NO month, precision YEAR
--   Anything else is NOT parsed: spaces / suffixes ('08-4 P', '2011-1 P'), dashed with YY < 25, month outside 1..12,
--   'S/N', 1-2 digit values, '20199-84', 3-digit bulls (NO_YEAR_ENCODING) and the two shapes the client has not confirmed
--   (UNCONFIRMED_SHAPE: 5 digits such as 19102; 4 digits with YY >= 25 such as 2534). To support a confirmed shape, add
--   one branch in fn_fire_number_shape and one in fn_estimate_birth_from_fire_number: nothing else changes.
--   A real birth_date of 2020-01-01 is the import placeholder and counts as "no date" (fn_is_placeholder_birth_date).
--   Every derived age carries its source (REGISTRADA / ESTIMADA_NUMERO_FUEGO / DESCONOCIDA) and precision
--   (MONTH / YEAR_ONLY). Ages are computed at month precision only; the day of a birth_date is never used.
--   The estimate is NEVER written into cattle_livestock.birth_date.
--
-- Fail-closed on every tool (fn_repro_ctx): the tenant must be a plain integer, the user an ACTIVE member of that
-- company (user_companies + users + active company) and the company must not be a palm company (fn_reject_palm_company,
-- P0094). Anything else RAISES (P0001): a user of company A never gets rows, or even a status, for company B. Every
-- query filters by tenant_id / id_company explicitly. numero_fuego is NOT unique: a lookup that matches several animals
-- answers status 'ambiguous' with the candidates and never picks one.
--
-- Objects (all in public):
--   helpers   fn_repro_txt, fn_repro_int, fn_repro_date, fn_repro_ctx
--   parser    type fire_number_estimate, fn_is_placeholder_birth_date, fn_fire_number_shape (IMMUTABLE),
--             fn_estimate_birth_from_fire_number (STABLE: it rejects future years, so it depends on today's date;
--             the pure structural part is the IMMUTABLE shape function)
--   view      vw_animal_effective_birth     (internal: read it only through the tools; NOT in crud_models)
--   tools     sp_repro_list_births                       -> list_births
--             sp_repro_dam_birth_history                 -> get_dam_birth_history
--             sp_repro_births_summary                    -> get_births_summary
--             sp_repro_list_unregistered_historical_births -> list_unregistered_historical_births   (REPORT ONLY)
--             sp_repro_identifier_quality_report         -> identifier_quality_report
--
-- Rollback: 084_rollback.sql (no DROP / DELETE: the 5 tools keep their signature and answer 'disabled').
-- State:    084_state_check.sql -v expect=before|applied|rolled_back (read-only).
-- Tests:    084_tests.sql (LOCAL / throwaway database, everything rolled back).
--
-- Usage (dry run is the default when apply is not given):
--   psql -v ON_ERROR_STOP=1 -f 084_repro_births_age.sql                 -> dry run (rolled back)
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 084_repro_births_age.sql   -> commit
-- 084_tests.sql includes this file with `embedded` set (the tests own the transaction and roll it back).

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
    IF to_regprocedure('public.fn_reject_palm_company(integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: fn_reject_palm_company not found (migration 082 is not applied here).';
    END IF;
    IF to_regclass('public.birth_events') IS NULL OR to_regclass('public.cattle_livestock') IS NULL
       OR to_regclass('public.cattle_weight_logs') IS NULL OR to_regclass('public.user_companies') IS NULL THEN
        RAISE EXCEPTION 'ABORT: birth_events / cattle_livestock / cattle_weight_logs / user_companies are missing.';
    END IF;
END $$;

-- 1) Helpers --------------------------------------------------------------------------------------------------

-- Trimmed text; NULL for '', 'null' and 'undefined' (what a tool sends for an omitted optional parameter).
CREATE OR REPLACE FUNCTION public.fn_repro_txt(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN lower(btrim(coalesce(p, ''))) IN ('', 'null', 'undefined') THEN NULL ELSE btrim(p) END
$$;

-- Non-negative integer from text; NULL when empty or not a plain integer (at most 9 digits).
CREATE OR REPLACE FUNCTION public.fn_repro_int(p text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN public.fn_repro_txt(p) ~ '^[0-9]{1,9}$' THEN public.fn_repro_txt(p)::integer END
$$;

-- Date from 'YYYY-MM-DD' text; NULL when empty or not a valid date (never raises).
CREATE OR REPLACE FUNCTION public.fn_repro_date(p text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF public.fn_repro_txt(p) IS NULL OR public.fn_repro_txt(p) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        RETURN NULL;
    END IF;
    RETURN public.fn_repro_txt(p)::date;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- Fail-closed context of every tool. Returns the tenant as integer, or RAISES:
--   P0001  tenant is not a plain integer, or the user is not an ACTIVE member of that ACTIVE company
--   P0094  the company is a palm company (fn_reject_palm_company)
-- Membership is checked BEFORE the domain, so a stranger learns nothing about the company.
CREATE OR REPLACE FUNCTION public.fn_repro_ctx(p_tenant_id text, p_user_email text)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_int(p_tenant_id);
    v_email  text    := lower(public.fn_repro_txt(p_user_email));
BEGIN
    IF v_tenant IS NULL OR v_email IS NULL THEN
        RAISE EXCEPTION 'Contexto invalido: se requiere empresa (numero) y correo del usuario.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (
        SELECT 1
          FROM public.user_companies uc
          JOIN public.users u      ON lower(u.email) = lower(uc.email)
          JOIN public.companys c   ON c.id_company = uc.id_company
         WHERE uc.id_company = v_tenant
           AND uc.is_active IS TRUE
           AND c.is_active IS TRUE
           AND lower(u.email) = v_email
    ) THEN
        RAISE EXCEPTION 'El usuario no tiene acceso activo a la empresa %.', v_tenant USING ERRCODE = 'P0001';
    END IF;
    PERFORM public.fn_reject_palm_company(v_tenant);
    RETURN v_tenant;
END;
$$;

-- 2) numero_fuego parser --------------------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'fire_number_estimate' AND typnamespace = 'public'::regnamespace) THEN
        CREATE TYPE public.fire_number_estimate AS (
            birth_year     integer,
            birth_month    integer,   -- NULL for the legacy format: a legacy number has NO month
            month_reliable boolean,
            birth_precision text,     -- 'MONTH' (current format) or 'YEAR' (legacy)
            shape          text
        );
    END IF;
END $$;

-- The import placeholder that means "no date". One place to change if another placeholder shows up.
CREATE OR REPLACE FUNCTION public.fn_is_placeholder_birth_date(p date)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p = DATE '2020-01-01'
$$;

-- Structural classification of a numero_fuego. Pure: no date, no table. The value is NOT trimmed or normalised
-- (' 26-45-4', '26-45-4 ' and '08-4 P' are OTHER). Labels:
--   EMPTY                 NULL or blank
--   CURRENT               YY-CC-M, YY >= 25, month 1..12
--   LEGACY                YYCC, YY 05..24 (no month)
--   INVALID_MONTH         YY-CC-M with YY >= 25 but month 0 or > 12
--   DASHED_REJECTED       YY-CC-M with YY < 25 (not the current format)
--   UNCONFIRMED_SHAPE     5 digits (19102) or 4 digits with YY >= 25 (2534): hypotheses the client has not confirmed
--   NO_YEAR_ENCODING      3 digits (375): bulls, no year in the number
--   FOUR_DIGITS_REJECTED  4 digits with YY < 05
--   OTHER                 everything else
CREATE OR REPLACE FUNCTION public.fn_fire_number_shape(p text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    m  text[];
    yy integer;
    mm integer;
BEGIN
    IF p IS NULL OR btrim(p) = '' THEN
        RETURN 'EMPTY';
    END IF;

    m := regexp_match(p, '^([0-9]{2})-([0-9]+)-([0-9]{1,2})$');
    IF m IS NOT NULL THEN
        yy := m[1]::integer;
        mm := m[3]::integer;
        IF yy < 25 THEN RETURN 'DASHED_REJECTED'; END IF;
        IF mm < 1 OR mm > 12 THEN RETURN 'INVALID_MONTH'; END IF;
        RETURN 'CURRENT';
    END IF;

    IF p ~ '^[0-9]{5}$' THEN
        RETURN 'UNCONFIRMED_SHAPE';
    END IF;
    IF p ~ '^[0-9]{4}$' THEN
        yy := substr(p, 1, 2)::integer;
        IF yy >= 25 THEN RETURN 'UNCONFIRMED_SHAPE'; END IF;
        IF yy >= 5  THEN RETURN 'LEGACY'; END IF;
        RETURN 'FOUR_DIGITS_REJECTED';
    END IF;
    IF p ~ '^[0-9]{3}$' THEN
        RETURN 'NO_YEAR_ENCODING';
    END IF;
    RETURN 'OTHER';
END;
$$;

-- Birth year / month estimated from the burned number. NULL (never an exception) when the value is not a validated
-- shape, the month is not 1..12, or the year is implausible (before 2005 or later than today). STABLE because of the
-- "not in the future" test.
CREATE OR REPLACE FUNCTION public.fn_estimate_birth_from_fire_number(p_numero_fuego text)
RETURNS public.fire_number_estimate
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_shape text := public.fn_fire_number_shape(p_numero_fuego);
    m       text[];
    v_year  integer;
    v_month integer;
BEGIN
    IF v_shape = 'CURRENT' THEN
        m := regexp_match(p_numero_fuego, '^([0-9]{2})-([0-9]+)-([0-9]{1,2})$');
        v_year  := 2000 + m[1]::integer;
        v_month := m[3]::integer;
        IF v_year < 2005
           OR (v_year * 12 + v_month) > (extract(year FROM current_date)::integer * 12 + extract(month FROM current_date)::integer) THEN
            RETURN NULL;
        END IF;
        RETURN ROW(v_year, v_month, true, 'MONTH', v_shape)::public.fire_number_estimate;
    ELSIF v_shape = 'LEGACY' THEN
        v_year := 2000 + substr(p_numero_fuego, 1, 2)::integer;
        IF v_year < 2005 OR v_year > extract(year FROM current_date)::integer THEN
            RETURN NULL;
        END IF;
        RETURN ROW(v_year, NULL::integer, false, 'YEAR', v_shape)::public.fire_number_estimate;
    END IF;
    RETURN NULL;
END;
$$;

-- 3) Effective birth ------------------------------------------------------------------------------------------
-- One row per animal. A real birth_date wins (except the 2020-01-01 placeholder, treated as no date); otherwise the
-- estimate from numero_fuego; otherwise unknown. Month precision only. INTERNAL: it has no access control of its own;
-- every tenant-facing reader (the sp_repro_* tools) filters by tenant_id and membership. Not registered in crud_models.
--   age_months      calendar-month difference when the precision is MONTH, else NULL
--   age_months_min  smallest possible age: for YEAR_ONLY the animal is assumed born in December of that year
--   date_quality    NULL | PLACEHOLDER_DATE_IGNORED | FUTURE_REGISTERED_DATE
CREATE OR REPLACE VIEW public.vw_animal_effective_birth AS
WITH base AS (
    SELECT l.id AS livestock_id,
           l.tenant_id,
           l.numero_fuego,
           l.category,
           l.current_status,
           l.birth_date,
           (l.birth_date IS NOT NULL AND NOT public.fn_is_placeholder_birth_date(l.birth_date)) AS has_real_date,
           est.birth_year  AS est_year,
           est.birth_month AS est_month,
           est.month_reliable AS est_month_reliable,
           est.birth_precision AS est_precision
      FROM public.cattle_livestock l
      LEFT JOIN LATERAL public.fn_estimate_birth_from_fire_number(l.numero_fuego) est ON true
), pick AS (
    SELECT b.*,
           CASE WHEN b.has_real_date THEN 'REGISTRADA'
                WHEN b.est_year IS NOT NULL THEN 'ESTIMADA_NUMERO_FUEGO'
                ELSE 'DESCONOCIDA' END AS age_source,
           CASE WHEN b.has_real_date THEN extract(year FROM b.birth_date)::integer ELSE b.est_year END AS effective_birth_year,
           CASE WHEN b.has_real_date THEN extract(month FROM b.birth_date)::integer ELSE b.est_month END AS effective_birth_month,
           CASE WHEN b.has_real_date THEN 'MONTH'
                WHEN b.est_year IS NULL THEN NULL
                WHEN b.est_precision = 'MONTH' THEN 'MONTH'
                ELSE 'YEAR_ONLY' END AS age_precision,
           CASE WHEN b.has_real_date THEN true WHEN b.est_year IS NOT NULL THEN b.est_month_reliable ELSE NULL END AS month_reliable
      FROM base b
), cur AS (
    SELECT (extract(year FROM current_date)::integer * 12 + extract(month FROM current_date)::integer) AS cur_months
)
SELECT p.livestock_id,
       p.tenant_id,
       p.numero_fuego,
       p.category,
       p.current_status,
       CASE WHEN p.has_real_date THEN p.birth_date END AS registered_birth_date,
       p.effective_birth_year,
       p.effective_birth_month,
       p.age_source,
       p.age_precision,
       p.month_reliable,
       CASE WHEN p.age_precision = 'MONTH'
            THEN c.cur_months - (p.effective_birth_year * 12 + p.effective_birth_month) END AS age_months,
       CASE WHEN p.age_precision = 'MONTH' THEN c.cur_months - (p.effective_birth_year * 12 + p.effective_birth_month)
            WHEN p.age_precision = 'YEAR_ONLY' THEN c.cur_months - (p.effective_birth_year * 12 + 12) END AS age_months_min,
       CASE WHEN p.birth_date IS NOT NULL AND NOT p.has_real_date THEN 'PLACEHOLDER_DATE_IGNORED'
            WHEN p.has_real_date AND p.birth_date > current_date THEN 'FUTURE_REGISTERED_DATE' END AS date_quality
  FROM pick p CROSS JOIN cur c;

COMMENT ON VIEW public.vw_animal_effective_birth IS
    'Effective birth per animal (084). Real birth_date (not the 2020-01-01 placeholder) > estimate from numero_fuego > unknown. Month precision. Internal: read through sp_repro_* tools, which filter by tenant and membership. Never written back to cattle_livestock.';

-- 4) Tools ----------------------------------------------------------------------------------------------------
-- Every parameter is text (n8n convention, Rule 15 of the agro-erp CLAUDE.md). Expected conditions are answers:
--   status ok | ambiguous | not_found | invalid.  Membership / palm failures raise (see fn_repro_ctx).

-- 4.1 list_births: births in a date range (default: last 30 days), paginated.
CREATE OR REPLACE FUNCTION public.sp_repro_list_births(
    p_tenant_id  text,
    p_user_email text,
    p_date_from  text DEFAULT NULL,
    p_date_to    text DEFAULT NULL,
    p_limit      text DEFAULT NULL,
    p_offset     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_from   date := coalesce(public.fn_repro_date(p_date_from), current_date - 30);
    v_to     date := coalesce(public.fn_repro_date(p_date_to), current_date);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 50), 100);
    v_offset integer := coalesce(public.fn_repro_int(p_offset), 0);
    v_total  bigint;
    v_rows   jsonb;
BEGIN
    IF (public.fn_repro_txt(p_date_from) IS NOT NULL AND public.fn_repro_date(p_date_from) IS NULL)
       OR (public.fn_repro_txt(p_date_to) IS NOT NULL AND public.fn_repro_date(p_date_to) IS NULL) THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Las fechas deben tener el formato AAAA-MM-DD.');
    END IF;
    IF v_from > v_to THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'La fecha inicial es posterior a la final.');
    END IF;
    IF v_limit < 1 THEN v_limit := 50; END IF;

    SELECT count(*) INTO v_total
      FROM public.birth_events be
     WHERE be.id_company = v_tenant AND be.birth_date BETWEEN v_from AND v_to;

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.birth_date DESC, x.created_at DESC, x.id), '[]'::jsonb)
      INTO v_rows
      FROM (
        SELECT be.id, be.birth_date, be.created_at,
               jsonb_build_object(
                 'birth_event_id', be.id,
                 'birth_date', be.birth_date,
                 'calf_sex', be.calf_sex,
                 'source', be.source,
                 'dam', jsonb_build_object(
                          'livestock_id', dam.id,
                          'rfid_siniiga', dam.rfid_siniiga,
                          'numero_fuego', dam.numero_fuego,
                          'electronic_rfid', dam.electronic_rfid,
                          'linked', dam.id IS NOT NULL,
                          'reported_ear_tag', be.dam_ear_tag,
                          'reported_fire_number', be.dam_fire_number),
                 'calf', CASE WHEN calf.id IS NULL THEN NULL ELSE jsonb_build_object(
                          'livestock_id', calf.id,
                          'rfid_siniiga', calf.rfid_siniiga,
                          'numero_fuego', calf.numero_fuego,
                          'electronic_rfid', calf.electronic_rfid) END,
                 'birth_weight_kg', bw.weight_kg,
                 'upp', pu.ranch_name,
                 'notes', be.notes) AS j
          FROM public.birth_events be
          LEFT JOIN public.cattle_livestock dam  ON dam.id = be.dam_id   AND dam.tenant_id = v_tenant
          LEFT JOIN public.cattle_livestock calf ON calf.id = be.calf_id AND calf.tenant_id = v_tenant
          LEFT JOIN public.production_units pu   ON pu.id = be.production_unit_id AND pu.id_company = v_tenant
          LEFT JOIN LATERAL (
                SELECT w.weight_kg FROM public.cattle_weight_logs w
                 WHERE w.livestock_id = calf.id AND w.source_device = 'BIRTH_EVENT'
                 ORDER BY w.log_date LIMIT 1) bw ON true
         WHERE be.id_company = v_tenant AND be.birth_date BETWEEN v_from AND v_to
         ORDER BY be.birth_date DESC, be.created_at DESC, be.id
         LIMIT v_limit OFFSET v_offset
      ) x;

    RETURN jsonb_build_object(
        'status', 'ok',
        'date_from', v_from, 'date_to', v_to,
        'total', v_total, 'limit', v_limit, 'offset', v_offset,
        'has_more', (v_offset + v_limit) < v_total,
        'births', v_rows);
END;
$$;

-- 4.2 get_dam_birth_history: all births of one dam, resolved by arete / fuego / RFID (never guessed).
CREATE OR REPLACE FUNCTION public.sp_repro_dam_birth_history(
    p_tenant_id  text,
    p_user_email text,
    p_identifier text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_ident  text := public.fn_repro_txt(p_identifier);
    v_count  integer;
    v_dam    uuid;
    v_cands  jsonb;
BEGIN
    IF v_ident IS NULL THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Falta el identificador de la madre (arete, numero de fuego o RFID).');
    END IF;

    SELECT count(*) INTO v_count
      FROM public.cattle_livestock l
     WHERE l.tenant_id = v_tenant
       AND (l.electronic_rfid = v_ident OR l.rfid_siniiga = v_ident OR l.numero_fuego = v_ident);

    IF v_count = 0 THEN
        RETURN jsonb_build_object('status', 'not_found', 'message', 'Ningun animal coincide con ese identificador en esta empresa.');
    END IF;

    IF v_count > 1 THEN
        SELECT jsonb_agg(jsonb_build_object(
                   'livestock_id', l.id, 'rfid_siniiga', l.rfid_siniiga, 'numero_fuego', l.numero_fuego,
                   'electronic_rfid', l.electronic_rfid, 'category', l.category, 'current_status', l.current_status,
                   'lote', lot.lot_name, 'upp', pu.ranch_name) ORDER BY l.category, l.id)
          INTO v_cands
          FROM public.cattle_livestock l
          LEFT JOIN public.production_unit_lots lot ON lot.id = l.lot_id AND lot.id_company = v_tenant
          LEFT JOIN public.production_units pu      ON pu.id = l.production_unit_id AND pu.id_company = v_tenant
         WHERE l.tenant_id = v_tenant
           AND (l.electronic_rfid = v_ident OR l.rfid_siniiga = v_ident OR l.numero_fuego = v_ident);
        RETURN jsonb_build_object('status', 'ambiguous',
            'message', 'Mas de un animal coincide con ese identificador; pide al usuario que indique cual (categoria, lote o arete).',
            'candidates', v_cands);
    END IF;

    SELECT l.id INTO v_dam
      FROM public.cattle_livestock l
     WHERE l.tenant_id = v_tenant
       AND (l.electronic_rfid = v_ident OR l.rfid_siniiga = v_ident OR l.numero_fuego = v_ident);

    RETURN (
        SELECT jsonb_build_object(
            'status', 'ok',
            'dam', jsonb_build_object(
                     'livestock_id', d.id, 'rfid_siniiga', d.rfid_siniiga, 'numero_fuego', d.numero_fuego,
                     'electronic_rfid', d.electronic_rfid, 'category', d.category, 'current_status', d.current_status,
                     'age_source', eb.age_source, 'age_precision', eb.age_precision),
            'total_births', (SELECT count(*) FROM public.birth_events be WHERE be.id_company = v_tenant AND be.dam_id = d.id),
            'births', coalesce((
                SELECT jsonb_agg(jsonb_build_object(
                         'birth_event_id', be.id, 'birth_date', be.birth_date, 'calf_sex', be.calf_sex, 'source', be.source,
                         'calf', CASE WHEN calf.id IS NULL THEN NULL ELSE jsonb_build_object(
                                   'livestock_id', calf.id, 'rfid_siniiga', calf.rfid_siniiga,
                                   'numero_fuego', calf.numero_fuego, 'electronic_rfid', calf.electronic_rfid,
                                   'current_status', calf.current_status) END,
                         'birth_weight_kg', bw.weight_kg,
                         'notes', be.notes) ORDER BY be.birth_date DESC, be.created_at DESC, be.id)
                  FROM public.birth_events be
                  LEFT JOIN public.cattle_livestock calf ON calf.id = be.calf_id AND calf.tenant_id = v_tenant
                  LEFT JOIN LATERAL (
                        SELECT w.weight_kg FROM public.cattle_weight_logs w
                         WHERE w.livestock_id = calf.id AND w.source_device = 'BIRTH_EVENT'
                         ORDER BY w.log_date LIMIT 1) bw ON true
                 WHERE be.id_company = v_tenant AND be.dam_id = d.id), '[]'::jsonb))
          FROM public.cattle_livestock d
          LEFT JOIN public.vw_animal_effective_birth eb ON eb.livestock_id = d.id AND eb.tenant_id = v_tenant
         WHERE d.id = v_dam AND d.tenant_id = v_tenant);
END;
$$;

-- 4.3 get_births_summary: counts per day or per month (default: months of the last year).
CREATE OR REPLACE FUNCTION public.sp_repro_births_summary(
    p_tenant_id  text,
    p_user_email text,
    p_group_by   text DEFAULT NULL,
    p_date_from  text DEFAULT NULL,
    p_date_to    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_group  text := lower(coalesce(public.fn_repro_txt(p_group_by), 'month'));
    v_from   date;
    v_to     date := coalesce(public.fn_repro_date(p_date_to), current_date);
    v_rows   jsonb;
    v_total  bigint;
BEGIN
    IF v_group NOT IN ('day', 'month') THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'group_by debe ser day o month.');
    END IF;
    IF (public.fn_repro_txt(p_date_from) IS NOT NULL AND public.fn_repro_date(p_date_from) IS NULL)
       OR (public.fn_repro_txt(p_date_to) IS NOT NULL AND public.fn_repro_date(p_date_to) IS NULL) THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Las fechas deben tener el formato AAAA-MM-DD.');
    END IF;
    v_from := coalesce(public.fn_repro_date(p_date_from),
                       CASE WHEN v_group = 'day' THEN current_date - 30
                            ELSE (date_trunc('month', current_date) - interval '11 months')::date END);
    IF v_from > v_to THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'La fecha inicial es posterior a la final.');
    END IF;
    IF v_group = 'day' AND (v_to - v_from) > 366 THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Para agrupar por dia el rango maximo es de un ano.');
    END IF;

    SELECT coalesce(jsonb_agg(jsonb_build_object('period', t.period, 'births', t.n, 'male', t.male, 'female', t.female)
                              ORDER BY t.period), '[]'::jsonb),
           coalesce(sum(t.n), 0)
      INTO v_rows, v_total
      FROM (
        SELECT CASE WHEN v_group = 'day' THEN to_char(be.birth_date, 'YYYY-MM-DD') ELSE to_char(be.birth_date, 'YYYY-MM') END AS period,
               count(*) AS n,
               count(*) FILTER (WHERE be.calf_sex = 'MACHO')  AS male,
               count(*) FILTER (WHERE be.calf_sex = 'HEMBRA') AS female
          FROM public.birth_events be
         WHERE be.id_company = v_tenant AND be.birth_date BETWEEN v_from AND v_to
         GROUP BY 1
      ) t;

    RETURN jsonb_build_object('status', 'ok', 'group_by', v_group, 'date_from', v_from, 'date_to', v_to,
                              'total_births', v_total, 'periods', v_rows);
END;
$$;

-- 4.4 list_unregistered_historical_births: REPORT ONLY. Calves with mother_id but no birth_events row. Inserts nothing,
-- anywhere, ever: there is no backfill in this migration or in any tool.
CREATE OR REPLACE FUNCTION public.sp_repro_list_unregistered_historical_births(
    p_tenant_id  text,
    p_user_email text,
    p_limit      text DEFAULT NULL,
    p_offset     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 50), 100);
    v_offset integer := coalesce(public.fn_repro_int(p_offset), 0);
    v_total  bigint;
    v_rows   jsonb;
BEGIN
    IF v_limit < 1 THEN v_limit := 50; END IF;

    SELECT count(*) INTO v_total
      FROM public.cattle_livestock c
     WHERE c.tenant_id = v_tenant AND c.mother_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.birth_events be WHERE be.id_company = v_tenant AND be.calf_id = c.id);

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.sort_year DESC NULLS LAST, x.sort_month DESC NULLS LAST, x.id), '[]'::jsonb)
      INTO v_rows
      FROM (
        SELECT c.id, eb.effective_birth_year AS sort_year, eb.effective_birth_month AS sort_month,
               jsonb_build_object(
                 'calf', jsonb_build_object('livestock_id', c.id, 'rfid_siniiga', c.rfid_siniiga, 'numero_fuego', c.numero_fuego,
                                            'electronic_rfid', c.electronic_rfid, 'category', c.category,
                                            'current_status', c.current_status),
                 'dam', jsonb_build_object('found', dam.id IS NOT NULL, 'livestock_id', dam.id,
                                           'rfid_siniiga', dam.rfid_siniiga, 'numero_fuego', dam.numero_fuego,
                                           'electronic_rfid', dam.electronic_rfid),
                 'estimated_birth', jsonb_build_object(
                                      'year', eb.effective_birth_year, 'month', eb.effective_birth_month,
                                      'registered_birth_date', eb.registered_birth_date,
                                      'age_source', eb.age_source, 'age_precision', eb.age_precision,
                                      'date_quality', eb.date_quality)) AS j
          FROM public.cattle_livestock c
          LEFT JOIN public.cattle_livestock dam ON dam.id = c.mother_id AND dam.tenant_id = v_tenant
          LEFT JOIN public.vw_animal_effective_birth eb ON eb.livestock_id = c.id AND eb.tenant_id = v_tenant
         WHERE c.tenant_id = v_tenant AND c.mother_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM public.birth_events be WHERE be.id_company = v_tenant AND be.calf_id = c.id)
         ORDER BY eb.effective_birth_year DESC NULLS LAST, eb.effective_birth_month DESC NULLS LAST, c.id
         LIMIT v_limit OFFSET v_offset
      ) x;

    RETURN jsonb_build_object('status', 'ok', 'report_only', true, 'total', v_total, 'limit', v_limit, 'offset', v_offset,
                              'has_more', (v_offset + v_limit) < v_total, 'calves', v_rows);
END;
$$;

-- 4.5 identifier_quality_report: read-only. Scope: animals still in the herd (not sold / dead / finished / purged).
-- Does NOT normalise or clean anything. Proposed follow-up (separate migration, not applied): a trigger that turns ''
-- into NULL on electronic_rfid and rfid_siniiga; '' collides with the UNIQUE constraints and already caused a production error.
CREATE OR REPLACE FUNCTION public.sp_repro_identifier_quality_report(
    p_tenant_id  text,
    p_user_email text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_result jsonb;
BEGIN
    WITH herd AS (
        SELECT l.id, l.numero_fuego, l.rfid_siniiga, l.electronic_rfid,
               CASE WHEN public.fn_fire_number_shape(l.numero_fuego) IN ('CURRENT', 'LEGACY')
                         AND (public.fn_estimate_birth_from_fire_number(l.numero_fuego)).birth_year IS NULL
                    THEN 'IMPLAUSIBLE_YEAR'
                    ELSE public.fn_fire_number_shape(l.numero_fuego) END AS shape
          FROM public.cattle_livestock l
         WHERE l.tenant_id = v_tenant
           AND l.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS')
    ), dup AS (
        SELECT h.numero_fuego, count(*) AS copies
          FROM herd h
         WHERE h.shape <> 'EMPTY'
         GROUP BY h.numero_fuego HAVING count(*) > 1
    ), shapes AS (
        SELECT h.shape, count(*) AS animals,
               (array_agg(DISTINCT h.numero_fuego) FILTER (WHERE h.numero_fuego IS NOT NULL))[1:5] AS examples
          FROM herd h GROUP BY h.shape
    ), bad_siniiga AS (
        SELECT h.rfid_siniiga, h.numero_fuego FROM herd h
         WHERE h.rfid_siniiga IS NULL OR h.rfid_siniiga !~ '^[0-9]{10}$'
    )
    SELECT jsonb_build_object(
        'status', 'ok',
        'scope', 'animals still in the herd (not VENDIDO, BAJA_MORTANDAD, FINALIZADO, BAJA_DEPURACION_DATOS)',
        'animals_in_scope', (SELECT count(*) FROM herd),
        'duplicate_numero_fuego', jsonb_build_object(
            'distinct_values', (SELECT count(*) FROM dup),
            'animals_involved', (SELECT coalesce(sum(copies), 0) FROM dup),
            'top', coalesce((SELECT jsonb_agg(jsonb_build_object('numero_fuego', d.numero_fuego, 'copies', d.copies)
                                              ORDER BY d.copies DESC, d.numero_fuego)
                               FROM (SELECT * FROM dup ORDER BY copies DESC, numero_fuego LIMIT 20) d), '[]'::jsonb)),
        'siniiga_not_10_digits', jsonb_build_object(
            'count', (SELECT count(*) FROM bad_siniiga),
            'examples', coalesce((SELECT jsonb_agg(jsonb_build_object('rfid_siniiga', b.rfid_siniiga, 'numero_fuego', b.numero_fuego))
                                    FROM (SELECT * FROM bad_siniiga ORDER BY rfid_siniiga NULLS FIRST LIMIT 10) b), '[]'::jsonb)),
        'numero_fuego_by_shape', coalesce((SELECT jsonb_object_agg(s.shape, jsonb_build_object('animals', s.animals, 'examples', to_jsonb(s.examples)))
                                             FROM shapes s), '{}'::jsonb),
        'numero_fuego_not_parsable', (SELECT count(*) FROM herd h WHERE h.shape NOT IN ('CURRENT', 'LEGACY')),
        'missing_electronic_rfid', (SELECT count(*) FROM herd h WHERE h.electronic_rfid IS NULL OR btrim(h.electronic_rfid) = ''),
        'electronic_rfid_empty_string', (SELECT count(*) FROM herd h WHERE h.electronic_rfid = ''),
        'rfid_siniiga_empty_string', (SELECT count(*) FROM herd h WHERE h.rfid_siniiga = ''),
        'proposed_followup', 'Separate migration (not applied): trigger normalising empty-string electronic_rfid and rfid_siniiga to NULL.'
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- 5) Sanity ---------------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY['fn_repro_txt', 'fn_repro_int', 'fn_repro_date', 'fn_repro_ctx', 'fn_is_placeholder_birth_date',
                        'fn_fire_number_shape', 'fn_estimate_birth_from_fire_number', 'sp_repro_list_births',
                        'sp_repro_dam_birth_history', 'sp_repro_births_summary',
                        'sp_repro_list_unregistered_historical_births', 'sp_repro_identifier_quality_report']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '084: missing functions: %', v_missing;
    END IF;
    IF to_regclass('public.vw_animal_effective_birth') IS NULL THEN
        RAISE EXCEPTION '084: view vw_animal_effective_birth missing';
    END IF;
    IF (public.fn_estimate_birth_from_fire_number('2097')).birth_year IS DISTINCT FROM 2020
       OR (public.fn_estimate_birth_from_fire_number('2097')).birth_month IS NOT NULL
       OR (public.fn_estimate_birth_from_fire_number('08-4 P')).birth_year IS NOT NULL THEN
        RAISE EXCEPTION '084: parser sanity failed';
    END IF;
    RAISE NOTICE '084: OK';
END $$;

\if :{?embedded}
\echo '*** 084 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 084 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
