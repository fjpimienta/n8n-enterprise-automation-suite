-- births_names_check.sql — runs the NEW node queries of register_birth_checked, births_batch_preview and births_batch_register
-- (the ones that add lot_name_resolved / upp_name_resolved) against the QA fixtures of company 3, BEFORE the MCP server is imported.
--
-- ##########################################################################################################################
-- #  UNTESTED: nobody has run this file. It is meant for the LOCAL rehearsal database ONLY (hosting3m_rehearsal) and it         #
-- #  refuses to run anywhere else. It writes nothing that survives: everything happens inside ONE transaction that ends in       #
-- #  ROLLBACK, and a before/after count proves it. It touches company 3 ("Rancho El Palomar") and no other company.            #
-- ##########################################################################################################################
--
-- The three query texts below are the node queries BYTE FOR BYTE (check_repro_consistency.js compares them with the MCP export), run through
-- EXECUTE ... USING, which binds $1..$n like the n8n Postgres node does. The arguments are TEXT (as the node sends them: '' for an omitted value).
-- What this does NOT prove: the n8n node itself. After this passes, still execute each node once in the LOCAL n8n with real values (root CLAUDE.md).
--
-- Needs the qa_fixtures.sql data of the run you pass (default 5 = "tanda 5"): the dams B1-B5, B2, X1, X2, the lots and the two UPPs. The dams used here
-- must have NO births yet (the file aborts otherwise: run it before the QA dialogs, or use a fresh run of qa_fixtures.sql).
--
-- Usage:   psql -d hosting3m_rehearsal -X -v ON_ERROR_STOP=1 -v run=5 -f births_names_check.sql
-- Output:  one table (n, test, ok, detail), then "ALL n TESTS OK" or "FAILED: k", then a before/after count proving that nothing was left behind.

\set ON_ERROR_STOP on
\if :{?run}
\else
\set run 5
\endif

-- guard 1: only the rehearsal database
SELECT current_database() = 'hosting3m_rehearsal' AS db_ok \gset
\if :db_ok
\else
\echo 'ABORT: this file runs only on the database hosting3m_rehearsal.'
\quit
\endif

-- counts BEFORE (company 3): the proof that nothing is left behind
SELECT (SELECT count(*) FROM public.cattle_livestock WHERE tenant_id = 3) AS n_animals_before,
       (SELECT count(*) FROM public.birth_events WHERE id_company = 3) AS n_births_before,
       (SELECT count(*) FROM public.cattle_weight_logs w JOIN public.cattle_livestock l ON l.id = w.livestock_id WHERE l.tenant_id = 3) AS n_weights_before \gset

BEGIN;

-- guard 2: company 3 is the test company, the run exists, the dams are fresh
SELECT set_config('qa.run', :'run', true);
DO $guard$
DECLARE
    v_name text;
    v_run  text := current_setting('qa.run');
    v_n    integer;
BEGIN
    SELECT company_name INTO v_name FROM public.companys WHERE id_company = 3 AND is_active IS TRUE;
    IF v_name IS DISTINCT FROM 'Rancho El Palomar' THEN
        RAISE EXCEPTION 'ABORT: company 3 is "%" here, not "Rancho El Palomar".', v_name;
    END IF;
    SELECT count(*) INTO v_n FROM public.production_unit_lots l JOIN public.production_units pu ON pu.id = l.production_unit_id
     WHERE l.id_company = 3 AND pu.id_company = 3 AND l.lot_name IN ('QA5R' || v_run || ' Lote Maternidad', 'QA5R' || v_run || ' Lote Repetido', 'QA5R' || v_run || ' Lote Sur');
    IF v_n <> 4 THEN
        RAISE EXCEPTION 'ABORT: found % of the 4 QA lots of run % in company 3: apply qa_fixtures.sql -v run=% first.', v_n, v_run, v_run;
    END IF;
    SELECT count(*) INTO v_n FROM public.birth_events be JOIN public.cattle_livestock d ON d.id = be.dam_id
     WHERE d.tenant_id = 3 AND d.rfid_siniiga IN ('9999' || v_run || '00007', '9999' || v_run || '00008', '9999' || v_run || '00009', '9999' || v_run || '00010',
                                                   '9999' || v_run || '00011', '9999' || v_run || '00036', '9999' || v_run || '00037');
    IF v_n > 0 THEN
        RAISE EXCEPTION 'ABORT: % birth(s) already exist for the dams this file uses (B1-B5, X1, X2 of run %): run it before the QA dialogs.', v_n, v_run;
    END IF;
