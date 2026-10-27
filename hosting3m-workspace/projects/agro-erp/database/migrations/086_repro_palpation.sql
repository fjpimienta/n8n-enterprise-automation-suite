-- 086_repro_palpation.sql
-- Reproduction tracking, phase 3: uterine condition of palpations, palpations due, upcoming calvings.
--
-- REQUIRES 084 and 085 (fn_repro_ctx / fn_repro_txt / fn_repro_int / fn_repro_date, fn_repro_today, fn_repro_empadre_cfg,
-- repro_empadre_entries / repro_empadre_voids, fn_trg_empadre_append_only). It aborts if they are not applied.
--
-- What it adds (all in public; nothing existing is altered, replaced or dropped):
--   tables     repro_condition_codes     per-company mapping  uterine code -> CICLANDO | ESTATICA | OTRO  (config, not history);
--                                        a NULL condition = code known but still pending veterinarian confirmation
--              palpation_repro_details   APPEND-ONLY side table of cattle_health_logs (which has no tenant column):
--                                        id_company on every row, raw code, mapped condition, ovary side, mapping_status
--   triggers   append-only guard (UPDATE / DELETE / TRUNCATE raise P0095) and tenant guard (P0096) on the side table
--   helpers    fn_repro_norm_code, fn_uterine_split (pure), fn_parse_uterine_code (never raises), fn_repro_diagnosis_kind,
--              fn_repro_palpations
--   tools      sp_repro_log_palpation_batch          -> log_palpation_with_condition   (write, all-or-nothing)
--              sp_repro_list_palpation_due           -> list_palpation_due             (read)
--              sp_repro_list_upcoming_calvings       -> list_upcoming_calvings         (read)
--              sp_repro_list_unmapped_uterine_codes  -> list_unmapped_uterine_codes    (read)
--              sp_repro_condition_code_set           -> NOT an agent tool; ADMIN only, by procedure
--
-- NOT touched: sp_log_palpation_event and the existing log_palpation_event / log_palpation_event_batch tools (their
-- fingerprints must stay identical: the new wrapper CALLS sp_log_palpation_event), sp_void_event, sp_register_birth_event,
-- sp_log_breeding_event, vw_cattle_kpi, crud_models, the gateway, the 084 / 085 objects, any existing row.
-- This migration writes no rows. The tenant-5 mapping lives in 086_seed_tenant5_uterine_codes.sql, applied separately by the owner.
--
-- Rules (agreed with the owner):
--   * A condition (CICLANDO / ESTATICA / OTRO) is only allowed on a VACÍA result (CHECK on the side table). A PREÑADA
--     palpation still gets a details row, with mapping_status NOT_APPLICABLE and no condition.
--   * fn_parse_uterine_code never raises. N/A and empty -> NOT_APPLICABLE. The value is split on '/'; one leading result
--     word (VACIA / VACÍA / PREÑADA, accent- and case-insensitive) is skipped; OI / OD are extracted as ovary_side; every
--     remaining token must be KNOWN (an explicit word, or a code confirmed for the company) with one single condition,
--     otherwise the WHOLE value is UNMAPPED and the condition stays NULL (so UNE/NR stays NULL while NR is unconfirmed).
--     Explicit free words typed by staff (ciclando, estatica / estática ...) map directly: mapping_status EXPLICIT.
--   * The wrapper does NOT default an unrecognised diagnosis to VACÍA (the existing batch tool does). A diagnosis is accepted
--     only if, accent- and case-insensitively, it contains a PREÑADA word (PRENADA), a VACIA word, an explicit word
--     (ciclando / estatica), or is made only of code tokens that ALREADY EXIST in repro_condition_codes for the company (a
--     row with a NULL condition = "known but pending veterinarian confirmation" counts; the shape of a token never does).
--     With an explicit PREÑADA / VACIA word, unknown tokens are accepted and stored UNMAPPED. Anything else ('PREÑDA',
--     'ok', 'pre', random text, an unknown bare code, N/A, empty) is rejected per item (DIAGNOSIS_UNRECOGNIZED /
--     DIAGNOSIS_CONFLICT when a PREÑADA word comes with a VACIA or explicit word). Months ('02 MESES') x 30 -> gestation days. All checks run BEFORE any write, so a bad
--     item rejects the whole batch with nothing written (status 'rejected' + issues), and the details row is written by the
--     same function call (same transaction) as the palpation.
--   * Palpations are read from cattle_health_logs JOINED THROUGH cattle_livestock for the company: both JSON key sets
--     (result / resultado, gestation_days / dias_gestacion), both spellings (VACIA / VACÍA, PRENADA / PREÑADA), the date is
--     event_date.
--   * stale_import_date: when the most common palpation date of a company covers more than 50% of its palpations (at
--     least 10 palpations) it is an import date, not a real one; returned as a flag and per row.
--   * Estimated calving date = last PREÑADA palpation date + (283 - gestation days at that palpation); without usable
--     gestation days = last non-voided service date + 283 (BOVINO only). Estimates more than 60 days in the past are
--     stale_data, never upcoming or overdue.
--
-- Fail-closed (fn_repro_ctx from 084): tenant must be a plain integer, the user an ACTIVE member of that ACTIVE company,
-- the company not a palm company (P0094); anything else RAISES P0001. Any active member may log and read (same as the
-- existing palpation tools); only an ADMIN may change a mapping.
--
-- Error codes: P0095 append-only table, P0096 cross-company reference (both already used by 085).
-- Rollback: 086_rollback.sql (no DROP / DELETE: the 5 procedures answer 'disabled'; tables, rows and helpers are kept).
-- State:    086_state_check.sql -v expect=before|applied|rolled_back (read-only).
-- Tests:    086_tests.sql (LOCAL / throwaway database, everything rolled back).
--
-- Usage (dry run is the default when apply is not given):
--   psql -v ON_ERROR_STOP=1 -f 086_repro_palpation.sql                 -> dry run (rolled back)
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 086_repro_palpation.sql   -> commit
-- 086_tests.sql includes this file with `embedded` set (the tests own the transaction and roll it back).

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
    IF to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 084 is not applied here (fn_repro_ctx missing).';
    END IF;
    IF to_regclass('public.repro_empadre_entries') IS NULL OR to_regclass('public.repro_empadre_voids') IS NULL
       OR to_regprocedure('public.fn_repro_today()') IS NULL
       OR to_regprocedure('public.fn_repro_empadre_cfg(integer)') IS NULL
       OR to_regprocedure('public.fn_trg_empadre_append_only()') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 085 is not applied here (empadre tables / helpers missing).';
    END IF;
    IF to_regclass('public.companys') IS NULL OR to_regclass('public.cattle_livestock') IS NULL
       OR to_regclass('public.cattle_health_logs') IS NULL OR to_regclass('public.cattle_breeding_events') IS NULL
       OR to_regclass('public.event_voids') IS NULL THEN
        RAISE EXCEPTION 'ABORT: companys / cattle_livestock / cattle_health_logs / cattle_breeding_events / event_voids are missing.';
    END IF;
    IF to_regprocedure('public.sp_log_palpation_event(integer,character varying,character varying,character varying,integer,character varying,text,date)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_log_palpation_event (8 parameters) not found; the wrapper calls it.';
    END IF;
END $$;

-- 1) Pure helpers: normalisation and tokenising ---------------------------------------------------------------

