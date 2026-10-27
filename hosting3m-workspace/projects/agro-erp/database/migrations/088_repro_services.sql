-- 088_repro_services.sql
-- Reproduction tracking, phase 4b: services linked to births, hardened service / void procedures, dam history.
--
-- REQUIRES 084, 085, 086 and 087. It aborts when they are missing, and it aborts when the live body of sp_log_breeding_event or
-- sp_void_event is not the one verified in production on 2026-10-28 (md5 below): a replacement is never written over an unknown body.
--
-- What it changes (everything else is untouched):
--   * cattle_breeding_events gets a nullable birth_event_id (additive, FK to birth_events) and a guard trigger. The ONLY update
--     the table ever accepts from now on is setting birth_event_id from NULL to a value, once, to a birth of the SAME company and
--     the SAME dam, for a service that is not voided (P0097 for anything else, P0096 for another company). Inserts cannot carry a link.
--   * fn_repro_link_birth_service(birth, company): links the dam's service to a registered birth ONLY when exactly one candidate falls
--     inside the species' plausible gestation window (candidates exclude voided services and services already linked); otherwise the
--     service stays unlinked and the answer says why (no_candidate / ambiguous). sp_register_birth_event (087) calls it after a birth.
--     Windows (days between the service and the birth; both name sets are mapped: EQUINO = EQUIDO, OVINO = BORREGO):
--       BOVINO 283 (238-328) | OVINO / BORREGO 152 (132-172) | EQUINO / EQUIDO 340 (295-385) | BUFALO 310 (280-340)
--     No backfill: old services are never linked automatically.
--   * sp_log_breeding_event (SAME 8-parameter signature, CREATE OR REPLACE):
--       - the reporter must be an ACTIVE member (P0001); a NULL / blank / non-member e-mail is refused (every caller sends one)
--       - the sire is resolved inside the company only: several matches => {success:false, status:'ambiguous', candidates};
--         it resolves but is not a TORO / BECERRO_TORETE (or is the female herself) => {success:false, status:'rejected'};
--         it does not resolve => kept as free text with the warning sire_not_resolved (a sire of ANOTHER company cannot be told
--         apart from an unknown name without a cross-company lookup, so it is the same warning, never a leak)
--       - INSEMINACION_ARTIFICIAL without semen_batch => warning semen_batch_missing (never blocks)
--       - exact retry (same female, date, method and sire within 5 minutes, not voided) => {success:true, duplicate_skipped:true}
--       - the existing errors (method, unknown / ambiguous / sold female) are unchanged
--   * sp_void_event (SAME 5-parameter signature, CREATE OR REPLACE):
--       - the voider must be an ACTIVE member (P0001); a NULL / blank / non-member e-mail is refused
--       - a service linked to a birth answers {success:false, status:'rejected', code:'LINKED_TO_BIRTH', birth_event_id}
--       - the whitelist, one-void-per-event (P0017) and "no side effects reversed" are unchanged
-- New tool: sp_repro_get_dam_history -> get_dam_reproductive_history (read).
--
-- Fail-closed (fn_repro_ctx from 084) for the new tool: non-member, bad tenant, blank e-mail, palm company RAISE (P0001 / P0094).
-- Error codes: P0095 / P0096 from 085, P0097 service link guard (new).
-- Rollback: 088_rollback.sql (restores the ORIGINAL bodies of both procedures, disables the tool; drops nothing).
-- State: 088_state_check.sql. Tests: 088_tests.sql.
--
-- Usage (dry run is the default):
--   psql -v ON_ERROR_STOP=1 -f 088_repro_services.sql                 -> dry run (rolled back)
--   psql -v ON_ERROR_STOP=1 -v apply=true -f 088_repro_services.sql   -> commit
-- 088_tests.sql includes this file with `embedded` set.

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
    v_brd oid := to_regprocedure('public.sp_log_breeding_event(character varying,integer,date,character varying,character varying,character varying,character varying,text)');
    v_void oid := to_regprocedure('public.sp_void_event(character varying,uuid,integer,character varying,text)');