END
$guard$;

-- the member (an active ADMIN of company 3), the ids and the tags: psql variables, never printed
SELECT uc.email AS qa_email FROM public.user_companies uc WHERE uc.id_company = 3 AND uc.is_active AND uc.role = 'ADMIN' ORDER BY uc.email LIMIT 1 \gset
SELECT l.id AS lot_rep_sur, pu.id AS upp_sur FROM public.production_unit_lots l JOIN public.production_units pu ON pu.id = l.production_unit_id
 WHERE l.id_company = 3 AND l.lot_name = 'QA5R' || :'run' || ' Lote Repetido' AND pu.ranch_name = 'QA5R' || :'run' || ' UPP Sur' \gset
SELECT l.id AS lot_sur FROM public.production_unit_lots l WHERE l.id_company = 3 AND l.lot_name = 'QA5R' || :'run' || ' Lote Sur' \gset
SELECT l.id AS lot_mat, pu.id AS upp_norte FROM public.production_unit_lots l JOIN public.production_units pu ON pu.id = l.production_unit_id
 WHERE l.id_company = 3 AND l.lot_name = 'QA5R' || :'run' || ' Lote Maternidad' AND pu.ranch_name = 'QA5R' || :'run' || ' UPP Norte' \gset
SELECT '9999' || :'run' || '00007' AS d_b1, '9999' || :'run' || '00008' AS d_b2, '9999' || :'run' || '00009' AS d_b3, '9999' || :'run' || '00010' AS d_b4,
       '9999' || :'run' || '00011' AS d_b5, '9999' || :'run' || '00036' AS d_x1, '9999' || :'run' || '00037' AS d_x2, 'QA5R' || :'run' || '-DUP' AS d_dup \gset

CREATE TEMP TABLE q (name text PRIMARY KEY, sql text NOT NULL);
CREATE TEMP TABLE res (label text PRIMARY KEY, j jsonb);
CREATE TEMP TABLE t (n serial, test text, ok boolean, detail text);

-- ===== the node queries, verbatim =====
INSERT INTO q VALUES ('rbc', $q$WITH r AS (
  SELECT public.sp_repro_register_birth($1::text, $2::text, $3::text, $4::text, $5::text, $6::text, $7::text, $8::text, $9::text, $10::text, $11::text, $12::text, $13::text) AS result
)
SELECT CASE WHEN r.result->'lot_id_resolved' IS NOT NULL
  THEN r.result || jsonb_build_object('lot_name_resolved', (SELECT l.lot_name FROM public.production_unit_lots l WHERE l.id = NULLIF(r.result->>'lot_id_resolved', '')::uuid AND l.id_company = public.fn_repro_int($1::text)),
                                      'upp_name_resolved', (SELECT pu.ranch_name FROM public.production_units pu WHERE pu.id = NULLIF(r.result->>'production_unit_id_resolved', '')::uuid AND pu.id_company = public.fn_repro_int($1::text)))
  ELSE r.result END AS result
FROM r;$q$);

INSERT INTO q VALUES ('preview', $q$WITH r AS (
  SELECT public.sp_repro_births_batch_preview($1::text, $2::text, $3::text, $4::text) AS result
)
SELECT CASE WHEN jsonb_typeof(r.result->'lines') = 'array'
  THEN jsonb_set(r.result, '{lines}', COALESCE((
    SELECT jsonb_agg(CASE WHEN t.e->>'status' = 'ok'
                          THEN t.e || jsonb_build_object('lot_id_resolved', w.lot_id, 'production_unit_id_resolved', w.upp_id,
                                                       'lot_name_resolved', (SELECT l.lot_name FROM public.production_unit_lots l WHERE l.id = w.lot_id AND l.id_company = public.fn_repro_int($1::text)),
                                                       'upp_name_resolved', (SELECT pu.ranch_name FROM public.production_units pu WHERE pu.id = w.upp_id AND pu.id_company = public.fn_repro_int($1::text)))
                          ELSE t.e END ORDER BY t.o)
      FROM jsonb_array_elements(r.result->'lines') WITH ORDINALITY AS t(e, o)
      CROSS JOIN LATERAL (SELECT
          CASE WHEN t.e->>'status' = 'ok' THEN COALESCE(NULLIF(t.e->>'lot_id', '')::uuid,
               (SELECT c.lot_id FROM public.cattle_livestock c WHERE c.id = NULLIF(t.e->>'dam_id', '')::uuid AND c.tenant_id = public.fn_repro_int($1::text))) END AS lot_id,
          CASE WHEN t.e->>'status' = 'ok' THEN COALESCE(
               (SELECT x.production_unit_id FROM public.production_unit_lots x WHERE x.id = NULLIF(t.e->>'lot_id', '')::uuid AND x.id_company = public.fn_repro_int($1::text)),
               (SELECT c.production_unit_id FROM public.cattle_livestock c WHERE c.id = NULLIF(t.e->>'dam_id', '')::uuid AND c.tenant_id = public.fn_repro_int($1::text)),
               NULLIF(t.e->>'production_unit_id', '')::uuid) END AS upp_id
      ) w), '[]'::jsonb))
  ELSE r.result END AS result
FROM r;$q$);

