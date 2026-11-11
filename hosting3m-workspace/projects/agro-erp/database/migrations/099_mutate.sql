-- 099_mutate.sql: used ONLY by 099_tests.sql when -v mutation=<M1..M14> is given (see 099_mutation_check.sh).
-- It breaks one protection inside the test transaction (which always ends in ROLLBACK) so that the matching test must fail.
-- Each mutation rewrites a function from its LIVE definition by an exact text anchor; a missing anchor raises an ERROR
-- (reported by the check as NOT DETECTED, so a stale anchor can never pass silently).
\set ON_ERROR_STOP on
\echo MUTATION :mutation

CREATE OR REPLACE FUNCTION pg_temp.fn_099_patch(p_sig text, p_from text, p_to text, p_times integer DEFAULT 1)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_def   text := pg_get_functiondef(p_sig::regprocedure);
    v_count integer := (length(v_def) - length(replace(v_def, p_from, ''))) / length(p_from);
BEGIN
    IF v_count <> p_times THEN
        RAISE EXCEPTION 'MUTATION anchor found % time(s) in %, expected %: %', v_count, p_sig, p_times, left(p_from, 80);
    END IF;
    EXECUTE replace(v_def, p_from, p_to);
END $fn$;

SELECT set_config('t099.mutation', :'mutation', false) AS mutation;

DO $$
DECLARE
    m      text := current_setting('t099.mutation');
    c_reg  constant text := 'public.sp_register_livestock_regularization(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)';
    c_buy  constant text := 'public.sp_register_livestock_purchase_chat(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text)';
    c_ctx  constant text := 'public.fn_livestock_chat_ctx(text,text)';
    c_upp  constant text := 'public.fn_livestock_chat_resolve_upp(integer,text)';
    c_lot  constant text := 'public.fn_livestock_chat_resolve_lot(integer,uuid,text)';
    c_tag  constant text := 'public.fn_livestock_chat_tag_conflict(integer,text)';
    c_cat  constant text := 'public.fn_livestock_chat_valid_categories(text)';
    c_plh  constant text := 'public.fn_livestock_chat_is_placeholder(text)';
    c_hash constant text := 'IF public.fn_livestock_chat_txt(p_preview_hash) IS DISTINCT FROM v_hash THEN';
BEGIN
    CASE m
    -- M1: a UPP code of ANY company resolves (expect B5)
    WHEN 'M1' THEN PERFORM pg_temp.fn_099_patch(c_upp,
        'OR (v_code IS NOT NULL AND pu.upp_code = v_code));',
        'OR (v_code IS NOT NULL AND pu.upp_code = v_code))' || chr(10) || '       OR (v_code IS NOT NULL AND pu.upp_code = v_code AND pu.is_active IS TRUE);');
    -- M2: the lot is not limited to the resolved UPP (expect C2)
    WHEN 'M2' THEN PERFORM pg_temp.fn_099_patch(c_lot,
        '       AND l.production_unit_id = p_unit' || chr(10) || '       AND l.is_active IS TRUE' || chr(10),
        '       AND l.is_active IS TRUE' || chr(10));
    -- M3: purchase price 0 accepted (expect G1)
    WHEN 'M3' THEN PERFORM pg_temp.fn_099_patch(c_buy, 'IF v_price IS NULL OR v_price <= 0 THEN', 'IF v_price IS NULL OR v_price < 0 THEN');
    -- M4: no placeholder detection (expect D3)
    WHEN 'M4' THEN PERFORM pg_temp.fn_099_patch(c_plh, 'SELECT k = '''' OR k IN (', 'SELECT false AND k IN (');
    -- M5: a regularization preview writes (expect F1)
    WHEN 'M5' THEN
        PERFORM pg_temp.fn_099_patch(c_reg, 'IF lower(coalesce(public.fn_livestock_chat_txt(p_confirmed), '''')) <> ''true'' THEN', 'IF false THEN');
        PERFORM pg_temp.fn_099_patch(c_reg, c_hash, 'IF false THEN');
    -- M6: membership not required (expect A2)
    WHEN 'M6' THEN PERFORM pg_temp.fn_099_patch(c_ctx,
        'IF v_actor IS NULL OR v_role IS NULL OR v_company IS NULL THEN',
        'v_role := coalesce(v_role, ''ADMIN'');' || chr(10) || '    IF v_company IS NULL THEN');
    -- M7: palm companies accepted (expect A5)
    WHEN 'M7' THEN PERFORM pg_temp.fn_099_patch(c_ctx, 'IS NOT DISTINCT FROM ''PALM'' THEN', 'IS NOT DISTINCT FROM ''NOT_A_DOMAIN'' THEN');
    -- M8: tags of other companies not checked (expect E5)
    WHEN 'M8' THEN PERFORM pg_temp.fn_099_patch(c_tag, 'WHERE cl.tenant_id <> p_tenant AND', 'WHERE false AND');
    -- M9: commit without the preview_hash, in both tools (expect F2)
    WHEN 'M9' THEN
        PERFORM pg_temp.fn_099_patch(c_reg, c_hash, 'IF false THEN');
        PERFORM pg_temp.fn_099_patch(c_buy, c_hash, 'IF false THEN');
    -- M10: CUSTOMER allowed (expect A3)
    WHEN 'M10' THEN PERFORM pg_temp.fn_099_patch(c_ctx,
        'IF v_role NOT IN (''ADMIN'', ''OWNER'', ''EDITOR'') THEN', 'IF v_role NOT IN (''ADMIN'', ''OWNER'', ''EDITOR'', ''CUSTOMER'') THEN');
    -- M11: BUFALO accepts NOVILLO (expect D7)
    WHEN 'M11' THEN PERFORM pg_temp.fn_099_patch(c_cat,
        'ARRAY[''BUCERRA'', ''BUCERRO'', ''BUFALA'', ''BUFALO'']', 'ARRAY[''BUCERRA'', ''BUCERRO'', ''BUFALA'', ''BUFALO'', ''NOVILLO'']');
    -- M12: a numero_fuego match rejects again instead of warning (expect E6)
    WHEN 'M12' THEN PERFORM pg_temp.fn_099_patch(c_tag,
        'AND (cl.rfid_siniiga = p_tag OR cl.electronic_rfid = p_tag)' || chr(10) || '     ORDER BY',
        'AND (cl.rfid_siniiga = p_tag OR cl.electronic_rfid = p_tag OR cl.numero_fuego = p_tag)' || chr(10) || '     ORDER BY');
    -- M13: no upper limit for the approximate age (expect D5)
    WHEN 'M13' THEN PERFORM pg_temp.fn_099_patch(c_reg, 'OR v_age > 240 THEN', 'OR v_age > 100000 THEN');
    -- M14: bovine ear tag not required (expect D1)
    WHEN 'M14' THEN PERFORM pg_temp.fn_099_patch(c_reg,
        '        IF v_bovine THEN' || chr(10) || '            v_issues := v_issues || jsonb_build_object(''type'', ''missing'', ''field'', ''ear_tag''',
        '        IF false THEN' || chr(10) || '            v_issues := v_issues || jsonb_build_object(''type'', ''missing'', ''field'', ''ear_tag''');
    ELSE
        RAISE EXCEPTION 'unknown mutation %', m;
    END CASE;
    RAISE NOTICE 'MUTATION % applied', m;
END $$;
