-- Migration 027: Restore truncated SINIIGA ear tags and harden the validator.
--
-- ROOT CAUSE
--   The official bovine SINIIGA identifier is 10 digits: EE + 4 + 4, where EE is the
--   INEGI state code (07 Chiapas, 27 Tabasco). Confirmed against three independent
--   client sources on 2026-07-28:
--     * field notebooks, written with the grouping visible: "07 2303 - 9595"
--     * the San Pedro spreadsheet, split into columns: serie 271442 + grande 9552
--     * the tag itself, where "grande" is the large-print number read at a distance —
--       which is why the notebooks only record the last 4 digits
--
--   188 rows in production carry 9 digits. They lost the LEADING ZERO of the Chiapas
--   prefix, the classic symptom of a spreadsheet import casting the column to numeric.
--   '718436811' is really '0718436811' -> 07 1843 6811, and the notebook independently
--   records "07 1843 - 6809" for a neighbouring animal. Tabasco tags (27...) were never
--   affected, which is exactly why UPP 54's 54 records are intact.
--
-- WHAT THIS MIGRATION DOES NOT FIX
--   4 rows carry 7 or 8 characters, and a handful are free-text ('09-1234', '12654656').
--   Their correct value cannot be derived — a missing digit in the middle is unrecoverable.
--   They are left untouched and will simply fail the hardened validator, surfacing in
--   vw_livestock_movement_readiness for manual correction against the physical tag.
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Fix the mistyped letter O for a zero (found in production: 'O718127685')
-- ---------------------------------------------------------------------------
UPDATE public.cattle_livestock
   SET rfid_siniiga = '0' || substring(btrim(rfid_siniiga) from 2)
 WHERE rfid_siniiga ~ '^[Oo][0-9]{9}$'
   AND NOT EXISTS (
        SELECT 1 FROM public.cattle_livestock c2
         WHERE c2.rfid_siniiga = '0' || substring(btrim(public.cattle_livestock.rfid_siniiga) from 2));

-- ---------------------------------------------------------------------------
-- 2. Restore the leading zero on 9-digit tags
-- ---------------------------------------------------------------------------
-- Guarded against the UNIQUE index: if padding would collide with an existing tag the
-- row is skipped rather than aborting the whole migration. Collisions are reported below.
UPDATE public.cattle_livestock cl
   SET rfid_siniiga = lpad(btrim(cl.rfid_siniiga), 10, '0')
 WHERE btrim(cl.rfid_siniiga) ~ '^[0-9]{9}$'
   AND NOT EXISTS (
        SELECT 1 FROM public.cattle_livestock c2
         WHERE c2.rfid_siniiga = lpad(btrim(cl.rfid_siniiga), 10, '0')
           AND c2.id <> cl.id);

DO $$
DECLARE
    v_remaining integer;
    v_invalid   integer;
BEGIN
    SELECT count(*) INTO v_remaining
      FROM public.cattle_livestock
     WHERE btrim(rfid_siniiga) ~ '^[0-9]{9}$';

    SELECT count(*) INTO v_invalid
      FROM public.cattle_livestock
     WHERE current_status NOT IN ('VENDIDO', 'BAJA_MORTANDAD')
       AND (rfid_siniiga IS NULL
            OR NOT btrim(rfid_siniiga) ~ '^[0-9]{10}$');

    IF v_remaining > 0 THEN
        RAISE NOTICE '% rows still hold 9 digits: padding would have collided with an existing tag. Review manually.', v_remaining;
    END IF;
    RAISE NOTICE '% active animals do not carry a valid 10-digit tag (includes the S/A placeholders).', v_invalid;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Harden the validator
-- ---------------------------------------------------------------------------
-- Migration 024 deliberately checked only "not a placeholder", because the correct length
-- was unconfirmed and blocking 188 animals on a hunch would have been worse than the gap.
-- The format is now confirmed by three sources, so the check becomes the real one.
CREATE OR REPLACE FUNCTION public.fn_has_official_ear_tag(p_rfid_siniiga character varying)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_rfid_siniiga IS NOT NULL
       AND btrim(p_rfid_siniiga) ~ '^[0-9]{10}$';
$$;

COMMENT ON FUNCTION public.fn_has_official_ear_tag(character varying) IS
    'True for a well-formed SINIIGA bovine tag: exactly 10 digits (EE + 4 + 4, EE = INEGI state code). Format confirmed 2026-07-28 against field notebooks, the San Pedro spreadsheet and the physical tag layout. Does NOT verify that the state prefix matches the unit: a legitimately transferred animal keeps the tag of its origin.';

-- ---------------------------------------------------------------------------
-- 4. Expose the tag components for search and reporting
-- ---------------------------------------------------------------------------
-- The field notebooks only ever record the last 4 digits (the large-print number), so any
-- search UI must be able to match on that fragment alone.
CREATE OR REPLACE VIEW public.vw_livestock_tag_parts AS
 SELECT cl.id                              AS livestock_id,
        cl.tenant_id                       AS id_company,
        cl.rfid_siniiga,
        CASE WHEN public.fn_has_official_ear_tag(cl.rfid_siniiga)
             THEN substring(btrim(cl.rfid_siniiga) from 1 for 2) END  AS tag_state_code,
        CASE WHEN public.fn_has_official_ear_tag(cl.rfid_siniiga)
             THEN substring(btrim(cl.rfid_siniiga) from 3 for 4) END  AS tag_series,
        CASE WHEN public.fn_has_official_ear_tag(cl.rfid_siniiga)
             THEN substring(btrim(cl.rfid_siniiga) from 7 for 4) END  AS tag_printed_number,
        cl.numero_fuego,
        cl.electronic_rfid,
        cl.category,
        cl.current_status,
        cl.production_unit_id,
        cl.created_at
   FROM public.cattle_livestock cl;

COMMENT ON VIEW public.vw_livestock_tag_parts IS
    'Decomposes the SINIIGA tag into state / series / printed number. tag_printed_number is the large digits stamped on the tag and the only part written in the field notebooks, so it is the natural search key in the corral.';

CREATE INDEX IF NOT EXISTS idx_livestock_tag_printed
    ON public.cattle_livestock (substring(btrim(rfid_siniiga) from 7 for 4))
    WHERE rfid_siniiga ~ '^[0-9]{10}$';

COMMIT;