INSERT INTO q VALUES ('register', $q$WITH r AS (
  SELECT public.sp_repro_births_batch_register($1::text, $2::text, $3::text, $4::text) AS result
)
SELECT CASE WHEN jsonb_typeof(r.result->'results') = 'array'
  THEN jsonb_set(r.result, '{results}', COALESCE((
    SELECT jsonb_agg(CASE WHEN e->'lot_id_resolved' IS NOT NULL
                          THEN e || jsonb_build_object('lot_name_resolved', (SELECT l.lot_name FROM public.production_unit_lots l WHERE l.id = NULLIF(e->>'lot_id_resolved', '')::uuid AND l.id_company = public.fn_repro_int($1::text)),
                                                       'upp_name_resolved', (SELECT pu.ranch_name FROM public.production_units pu WHERE pu.id = NULLIF(e->>'production_unit_id_resolved', '')::uuid AND pu.id_company = public.fn_repro_int($1::text)))
                          ELSE e END ORDER BY o)
      FROM jsonb_array_elements(r.result->'results') WITH ORDINALITY AS t(e, o)), '[]'::jsonb))
  ELSE r.result END AS result
FROM r;$q$);

-- EXECUTE ... USING with a fixed number of text arguments (the node sends text; '' when a value is omitted)
CREATE FUNCTION pg_temp.run13(p_name text, a text[]) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_sql text; v_j jsonb;
BEGIN
    SELECT sql INTO v_sql FROM pg_temp.q WHERE name = p_name;
    EXECUTE v_sql INTO v_j USING a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13];
    RETURN v_j;
END
$f$;
CREATE FUNCTION pg_temp.run4(p_name text, a text[]) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_sql text; v_j jsonb;
BEGIN
    SELECT sql INTO v_sql FROM pg_temp.q WHERE name = p_name;
    EXECUTE v_sql INTO v_j USING a[1], a[2], a[3], a[4];
    RETURN v_j;
END
$f$;

-- ===== setup inside the transaction (rolled back): B4, B5 and X2 get a lot / UPP of their own, to exercise "the calf takes the dam's" =====
UPDATE public.cattle_livestock SET lot_id = :'lot_mat', production_unit_id = :'upp_norte' WHERE tenant_id = 3 AND rfid_siniiga IN (:'d_b4', :'d_b5', :'d_x2');

-- ===== register_birth_checked =====
-- A: explicit lot "Lote Repetido" of the SOUTH UPP (the neighbour row is "Lote Sur": the failure of round 3)
INSERT INTO res SELECT 'A', pg_temp.run13('rbc', ARRAY['3', :'qa_email', 'HEMBRA', :'d_b1', '', '', '35', :'lot_rep_sur', :'upp_sur', '', '', '', '']);
-- B: no lot, the dam has none
INSERT INTO res SELECT 'B', pg_temp.run13('rbc', ARRAY['3', :'qa_email', 'MACHO', :'d_b3', '', '', '', '', '', '', '', '', '']);
-- C: no lot, the dam has "Lote Maternidad" / "UPP Norte": the calf takes them
INSERT INTO res SELECT 'C', pg_temp.run13('rbc', ARRAY['3', :'qa_email', 'HEMBRA', :'d_b4', '', '', '', '', '', '', '', '', '']);
-- D: only a UPP (Sur) and the dam already has a UPP (Norte): the database ignores the UPP asked for -> the name shows it
INSERT INTO res SELECT 'D', pg_temp.run13('rbc', ARRAY['3', :'qa_email', 'MACHO', :'d_b5', '', '', '', '', :'upp_sur', '', '', '', '']);
-- E: ambiguous dam (two animals share the fire number): the answer is the untouched 'ambiguous' object, with no name keys
INSERT INTO res SELECT 'E', pg_temp.run13('rbc', ARRAY['3', :'qa_email', 'HEMBRA', :'d_dup', '', '', '', '', '', '', '', '', '']);

