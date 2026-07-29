-- Migration 025: Adds REVERSION to the historico_movimientos movement type CHECK.
--
-- WHY: on 2026-07-28 a test invocation of sp_procesar_salida_ganado was executed against
-- PRODUCTION by mistake, marking a real cow (id b54d16a5-ebad-4f22-bc7b-0225df5299d2,
-- rfid_siniiga '09-1234') as VENDIDO. The animal was restored, and instead of deleting the
-- VENTA row from the audit log a compensating REVERSION row was inserted: an audit table
-- that gets rows removed when something goes wrong is not an audit table.
--
-- The CHECK was widened by hand in production during that incident. This migration versions
-- the change so the local clone and any from-scratch deployment match, and so the next
-- restore of the clone does not silently lose it.
--
-- REVERSION semantics: a compensating entry that annuls an earlier movement for the same
-- livestock_id. It never replaces the original row — both remain, and the chronology shows
-- what happened. It is NOT a status of the animal, only a movement-log entry.
--
-- Same DROP + ADD CONSTRAINT pattern used by migrations 001 and 005 for VARCHAR + CHECK
-- columns (these are not native ENUMs).
BEGIN;

ALTER TABLE public.historico_movimientos
    DROP CONSTRAINT IF EXISTS historico_movimientos_tipo_check;

ALTER TABLE public.historico_movimientos
ADD CONSTRAINT historico_movimientos_tipo_check CHECK (
    (tipo_movimiento)::text = ANY (ARRAY[
        'VENTA',
        'BAJA_MORTANDAD',
        'TRASLADO',
        'REVERSION'
    ]::text[])
);

COMMENT ON COLUMN public.historico_movimientos.tipo_movimiento IS
    'VENTA / BAJA_MORTANDAD / TRASLADO are real movements. REVERSION is a compensating entry that annuls a previous movement for the same animal: the original row is always kept.';

COMMIT;
