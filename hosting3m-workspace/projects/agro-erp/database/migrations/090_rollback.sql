-- 090 ROLLBACK. No DROP / DELETE / TRUNCATE / UPDATE of rows. It puts the 7 bodies created by 086 and 088 back, byte for byte
-- (the md5 of each is verified at the end against the value the owner checked on 2026-10-28), so the tools answer exactly as they did
-- before 090.
-- LEFT IN PLACE on purpose: the column repro_condition_codes.meaning with its two CHECKs and every meaning the seed set, and the three
-- new helpers (fn_repro_code_meaning, fn_repro_palp_text, fn_repro_palp_code_info). The 086 / 088 bodies do not read any of them.
-- Note: with the original sp_repro_condition_code_set a re-confirmation of a code that has a meaning would hit the CHECK
-- ck_cond_code_meaning_no_condition (a raw database error instead of a friendly answer); nobody does that by accident, and the
-- seed's undo clears the meanings first if you want them gone.
-- Re-applying 090 (CREATE OR REPLACE / IF NOT EXISTS) restores the new behaviour and keeps the rows.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 090_rollback.sql                -> dry run
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 090_rollback.sql  -> commit
-- Then: 090_state_check.sql -v expect=rolled_back

\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;

DO $$
DECLARE
    g record;
    v_oid oid;
BEGIN
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
            RAISE EXCEPTION 'ABORT: % not found - 086 / 088 were never applied here.', g.sig;
        END IF;
        IF md5(pg_get_functiondef(v_oid)) <> g.expected
           AND (SELECT p.prosrc FROM pg_proc p WHERE p.oid = v_oid) NOT LIKE '%090:vet-codes-v1%' THEN
            RAISE EXCEPTION 'ABORT: the live % is neither the 086 / 088 body nor the 090 body (md5 %). Not touching it.',
                g.sig, md5(pg_get_functiondef(v_oid));
        END IF;
    END LOOP;
END $$;

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

CREATE OR REPLACE FUNCTION public.sp_repro_get_dam_history(
    p_tenant_id text, p_user_email text, p_dam_identifier text DEFAULT NULL, p_dam_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
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
                                      'on_stale_import_date', (v_stale AND p.pdate = v_top_d)) AS j
              FROM public.fn_repro_palpations(v_tenant) p
              JOIN public.cattle_health_logs h ON h.id = p.health_log_id
              LEFT JOIN public.palpation_repro_details pd ON pd.health_log_id = p.health_log_id AND pd.id_company = v_tenant
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

DO $$
DECLARE
    g record;
BEGIN
    FOR g IN SELECT * FROM (VALUES
        ('public.fn_repro_diagnosis_kind(text,integer)', 'c14027757d85c745756a704ced03ab5f'),
        ('public.sp_repro_log_palpation_batch(text,text,text,text,text)', '845854fd40df5406c8c4f1f90fd558c9'),
        ('public.sp_repro_list_palpation_due(text,text,text,text,text)', 'd04d1f85f5d3aadae7d7bf1b8df73518'),
        ('public.sp_repro_list_upcoming_calvings(text,text,text,text,text)', '0fab0832c5818b6be09cd94efb826ddb'),
        ('public.sp_repro_list_unmapped_uterine_codes(text,text,text)', '4f682a0ea099c051d5b3b95a8eb553d0'),
        ('public.sp_repro_condition_code_set(text,text,text,text,text)', '46e720910cf97de3eb3921fb83f820b3'),
        ('public.sp_repro_get_dam_history(text,text,text,text)', '79927c5b2478ae8f31307b9eb89d97d7')
    ) AS v (sig, expected) LOOP
        IF md5(pg_get_functiondef(to_regprocedure(g.sig))) <> g.expected THEN
            RAISE EXCEPTION '090 rollback: % does not match the 086 / 088 body (md5 %)', g.sig, md5(pg_get_functiondef(to_regprocedure(g.sig)));
        END IF;
    END LOOP;
    RAISE NOTICE '090 rollback: OK (7 bodies restored)';
END $$;

\if :apply
COMMIT;
\echo '*** 090 ROLLBACK COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
