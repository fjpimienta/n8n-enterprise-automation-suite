-- 116_tag_change_chat_guard.sql (PR 2b, DATABASE part). Migration 116 (113 is reserved). Requires 115_tag_change_authorization.sql (PR 2a) applied.
--
-- Why: the chat agent approves and rejects requests through the MCP tool review_pending_request -> sp_review_pending_request -> sp_resolver_autorizacion.
-- Since PR 2a, sp_resolver_autorizacion has a CAMBIO_ARETE branch. The decision is that a tag change
-- is approved ONLY from the web panel (which calls sp_resolver_autorizacion directly, not this wrapper). Rejecting (with a note) stays allowed from chat.
--
-- What it does: sp_review_pending_request (the chat-only wrapper) is patched IN PLACE: after its tenant check and before it calls sp_resolver_autorizacion, any decision
-- other than RECHAZADO on a CAMBIO_ARETE request raises P0136. The patch is md5-gated (refuses any text but the measured one) and carries the marker
-- 'chat-guard-cambio-arete' so the rollback can remove exactly it. Nothing else changes: sp_resolver_autorizacion, the web panel path, baja and venta are untouched.
--
-- The rule lives in the database; the tool description and the prompt state it as well.
--
-- BACKUP: save the text of public.sp_review_pending_request (\sf) to a private file before applying anywhere that matters.
-- DRY RUN (default): psql -X -v ON_ERROR_STOP=1 -f 116_tag_change_chat_guard.sql ; commit with -v apply=true. Idempotent.
-- Rollback: 116_rollback.sql. Tests (throwaway database only): 116_tests.sql.
-- Error code: P0136 (a tag change cannot be approved from chat).

\if :{?embedded}
\else
\set ON_ERROR_STOP on
\endif
\if :{?apply}
\else
\set apply false
\endif
\if :{?embedded}
\else
BEGIN;
\endif

DO $patch$
DECLARE
    v_oid regprocedure := 'public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure;
    v_def text;
    -- \1 = the blank/new lines before RETURN, \2 = its indentation: the block is inserted in front of RETURN and RETURN keeps EXACTLY its original whitespace
    v_pat text := $r$(\s*\n)([ \t]*)RETURN sp_resolver_autorizacion\(p_request_id, p_decision, p_resuelto_por_email, p_notas\);$r$;
    v_rep text := $r$\1\2-- chat-guard-cambio-arete: a tag change is approved only from the web panel; chat may only reject it (with a note, checked by the resolver)
\2IF upper(coalesce(p_decision, '')) <> 'RECHAZADO'
\2   AND EXISTS (SELECT 1 FROM pending_authorizations pa WHERE pa.id = p_request_id AND pa.tipo_evento = 'CAMBIO_ARETE') THEN
\2    RAISE EXCEPTION 'Un cambio de identificador solo se aprueba desde el panel web' USING ERRCODE = 'P0136';
\2END IF;\1\2RETURN sp_resolver_autorizacion(p_request_id, p_decision, p_resuelto_por_email, p_notas);$r$;
BEGIN
    IF to_regprocedure('public.sp_apply_tag_change(uuid,text)') IS NULL THEN
        RAISE EXCEPTION 'ABORT: 115_tag_change_authorization (PR 2a) is not applied.';
    END IF;
    v_def := pg_get_functiondef(v_oid);
    IF v_def LIKE '%chat-guard-cambio-arete%' THEN
        RAISE NOTICE 'chat guard already applied';
        RETURN;
    END IF;
    IF md5(v_def) <> '69721334b082bdf3aa1f70a362e3440c' THEN
        RAISE EXCEPTION 'ABORT: sp_review_pending_request differs from the measured text (md5 %). Compare with production and rebuild from the live text. Nothing was changed.', md5(v_def);
    END IF;
    IF regexp_count(v_def, v_pat) <> 1 THEN
        RAISE EXCEPTION 'ABORT: expected exactly one RETURN sp_resolver_autorizacion(...) in the wrapper, found %.', regexp_count(v_def, v_pat);
    END IF;
    EXECUTE regexp_replace(v_def, v_pat, v_rep);
END $patch$;

DO $$
BEGIN
    IF pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure) NOT LIKE '%chat-guard-cambio-arete%' THEN
        RAISE EXCEPTION 'POST-CHECK: the guard is not in the wrapper.';
    END IF;
    RAISE NOTICE '116_tag_change_chat_guard: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo '116_tag_change_chat_guard: COMMITTED'
\else
ROLLBACK;
\echo '116_tag_change_chat_guard: DRY RUN, rolled back. Re-run with -v apply=true to commit.'
\endif
\endif
