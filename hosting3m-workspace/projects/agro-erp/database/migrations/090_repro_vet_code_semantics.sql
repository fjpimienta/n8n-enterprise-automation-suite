-- 090_repro_vet_code_semantics.sql
-- Reproduction tracking, phase 3b: what the ranch's uterine codes MEAN beyond a uterine condition.
--
-- REQUIRES 084 - 088 (it replaces 7 bodies created by 086 and 088 and calls a function of 087). It aborts if they are not applied.
-- It does not touch 086 / 088 files: those stay as merged; this migration replaces the live bodies with CREATE OR REPLACE
-- (same names, same signatures, no new overload) and ADDS one nullable column.
--
-- MEANINGS (confirmed by the ranch FOREMAN, NOT by a veterinarian; see 090_seed_tenant5_vet_code_meanings.sql):
--   MATRIZ OCUPADA  = pregnant. A fixed Spanish PHRASE (the same for every company), not a per-company code.
--   NR              = No Revision: the animal was NOT examined. It is not a diagnosis.      meaning NOT_EXAMINED
--   RP              = Recien Parida (recently calved).                                       meaning POSTPARTUM
--   NO APTO         = unfit for breeding (reproductive tract too small or uterine cysts).    meaning UNFIT
--   UTC2            = general uterine tone ("utero tonico"); NOT ciclando. Stays known-pending (NULL condition, NULL meaning).
--   UNE / UTCL1-3 / OI / OD and N/A: unchanged. N/A (the code carried by the PREÑADA cows of the 2023 load) is still "no code".
--
-- What changes (the 086 tools keep their names and signatures; only keys are ADDED to their answers):
--   * MATRIZ OCUPADA is a PREÑADA diagnosis (kind PRENADA): no gestation days needed, never VACÍA; together with a VACIA or explicit
--     word it is a DIAGNOSIS_CONFLICT. For a PREÑADA line the details row keeps the wording in raw_code (NOT_APPLICABLE, no condition).
--   * NR ALONE (no result word) = not examined: the line is validated (animal found, active, not repeated in the batch) and then
--     skipped: no palpation, no details row, no status change; line_status 'not_examined'; the other lines are processed; a batch of only
--     NR lines answers 'recorded' with written 0. NR inside a composite (UNE/NR) is unchanged: a real palpation, condition NULL, UNMAPPED.
--   * RP and NO APTO write a VACÍA palpation with repro_condition NULL, the wording in raw_code, mapping_status NOT_APPLICABLE and
--     vet_flag POSTPARTUM / UNFIT; the category is never touched. GUARD (owner decision, extended to EVERY code): a line with a code
--     but NO explicit result word (UTC2, UNE, UTCL1-3, RP, NO APTO, any known code) on an animal whose current_status is PREÑADA is
--     REJECTED (NEEDS_EXPLICIT_RESULT, and so the whole batch): the VACÍA would be inferred and could erase a real pregnancy; the caller
--     restates it with an explicit result ("VACIA RP", "PREÑADA UNE"). A line with an explicit word, any line on a non-PREÑADA animal,
--     N/A and NR alone behave as designed. RP / NO APTO with a PREÑADA word (or the
--     MATRIZ OCUPADA phrase) is a DIAGNOSIS_CONFLICT. An RP line whose animal has no registered birth within 90 days of the palpation
--     date answers rp_without_registered_birth = true (RP is evidence of a birth that may not have been captured).
--   * list_palpation_due, list_upcoming_calvings and get_dam_reproductive_history show the last palpation's code and vet_flag; the dam
--     history adds the read-only quality flags palpation_code_contradicts_result (a stored code that means PREÑADA next to a stored
--     result VACÍA) and palpations_with_vet_flag. Display only: no data is ever corrected by this migration.
--   * list_unmapped_uterine_codes no longer reports codes with a meaning (nor the MATRIZ OCUPADA phrase) as unknown: they go to
--     known_meanings; NR next to other tokens goes to composite_unconfirmed; meanings_configured lists the configured rows.
--   * sp_repro_condition_code_set cannot (re)define MATRIZ OCUPADA, and cannot give a condition to a code that has a meaning.
--
-- The one DDL change (additive): repro_condition_codes.meaning text NULL, CHECK in (NOT_EXAMINED, POSTPARTUM, UNFIT), and a CHECK that a
-- code with a meaning has a NULL repro_condition. ADD COLUMN IF NOT EXISTS: no default, no table rewrite, no row changes. This file
-- writes NO rows (the meanings are set by the separate seed file, applied by the owner).
--
-- NOT touched: 084 - 089 objects other than the 7 bodies below, sp_log_palpation_event and the existing palpation tools, crud_models,
-- the gateway, palpation_repro_details (no DDL, no row), fn_uterine_split and fn_parse_uterine_code (N/A handling is therefore identical).
--
-- md5 GUARDS: each body to be replaced must be the one created by 086 / 088 (verified equal to the owner's LOCAL database on 2026-10-28)
-- or already carry the marker "-- 090:vet-codes-v1"; otherwise the migration ABORTS (a body edited by hand is never overwritten):
--   fn_repro_diagnosis_kind              c14027757d85c745756a704ced03ab5f
--   sp_repro_log_palpation_batch         845854fd40df5406c8c4f1f90fd558c9
--   sp_repro_list_palpation_due          d04d1f85f5d3aadae7d7bf1b8df73518
--   sp_repro_list_upcoming_calvings      0fab0832c5818b6be09cd94efb826ddb
--   sp_repro_list_unmapped_uterine_codes 4f682a0ea099c051d5b3b95a8eb553d0
--   sp_repro_condition_code_set          46e720910cf97de3eb3921fb83f820b3
--   sp_repro_get_dam_history             79927c5b2478ae8f31307b9eb89d97d7
--
-- Rollback: 090_rollback.sql (puts the 7 ORIGINAL bodies back byte for byte; drops nothing: the column, the 3 new helpers and any
-- meaning set by the seed stay). State: 090_state_check.sql -v expect=before|applied|rolled_back. Tests: 090_tests.sql.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 090_repro_vet_code_semantics.sql                 -> dry run (rolled back)
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 090_repro_vet_code_semantics.sql   -> commit
-- 090_tests.sql includes this file with `embedded` set.

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

-- 0) Preconditions and md5 guards -----------------------------------------------------------------------------