BEGIN
    IF to_regprocedure('public.fn_repro_ctx(text,text)') IS NULL OR to_regprocedure('public.fn_trg_empadre_append_only()') IS NULL
       OR to_regprocedure('public.fn_repro_palpations(integer)') IS NULL OR to_regprocedure('public.fn_repro_is_member(integer,text)') IS NULL
       OR to_regclass('public.repro_historical_births') IS NULL THEN
        RAISE EXCEPTION 'ABORT: migrations 084, 085, 086 and 087 must be applied first (their helpers are missing).';
    END IF;
    IF to_regclass('public.cattle_breeding_events') IS NULL OR to_regclass('public.birth_events') IS NULL OR to_regclass('public.event_voids') IS NULL THEN
        RAISE EXCEPTION 'ABORT: cattle_breeding_events / birth_events / event_voids are missing.';
    END IF;
    IF v_brd IS NULL OR v_void IS NULL THEN
        RAISE EXCEPTION 'ABORT: sp_log_breeding_event or sp_void_event not found with their production signatures.';
    END IF;
    IF md5(pg_get_functiondef(v_brd)) <> '2c1ff0adf25284e069ebf46ddc3108f8'
       AND (SELECT prosrc FROM pg_proc WHERE oid = v_brd) NOT LIKE '%088:legacy-breeding-v1%' THEN
        RAISE EXCEPTION 'ABORT: the live sp_log_breeding_event is not the verified production body (md5 %). STOP and compare it before replacing it.', md5(pg_get_functiondef(v_brd));
    END IF;
    IF md5(pg_get_functiondef(v_void)) <> 'c81f6faec5e61a28eca5d24b0f62a61c'
       AND (SELECT prosrc FROM pg_proc WHERE oid = v_void) NOT LIKE '%088:legacy-void-v1%' THEN
        RAISE EXCEPTION 'ABORT: the live sp_void_event is not the verified production body (md5 %). STOP and compare it before replacing it.', md5(pg_get_functiondef(v_void));
    END IF;
END $$;

-- 1) Additive column, index and guard --------------------------------------------------------------------------

ALTER TABLE public.cattle_breeding_events ADD COLUMN IF NOT EXISTS birth_event_id uuid REFERENCES public.birth_events (id);
COMMENT ON COLUMN public.cattle_breeding_events.birth_event_id IS '088: the birth this service ended in. Set at most once (NULL -> value) by fn_repro_link_birth_service; no backfill.';
CREATE INDEX IF NOT EXISTS idx_breeding_events_birth ON public.cattle_breeding_events (birth_event_id) WHERE birth_event_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fn_trg_breeding_birth_link_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.birth_event_id IS NOT NULL THEN
            RAISE EXCEPTION 'Un servicio nuevo no puede nacer ligado a un parto.' USING ERRCODE = 'P0097';
        END IF;
        RETURN NEW;
    END IF;
    -- UPDATE: the only accepted change is birth_event_id NULL -> value, once
    IF (to_jsonb(NEW) - 'birth_event_id') IS DISTINCT FROM (to_jsonb(OLD) - 'birth_event_id') THEN
        RAISE EXCEPTION 'Un servicio solo admite el enlace con su parto; ninguna otra columna se modifica.' USING ERRCODE = 'P0097';
    END IF;
    IF NEW.birth_event_id IS DISTINCT FROM OLD.birth_event_id THEN
        IF OLD.birth_event_id IS NOT NULL OR NEW.birth_event_id IS NULL THEN
            RAISE EXCEPTION 'El enlace de un servicio con su parto se fija una sola vez y no se deshace.' USING ERRCODE = 'P0097';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.birth_events b
                        WHERE b.id = NEW.birth_event_id AND b.id_company = NEW.tenant_id AND b.dam_id = NEW.livestock_id) THEN
            RAISE EXCEPTION 'El parto no pertenece a la empresa o a la hembra del servicio.' USING ERRCODE = 'P0096';
        END IF;
        IF EXISTS (SELECT 1 FROM public.event_voids v
                    WHERE v.event_table = 'cattle_breeding_events' AND v.event_id = NEW.id) THEN
            RAISE EXCEPTION 'Un servicio anulado no se liga a un parto.' USING ERRCODE = 'P0097';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgname = 'trg_breeding_birth_link_guard'
                      AND g.tgrelid = 'public.cattle_breeding_events'::regclass AND NOT g.tgisinternal) THEN
        CREATE TRIGGER trg_breeding_birth_link_guard BEFORE INSERT OR UPDATE ON public.cattle_breeding_events
            FOR EACH ROW EXECUTE FUNCTION public.fn_trg_breeding_birth_link_guard();
    END IF;