-- Upper-case, accent-free, single-spaced, trimmed; NULL for empty. Locale independent (translate, not unaccent).
CREATE OR REPLACE FUNCTION public.fn_repro_norm_code(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT NULLIF(upper(regexp_replace(
        translate(btrim(coalesce(p, '')),
                  'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ',
                  'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn'),
        '\s+', ' ', 'g')), '')
$$;

-- Splits a stored / typed uterine value into its parts. Never raises.
--   is_empty    nothing to interpret (NULL, '', 'N/A', or only a result word)
--   raw_code    normalised value without the leading result word, e.g. 'UTCL2/OI'   (NULL when is_empty)
--   tokens      the remaining tokens WITHOUT OI / OD, e.g. {UTCL2}; {UNE,NR}; {NO APTO}
--   ovary_side  'OI' | 'OD', or NULL (none, or both present)
CREATE OR REPLACE FUNCTION public.fn_uterine_split(p_text text, OUT is_empty boolean, OUT raw_code text, OUT tokens text[], OUT ovary_side text)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    s       text;
    parts   text[];
    part    text;
    m       text[];
    raw     text[] := ARRAY[]::text[];
    sides   text[] := ARRAY[]::text[];
    one     text;
BEGIN
    is_empty := true; raw_code := NULL; tokens := ARRAY[]::text[]; ovary_side := NULL;
    s := public.fn_repro_norm_code(p_text);
    IF s IS NULL THEN RETURN; END IF;
    -- one leading result word (VACIA / PRENADA), followed by '/', blanks or the end
    s := btrim(regexp_replace(s, '^(VACIA|PRENADA)(\s*/\s*|\s+|$)', ''));
    IF s = '' OR s ~ '^N\s*/\s*A$' THEN RETURN; END IF;

    parts := regexp_split_to_array(s, '\s*/\s*');
    FOREACH part IN ARRAY parts LOOP
        part := btrim(part);
        IF part = '' THEN CONTINUE; END IF;
        -- "UTCL2 OI" / "OI UTCL2" written with a blank instead of a slash
        m := regexp_match(part, '^(.+?)\s+(OI|OD)$');
        IF m IS NULL THEN m := regexp_match(part, '^(OI|OD)\s+(.+)$'); IF m IS NOT NULL THEN m := ARRAY[m[2], m[1]]; END IF; END IF;
        IF m IS NOT NULL THEN
            raw := raw || m[1]; tokens := tokens || m[1];
            raw := raw || m[2]; sides := sides || m[2];
        ELSIF part IN ('OI', 'OD') THEN
            raw := raw || part; sides := sides || part;
        ELSE
            raw := raw || part; tokens := tokens || part;
        END IF;
    END LOOP;
    IF cardinality(raw) = 0 THEN RETURN; END IF;

    is_empty := false;
    raw_code := array_to_string(raw, '/');
    SELECT CASE WHEN count(DISTINCT x) = 1 THEN min(x) END INTO one FROM unnest(sides) AS x;
    ovary_side := one;
END;
$$;

-- 2) Tables ---------------------------------------------------------------------------------------------------
-- No ON DELETE CASCADE anywhere: nothing in this feature is ever deleted by a cascade.

CREATE TABLE IF NOT EXISTS public.repro_condition_codes (
    id_company       integer NOT NULL REFERENCES public.companys (id_company),
    code             text    NOT NULL CONSTRAINT ck_cond_code_norm CHECK (code = public.fn_repro_norm_code(code) AND length(code) <= 40),
    -- NULL = the code is known but its meaning is pending veterinarian confirmation (it maps to nothing: UNMAPPED)
    repro_condition  text    CONSTRAINT ck_cond_code_value CHECK (repro_condition IN ('CICLANDO', 'ESTATICA', 'OTRO')),
    source           text    NOT NULL,
    confirmed_by     text,
    confirmed_at     timestamptz DEFAULT now(),
    CONSTRAINT pk_repro_condition_codes PRIMARY KEY (id_company, code),
    CONSTRAINT ck_cond_code_confirmed CHECK (repro_condition IS NULL OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL))
);

-- A database that got the first version of this table (condition / confirmed_by / confirmed_at NOT NULL) is brought to
-- the same shape. Idempotent; it relaxes constraints only, nothing is dropped and no row changes.
ALTER TABLE public.repro_condition_codes ALTER COLUMN repro_condition DROP NOT NULL;
ALTER TABLE public.repro_condition_codes ALTER COLUMN confirmed_by DROP NOT NULL;
ALTER TABLE public.repro_condition_codes ALTER COLUMN confirmed_at DROP NOT NULL;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_cond_code_confirmed'
                      AND conrelid = 'public.repro_condition_codes'::regclass) THEN
        ALTER TABLE public.repro_condition_codes ADD CONSTRAINT ck_cond_code_confirmed
            CHECK (repro_condition IS NULL OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL));
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.palpation_repro_details (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    id_company           integer NOT NULL REFERENCES public.companys (id_company),
    health_log_id        uuid    NOT NULL UNIQUE REFERENCES public.cattle_health_logs (id),
    livestock_id         uuid    NOT NULL REFERENCES public.cattle_livestock (id),
    result               text    NOT NULL CONSTRAINT ck_palp_det_result CHECK (result IN ('PREÑADA', 'VACÍA')),
    raw_code             text,
    repro_condition      text    CONSTRAINT ck_palp_det_condition CHECK (repro_condition IN ('CICLANDO', 'ESTATICA', 'OTRO')),
    ovary_side           text    CONSTRAINT ck_palp_det_side CHECK (ovary_side IN ('OI', 'OD')),
    mapping_status       text    NOT NULL CONSTRAINT ck_palp_det_status CHECK (mapping_status IN ('MAPPED', 'UNMAPPED', 'EXPLICIT', 'NOT_APPLICABLE')),
    registered_by_email  text    NOT NULL,
    created_at           timestamptz NOT NULL DEFAULT now(),
    -- a condition only exists on a VACÍA result
    CONSTRAINT ck_palp_det_only_vacia CHECK (repro_condition IS NULL OR result = 'VACÍA'),
    -- the status says whether a condition is present
    CONSTRAINT ck_palp_det_status_condition CHECK (
        (mapping_status IN ('MAPPED', 'EXPLICIT') AND repro_condition IS NOT NULL)
        OR (mapping_status IN ('UNMAPPED', 'NOT_APPLICABLE') AND repro_condition IS NULL))
);
CREATE INDEX IF NOT EXISTS idx_palp_details_company ON public.palpation_repro_details (id_company, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_palp_details_animal  ON public.palpation_repro_details (id_company, livestock_id);

COMMENT ON TABLE public.repro_condition_codes IS '086: per-company mapping uterine code -> repro_condition (NULL condition = known code pending veterinarian confirmation). Written only by sp_repro_condition_code_set (ADMIN) or by the owner''s seed file. Not in crud_models.';
COMMENT ON TABLE public.palpation_repro_details IS '086: append-only side table of cattle_health_logs palpations (P0095 on UPDATE / DELETE / TRUNCATE). A condition snapshot taken when the palpation was logged: re-mapping a code later does not rewrite it. Written only by sp_repro_log_palpation_batch. Not in crud_models.';

-- 3) Triggers -------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_trg_palp_details_tenant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM public.cattle_health_logs h
          JOIN public.cattle_livestock l ON l.id = h.livestock_id
         WHERE h.id = NEW.health_log_id
           AND h.livestock_id = NEW.livestock_id
           AND l.tenant_id = NEW.id_company
           AND upper(translate(h.event_type, 'Óó', 'Oo')) = 'PALPACION') THEN
        RAISE EXCEPTION 'La palpacion no pertenece a la empresa o al animal del detalle.' USING ERRCODE = 'P0096';
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
            ('trg_palp_details_append_only',  'BEFORE UPDATE OR DELETE', 'FOR EACH ROW',       'fn_trg_empadre_append_only'),
            ('trg_palp_details_no_truncate',  'BEFORE TRUNCATE',         'FOR EACH STATEMENT', 'fn_trg_empadre_append_only'),
            ('trg_palp_details_tenant',       'BEFORE INSERT',           'FOR EACH ROW',       'fn_trg_palp_details_tenant')
        ) AS v (trg, timing, scope, fn)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger g
                        WHERE g.tgname = t.trg AND g.tgrelid = 'public.palpation_repro_details'::regclass AND NOT g.tgisinternal) THEN
            EXECUTE format('CREATE TRIGGER %I %s ON public.palpation_repro_details %s EXECUTE FUNCTION public.%I()',
                           t.trg, t.timing, t.scope, t.fn);
        END IF;
    END LOOP;
