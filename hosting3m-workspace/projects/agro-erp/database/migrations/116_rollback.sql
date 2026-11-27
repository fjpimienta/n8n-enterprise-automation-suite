-- 116_rollback.sql. No DROP, nothing deleted: removes exactly the block the migration inserted into sp_review_pending_request.
-- After this rollback the chat tool review_pending_request can APPROVE a CAMBIO_ARETE again (if PR 2a is still applied). Roll back PR 2b's n8n part first, or accept that.
-- Order when several parts are applied: n8n part of 2b (re-import the originals) -> this script -> 2a -> step 1.
--   psql -X -v ON_ERROR_STOP=1 -f 116_rollback.sql                 -> dry run
--   psql -X -v ON_ERROR_STOP=1 -v apply=true -f 116_rollback.sql   -> commit

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
    v_def text := pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure);
    -- the block starts at the marker and ends at its END IF;; the whitespace after it is removed too, so the whitespace in front of the block is the original one in front of RETURN
    v_pat text := $r$-- chat-guard-cambio-arete.*?END IF;\s+(?=RETURN sp_resolver_autorizacion)$r$;
BEGIN
    IF v_def NOT LIKE '%chat-guard-cambio-arete%' THEN RAISE NOTICE 'the wrapper has no chat guard'; RETURN; END IF;
    IF regexp_count(v_def, v_pat) <> 1 THEN RAISE EXCEPTION 'ABORT rollback: the guard block was not found exactly once.'; END IF;
    EXECUTE regexp_replace(v_def, v_pat, '');
END $patch$;

DO $$
BEGIN
    IF pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure) LIKE '%chat-guard-cambio-arete%' THEN
        RAISE EXCEPTION 'POST-CHECK rollback: the guard is still there.';
    END IF;
    RAISE NOTICE '116_tag_change_chat_guard rollback: OK';
END $$;

\if :{?embedded}
\else
\if :apply
COMMIT;
\echo 'rollback: COMMITTED'
\else
ROLLBACK;
\echo 'rollback: DRY RUN, rolled back. Re-run with -v apply=true to commit.'
\endif
\endif