END $$;

-- 2) Helpers ---------------------------------------------------------------------------------------------------

-- Gestation (days) and plausible window (days between the service and the birth) per species; no row = unknown species.
CREATE OR REPLACE FUNCTION public.fn_repro_gestation_bounds(p_species text, OUT days integer, OUT lo integer, OUT hi integer)
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT v.d, v.lo, v.hi
      FROM (VALUES ('BOVINO', 283, 238, 328), ('OVINO', 152, 132, 172), ('BORREGO', 152, 132, 172),
                   ('EQUINO', 340, 295, 385), ('EQUIDO', 340, 295, 385), ('BUFALO', 310, 280, 340)) AS v (sp, d, lo, hi)
     WHERE v.sp = upper(coalesce(p_species, ''))
$$;

-- Links the dam's single plausible service to a registered birth. Writes at most one UPDATE (birth_event_id NULL -> value).
-- status: linked | already_linked | no_candidate | ambiguous | no_dam | no_gestation_data | not_found
CREATE OR REPLACE FUNCTION public.fn_repro_link_birth_service(p_birth_event_id uuid, p_tenant integer)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    b         record;
    g         record;
    v_species text;
    v_cands   jsonb;
    v_n       integer;
    v_svc     uuid;
    v_prev    uuid;
BEGIN
    SELECT be.id, be.id_company, be.dam_id, be.birth_date, be.species INTO b
      FROM public.birth_events be WHERE be.id = p_birth_event_id AND be.id_company = p_tenant;
    IF b.id IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;
    IF b.dam_id IS NULL THEN
        RETURN jsonb_build_object('status', 'no_dam', 'message', 'El parto no tiene madre identificada; no se liga ningun servicio.');
    END IF;
    SELECT e.id INTO v_prev FROM public.cattle_breeding_events e WHERE e.birth_event_id = b.id AND e.tenant_id = p_tenant LIMIT 1;
    IF v_prev IS NOT NULL THEN
        RETURN jsonb_build_object('status', 'already_linked', 'breeding_event_id', v_prev);
    END IF;
    v_species := coalesce(b.species, (SELECT l.species FROM public.cattle_livestock l WHERE l.id = b.dam_id AND l.tenant_id = p_tenant), 'BOVINO');
    SELECT * INTO g FROM public.fn_repro_gestation_bounds(v_species);
    IF g.days IS NULL THEN
        RETURN jsonb_build_object('status', 'no_gestation_data', 'species', v_species,
                                  'message', 'No hay ventana de gestacion para la especie ' || v_species || '; el servicio queda sin ligar.');
    END IF;

    SELECT count(*),
           coalesce(jsonb_agg(jsonb_build_object('breeding_event_id', e.id, 'breeding_date', e.breeding_date, 'method', e.method,
                                                 'days_to_birth', b.birth_date - e.breeding_date) ORDER BY e.breeding_date), '[]'::jsonb),
           (array_agg(e.id ORDER BY e.breeding_date))[1]
      INTO v_n, v_cands, v_svc
      FROM public.cattle_breeding_events e
     WHERE e.tenant_id = p_tenant AND e.livestock_id = b.dam_id AND e.birth_event_id IS NULL
       AND e.breeding_date BETWEEN b.birth_date - g.hi AND b.birth_date - g.lo
       AND NOT EXISTS (SELECT 1 FROM public.event_voids v
                        WHERE v.event_table = 'cattle_breeding_events' AND v.event_id = e.id AND v.tenant_id = p_tenant);

    IF v_n = 1 THEN
        UPDATE public.cattle_breeding_events SET birth_event_id = b.id
         WHERE id = v_svc AND tenant_id = p_tenant AND birth_event_id IS NULL;
        RETURN jsonb_build_object('status', 'linked', 'breeding_event_id', v_svc, 'candidates', v_cands, 'gestation_window_days', jsonb_build_array(g.lo, g.hi));
    ELSIF v_n = 0 THEN
        RETURN jsonb_build_object('status', 'no_candidate', 'gestation_window_days', jsonb_build_array(g.lo, g.hi),
            'message', 'Ningun servicio de la madre cae en la ventana de gestacion; el parto queda sin servicio ligado.');
    END IF;
    RETURN jsonb_build_object('status', 'ambiguous', 'candidates', v_cands, 'gestation_window_days', jsonb_build_array(g.lo, g.hi),
        'message', 'Varios servicios de la madre caen en la ventana de gestacion; no se adivina cual fue: el parto queda sin servicio ligado.');