END $$;

-- 4) Parser and palpation reader (internal) -------------------------------------------------------------------

-- Interprets a uterine value for ONE company (p_tenant NULL = no mapping lookup, only the explicit words). NEVER raises.
CREATE OR REPLACE FUNCTION public.fn_parse_uterine_code(
    p_text text, p_tenant integer DEFAULT NULL,
    OUT raw_code text, OUT ovary_side text, OUT repro_condition text, OUT mapping_status text
)
LANGUAGE plpgsql
STABLE
AS $$
#variable_conflict use_column
DECLARE
    sp      record;
    tk      text;
    c       text;
    conds   text[] := ARRAY[]::text[];
    known   boolean := true;
    first_explicit boolean := false;
    n       integer := 0;
BEGIN
    raw_code := NULL; ovary_side := NULL; repro_condition := NULL; mapping_status := 'NOT_APPLICABLE';
    SELECT * INTO sp FROM public.fn_uterine_split(p_text);
    IF sp.is_empty THEN RETURN; END IF;
    raw_code := sp.raw_code;
    ovary_side := sp.ovary_side;
    IF cardinality(sp.tokens) = 0 THEN RETURN; END IF;       -- only an ovary side: nothing to map

    FOREACH tk IN ARRAY sp.tokens LOOP
        n := n + 1;
        c := CASE WHEN tk = 'CICLANDO' THEN 'CICLANDO' WHEN tk IN ('ESTATICA', 'ESTATICO') THEN 'ESTATICA' END;
        IF n = 1 AND c IS NOT NULL THEN first_explicit := true; END IF;
        IF c IS NULL AND p_tenant IS NOT NULL THEN
            SELECT cc.repro_condition INTO c
              FROM public.repro_condition_codes cc WHERE cc.id_company = p_tenant AND cc.code = tk;
        END IF;
        IF c IS NULL THEN known := false; EXIT; END IF;
        conds := conds || c;
    END LOOP;

    IF NOT known OR (SELECT count(DISTINCT x) FROM unnest(conds) AS x) <> 1 THEN
        mapping_status := 'UNMAPPED';
        RETURN;
    END IF;
    repro_condition := conds[1];
    mapping_status := CASE WHEN first_explicit THEN 'EXPLICIT' ELSE 'MAPPED' END;
    RETURN;
EXCEPTION WHEN OTHERS THEN
    raw_code := NULL; ovary_side := NULL; repro_condition := NULL; mapping_status := 'UNMAPPED';
END;
$$;

-- Classifies the free-text diagnosis of a palpation for ONE company. Never raises.
--   PRENADA | VACIA | CODE   accepted (see the header for the rules)
--   CONFLICT                 a PREÑADA word together with a VACIA or explicit word
--   UNRECOGNIZED             anything else, including empty and N/A
CREATE OR REPLACE FUNCTION public.fn_repro_diagnosis_kind(p_text text, p_tenant integer)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    n   text := public.fn_repro_norm_code(p_text);
    pre boolean;
    vac boolean;
    ex  boolean;
    sp  record;
    tk  text;
BEGIN
    IF n IS NULL THEN RETURN 'UNRECOGNIZED'; END IF;
    pre := n ~ '\mPREN?ADA\M';
    vac := n ~ '\mVACIA\M';
    ex  := n ~ '\m(CICLANDO|ESTATICA|ESTATICO)\M';
    IF pre AND (vac OR ex) THEN RETURN 'CONFLICT'; END IF;
    IF pre THEN RETURN 'PRENADA'; END IF;
    IF vac OR ex THEN RETURN 'VACIA'; END IF;

    SELECT * INTO sp FROM public.fn_uterine_split(p_text);
    IF sp.is_empty OR cardinality(sp.tokens) = 0 THEN RETURN 'UNRECOGNIZED'; END IF;
    -- no result word: every token must already exist for the company (any condition, NULL = pending). Never by shape.
    FOREACH tk IN ARRAY sp.tokens LOOP
        IF p_tenant IS NULL
           OR NOT EXISTS (SELECT 1 FROM public.repro_condition_codes cc WHERE cc.id_company = p_tenant AND cc.code = tk) THEN
            RETURN 'UNRECOGNIZED';
        END IF;
    END LOOP;
    RETURN 'CODE';
EXCEPTION WHEN OTHERS THEN
    RETURN 'UNRECOGNIZED';
END;
$$;

