-- 068_fix_purchase_date_utc_20261008.sql
-- ALREADY APPLIED in LOCAL and PRODUCTION on 2026-10-08. Versioned retroactively.
-- One-off data fix: two tenant-3 purchases captured on 2026-10-07 after 18:00 Mexico City
-- time got purchase_date = 2026-10-08 because register_livestock_purchase used CURRENT_DATE
-- (server UTC). Guards make re-running a no-op.
-- Backup table: cattle_livestock_bkp_20261008_purchase_date

BEGIN;

CREATE TABLE IF NOT EXISTS cattle_livestock_bkp_20261008_purchase_date AS
SELECT * FROM cattle_livestock
WHERE id IN ('35451bfb-cacf-4a13-9d92-3275bc06ae51',
             '3314a162-4f03-472a-af9f-f503ef34bcba');

UPDATE cattle_livestock
SET metadata = jsonb_set(metadata, '{purchase_date}',
                         to_jsonb(fn_utc_to_cdmx(created_at)::date::text))
WHERE id IN ('35451bfb-cacf-4a13-9d92-3275bc06ae51',
             '3314a162-4f03-472a-af9f-f503ef34bcba')
  AND tenant_id = 3
  AND metadata->>'source' = 'COMPRA'
  AND metadata->>'purchase_date' = '2026-10-08'
  AND fn_utc_to_cdmx(created_at)::date = DATE '2026-10-07';

COMMIT;