DO $$
DECLARE
    g record;
    v_oid oid;
BEGIN
    IF to_regclass('public.repro_condition_codes') IS NULL OR to_regclass('public.palpation_repro_details') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 086 is not applied here (repro_condition_codes / palpation_repro_details missing).';
    END IF;
    IF to_regprocedure('public.fn_repro_birth_window_matches(integer,uuid,date,integer)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 087 is not applied here (fn_repro_birth_window_matches missing).';
    END IF;
    IF to_regprocedure('public.sp_repro_get_dam_history(text,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migration 088 is not applied here (sp_repro_get_dam_history missing).';
    END IF;
    FOR g IN SELECT * FROM (VALUES
        ('public.fn_repro_diagnosis_kind(text,integer)', 'c14027757d85c745756a704ced03ab5f'),
        ('public.sp_repro_log_palpation_batch(text,text,text,text,text)', '845854fd40df5406c8c4f1f90fd558c9'),
        ('public.sp_repro_list_palpation_due(text,text,text,text,text)', 'd04d1f85f5d3aadae7d7bf1b8df73518'),
        ('public.sp_repro_list_upcoming_calvings(text,text,text,text,text)', '0fab0832c5818b6be09cd94efb826ddb'),
        ('public.sp_repro_list_unmapped_uterine_codes(text,text,text)', '4f682a0ea099c051d5b3b95a8eb553d0'),
        ('public.sp_repro_condition_code_set(text,text,text,text,text)', '46e720910cf97de3eb3921fb83f820b3'),
        ('public.sp_repro_get_dam_history(text,text,text,text)', '79927c5b2478ae8f31307b9eb89d97d7')
    ) AS v (sig, expected) LOOP
        v_oid := to_regprocedure(g.sig);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'ABORT: % not found (is it disabled by a rollback, or a different signature?). Apply 086 / 088 first.', g.sig;
        END IF;
        IF md5(pg_get_functiondef(v_oid)) <> g.expected
           AND (SELECT p.prosrc FROM pg_proc p WHERE p.oid = v_oid) NOT LIKE '%090:vet-codes-v1%' THEN
            RAISE EXCEPTION 'ABORT: the live % is not the body created by 086 / 088 (md5 %). STOP and compare it before replacing it.',
                g.sig, md5(pg_get_functiondef(v_oid));
        END IF;
    END LOOP;
END $$;

-- 1) The one additive column ----------------------------------------------------------------------------------

ALTER TABLE public.repro_condition_codes ADD COLUMN IF NOT EXISTS meaning text;
COMMENT ON COLUMN public.repro_condition_codes.meaning IS '090: what a code means when it is NOT a uterine condition: NOT_EXAMINED (NR), POSTPARTUM (RP), UNFIT (NO APTO). NULL for the CICLANDO / ESTATICA / OTRO codes and for the codes pending confirmation. A code with a meaning has a NULL repro_condition.';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_cond_code_meaning' AND conrelid = 'public.repro_condition_codes'::regclass) THEN
        ALTER TABLE public.repro_condition_codes ADD CONSTRAINT ck_cond_code_meaning
            CHECK (meaning IS NULL OR meaning IN ('NOT_EXAMINED', 'POSTPARTUM', 'UNFIT'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_cond_code_meaning_no_condition' AND conrelid = 'public.repro_condition_codes'::regclass) THEN
        ALTER TABLE public.repro_condition_codes ADD CONSTRAINT ck_cond_code_meaning_no_condition
            CHECK (meaning IS NULL OR repro_condition IS NULL);
    END IF;
END $$;

-- 2) Helpers (new) ---------------------------------------------------------------------------------------------

-- The meaning of ONE normalised token for ONE company: PREGNANT (the fixed phrase MATRIZ OCUPADA, same for every company),
-- NOT_EXAMINED | POSTPARTUM | UNFIT (from repro_condition_codes.meaning) or NULL.
CREATE OR REPLACE FUNCTION public.fn_repro_code_meaning(p_tenant integer, p_token text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT CASE WHEN public.fn_repro_norm_code(p_token) = 'MATRIZ OCUPADA' THEN 'PREGNANT'
                ELSE (SELECT cc.meaning FROM public.repro_condition_codes cc
                       WHERE cc.id_company = p_tenant AND cc.code = public.fn_repro_norm_code(p_token)) END
$$;

-- The uterine text of ONE palpation of ONE company: the code of the side table when the wrapper logged it, else the
-- bulk-loaded condicion_utero (normalised). NULL when the palpation is not in the company. INTERNAL (no access control).
CREATE OR REPLACE FUNCTION public.fn_repro_palp_text(p_tenant integer, p_health_log_id uuid)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(pd.raw_code, public.fn_repro_norm_code(h.medicines_json->>'condicion_utero'))
      FROM public.cattle_health_logs h
      JOIN public.cattle_livestock l ON l.id = h.livestock_id AND l.tenant_id = p_tenant
      LEFT JOIN public.palpation_repro_details pd ON pd.health_log_id = h.id AND pd.id_company = p_tenant
     WHERE h.id = p_health_log_id
$$;

-- What a stored / typed uterine text means for ONE company (read side). NEVER raises. N/A and empty -> nothing (same as the
-- parser: fn_uterine_split). Tokens are the parts of the text without OI / OD and without the leading result word.
--   uterine_code    normalised text without the leading result word (NULL when empty)
--   vet_flag        UNFIT | POSTPARTUM (any token) | NOT_EXAMINED (EVERY token) | NULL
--   means_pregnant  a token is the fixed phrase MATRIZ OCUPADA
--   nr_composite    a NOT_EXAMINED token comes WITH other tokens (e.g. UNE/NR): its meaning in that position is NOT confirmed
--   unknown_tokens  tokens that are neither a registered code, an explicit word nor the fixed phrase
CREATE OR REPLACE FUNCTION public.fn_repro_palp_code_info(
    p_tenant integer, p_text text,
    OUT uterine_code text, OUT vet_flag text, OUT means_pregnant boolean, OUT nr_composite boolean, OUT unknown_tokens integer
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    sp      record;
    tk      text;
    m       text;
    n_tok   integer := 0;
    n_ne    integer := 0;
    f_unfit boolean := false;
    f_pp    boolean := false;
BEGIN
    uterine_code := NULL; vet_flag := NULL; means_pregnant := false; nr_composite := false; unknown_tokens := 0;
    SELECT * INTO sp FROM public.fn_uterine_split(p_text);
    IF sp.is_empty THEN RETURN; END IF;
    uterine_code := sp.raw_code;
    IF sp.raw_code ~ '\mMATRIZ OCUPADA\M' THEN means_pregnant := true; END IF;     -- also inside a longer text ("MATRIZ OCUPADA 3 MESES")
    FOREACH tk IN ARRAY sp.tokens LOOP
        n_tok := n_tok + 1;
        m := public.fn_repro_code_meaning(p_tenant, tk);
        IF m = 'PREGNANT' THEN means_pregnant := true;
        ELSIF m = 'UNFIT' THEN f_unfit := true;
        ELSIF m = 'POSTPARTUM' THEN f_pp := true;
        ELSIF m = 'NOT_EXAMINED' THEN n_ne := n_ne + 1;
        ELSIF tk IN ('CICLANDO', 'ESTATICA', 'ESTATICO') THEN NULL;
        ELSIF p_tenant IS NULL OR NOT EXISTS (SELECT 1 FROM public.repro_condition_codes cc WHERE cc.id_company = p_tenant AND cc.code = tk) THEN
            unknown_tokens := unknown_tokens + 1;
        END IF;
    END LOOP;
    vet_flag := CASE WHEN f_unfit THEN 'UNFIT' WHEN f_pp THEN 'POSTPARTUM' WHEN n_tok > 0 AND n_ne = n_tok THEN 'NOT_EXAMINED' END;
    nr_composite := (n_ne > 0 AND n_tok > n_ne);
    RETURN;
EXCEPTION WHEN OTHERS THEN
    uterine_code := NULL; vet_flag := NULL; means_pregnant := false; nr_composite := false; unknown_tokens := 0;
END;
$$;

-- 3) Replaced bodies (same names and signatures; each carries the marker "-- 090:vet-codes-v1") ------------------------------

CREATE OR REPLACE FUNCTION public.fn_repro_diagnosis_kind(p_text text, p_tenant integer)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
-- 090:vet-codes-v1
DECLARE
    n      text := public.fn_repro_norm_code(p_text);
    pre    boolean;
    vac    boolean;
    ex     boolean;
    sp     record;
    tk     text;
    m      text;
    n_tok  integer := 0;
    n_ne   integer := 0;
    n_flag integer := 0;
    flag_word boolean := false;
BEGIN
    IF n IS NULL THEN RETURN 'UNRECOGNIZED'; END IF;
    -- MATRIZ OCUPADA is a PREÑADA phrase, the same for every company (a fixed phrase, not a veterinarian code)
    pre := n ~ '\mPREN?ADA\M' OR n ~ '\mMATRIZ OCUPADA\M';
    vac := n ~ '\mVACIA\M';
    ex  := n ~ '\m(CICLANDO|ESTATICA|ESTATICO)\M';

    -- an RP / NO APTO code anywhere in the text as a WORD (also when it is not a slash-separated token: "MATRIZ OCUPADA RP")
    IF p_tenant IS NOT NULL THEN
        SELECT EXISTS (SELECT 1 FROM public.repro_condition_codes cc
                        WHERE cc.id_company = p_tenant AND cc.meaning IN ('POSTPARTUM', 'UNFIT')
                          AND regexp_replace(cc.code, '[^A-Z0-9 ]', '', 'g') <> ''
                          AND n ~ ('\m' || regexp_replace(cc.code, '[^A-Z0-9 ]', '', 'g') || '\M')) INTO flag_word;
    END IF;

    SELECT * INTO sp FROM public.fn_uterine_split(p_text);
    IF NOT sp.is_empty THEN
        FOREACH tk IN ARRAY sp.tokens LOOP
            n_tok := n_tok + 1;
            m := public.fn_repro_code_meaning(p_tenant, tk);
            IF m = 'NOT_EXAMINED' THEN n_ne := n_ne + 1;
            ELSIF m IN ('POSTPARTUM', 'UNFIT') THEN n_flag := n_flag + 1;
            END IF;
        END LOOP;
    END IF;

    IF pre AND (vac OR ex) THEN RETURN 'CONFLICT'; END IF;
    IF pre AND (n_flag > 0 OR flag_word) THEN RETURN 'CONFLICT'; END IF;     -- RP / NO APTO together with a PREÑADA word
    IF pre THEN RETURN 'PRENADA'; END IF;
    IF vac OR ex THEN RETURN 'VACIA'; END IF;

    IF sp.is_empty OR cardinality(sp.tokens) = 0 THEN RETURN 'UNRECOGNIZED'; END IF;
    -- NR ALONE (every token is NOT_EXAMINED): the animal was not examined, it is not a diagnosis
    IF n_ne = n_tok THEN RETURN 'NOT_EXAMINED'; END IF;
    -- no result word: every token must already exist for the company (any condition or meaning, NULL = pending). Never by shape.
    FOREACH tk IN ARRAY sp.tokens LOOP
        IF p_tenant IS NULL
           OR NOT EXISTS (SELECT 1 FROM public.repro_condition_codes cc WHERE cc.id_company = p_tenant AND cc.code = tk) THEN
            RETURN 'UNRECOGNIZED';
        END IF;
    END LOOP;
    -- a code without an explicit result word: VACÍA is inferred (CODE_FLAG = it carries RP / NO APTO); the wrapper never lets it flip a PREÑADA animal
    IF n_flag > 0 THEN RETURN 'CODE_FLAG'; END IF;
    RETURN 'CODE';
EXCEPTION WHEN OTHERS THEN
    RETURN 'UNRECOGNIZED';
END;
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_log_palpation_batch(
    p_tenant_id text, p_user_email text, p_items text,
    p_palpation_date text DEFAULT NULL, p_technician_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
-- 090:vet-codes-v1
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
    v_notexam jsonb := '[]'::jsonb;
    v_info    record;
    v_flag    text;
    v_rp_nobirth boolean;
    v_n_rpnb  integer := 0;
    v_birth_win constant integer := 90;     -- RP: a registered birth within this many days of the palpation date
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
        IF v_kind = 'NOT_EXAMINED' THEN
            -- NR alone: validated (animal found, active, not repeated) but NOT a diagnosis: no palpation, no details row,
            -- no status change. It is not an error either, so the other lines are still processed.
            v_notexam := v_notexam || jsonb_build_object('index', i, 'identifier', v_ident, 'raw_diagnosis', v_diag,
                'livestock_id', v_lid, 'line_status', 'not_examined', 'current_status', v_status, 'written', false);
            CONTINUE;
        END IF;
        -- a line with a code but NO explicit result word (kind CODE / CODE_FLAG) infers its VACÍA: never over a PREÑADA animal
        IF v_kind IN ('CODE', 'CODE_FLAG') AND v_status = 'PREÑADA' THEN
            v_issues := v_issues || jsonb_build_object('index', i, 'identifier', v_ident, 'code', 'NEEDS_EXPLICIT_RESULT',
                'line_status', 'needs_explicit_result', 'current_status', v_status,
                'message', 'El animal ' || v_ident || ' esta PREÑADA y "' || v_diag || '" no dice VACIA ni PREÑADA: el resultado seria inferido y podria borrar una gestacion real. Repite el renglon diciendo el resultado de forma explicita (por ejemplo "VACIA ' || v_diag || '" o "PREÑADA ' || v_diag || '").');
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
        -- what the uterine text means for this company (RP / NO APTO flags, the MATRIZ OCUPADA phrase)
        SELECT * INTO v_info FROM public.fn_repro_palp_code_info(v_tenant, v_diag);
        v_flag := CASE WHEN v_result = 'VACÍA' AND v_info.vet_flag IN ('POSTPARTUM', 'UNFIT') THEN v_info.vet_flag END;
        v_rp_nobirth := NULL;
        IF v_flag = 'POSTPARTUM' THEN
            -- RP is evidence of a birth: flag it when no birth of this animal is registered around the palpation date
            v_rp_nobirth := jsonb_array_length(public.fn_repro_birth_window_matches(v_tenant, v_lid, coalesce(v_date, v_today), v_birth_win)) = 0;
        END IF;
        v_plan := v_plan || jsonb_build_object('index', i, 'livestock_id', v_lid, 'identifier', v_ident, 'raw_diagnosis', v_diag,
                                               'result', v_result, 'gestation_days', v_gest, 'gestation_note', v_gnote,
                                               'vet_flag', v_flag, 'code_known', (v_info.unknown_tokens = 0),
                                               'phrase', (v_result = 'PREÑADA' AND v_info.means_pregnant),
                                               'rp_without_registered_birth', v_rp_nobirth);
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
                    q->>'result' AS result, (q->>'gestation_days')::integer AS gest, q->>'gestation_note' AS gnote,
                    q->>'vet_flag' AS vet_flag, coalesce((q->>'code_known')::boolean, false) AS code_known,
                    coalesce((q->>'phrase')::boolean, false) AS phrase, (q->>'rp_without_registered_birth')::boolean AS rp_nobirth
               FROM jsonb_array_elements(v_plan) WITH ORDINALITY AS t(q, o) ORDER BY o LOOP
        r := public.sp_log_palpation_event(v_tenant, v_email, p.ident, p.result, p.gest, v_tech, p.diag, v_date);

        IF p.result = 'VACÍA' THEN
            SELECT * INTO x FROM public.fn_parse_uterine_code(p.diag, v_tenant);
            -- RP / NO APTO are known, but they are not a uterine condition: the condition stays NULL, the original wording is
            -- kept in raw_code, and the row is NOT_APPLICABLE (nothing is pending). An unknown token keeps it UNMAPPED.
            IF p.vet_flag IN ('POSTPARTUM', 'UNFIT') AND x.mapping_status = 'UNMAPPED' AND p.code_known THEN
                x.repro_condition := NULL; x.mapping_status := 'NOT_APPLICABLE';
            END IF;
        ELSE
            SELECT NULL::text AS raw_code, NULL::text AS ovary_side, NULL::text AS repro_condition, 'NOT_APPLICABLE'::text AS mapping_status INTO x;
            IF p.phrase THEN x.raw_code := 'MATRIZ OCUPADA'; END IF;       -- the wording of a PREÑADA phrase stays visible
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
        IF p.rp_nobirth IS TRUE THEN v_n_rpnb := v_n_rpnb + 1; END IF;

        v_results := v_results || jsonb_build_object(
            'index', p.idx::integer, 'identifier', p.ident, 'raw_diagnosis', p.diag,
            'livestock_id', r->>'livestock_id_resolved', 'log_id', r->>'log_id',
            'result_used', p.result, 'gestation_days_used', p.gest, 'gestation_note', p.gnote,
            'current_status', r->>'current_status',
            'duplicate_skipped', coalesce((r->>'duplicate_skipped')::boolean, false),
            'line_status', CASE WHEN coalesce((r->>'duplicate_skipped')::boolean, false) THEN 'duplicate_skipped' ELSE 'recorded' END,
            'raw_code', x.raw_code, 'ovary_side', x.ovary_side,
            'repro_condition', x.repro_condition, 'mapping_status', x.mapping_status,
            'vet_flag', p.vet_flag, 'rp_without_registered_birth', p.rp_nobirth);
    END LOOP;

    SELECT coalesce(jsonb_agg(DISTINCT e2->>'raw_code'), '[]'::jsonb) INTO v_unm
      FROM jsonb_array_elements(v_results) e2 WHERE e2->>'mapping_status' = 'UNMAPPED';

    RETURN jsonb_build_object('status', 'recorded', 'written', jsonb_array_length(v_results),
        'pregnant', v_n_preg, 'empty', v_n_vac, 'with_condition', v_n_cond,
        'unmapped', v_n_unm, 'unmapped_codes', v_unm, 'duplicate_skipped', v_n_dup,
        'not_examined', jsonb_array_length(v_notexam), 'not_examined_lines', v_notexam,
        'rp_without_registered_birth', v_n_rpnb,
        'results', v_results,
        'note', 'Las condiciones UNMAPPED se guardan solo como codigo en bruto hasta que los veterinarios confirmen su significado. '
                || 'not_examined = renglones con NR solo (animal no revisado): se validaron pero no se guardo nada de ellos. '
                || 'rp_without_registered_birth = renglones RP de animales sin parto registrado cerca de la fecha: el parto pudo no haberse capturado.');
END;
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_palpation_due(
    p_tenant_id text, p_user_email text, p_days text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
-- 090:vet-codes-v1
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
        SELECT DISTINCT ON (p.livestock_id) p.livestock_id, p.health_log_id, p.pdate, p.result, p.gestation_days
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
               ci.uterine_code AS lp_code, ci.vet_flag AS lp_vet_flag, ci.means_pregnant AS lp_means_pregnant, ci.nr_composite AS lp_nr_composite,
               (l.current_status = 'PREÑADA') AS is_pregnant, (emp.heifer_id IS NOT NULL) AS in_empadre
          FROM public.cattle_livestock l
          LEFT JOIN emp      ON emp.heifer_id = l.id
          LEFT JOIN last_pal lp ON lp.livestock_id = l.id
          LEFT JOIN LATERAL public.fn_repro_palp_code_info(v_tenant, public.fn_repro_palp_text(v_tenant, lp.health_log_id)) ci ON true
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
                                      'last_palpation_code', d.lp_code, 'last_palpation_vet_flag', d.lp_vet_flag,
                                      'last_palpation_code_means_pregnant', coalesce(d.lp_means_pregnant, false),
                                      'last_palpation_code_nr_composite', coalesce(d.lp_nr_composite, false),
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
                || 'Si stale_import_date.flag es true, esa fecha es la de una carga masiva y no la de una palpacion real: no la presentes como fecha de palpacion. '
                || 'last_palpation_vet_flag: UNFIT = no apta para reproduccion, POSTPARTUM = recien parida (RP), NOT_EXAMINED = no revisada; es solo informativo y no cambia ninguna lista.');
END;
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_list_upcoming_calvings(
    p_tenant_id text, p_user_email text, p_days text DEFAULT NULL, p_limit text DEFAULT NULL, p_offset text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
-- 090:vet-codes-v1
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
        SELECT DISTINCT ON (p.livestock_id) p.livestock_id, p.health_log_id, p.pdate, p.result
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
               lp.pdate AS palp_date, lp.gestation_days AS palp_gest, la.result AS last_result, la.pdate AS last_date, la.health_log_id AS last_log,
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
                   'last_palpation_code', ci.uterine_code, 'last_palpation_vet_flag', ci.vet_flag,
                   'last_palpation_code_means_pregnant', coalesce(ci.means_pregnant, false),
                   'date_is_stale_import', (v_stale AND e2.palp_date = v_top_d)) AS j
          FROM e2
          LEFT JOIN LATERAL public.fn_repro_palp_code_info(v_tenant, public.fn_repro_palp_text(v_tenant, e2.last_log)) ci ON true
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

CREATE OR REPLACE FUNCTION public.sp_repro_list_unmapped_uterine_codes(
    p_tenant_id text, p_user_email text, p_limit text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
-- 090:vet-codes-v1
DECLARE
    v_tenant integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_limit  integer := least(coalesce(public.fn_repro_int(p_limit), 100), 200);
    v_codes  jsonb;
    v_conf   jsonb;
    v_total  bigint;
    v_known  jsonb;
    v_comp   jsonb;
    v_cfg    jsonb;
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
        SELECT t.token, v.val, v.src, v.n, cardinality(s.tokens) AS ntok, public.fn_repro_code_meaning(v_tenant, t.token) AS meaning
          FROM vals v
         CROSS JOIN LATERAL public.fn_uterine_split(v.val) s
         CROSS JOIN LATERAL unnest(s.tokens) AS t(token)
    ), unk AS (
        -- a code is "unmapped" unless it has a CONFIRMED condition; a row with a NULL condition is known but pending
        SELECT tok.*, EXISTS (SELECT 1 FROM public.repro_condition_codes cp
                               WHERE cp.id_company = v_tenant AND cp.code = tok.token AND cp.repro_condition IS NULL AND cp.meaning IS NULL) AS pending
          FROM tok
         WHERE token NOT IN ('CICLANDO', 'ESTATICA', 'ESTATICO')
           AND meaning IS NULL                 -- a code with a meaning (or the MATRIZ OCUPADA phrase) is KNOWN: see known_meanings
           AND NOT EXISTS (SELECT 1 FROM public.repro_condition_codes cc
                            WHERE cc.id_company = v_tenant AND cc.code = tok.token AND cc.repro_condition IS NOT NULL)
    ), mean AS (
        -- known meanings seen in the data. NR (NOT_EXAMINED) next to other tokens (UNE/NR) is NOT confirmed in that position and is
        -- reported separately in composite_unconfirmed.
        SELECT tok.*, (tok.meaning = 'NOT_EXAMINED' AND tok.ntok > 1) AS composite FROM tok WHERE tok.meaning IS NOT NULL
    ), agg AS (
        SELECT token, bool_or(pending) AS known_pending, sum(n) AS palpations,
               coalesce(sum(n) FILTER (WHERE src = 'CARGA_MASIVA'), 0) AS from_bulk_load,
               coalesce(sum(n) FILTER (WHERE src = 'REGISTRO'), 0) AS from_logged,
               (array_agg(DISTINCT val ORDER BY val))[1:5] AS example_values
          FROM unk GROUP BY token
    )
    SELECT (SELECT count(*) FROM agg),
           coalesce((SELECT jsonb_agg(jsonb_build_object('code', k.token, 'meaning', k.meaning, 'palpations', k.palpations,
                                                         'from_bulk_load', k.from_bulk_load, 'from_logged', k.from_logged) ORDER BY k.palpations DESC, k.token)
                       FROM (SELECT token, meaning, sum(n) AS palpations,
                                    coalesce(sum(n) FILTER (WHERE src = 'CARGA_MASIVA'), 0) AS from_bulk_load,
                                    coalesce(sum(n) FILTER (WHERE src = 'REGISTRO'), 0) AS from_logged
                               FROM mean WHERE NOT composite GROUP BY token, meaning) k), '[]'::jsonb),
           coalesce((SELECT jsonb_agg(jsonb_build_object('code', k.token, 'meaning', k.meaning, 'palpations', k.palpations,
                                                         'example_values', to_jsonb(k.example_values),
                                                         'note', 'NR junto a otro codigo: su significado en esa posicion no esta confirmado.') ORDER BY k.palpations DESC, k.token)
                       FROM (SELECT token, meaning, sum(n) AS palpations, (array_agg(DISTINCT val ORDER BY val))[1:5] AS example_values
                               FROM mean WHERE composite GROUP BY token, meaning) k), '[]'::jsonb),
           coalesce((SELECT jsonb_agg(jsonb_build_object('code', cc.code, 'meaning', cc.meaning, 'source', cc.source,
                                                         'confirmed_by', cc.confirmed_by, 'confirmed_at', cc.confirmed_at) ORDER BY cc.code)
                       FROM public.repro_condition_codes cc WHERE cc.id_company = v_tenant AND cc.meaning IS NOT NULL), '[]'::jsonb),
           coalesce((SELECT jsonb_agg(jsonb_build_object('code', a.token, 'known_pending', a.known_pending, 'palpations', a.palpations,
                                                         'from_bulk_load', a.from_bulk_load, 'from_logged', a.from_logged,
                                                         'example_values', to_jsonb(a.example_values))
                                      ORDER BY a.palpations DESC, a.token)
                       FROM (SELECT * FROM agg ORDER BY palpations DESC, token LIMIT v_limit) a), '[]'::jsonb),
           coalesce((SELECT jsonb_agg(jsonb_build_object('code', cc.code, 'repro_condition', cc.repro_condition,
                                                         'source', cc.source, 'confirmed_by', cc.confirmed_by,
                                                         'confirmed_at', cc.confirmed_at) ORDER BY cc.code)
                       FROM public.repro_condition_codes cc WHERE cc.id_company = v_tenant AND cc.repro_condition IS NOT NULL), '[]'::jsonb)
      INTO v_total, v_known, v_comp, v_cfg, v_codes, v_conf;

    RETURN jsonb_build_object('status', 'ok', 'unmapped_total', v_total, 'unmapped', v_codes, 'confirmed', v_conf,
        'known_meanings', v_known, 'composite_unconfirmed', v_comp, 'meanings_configured', v_cfg,
        'note', 'Codigos (o partes de un codigo compuesto como UNE/NR) sin significado confirmado para esta empresa. '
                || 'known_pending = el codigo ya esta registrado pero su significado espera la confirmacion del veterinario. Los veterinarios los confirman; un ADMIN los registra. Mientras tanto la condicion queda vacia (UNMAPPED), nunca adivinada. '
                || 'known_meanings = codigos con significado (NR no revisada, RP recien parida, NO APTO) y la frase MATRIZ OCUPADA (preñada): ya no son desconocidos. '
                || 'composite_unconfirmed = NR junto a otro codigo (UNE/NR), cuyo significado en esa posicion sigue sin confirmar.');
END;
$$;

CREATE OR REPLACE FUNCTION public.sp_repro_condition_code_set(
    p_tenant_id text, p_user_email text, p_code text, p_repro_condition text, p_source text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
-- 090:vet-codes-v1
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
    IF v_code IN ('OI', 'OD', 'VACIA', 'PRENADA', 'CICLANDO', 'ESTATICA', 'ESTATICO', 'N', 'A', 'MATRIZ OCUPADA') THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Ese texto ya tiene un significado fijo y no se puede redefinir.');
    END IF;

    -- a code that carries a meaning (NR / RP / NO APTO) is not a uterine condition: it cannot also get one
    IF EXISTS (SELECT 1 FROM public.repro_condition_codes cc WHERE cc.id_company = v_tenant AND cc.code = v_code AND cc.meaning IS NOT NULL) THEN
        RETURN jsonb_build_object('status', 'invalid', 'message', 'Ese codigo ya tiene un significado confirmado (no revisada / recien parida / no apta) y no admite una condicion uterina.');
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

CREATE OR REPLACE FUNCTION public.sp_repro_get_dam_history(
    p_tenant_id text, p_user_email text, p_dam_identifier text DEFAULT NULL, p_dam_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
-- 090:vet-codes-v1
DECLARE
    v_tenant   integer := public.fn_repro_ctx(p_tenant_id, p_user_email);
    v_today    date := public.fn_repro_today();
    d          jsonb;
    v_dam      uuid;
    v_dam_j    jsonb;
    v_species  text;
    v_gest     integer;
    v_births   jsonb;
    v_hist     jsonb;
    v_services jsonb;
    v_palps    jsonb;
    v_empadre  jsonb;
    v_pal_n    bigint;
    v_top_d    date;
    v_top_n    bigint;
    v_stale    boolean;
    v_est      jsonb := jsonb_build_object('applies', false);
    v_pdate    date;
    v_pgest    integer;
    v_est_p    date;
    v_last_svc date;
    v_est_s    date;
    v_est_d    date;
    v_src      text;
    v_days_to  integer;
    v_last_any record;
    v_flags    jsonb;
    v_unlinked integer;
    v_birth_no_svc integer;
BEGIN
    d := public.fn_repro_birth_dam(v_tenant, p_dam_id, p_dam_identifier);
    IF d->>'status' <> 'ok' THEN
        RETURN d;
    END IF;
    v_dam := (d->>'dam_id')::uuid;
    v_dam_j := d->'dam';
    v_species := coalesce(v_dam_j->>'species', 'BOVINO');
    SELECT g.days INTO v_gest FROM public.fn_repro_gestation_bounds(v_species) g;

    -- stale import date of the company (more than 50% of >= 10 palpations share one date)
    SELECT count(*) INTO v_pal_n FROM public.fn_repro_palpations(v_tenant);
    SELECT q.pdate, q.n INTO v_top_d, v_top_n
      FROM (SELECT pdate, count(*) AS n FROM public.fn_repro_palpations(v_tenant) GROUP BY pdate ORDER BY count(*) DESC, pdate LIMIT 1) q;
    v_stale := coalesce(v_pal_n >= 10 AND v_top_n::numeric / v_pal_n > 0.5, false);

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.d DESC, x.k), '[]'::jsonb) INTO v_births
      FROM (SELECT be.birth_date AS d, be.id::text AS k,
                   jsonb_build_object('birth_event_id', be.id, 'birth_date', be.birth_date, 'species', be.species, 'calf_sex', be.calf_sex,
                                      'calf_id', be.calf_id, 'calf_rfid_siniiga', c.rfid_siniiga, 'calf_numero_fuego', c.numero_fuego,
                                      'calf_category', c.category, 'calf_status', c.current_status, 'source', be.source,
                                      'reported_by_email', be.reported_by_email, 'created_at', be.created_at,
                                      'linked_service_id', (SELECT e.id FROM public.cattle_breeding_events e
                                                             WHERE e.birth_event_id = be.id AND e.tenant_id = v_tenant LIMIT 1)) AS j
              FROM public.birth_events be
              LEFT JOIN public.cattle_livestock c ON c.id = be.calf_id AND c.tenant_id = v_tenant
             WHERE be.id_company = v_tenant AND be.dam_id = v_dam
             ORDER BY be.birth_date DESC, be.id::text LIMIT 200) x;

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.d DESC, x.k), '[]'::jsonb) INTO v_hist
      FROM (SELECT h.birth_date AS d, h.id::text AS k,
                   jsonb_build_object('historical_birth_id', h.id, 'birth_date', h.birth_date, 'date_precision', h.date_precision,
                                      'calf_sex', h.calf_sex, 'litter_position', h.litter_position, 'source', h.source, 'notes', h.notes,
                                      'voided', v.id IS NOT NULL, 'void_reason', v.reason) AS j
              FROM public.repro_historical_births h
              LEFT JOIN public.repro_historical_birth_voids v ON v.historical_birth_id = h.id AND v.id_company = v_tenant
             WHERE h.id_company = v_tenant AND h.dam_id = v_dam
             ORDER BY h.birth_date DESC, h.id::text LIMIT 200) x;

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.d DESC, x.k), '[]'::jsonb) INTO v_services
      FROM (SELECT e.breeding_date AS d, e.id::text AS k,
                   jsonb_build_object('breeding_event_id', e.id, 'breeding_date', e.breeding_date, 'method', e.method,
                                      'sire_identifier', e.sire_identifier, 'semen_batch', e.semen_batch,
                                      'estimated_due_date', e.estimated_due_date, 'registered_by_email', e.registered_by_email,
                                      'birth_event_id', e.birth_event_id, 'linked_to_birth', e.birth_event_id IS NOT NULL,
                                      'voided', v.id IS NOT NULL, 'notes', e.notes) AS j
              FROM public.cattle_breeding_events e
              LEFT JOIN public.event_voids v ON v.event_table = 'cattle_breeding_events' AND v.event_id = e.id AND v.tenant_id = v_tenant
             WHERE e.tenant_id = v_tenant AND e.livestock_id = v_dam
             ORDER BY e.breeding_date DESC, e.id::text LIMIT 200) x;

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.d DESC, x.k), '[]'::jsonb) INTO v_palps
      FROM (SELECT p.pdate AS d, p.health_log_id::text AS k,
                   jsonb_build_object('health_log_id', p.health_log_id, 'palpation_date', p.pdate, 'result', p.result,
                                      'gestation_days', p.gestation_days,
                                      'repro_condition', pd.repro_condition, 'raw_uterine_code', pd.raw_code,
                                      'mapping_status', pd.mapping_status, 'ovary_side', pd.ovary_side,
                                      'legacy_condicion_utero', h.medicines_json->>'condicion_utero',
                                      'uterine_code', ci.uterine_code, 'vet_flag', ci.vet_flag,
                                      'code_means_pregnant', coalesce(ci.means_pregnant, false),
                                      'code_contradicts_result', (coalesce(ci.means_pregnant, false) AND p.result = 'VACÍA'),
                                      'code_nr_composite', coalesce(ci.nr_composite, false),
                                      'on_stale_import_date', (v_stale AND p.pdate = v_top_d)) AS j
              FROM public.fn_repro_palpations(v_tenant) p
              JOIN public.cattle_health_logs h ON h.id = p.health_log_id
              LEFT JOIN public.palpation_repro_details pd ON pd.health_log_id = p.health_log_id AND pd.id_company = v_tenant
              LEFT JOIN LATERAL public.fn_repro_palp_code_info(v_tenant, coalesce(pd.raw_code, public.fn_repro_norm_code(h.medicines_json->>'condicion_utero'))) ci ON true
             WHERE p.livestock_id = v_dam
             ORDER BY p.pdate DESC, p.health_log_id::text LIMIT 200) x;

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.d DESC, x.k), '[]'::jsonb) INTO v_empadre
      FROM (SELECT en.entry_date AS d, en.id::text AS k,
                   jsonb_build_object('entry_id', en.id, 'entry_date', en.entry_date, 'bull_id', en.bull_id, 'method', en.method,
                                      'warning_code', en.warning_code, 'registered_by_email', en.registered_by_email,
                                      'voided', vo.id IS NOT NULL, 'void_reason', vo.reason) AS j
              FROM public.repro_empadre_entries en
              LEFT JOIN public.repro_empadre_voids vo ON vo.entry_id = en.id AND vo.id_company = v_tenant
             WHERE en.id_company = v_tenant AND en.heifer_id = v_dam
             ORDER BY en.entry_date DESC, en.id::text LIMIT 200) x;

    -- expected calving: only for a PREÑADA female
    IF v_dam_j->>'current_status' = 'PREÑADA' AND v_gest IS NOT NULL THEN
        SELECT p.pdate, p.gestation_days INTO v_pdate, v_pgest
          FROM public.fn_repro_palpations(v_tenant) p
         WHERE p.livestock_id = v_dam AND p.result = 'PREÑADA'
         ORDER BY p.pdate DESC, p.created_at DESC LIMIT 1;
        IF v_pdate IS NOT NULL AND v_pgest IS NOT NULL AND v_pgest <= v_gest THEN v_est_p := v_pdate + (v_gest - v_pgest); END IF;
        SELECT max(e.breeding_date) INTO v_last_svc
          FROM public.cattle_breeding_events e
         WHERE e.tenant_id = v_tenant AND e.livestock_id = v_dam AND e.breeding_date <= v_today
           AND NOT EXISTS (SELECT 1 FROM public.event_voids v WHERE v.event_table = 'cattle_breeding_events' AND v.event_id = e.id AND v.tenant_id = v_tenant);
        IF v_last_svc IS NOT NULL THEN v_est_s := v_last_svc + v_gest; END IF;
        v_est_d := coalesce(v_est_p, v_est_s);
        v_src := CASE WHEN v_est_p IS NOT NULL THEN 'PALPACION' WHEN v_est_s IS NOT NULL THEN 'SERVICIO' END;
        v_days_to := v_est_d - v_today;
        v_est := jsonb_build_object('applies', true, 'estimated_calving_date', v_est_d, 'estimate_source', v_src, 'days_to_calving', v_days_to,
            'bucket', CASE WHEN v_est_d IS NULL THEN 'no_estimate' WHEN v_days_to >= 0 THEN 'upcoming' WHEN v_days_to >= -60 THEN 'overdue' ELSE 'stale_data' END,
            'palpation_date', v_pdate, 'gestation_days_at_palpation', v_pgest, 'last_service_date', v_last_svc,
            'note', 'stale_data = estimado vencido por mas de 60 dias: dato viejo, no un parto proximo ni atrasado.');
    ELSE
        v_est := jsonb_build_object('applies', false, 'reason', CASE WHEN v_dam_j->>'current_status' <> 'PREÑADA' THEN 'La hembra no esta PREÑADA.' ELSE 'Sin datos de gestacion para la especie.' END);
    END IF;

    -- quality flags
    SELECT p.result, p.pdate INTO v_last_any
      FROM public.fn_repro_palpations(v_tenant) p WHERE p.livestock_id = v_dam ORDER BY p.pdate DESC, p.created_at DESC LIMIT 1;
    SELECT count(*) INTO v_unlinked
      FROM public.cattle_breeding_events e
     WHERE e.tenant_id = v_tenant AND e.livestock_id = v_dam AND e.birth_event_id IS NULL
       AND e.breeding_date <= v_today - coalesce((SELECT g.hi FROM public.fn_repro_gestation_bounds(v_species) g), 328)
       AND NOT EXISTS (SELECT 1 FROM public.event_voids v WHERE v.event_table = 'cattle_breeding_events' AND v.event_id = e.id AND v.tenant_id = v_tenant);
    SELECT count(*) INTO v_birth_no_svc
      FROM public.birth_events be
     WHERE be.id_company = v_tenant AND be.dam_id = v_dam
       AND NOT EXISTS (SELECT 1 FROM public.cattle_breeding_events e WHERE e.birth_event_id = be.id AND e.tenant_id = v_tenant);
    v_flags := jsonb_build_object(
        'stale_import_date_company', jsonb_build_object('flag', v_stale, 'date', CASE WHEN v_stale THEN v_top_d END),
        'palpations_on_stale_import_date', (SELECT count(*) FROM jsonb_array_elements(v_palps) e WHERE (e->>'on_stale_import_date')::boolean),
        'services_older_than_gestation_still_unlinked', v_unlinked,
        'births_without_linked_service', v_birth_no_svc,
        'palpations_with_unmapped_code', (SELECT count(*) FROM jsonb_array_elements(v_palps) e WHERE e->>'mapping_status' = 'UNMAPPED'),
        -- display only: a stored code that means PREÑADA (MATRIZ OCUPADA) next to a stored result VACÍA. Nothing is corrected.
        'palpation_code_contradicts_result', (SELECT count(*) FROM jsonb_array_elements(v_palps) e WHERE (e->>'code_contradicts_result')::boolean),
        'palpations_with_vet_flag', (SELECT count(*) FROM jsonb_array_elements(v_palps) e WHERE e->>'vet_flag' IS NOT NULL),
        'status_vs_last_palpation_mismatch',
            (v_last_any.result IS NOT NULL AND ((v_dam_j->>'current_status' = 'PREÑADA' AND v_last_any.result = 'VACÍA')
                                              OR (v_dam_j->>'current_status' = 'VACÍA' AND v_last_any.result = 'PREÑADA'))),
        'sections_truncated_at_200', (jsonb_array_length(v_births) = 200 OR jsonb_array_length(v_hist) = 200 OR jsonb_array_length(v_services) = 200
                                      OR jsonb_array_length(v_palps) = 200 OR jsonb_array_length(v_empadre) = 200));

    RETURN jsonb_build_object('status', 'ok', 'dam', v_dam_j, 'current_status', v_dam_j->>'current_status',
        'births', v_births, 'historical_births', v_hist, 'services', v_services, 'palpations', v_palps, 'empadre_entries', v_empadre,
        'expected_calving', v_est, 'quality_flags', v_flags,
        'note', 'Los partos historicos no tienen cria registrada. Un servicio sin birth_event_id no esta ligado a ningun parto (no se adivina). on_stale_import_date = la fecha de esa palpacion es la de una carga masiva, no una palpacion real.');