-- ===== births_batch_preview, then births_batch_register with the SAME items =====
SELECT jsonb_build_array(
         jsonb_build_object('dam_identifier', :'d_b2', 'calf_sex', 'HEMBRA', 'lot_id', :'lot_rep_sur', 'production_unit_id', :'upp_sur'),
         jsonb_build_object('dam_identifier', :'d_x1', 'calf_sex', 'MACHO'),
         jsonb_build_object('dam_identifier', :'d_x2', 'calf_sex', 'HEMBRA'))::text AS items_ok \gset
INSERT INTO res SELECT 'P', pg_temp.run4('preview', ARRAY['3', :'qa_email', :'items_ok', '']);
-- a preview with a line that cannot be resolved and a lot id that is not a uuid: no exception, no names on those lines
SELECT jsonb_build_array(
         jsonb_build_object('dam_identifier', 'NO-SUCH-DAM-' || :'run', 'calf_sex', 'MACHO'),
         jsonb_build_object('dam_identifier', :'d_x1', 'calf_sex', 'MACHO', 'lot_id', 'not-a-uuid'))::text AS items_bad \gset
INSERT INTO res SELECT 'PB', pg_temp.run4('preview', ARRAY['3', :'qa_email', :'items_bad', '']);
INSERT INTO res SELECT 'R', pg_temp.run4('register', ARRAY['3', :'qa_email', :'items_ok', '']);

-- ===== checks =====
INSERT INTO t (test, ok, detail)
SELECT 'A  register_birth_checked: explicit "Lote Repetido" of UPP Sur -> that lot and that UPP, not the neighbour "Lote Sur"',
       j->>'status' = 'recorded' AND j->>'lot_id_resolved' = :'lot_rep_sur' AND j->>'lot_id_resolved' <> :'lot_sur'
       AND j->>'lot_name_resolved' = 'QA5R' || :'run' || ' Lote Repetido' AND j->>'upp_name_resolved' = 'QA5R' || :'run' || ' UPP Sur', j->>'lot_name_resolved' || ' / ' || coalesce(j->>'upp_name_resolved', 'null')
  FROM res WHERE label = 'A';
INSERT INTO t (test, ok, detail)
SELECT 'B  register_birth_checked: no lot and the dam has none -> the keys are there and are null',
       j->>'status' = 'recorded' AND j ? 'lot_name_resolved' AND j ? 'upp_name_resolved' AND j->'lot_name_resolved' = 'null'::jsonb AND j->'upp_name_resolved' = 'null'::jsonb, j::text
  FROM res WHERE label = 'B';
INSERT INTO t (test, ok, detail)
SELECT 'C  register_birth_checked: no lot, the dam has "Lote Maternidad" / "UPP Norte" -> the calf takes both and the names say so',
       j->>'status' = 'recorded' AND j->>'lot_name_resolved' = 'QA5R' || :'run' || ' Lote Maternidad' AND j->>'upp_name_resolved' = 'QA5R' || :'run' || ' UPP Norte', j->>'lot_name_resolved' || ' / ' || coalesce(j->>'upp_name_resolved', 'null')
  FROM res WHERE label = 'C';
INSERT INTO t (test, ok, detail)
SELECT 'D  register_birth_checked: only UPP Sur asked and the dam has UPP Norte -> upp_name_resolved shows Norte (what was really written)',
       j->>'status' = 'recorded' AND j->>'upp_name_resolved' = 'QA5R' || :'run' || ' UPP Norte', coalesce(j->>'upp_name_resolved', 'null')
  FROM res WHERE label = 'D';
INSERT INTO t (test, ok, detail)
SELECT 'E  register_birth_checked: ambiguous dam -> status ambiguous with candidates and NO name keys',
       j->>'status' = 'ambiguous' AND NOT (j ? 'lot_name_resolved') AND NOT (j ? 'upp_name_resolved') AND jsonb_array_length(j->'candidates') = 2, j->>'status'
  FROM res WHERE label = 'E';