-- Every palpation of ONE company: cattle_health_logs JOINED THROUGH cattle_livestock (no tenant column on the logs).
-- Both JSON key sets, both spellings, date = event_date. result is NULL when the stored value is not PREÑADA / VACÍA.
-- INTERNAL: no access control; the callers are the tools below, after fn_repro_ctx.
CREATE OR REPLACE FUNCTION public.fn_repro_palpations(p_tenant integer)
RETURNS TABLE (health_log_id uuid, livestock_id uuid, pdate date, result text, gestation_days integer, created_at timestamp)
LANGUAGE sql
STABLE
AS $$
    SELECT h.id, h.livestock_id, h.event_date::date,
           CASE upper(translate(btrim(coalesce(h.medicines_json->>'result', h.medicines_json->>'resultado', '')), 'ÍíÑñ', 'IiNn'))
                WHEN 'VACIA' THEN 'VACÍA' WHEN 'PRENADA' THEN 'PREÑADA' END,
           CASE WHEN x.g ~ '^[0-9]{1,3}$' THEN CASE WHEN x.g::integer BETWEEN 1 AND 320 THEN x.g::integer END END,
           h.created_at
      FROM public.cattle_health_logs h
      JOIN public.cattle_livestock l ON l.id = h.livestock_id AND l.tenant_id = p_tenant
     CROSS JOIN LATERAL (SELECT NULLIF(btrim(coalesce(h.medicines_json->>'gestation_days', h.medicines_json->>'dias_gestacion')), '') AS g) x
     WHERE upper(translate(h.event_type, 'Óó', 'Oo')) = 'PALPACION'
$$;

-- 5) Tools ----------------------------------------------------------------------------------------------------
-- Every parameter is text (n8n convention). Expected conditions are answers (status); membership / palm failures raise.