END;
$$;

-- 4) Sanity ---------------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY['fn_repro_code_meaning', 'fn_repro_palp_text', 'fn_repro_palp_code_info', 'fn_repro_diagnosis_kind',
                        'sp_repro_log_palpation_batch', 'sp_repro_list_palpation_due', 'sp_repro_list_upcoming_calvings',
                        'sp_repro_list_unmapped_uterine_codes', 'sp_repro_condition_code_set', 'sp_repro_get_dam_history']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '090: missing functions: %', v_missing;
    END IF;
    IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (ARRAY[
            'fn_repro_diagnosis_kind', 'sp_repro_log_palpation_batch', 'sp_repro_list_palpation_due', 'sp_repro_list_upcoming_calvings',
            'sp_repro_list_unmapped_uterine_codes', 'sp_repro_condition_code_set', 'sp_repro_get_dam_history'])) <> 7 THEN
        RAISE EXCEPTION '090: a replaced function now has more than one overload';
    END IF;
    IF (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.prosrc LIKE '%090:vet-codes-v1%') <> 7 THEN
        RAISE EXCEPTION '090: expected the marker in exactly 7 bodies';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'repro_condition_codes'
                      AND column_name = 'meaning' AND is_nullable = 'YES' AND column_default IS NULL) THEN
        RAISE EXCEPTION '090: repro_condition_codes.meaning must exist, nullable, without a default';
    END IF;
    RAISE NOTICE '090: OK';
END $$;

\if :{?embedded}
\echo '*** 090 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 090 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