INSERT INTO t (test, ok, detail)
SELECT 'P1 births_batch_preview: 3 ok lines, can_register true, names = Lote Repetido/UPP Sur, null/null, Lote Maternidad/UPP Norte (the last one inherited from the dam)',
       j->>'status' = 'ok' AND (j->>'can_register')::boolean AND jsonb_array_length(j->'lines') = 3
       AND j->'lines'->0->>'lot_name_resolved' = 'QA5R' || :'run' || ' Lote Repetido' AND j->'lines'->0->>'upp_name_resolved' = 'QA5R' || :'run' || ' UPP Sur'
       AND j->'lines'->1->'lot_name_resolved' = 'null'::jsonb AND j->'lines'->1->'upp_name_resolved' = 'null'::jsonb
       AND j->'lines'->2->>'lot_name_resolved' = 'QA5R' || :'run' || ' Lote Maternidad' AND j->'lines'->2->>'upp_name_resolved' = 'QA5R' || :'run' || ' UPP Norte', j->>'status'
  FROM res WHERE label = 'P';
INSERT INTO t (test, ok, detail)
SELECT 'P2 births_batch_preview: a line that cannot be resolved and a lot id that is not a uuid -> no exception, those lines carry no names, can_register false',
       j->>'status' = 'ok' AND NOT (j->>'can_register')::boolean AND jsonb_array_length(j->'lines') = 2
       AND NOT (j->'lines'->0 ? 'lot_name_resolved') AND NOT (j->'lines'->1 ? 'lot_name_resolved'), j->'lines'->0->>'status' || ' / ' || (j->'lines'->1->>'status')
  FROM res WHERE label = 'PB';
INSERT INTO t (test, ok, detail)
SELECT 'R1 births_batch_register: 3 recorded, names per line = the names the preview announced (same order)',
       r.j->>'status' = 'recorded' AND (r.j->>'written')::int = 3 AND m.n = 3 AND m.same, m.n || ' lines compared'
  FROM res r JOIN res p ON p.label = 'P'
  CROSS JOIN LATERAL (SELECT count(*) AS n,
                             coalesce(bool_and(a->>'lot_name_resolved' IS NOT DISTINCT FROM b->>'lot_name_resolved' AND a->>'upp_name_resolved' IS NOT DISTINCT FROM b->>'upp_name_resolved'), false) AS same
                        FROM jsonb_array_elements(p.j->'lines') WITH ORDINALITY x(a, o)
                        JOIN jsonb_array_elements(r.j->'results') WITH ORDINALITY y(b, o2) ON y.o2 = x.o) m
 WHERE r.label = 'R';
INSERT INTO t (test, ok, detail)
SELECT 'R2 what the database really holds: for the 7 calves written here (A-D and the batch), the lot and the UPP of the row = the names the tool returned',
       count(*) = 7, count(*) || ' of 7 match'
  FROM (SELECT j AS x FROM res WHERE label IN ('A', 'B', 'C', 'D')
        UNION ALL SELECT b FROM res r, jsonb_array_elements(r.j->'results') b WHERE r.label = 'R') z
  JOIN public.cattle_livestock c ON c.id = (z.x->>'calf_id')::uuid
  LEFT JOIN public.production_unit_lots l ON l.id = c.lot_id
  LEFT JOIN public.production_units pu ON pu.id = c.production_unit_id
 WHERE l.lot_name IS NOT DISTINCT FROM z.x->>'lot_name_resolved' AND pu.ranch_name IS NOT DISTINCT FROM z.x->>'upp_name_resolved';

SELECT n, test, ok, detail FROM t ORDER BY n;
SELECT CASE WHEN count(*) FILTER (WHERE NOT ok) = 0 THEN 'ALL ' || count(*) || ' TESTS OK' ELSE 'FAILED: ' || count(*) FILTER (WHERE NOT ok) || ' of ' || count(*) END AS verdict FROM t;

ROLLBACK;

-- proof that nothing was left behind (company 3, before vs after)
SELECT (SELECT count(*) FROM public.cattle_livestock WHERE tenant_id = 3) = :n_animals_before AS animals_unchanged,
       (SELECT count(*) FROM public.birth_events WHERE id_company = 3) = :n_births_before AS births_unchanged,
       (SELECT count(*) FROM public.cattle_weight_logs w JOIN public.cattle_livestock l ON l.id = w.livestock_id WHERE l.tenant_id = 3) = :n_weights_before AS weights_unchanged;