-- 5.1 log_palpation_with_condition: ALL OR NOTHING. p_items is a JSON array (text) of {"identifier","raw_diagnosis"}.
-- Phase 1 validates every item without writing; phase 2 calls the EXISTING sp_log_palpation_event once per item and
-- fills palpation_repro_details from the raw diagnosis. Any exception aborts the whole call (nothing is kept).
CREATE OR REPLACE FUNCTION public.sp_repro_log_palpation_batch(
    p_tenant_id text, p_user_email text, p_items text,
    p_palpation_date text DEFAULT NULL, p_technician_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant  integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_email   text;
    v_today   date := public.fn_repro_today();
    v_date    date;
    v_tech    text := public.fn_repro_txt(p_technician_name);
    v_arr     jsonb;
    e         jsonb;
    i         integer := 0;
    v_ident   text;
    v_diag    text;
    v_n       integer;
    v_ids     uuid[];
    v_cand    jsonb;
    v_status  text;
    v_lid     uuid;
    v_seen    uuid[] := ARRAY[]::uuid[];
    v_lock    uuid;
    v_plan    jsonb := '[]'::jsonb;
    v_issues  jsonb := '[]'::jsonb;
    v_results jsonb := '[]'::jsonb;
    v_result  text;
    v_months  text;
    v_days    text;
    v_gest    integer;
    v_gnote   text;
    v_kind    text;
    p         record;
    r         jsonb;
    x         record;
    v_n_preg  integer := 0;
    v_n_vac   integer := 0;
    v_n_cond  integer := 0;
    v_n_unm   integer := 0;
    v_n_dup   integer := 0;
    v_unm     jsonb;
    v_blocked constant text[] := ARRAY['VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS'];
BEGIN
    -- the existing procedure compares the e-mail exactly: pass the stored spelling of an ACTIVE member
    SELECT u.email INTO v_email FROM public.users u WHERE lower(u.email) = lower(public.fn_repro_txt(p_user_email)) LIMIT 1;

    IF public.fn_repro_txt(p_palpation_date) IS NOT NULL THEN
        v_date := public.fn_repro_date(p_palpation_date);
        IF v_date IS NULL THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'La fecha debe tener el formato AAAA-MM-DD.');
        ELSIF v_date > v_today THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'La fecha de palpacion no puede ser futura.');
        ELSIF v_date < v_today - 365 THEN
            RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_DATE', 'message', 'La fecha de palpacion tiene mas de un ano de antiguedad.');
        END IF;
    END IF;

    BEGIN
        v_arr := public.fn_repro_txt(p_items)::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_arr := NULL;
    END;
    IF v_arr IS NULL OR jsonb_typeof(v_arr) <> 'array' OR jsonb_array_length(v_arr) = 0 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'BAD_ITEMS',
                                  'message', 'items debe ser un arreglo JSON no vacio de objetos {"identifier","raw_diagnosis"}.');
    END IF;
    IF jsonb_array_length(v_arr) > 100 THEN
        RETURN jsonb_build_object('status', 'invalid', 'code', 'TOO_MANY_ITEMS', 'message', 'Maximo 100 animales por lote.');
    END IF;

    -- Phase 1: validate everything, write nothing
    FOR e IN SELECT x2 FROM jsonb_array_elements(v_arr) AS t(x2) LOOP
        i := i + 1;
        v_ident := CASE WHEN jsonb_typeof(e) = 'object' THEN public.fn_repro_txt(e->>'identifier') END;
        v_diag  := CASE WHEN jsonb_typeof(e) = 'object' THEN public.fn_repro_txt(e->>'raw_diagnosis') END;
        IF v_ident IS NULL OR v_diag IS NULL THEN
            v_issues := v_issues || jsonb_build_object('index', i, 'identifier', v_ident, 'code', 'ITEM_INCOMPLETE',
                'message', 'Cada renglon necesita identifier y raw_diagnosis (el diagnostico tal como se dicto).');
            CONTINUE;
        END IF;

        -- same resolution as sp_log_palpation_event: the identifier against the three columns, inside the company
        SELECT count(*), array_agg(l.id ORDER BY l.id),
               coalesce(jsonb_agg(jsonb_build_object('livestock_id', l.id, 'rfid_siniiga', l.rfid_siniiga,
                                                     'numero_fuego', l.numero_fuego, 'electronic_rfid', l.electronic_rfid,
                                                     'category', l.category, 'current_status', l.current_status)
                                  ORDER BY l.id) FILTER (WHERE l.id IS NOT NULL), '[]'::jsonb)
          INTO v_n, v_ids, v_cand
          FROM public.cattle_livestock l
         WHERE l.tenant_id = v_tenant
           AND (l.rfid_siniiga = v_ident OR l.electronic_rfid = v_ident OR l.numero_fuego = v_ident);
        IF v_n = 0 THEN
            v_issues := v_issues || jsonb_build_object('index', i, 'identifier', v_ident, 'code', 'ANIMAL_NOT_FOUND',
                'message', 'No se encontro ningun animal con el identificador ' || v_ident || ' en esta empresa.');
            CONTINUE;
        ELSIF v_n > 1 THEN
            v_issues := v_issues || jsonb_build_object('index', i, 'identifier', v_ident, 'code', 'ANIMAL_AMBIGUOUS',
                'message', 'El identificador ' || v_ident || ' coincide con ' || v_n || ' animales; elige uno por su arete SINIIGA.',
                'candidates', v_cand);
            CONTINUE;
        END IF;
        v_lid := v_ids[1];
        SELECT l.current_status INTO v_status FROM public.cattle_livestock l WHERE l.id = v_lid AND l.tenant_id = v_tenant;
        IF v_status = ANY (v_blocked) THEN
            v_issues := v_issues || jsonb_build_object('index', i, 'identifier', v_ident, 'code', 'NOT_ACTIVE',
                'message', 'El animal ' || v_ident || ' tiene estatus ' || v_status || ' y ya no forma parte del hato activo.');
            CONTINUE;
        END IF;
        IF v_lid = ANY (v_seen) THEN
            v_issues := v_issues || jsonb_build_object('index', i, 'identifier', v_ident, 'code', 'DUPLICATE_IN_BATCH',
                'message', 'El animal ' || v_ident || ' aparece mas de una vez en el lote.');
            CONTINUE;
        END IF;
        v_seen := v_seen || v_lid;

        -- result and gestation: a diagnosis that is not recognised is NEVER defaulted to VACÍA
        v_kind := public.fn_repro_diagnosis_kind(v_diag, v_tenant);
        IF v_kind = 'CONFLICT' THEN
            v_issues := v_issues || jsonb_build_object('index', i, 'identifier', v_ident, 'code', 'DIAGNOSIS_CONFLICT',
                'message', 'El diagnostico "' || v_diag || '" mezcla PREÑADA con VACIA o con una condicion; aclara cual es.');
            CONTINUE;
        ELSIF v_kind = 'UNRECOGNIZED' THEN
            v_issues := v_issues || jsonb_build_object('index', i, 'identifier', v_ident, 'code', 'DIAGNOSIS_UNRECOGNIZED',
                'message', 'No se reconoce el diagnostico "' || v_diag || '": debe decir PREÑADA o VACIA, ciclando / estatica, o un codigo uterino. No se adivina el resultado.');
            CONTINUE;
        END IF;
        IF v_kind = 'PRENADA' THEN
            v_result := 'PREÑADA';
            v_months := substring(v_diag FROM '(?i)(\d{1,2})\s*mes');
            v_days   := substring(v_diag FROM '(?i)(\d{2,3})\s*d[ií]as');
            v_gest := NULL; v_gnote := NULL;
            IF v_months IS NOT NULL THEN
                IF v_months::integer BETWEEN 1 AND 10 THEN v_gest := v_months::integer * 30; ELSE v_gnote := 'MONTHS_OUT_OF_RANGE'; END IF;
            ELSIF v_days IS NOT NULL THEN
                IF v_days::integer BETWEEN 1 AND 300 THEN v_gest := v_days::integer; ELSE v_gnote := 'DAYS_OUT_OF_RANGE'; END IF;
            END IF;
        ELSE
            v_result := 'VACÍA'; v_gest := NULL; v_gnote := NULL;
        END IF;
        v_plan := v_plan || jsonb_build_object('index', i, 'livestock_id', v_lid, 'identifier', v_ident, 'raw_diagnosis', v_diag,
                                               'result', v_result, 'gestation_days', v_gest, 'gestation_note', v_gnote);
    END LOOP;

    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('status', 'rejected', 'written', 0, 'issues', v_issues,
                                  'message', 'No se guardo nada del lote: corrige los renglones indicados y vuelve a enviarlo completo.');
    END IF;

    -- Phase 2: write. Locks in a fixed order so two concurrent batches cannot deadlock.
    FOR v_lock IN SELECT (q->>'livestock_id')::uuid FROM jsonb_array_elements(v_plan) q ORDER BY 1 LOOP
        PERFORM pg_advisory_xact_lock(hashtextextended('palpation:' || v_tenant || ':' || v_lock::text, 0));
    END LOOP;

    FOR p IN SELECT q->>'index' AS idx, (q->>'livestock_id')::uuid AS lid, q->>'identifier' AS ident, q->>'raw_diagnosis' AS diag,
                    q->>'result' AS result, (q->>'gestation_days')::integer AS gest, q->>'gestation_note' AS gnote
               FROM jsonb_array_elements(v_plan) WITH ORDINALITY AS t(q, o) ORDER BY o LOOP
        r := public.sp_log_palpation_event(v_tenant, v_email, p.ident, p.result, p.gest, v_tech, p.diag, v_date);

        IF p.result = 'VACÍA' THEN
            SELECT * INTO x FROM public.fn_parse_uterine_code(p.diag, v_tenant);
        ELSE
            SELECT NULL::text AS raw_code, NULL::text AS ovary_side, NULL::text AS repro_condition, 'NOT_APPLICABLE'::text AS mapping_status INTO x;
        END IF;

        INSERT INTO public.palpation_repro_details
               (id_company, health_log_id, livestock_id, result, raw_code, repro_condition, ovary_side, mapping_status, registered_by_email)
        VALUES (v_tenant, (r->>'log_id')::uuid, p.lid, p.result, x.raw_code, x.repro_condition, x.ovary_side, x.mapping_status,
                lower(v_email))
        ON CONFLICT (health_log_id) DO NOTHING;

        IF p.result = 'PREÑADA' THEN v_n_preg := v_n_preg + 1; ELSE v_n_vac := v_n_vac + 1; END IF;
        IF x.repro_condition IS NOT NULL THEN v_n_cond := v_n_cond + 1; END IF;
        IF x.mapping_status = 'UNMAPPED' THEN v_n_unm := v_n_unm + 1; END IF;
        IF coalesce((r->>'duplicate_skipped')::boolean, false) THEN v_n_dup := v_n_dup + 1; END IF;

        v_results := v_results || jsonb_build_object(
            'index', p.idx::integer, 'identifier', p.ident, 'raw_diagnosis', p.diag,
            'livestock_id', r->>'livestock_id_resolved', 'log_id', r->>'log_id',
            'result_used', p.result, 'gestation_days_used', p.gest, 'gestation_note', p.gnote,
            'current_status', r->>'current_status',
            'duplicate_skipped', coalesce((r->>'duplicate_skipped')::boolean, false),
            'raw_code', x.raw_code, 'ovary_side', x.ovary_side,
            'repro_condition', x.repro_condition, 'mapping_status', x.mapping_status);
    END LOOP;

    SELECT coalesce(jsonb_agg(DISTINCT e2->>'raw_code'), '[]'::jsonb) INTO v_unm
      FROM jsonb_array_elements(v_results) e2 WHERE e2->>'mapping_status' = 'UNMAPPED';

    RETURN jsonb_build_object('status', 'recorded', 'written', jsonb_array_length(v_results),
        'pregnant', v_n_preg, 'empty', v_n_vac, 'with_condition', v_n_cond,
        'unmapped', v_n_unm, 'unmapped_codes', v_unm, 'duplicate_skipped', v_n_dup,
        'results', v_results,
        'note', 'Las condiciones UNMAPPED se guardan solo como codigo en bruto hasta que los veterinarios confirmen su significado.');
END;
$$;