END;
$$;

-- 3) Dam history -----------------------------------------------------------------------------------------------

-- get_dam_reproductive_history: everything recorded about one female in one company. Read-only. At most 200 rows per section.
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

-- 4) The two procedures -----------------------------------------------------------------------------------------
-- Same names, same parameters and defaults: CREATE OR REPLACE, not new overloads. The bodies are the verified production
-- bodies (sp_log_breeding_event md5 2c1ff0adf25284e069ebf46ddc3108f8, sp_void_event md5 c81f6faec5e61a28eca5d24b0f62a61c) plus
-- the 088 blocks marked "-- 088". 088_rollback.sql restores the originals.

CREATE OR REPLACE FUNCTION public.sp_log_breeding_event(p_animal_identifier character varying, p_tenant_id integer, p_breeding_date date DEFAULT CURRENT_DATE, p_method character varying DEFAULT 'MONTA_NATURAL'::character varying, p_sire_identifier character varying DEFAULT NULL::character varying, p_semen_batch character varying DEFAULT NULL::character varying, p_registered_by_email character varying DEFAULT NULL::character varying, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_livestock_id    uuid;
    v_current_status  character varying(50);
    v_species         character varying(50);
    v_match_count     integer;
    v_gestation_days  integer;
    v_estimated_due   date;
    v_breeding_event_id uuid;
    v_sire_txt        text;
    v_sire_res        jsonb;
    v_sire_id         uuid;
    v_sire_cat        character varying(50);
    v_warnings        jsonb := '[]'::jsonb;
    v_dup_id          uuid;
BEGIN
    -- 088:legacy-breeding-v1 (marker used by the migration, its rollback and its state check)
    -- 088: the reporter must be an ACTIVE member of the company (fail closed, P0001). Every known caller sends the e-mail.
    IF p_registered_by_email IS NULL OR btrim(p_registered_by_email) = ''
       OR NOT public.fn_repro_is_member(p_tenant_id, p_registered_by_email) THEN
        RAISE EXCEPTION 'El usuario % no tiene acceso activo a la empresa %', coalesce(p_registered_by_email, '(sin correo)'), p_tenant_id
            USING ERRCODE = 'P0001';
    END IF;

    IF p_method NOT IN ('MONTA_NATURAL', 'INSEMINACION_ARTIFICIAL') THEN
        RAISE EXCEPTION 'method debe ser MONTA_NATURAL o INSEMINACION_ARTIFICIAL' USING ERRCODE = 'P0009';
    END IF;

    SELECT count(*) INTO v_match_count
      FROM public.cattle_livestock
     WHERE tenant_id = p_tenant_id
       AND (electronic_rfid = p_animal_identifier
            OR rfid_siniiga = p_animal_identifier
            OR numero_fuego = p_animal_identifier);

    IF v_match_count = 0 THEN
        RAISE EXCEPTION 'Ningún animal coincide con el identificador "%" (tenant %)', p_animal_identifier, p_tenant_id
            USING ERRCODE = 'P0002';
    ELSIF v_match_count > 1 THEN
        RAISE EXCEPTION 'Identificador ambiguo: % animales coinciden con "%"', v_match_count, p_animal_identifier
            USING ERRCODE = 'P0004';
    END IF;

    SELECT id, current_status, species
      INTO v_livestock_id, v_current_status, v_species
      FROM public.cattle_livestock
     WHERE tenant_id = p_tenant_id
       AND (electronic_rfid = p_animal_identifier
            OR rfid_siniiga = p_animal_identifier
            OR numero_fuego = p_animal_identifier);

    IF v_current_status IN ('VENDIDO', 'BAJA_MORTANDAD') THEN
        RAISE EXCEPTION 'El animal ya fue procesado (estatus actual: %), no puede registrarse un servicio', v_current_status
            USING ERRCODE = 'P0001';
    END IF;

    -- 088: the sire. Resolved only inside THIS company (no cross-company lookup: it would reveal that an identifier exists
    -- elsewhere). A sire that does not resolve stays free text with a warning (external semen, a bull that was never loaded).
    v_sire_txt := NULLIF(btrim(p_sire_identifier), '');
    IF v_sire_txt IS NOT NULL THEN
        v_sire_res := public.fn_repro_resolve_animal(p_tenant_id, v_sire_txt);
        IF v_sire_res->>'status' = 'ambiguous' THEN
            RETURN jsonb_build_object('success', false, 'status', 'ambiguous', 'code', 'SIRE_AMBIGUOUS', 'which', 'sire',
                'candidates', v_sire_res->'candidates',
                'message', 'Hay varios animales con el identificador del semental; elige uno por su arete SINIIGA. No se registro el servicio.');
        ELSIF v_sire_res->>'status' = 'ok' THEN
            v_sire_id := (v_sire_res->>'livestock_id')::uuid;
            SELECT l.category INTO v_sire_cat FROM public.cattle_livestock l WHERE l.id = v_sire_id AND l.tenant_id = p_tenant_id;
            IF v_sire_id = v_livestock_id THEN
                RETURN jsonb_build_object('success', false, 'status', 'rejected', 'code', 'SIRE_IS_THE_FEMALE',
                    'message', 'El semental no puede ser la misma hembra. No se registro el servicio.');
            ELSIF v_sire_cat IS NULL OR v_sire_cat NOT IN ('TORO', 'BECERRO_TORETE') THEN
                RETURN jsonb_build_object('success', false, 'status', 'rejected', 'code', 'SIRE_NOT_BULL', 'sire_livestock_id', v_sire_id,
                    'message', 'El animal indicado como semental no es un toro (TORO o BECERRO_TORETE); su categoria es ' || coalesce(v_sire_cat, '?') || '. No se registro el servicio.');
            END IF;
        ELSE
            v_warnings := v_warnings || to_jsonb('sire_not_resolved'::text);
        END IF;
    END IF;
    IF p_method = 'INSEMINACION_ARTIFICIAL' AND NULLIF(btrim(p_semen_batch), '') IS NULL THEN
        v_warnings := v_warnings || to_jsonb('semen_batch_missing'::text);
    END IF;

    -- 088: exact retry (same female, date, method and sire, created within the last 5 minutes, not voided)
    SELECT be.id INTO v_dup_id
      FROM public.cattle_breeding_events be
     WHERE be.tenant_id = p_tenant_id AND be.livestock_id = v_livestock_id AND be.breeding_date = p_breeding_date
       AND be.method = p_method AND NULLIF(btrim(be.sire_identifier), '') IS NOT DISTINCT FROM v_sire_txt
       AND be.created_at > now() - interval '5 minutes'
       AND NOT EXISTS (SELECT 1 FROM public.event_voids v
                        WHERE v.event_table = 'cattle_breeding_events' AND v.event_id = be.id AND v.tenant_id = p_tenant_id)
     ORDER BY be.created_at LIMIT 1;
    IF v_dup_id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'duplicate_skipped', true, 'breeding_event_id', v_dup_id, 'livestock_id', v_livestock_id,
            'breeding_date', p_breeding_date, 'method', p_method, 'warnings', v_warnings,
            'message', 'Este servicio ya estaba registrado hace unos minutos; no se duplico.');
    END IF;

    v_gestation_days := CASE v_species
        WHEN 'BOVINO'  THEN 283
        WHEN 'EQUINO'  THEN 340
        WHEN 'OVINO'   THEN 152
        WHEN 'CAPRINO' THEN 150
        WHEN 'PORCINO' THEN 114
        ELSE NULL
    END;

    IF v_gestation_days IS NOT NULL THEN
        v_estimated_due := p_breeding_date + v_gestation_days;
    END IF;

    INSERT INTO public.cattle_breeding_events
        (livestock_id, tenant_id, breeding_date, method, sire_identifier, semen_batch,
         estimated_due_date, registered_by_email, notes)
    VALUES
        (v_livestock_id, p_tenant_id, p_breeding_date, p_method, p_sire_identifier, p_semen_batch,
         v_estimated_due, p_registered_by_email, p_notes)
    RETURNING id INTO v_breeding_event_id;

    RETURN jsonb_build_object(
        'success', true,
        'breeding_event_id', v_breeding_event_id,
        'livestock_id', v_livestock_id,
        'breeding_date', p_breeding_date,
        'method', p_method,
        'estimated_due_date', v_estimated_due,
        'duplicate_skipped', false,
        'warnings', v_warnings,
        'sire_livestock_id', v_sire_id
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.sp_void_event(p_event_table character varying, p_event_id uuid, p_tenant_id integer, p_voided_by_email character varying, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_allowed_tables  text[] := ARRAY['cattle_breeding_events','cattle_deworming_events','cattle_castration_events'];
    v_exists          boolean;
    v_already_voided  boolean;
    v_void_id         uuid;
    v_linked_birth    uuid;
BEGIN
    -- 088:legacy-void-v1 (marker used by the migration, its rollback and its state check)
    -- 088: the voider must be an ACTIVE member of the company (fail closed, P0001). Every known caller sends the e-mail.
    IF p_voided_by_email IS NULL OR btrim(p_voided_by_email) = ''
       OR NOT public.fn_repro_is_member(p_tenant_id, p_voided_by_email) THEN
        RAISE EXCEPTION 'El usuario % no tiene acceso activo a la empresa %', coalesce(p_voided_by_email, '(sin correo)'), p_tenant_id
            USING ERRCODE = 'P0001';
    END IF;

    -- Fail-closed: solo tablas explícitamente habilitadas, nunca un nombre arbitrario
    IF NOT (p_event_table = ANY(v_allowed_tables)) THEN
        RAISE EXCEPTION 'event_table "%" no está habilitada para anulación. Tablas permitidas: %', p_event_table, v_allowed_tables
            USING ERRCODE = 'P0016';
    END IF;

    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1 AND tenant_id = $2)', p_event_table)
      INTO v_exists
      USING p_event_id, p_tenant_id;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'El evento % no existe en % para la empresa %', p_event_id, p_event_table, p_tenant_id
            USING ERRCODE = 'P0002';
    END IF;

    -- 088: a service that is linked to a birth is part of that birth's history: it is not voided (rejected, with the birth).
    IF p_event_table = 'cattle_breeding_events' THEN
        SELECT be.birth_event_id INTO v_linked_birth
          FROM public.cattle_breeding_events be WHERE be.id = p_event_id AND be.tenant_id = p_tenant_id;
        IF v_linked_birth IS NOT NULL THEN
            RETURN jsonb_build_object('success', false, 'status', 'rejected', 'code', 'LINKED_TO_BIRTH',
                'birth_event_id', v_linked_birth, 'event_table', p_event_table, 'event_id', p_event_id,
                'message', 'Este servicio esta ligado a un parto (birth_event_id); no se anula. No se cambio nada.');
        END IF;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.event_voids
         WHERE event_table = p_event_table AND event_id = p_event_id
    ) INTO v_already_voided;

    IF v_already_voided THEN
        RAISE EXCEPTION 'El evento % en % ya fue anulado previamente', p_event_id, p_event_table
            USING ERRCODE = 'P0017';
    END IF;

    INSERT INTO public.event_voids (tenant_id, event_table, event_id, voided_by_email, voided_reason)
    VALUES (p_tenant_id, p_event_table, p_event_id, p_voided_by_email, p_reason)
    RETURNING id INTO v_void_id;

    RETURN jsonb_build_object(
        'success', true,
        'void_id', v_void_id,
        'event_table', p_event_table,
        'event_id', p_event_id,
        'voided_at', now()
    );
END;
$function$;

-- 5) Sanity ---------------------------------------------------------------------------------------------------

DO $$
DECLARE
    v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY['fn_trg_breeding_birth_link_guard', 'fn_repro_gestation_bounds', 'fn_repro_link_birth_service', 'sp_repro_get_dam_history']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '088: missing functions: %', v_missing;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cattle_breeding_events' AND column_name = 'birth_event_id') THEN
        RAISE EXCEPTION '088: cattle_breeding_events.birth_event_id missing';
    END IF;
    IF (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.sp_log_breeding_event(character varying,integer,date,character varying,character varying,character varying,character varying,text)')) NOT LIKE '%088:legacy-breeding-v1%'
       OR (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.sp_void_event(character varying,uuid,integer,character varying,text)')) NOT LIKE '%088:legacy-void-v1%' THEN
        RAISE EXCEPTION '088: a legacy procedure was not replaced';
    END IF;
    RAISE NOTICE '088: OK';
END $$;

\if :{?embedded}
\echo '*** 088 loaded inside the caller''s transaction (embedded) ***'
\elif :apply
COMMIT;
\echo '*** 088 COMMITTED ***'
\else
ROLLBACK;
\echo '*** DRY RUN: everything rolled back ***'
\endif