-- 5.2 list_palpation_due
CREATE OR REPLACE FUNCTION public.sp_repro_list_palpation_due(
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
    v_pal_n  bigint;
    v_top_d  date;
    v_top_n  bigint;
    v_stale  boolean;
BEGIN
    IF public.fn_repro_txt(p_days) IS NOT NULL AND (public.fn_repro_int(p_days) IS NULL OR v_days NOT BETWEEN 90 AND 120) THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Los dias deben ser un numero entre 90 y 120.');
    END IF;
    IF v_limit < 1 THEN v_limit := 50; END IF;
    SELECT * INTO cfg FROM public.fn_repro_empadre_cfg(v_tenant);

    -- import-date detector over ALL palpations of the company
    SELECT count(*) INTO v_pal_n FROM public.fn_repro_palpations(v_tenant);
    SELECT q.pdate, q.n INTO v_top_d, v_top_n
      FROM (SELECT pdate, count(*) AS n FROM public.fn_repro_palpations(v_tenant) GROUP BY pdate ORDER BY count(*) DESC, pdate LIMIT 1) q;
    v_stale := coalesce(v_pal_n >= 10 AND v_top_n::numeric / v_pal_n > 0.5, false);

    WITH pal AS (
        SELECT * FROM public.fn_repro_palpations(v_tenant)
    ), last_pal AS (
        SELECT DISTINCT ON (p.livestock_id) p.livestock_id, p.pdate, p.result, p.gestation_days
          FROM pal p ORDER BY p.livestock_id, p.pdate DESC, p.created_at DESC
    ), emp AS (
        SELECT DISTINCT ON (e.heifer_id) e.heifer_id, e.entry_date
          FROM public.repro_empadre_entries e
         WHERE e.id_company = v_tenant AND e.entry_date >= v_today - cfg.empadre_window_days
           AND NOT EXISTS (SELECT 1 FROM public.repro_empadre_voids v WHERE v.entry_id = e.id AND v.id_company = v_tenant)
         ORDER BY e.heifer_id, e.entry_date DESC
    ), due AS (
        SELECT l.id, l.rfid_siniiga, l.electronic_rfid, l.numero_fuego, l.category, l.current_status,
               lp.pdate, lp.result, lp.gestation_days, emp.entry_date,
               (l.current_status = 'PREÑADA') AS is_pregnant, (emp.heifer_id IS NOT NULL) AS in_empadre
          FROM public.cattle_livestock l
          LEFT JOIN emp      ON emp.heifer_id = l.id
          LEFT JOIN last_pal lp ON lp.livestock_id = l.id
         WHERE l.tenant_id = v_tenant AND l.species = 'BOVINO'
           AND l.category IN ('VACA', 'NOVILLONA', 'BECERRA')
           AND l.current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD', 'FINALIZADO', 'BAJA_DEPURACION_DATOS')
           AND (l.current_status = 'PREÑADA' OR emp.heifer_id IS NOT NULL)
           AND (lp.pdate IS NULL OR lp.pdate < v_today - v_days)
    )
    SELECT (SELECT count(*) FROM due),
           coalesce((SELECT jsonb_agg(q.j ORDER BY q.k1 NULLS FIRST, q.k2)
                       FROM (SELECT jsonb_build_object(
                                      'livestock_id', d.id, 'rfid_siniiga', d.rfid_siniiga, 'numero_fuego', d.numero_fuego,
                                      'electronic_rfid', d.electronic_rfid, 'category', d.category, 'current_status', d.current_status,
                                      'reason', CASE WHEN d.is_pregnant AND d.in_empadre THEN 'PREÑADA_Y_EMPADRE'
                                                     WHEN d.is_pregnant THEN 'PREÑADA' ELSE 'EMPADRE' END,
                                      'last_palpation_date', d.pdate, 'last_palpation_result', d.result,
                                      'gestation_days_at_palpation', d.gestation_days,
                                      'days_since_last_palpation', CASE WHEN d.pdate IS NULL THEN NULL ELSE v_today - d.pdate END,
                                      'never_palpated', d.pdate IS NULL,
                                      'empadre_entry_date', d.entry_date,
                                      'palpated_after_empadre_entry', (d.entry_date IS NOT NULL AND d.pdate IS NOT NULL AND d.pdate >= d.entry_date),
                                      'date_is_stale_import', (v_stale AND d.pdate = v_top_d)) AS j,
                                    d.pdate AS k1, d.id::text AS k2
                               FROM due d
                              ORDER BY d.pdate NULLS FIRST, d.id::text
                              LIMIT v_limit OFFSET v_offset) q), '[]'::jsonb)
      INTO v_total, v_rows;

    RETURN jsonb_build_object('status', 'ok', 'days', v_days, 'total', v_total, 'limit', v_limit, 'offset', v_offset,
        'has_more', (v_offset + v_limit) < v_total,
        'stale_import_date', jsonb_build_object('flag', v_stale, 'date', CASE WHEN v_stale THEN v_top_d END,
                                                'share_pct', CASE WHEN v_pal_n > 0 THEN round(100.0 * v_top_n / v_pal_n, 1) END,
                                                'palpations_total', v_pal_n),
        'cows', v_rows,
        'note', 'Hembras PREÑADA o con empadre vigente cuya ultima palpacion es mas antigua que los dias indicados (las nunca palpadas primero). '
                || 'Si stale_import_date.flag es true, esa fecha es la de una carga masiva y no la de una palpacion real: no la presentes como fecha de palpacion.');
END;
$$;

-- 5.3 list_upcoming_calvings
CREATE OR REPLACE FUNCTION public.sp_repro_list_upcoming_calvings(
    p_tenant_id text, p_user_email text, p_days text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_days   integer := coalesce(public.fn_repro_int(p_days), 60);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 50), 100);
    v_offset integer := coalesce(public.fn_repro_int(p_offset), 0);
    v_today  date := public.fn_repro_today();
    v_gest   constant integer := 283;     -- BOVINO; the same constant sp_log_breeding_event uses
    v_pal_n  bigint;
    v_top_d  date;
    v_top_n  bigint;
    v_stale  boolean;
    v_out    jsonb;
BEGIN
    IF public.fn_repro_txt(p_days) IS NOT NULL AND (public.fn_repro_int(p_days) IS NULL OR v_days NOT BETWEEN 1 AND 300) THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Los dias deben ser un numero entre 1 y 300.');
    END IF;
    IF v_limit < 1 THEN v_limit := 50; END IF;

    SELECT count(*) INTO v_pal_n FROM public.fn_repro_palpations(v_tenant);
    SELECT q.pdate, q.n INTO v_top_d, v_top_n
      FROM (SELECT pdate, count(*) AS n FROM public.fn_repro_palpations(v_tenant) GROUP BY pdate ORDER BY count(*) DESC, pdate LIMIT 1) q;
    v_stale := coalesce(v_pal_n >= 10 AND v_top_n::numeric / v_pal_n > 0.5, false);

    WITH pal AS (
        SELECT * FROM public.fn_repro_palpations(v_tenant)
    ), last_any AS (
        SELECT DISTINCT ON (p.livestock_id) p.livestock_id, p.pdate, p.result
          FROM pal p ORDER BY p.livestock_id, p.pdate DESC, p.created_at DESC
    ), last_preg AS (
        SELECT DISTINCT ON (p.livestock_id) p.livestock_id, p.pdate, p.gestation_days
          FROM pal p WHERE p.result = 'PREÑADA' ORDER BY p.livestock_id, p.pdate DESC, p.created_at DESC
    ), svc AS (
        SELECT be.livestock_id, max(be.breeding_date) AS last_service
          FROM public.cattle_breeding_events be
         WHERE be.tenant_id = v_tenant AND be.breeding_date <= v_today
           AND NOT EXISTS (SELECT 1 FROM public.event_voids v
                            WHERE v.event_table = 'cattle_breeding_events' AND v.event_id = be.id AND v.tenant_id = v_tenant)
         GROUP BY be.livestock_id
    ), est AS (
        SELECT l.id, l.rfid_siniiga, l.electronic_rfid, l.numero_fuego, l.category,
               lp.pdate AS palp_date, lp.gestation_days AS palp_gest, la.result AS last_result, la.pdate AS last_date,
               s.last_service,
               CASE WHEN lp.pdate IS NOT NULL AND lp.gestation_days IS NOT NULL AND lp.gestation_days <= v_gest
                    THEN lp.pdate + (v_gest - lp.gestation_days) END AS est_palp,
               CASE WHEN s.last_service IS NOT NULL THEN s.last_service + v_gest END AS est_svc
          FROM public.cattle_livestock l
          LEFT JOIN last_preg lp ON lp.livestock_id = l.id
          LEFT JOIN last_any  la ON la.livestock_id = l.id
          LEFT JOIN svc       s  ON s.livestock_id = l.id
         WHERE l.tenant_id = v_tenant AND l.species = 'BOVINO' AND l.current_status = 'PREÑADA'
           AND l.category IN ('VACA', 'NOVILLONA', 'BECERRA')
    ), e2 AS (
        SELECT est.*, coalesce(est.est_palp, est.est_svc) AS est_date,
               CASE WHEN est.est_palp IS NOT NULL THEN 'PALPACION' WHEN est.est_svc IS NOT NULL THEN 'SERVICIO' END AS est_source,
               (coalesce(est.est_palp, est.est_svc) - v_today) AS days_to
          FROM est
    ), rowj AS (
        SELECT e2.*,
               jsonb_build_object(
                   'livestock_id', e2.id, 'rfid_siniiga', e2.rfid_siniiga, 'numero_fuego', e2.numero_fuego,
                   'electronic_rfid', e2.electronic_rfid, 'category', e2.category,
                   'estimated_calving_date', e2.est_date, 'estimate_source', e2.est_source, 'days_to_calving', e2.days_to,
                   'palpation_date', e2.palp_date, 'gestation_days_at_palpation', e2.palp_gest,
                   'last_service_date', e2.last_service,
                   'estimate_from_palpation', e2.est_palp, 'estimate_from_service', e2.est_svc,
                   'last_palpation_result', e2.last_result, 'last_palpation_date', e2.last_date,
                   'status_conflict', (e2.last_result = 'VACÍA' AND e2.last_date > coalesce(e2.palp_date, e2.last_date - 1)),
                   'date_is_stale_import', (v_stale AND e2.palp_date = v_top_d)) AS j
          FROM e2
    )
    SELECT jsonb_build_object(
        'upcoming_total',   (SELECT count(*) FROM rowj WHERE days_to BETWEEN 0 AND v_days),
        'overdue_total',    (SELECT count(*) FROM rowj WHERE days_to BETWEEN -60 AND -1),
        'stale_data_total', (SELECT count(*) FROM rowj WHERE days_to < -60),
        'later_total',      (SELECT count(*) FROM rowj WHERE days_to > v_days),
        'no_estimate_total',(SELECT count(*) FROM rowj WHERE est_date IS NULL),
        'pregnant_total',   (SELECT count(*) FROM rowj),
        'upcoming', coalesce((SELECT jsonb_agg(q.j ORDER BY q.d, q.k) FROM
            (SELECT j, est_date AS d, id::text AS k FROM rowj WHERE days_to BETWEEN 0 AND v_days
              ORDER BY est_date, id::text LIMIT v_limit OFFSET v_offset) q), '[]'::jsonb),
        'overdue', coalesce((SELECT jsonb_agg(q.j ORDER BY q.d, q.k) FROM
            (SELECT j, est_date AS d, id::text AS k FROM rowj WHERE days_to BETWEEN -60 AND -1
              ORDER BY est_date, id::text LIMIT v_limit OFFSET v_offset) q), '[]'::jsonb),
        'stale_data', coalesce((SELECT jsonb_agg(q.j ORDER BY q.d DESC, q.k) FROM
            (SELECT j, est_date AS d, id::text AS k FROM rowj WHERE days_to < -60
              ORDER BY est_date DESC, id::text LIMIT v_limit OFFSET v_offset) q), '[]'::jsonb),
        'no_estimate', coalesce((SELECT jsonb_agg(q.j ORDER BY q.k) FROM
            (SELECT j, id::text AS k FROM rowj WHERE est_date IS NULL
              ORDER BY id::text LIMIT v_limit OFFSET v_offset) q), '[]'::jsonb))
      INTO v_out;

    RETURN v_out || jsonb_build_object('status', 'ok', 'days', v_days, 'limit', v_limit, 'offset', v_offset,
        'gestation_days_bovino', v_gest,
        'stale_import_date', jsonb_build_object('flag', v_stale, 'date', CASE WHEN v_stale THEN v_top_d END,
                                                'share_pct', CASE WHEN v_pal_n > 0 THEN round(100.0 * v_top_n / v_pal_n, 1) END,
                                                'palpations_total', v_pal_n),
        'note', 'Fecha estimada = fecha de la ultima palpacion PREÑADA + (283 - dias de gestacion de esa palpacion); sin dias de gestacion, ultimo servicio + 283. '
                || 'stale_data son estimaciones con mas de 60 dias de atraso: son datos viejos o sin actualizar, NUNCA partos proximos ni atrasados; no los anuncies como partos.');
END;
$$;

-- 5.4 list_unmapped_uterine_codes: the TOKENS (not whole values) seen in the company without a confirmed mapping
CREATE OR REPLACE FUNCTION public.sp_repro_list_unmapped_uterine_codes(
    p_tenant_id text, p_user_email text, p_limit text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 100), 200);
    v_codes  jsonb;
    v_conf   jsonb;
    v_total  bigint;
BEGIN
    IF v_limit < 1 THEN v_limit := 100; END IF;

    WITH vals AS (
        -- values logged through the wrapper (the side table already holds the normalised raw code)
        SELECT d.raw_code AS val, 'REGISTRO' AS src, count(*) AS n
          FROM public.palpation_repro_details d
         WHERE d.id_company = v_tenant AND d.raw_code IS NOT NULL
         GROUP BY d.raw_code
        UNION ALL
        -- values of the bulk-loaded palpations (Spanish key condicion_utero), joined through the company
        SELECT public.fn_repro_norm_code(h.medicines_json->>'condicion_utero'), 'CARGA_MASIVA', count(*)
          FROM public.cattle_health_logs h
          JOIN public.cattle_livestock l ON l.id = h.livestock_id AND l.tenant_id = v_tenant
         WHERE public.fn_repro_norm_code(h.medicines_json->>'condicion_utero') IS NOT NULL
         GROUP BY public.fn_repro_norm_code(h.medicines_json->>'condicion_utero')
    ), tok AS (
        SELECT t.token, v.val, v.src, v.n
          FROM vals v
         CROSS JOIN LATERAL public.fn_uterine_split(v.val) s
         CROSS JOIN LATERAL unnest(s.tokens) AS t(token)
    ), unk AS (
        -- a code is "unmapped" unless it has a CONFIRMED condition; a row with a NULL condition is known but pending
        SELECT tok.*, EXISTS (SELECT 1 FROM public.repro_condition_codes cp
                               WHERE cp.id_company = v_tenant AND cp.code = tok.token AND cp.repro_condition IS NULL) AS pending
          FROM tok
         WHERE token NOT IN ('CICLANDO', 'ESTATICA', 'ESTATICO')
           AND NOT EXISTS (SELECT 1 FROM public.repro_condition_codes cc
                            WHERE cc.id_company = v_tenant AND cc.code = tok.token AND cc.repro_condition IS NOT NULL)
    ), agg AS (
        SELECT token, bool_or(pending) AS known_pending, sum(n) AS palpations,
               coalesce(sum(n) FILTER (WHERE src = 'CARGA_MASIVA'), 0) AS from_bulk_load,
               coalesce(sum(n) FILTER (WHERE src = 'REGISTRO'), 0) AS from_logged,
               (array_agg(DISTINCT val ORDER BY val))[1:5] AS example_values
          FROM unk GROUP BY token
    )
    SELECT (SELECT count(*) FROM agg),
           coalesce((SELECT jsonb_agg(jsonb_build_object('code', a.token, 'known_pending', a.known_pending, 'palpations', a.palpations,
                                                         'from_bulk_load', a.from_bulk_load, 'from_logged', a.from_logged,
                                                         'example_values', to_jsonb(a.example_values))
                                      ORDER BY a.palpations DESC, a.token)
                       FROM (SELECT * FROM agg ORDER BY palpations DESC, token LIMIT v_limit) a), '[]'::jsonb),
           coalesce((SELECT jsonb_agg(jsonb_build_object('code', cc.code, 'repro_condition', cc.repro_condition,
                                                         'source', cc.source, 'confirmed_by', cc.confirmed_by,
                                                         'confirmed_at', cc.confirmed_at) ORDER BY cc.code)
                       FROM public.repro_condition_codes cc WHERE cc.id_company = v_tenant AND cc.repro_condition IS NOT NULL), '[]'::jsonb)
      INTO v_total, v_codes, v_conf;

    RETURN jsonb_build_object('status', 'ok', 'unmapped_total', v_total, 'unmapped', v_codes, 'confirmed', v_conf,
        'note', 'Codigos (o partes de un codigo compuesto como UNE/NR) sin significado confirmado para esta empresa. '
                || 'known_pending = el codigo ya esta registrado pero su significado espera la confirmacion del veterinario. Los veterinarios los confirman; un ADMIN los registra. Mientras tanto la condicion queda vacia (UNMAPPED), nunca adivinada.');
END;
$$;

-- 5.5 condition_code_set: ADMIN only, NOT an agent tool. Creates or re-confirms one mapping of the caller's company.
-- Re-mapping changes how FUTURE palpations are read; rows already in palpation_repro_details keep the value they had.
CREATE OR REPLACE FUNCTION public.sp_repro_condition_code_set(
    p_tenant_id text, p_user_email text, p_code text, p_repro_condition text, p_source text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_code   text := public.fn_repro_norm_code(p_code);
    v_cond   text := upper(public.fn_repro_txt(p_repro_condition));
    v_prev   text;
    v_exists boolean;
BEGIN
    IF public.fn_repro_member_role(v_tenant, p_user_email) IS DISTINCT FROM 'ADMIN' THEN
        RETURN jsonb_build_object('status', 'forbidden', 'message', 'Solo un ADMIN de la empresa puede confirmar el significado de un codigo.');
    END IF;
    IF v_cond IS NULL OR v_cond NOT IN ('CICLANDO', 'ESTATICA', 'OTRO') THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'La condicion debe ser CICLANDO, ESTATICA u OTRO.');
    END IF;
    IF v_code IS NULL OR length(v_code) > 40 OR v_code LIKE '%/%' THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'El codigo debe tener entre 1 y 40 caracteres y no puede contener "/".');
    END IF;
    -- the words the parser already treats specially cannot be (re)defined
    IF v_code IN ('OI', 'OD', 'VACIA', 'PRENADA', 'CICLANDO', 'ESTATICA', 'ESTATICO', 'N', 'A') THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Ese texto ya tiene un significado fijo y no se puede redefinir.');
    END IF;

    SELECT true, cc.repro_condition INTO v_exists, v_prev FROM public.repro_condition_codes cc WHERE cc.id_company = v_tenant AND cc.code = v_code;
    INSERT INTO public.repro_condition_codes AS cc (id_company, code, repro_condition, source, confirmed_by, confirmed_at)
    VALUES (v_tenant, v_code, v_cond, coalesce(public.fn_repro_txt(p_source), 'ADMIN_CONFIRMED'),
            lower(public.fn_repro_txt(p_user_email)), now())
    ON CONFLICT (id_company, code) DO UPDATE
       SET repro_condition = excluded.repro_condition, source = excluded.source,
           confirmed_by = excluded.confirmed_by, confirmed_at = excluded.confirmed_at
     WHERE cc.id_company = v_tenant;

    RETURN jsonb_build_object('status', CASE WHEN coalesce(v_exists, false) THEN 'updated' ELSE 'created' END,
                              'code', v_code, 'repro_condition', v_cond, 'previous_condition', v_prev,
                              'message', 'Codigo confirmado. Aplica a las palpaciones que se registren de ahora en adelante.');
END;
$$;

-- 6) Sanity ---------------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY['fn_repro_norm_code', 'fn_uterine_split', 'fn_parse_uterine_code', 'fn_repro_palpations',
                        'fn_repro_diagnosis_kind', 'fn_trg_palp_details_tenant',
                        'sp_repro_log_palpation_batch', 'sp_repro_list_palpation_due', 'sp_repro_list_upcoming_calvings',
                        'sp_repro_list_unmapped_uterine_codes', 'sp_repro_condition_code_set']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '086: missing functions: %', v_missing;
    END IF;
    IF to_regclass('public.repro_condition_codes') IS NULL OR to_regclass('public.palpation_repro_details') IS NULL THEN
        RAISE EXCEPTION '086: tables missing';
    END IF;
    RAISE NOTICE '086: OK';
END $$;

\if :{?embedded}
\echo '*** 086 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 086 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
