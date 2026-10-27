-- repro_03_counts.sql  (READ-ONLY, per tenant)
-- Phase 0 baseline counts for births, empadre eligibility, palpations and services.
--
--   psql -v ON_ERROR_STOP=1 -X -v tenant=5 -d hosting3m_db -f repro_03_counts.sql > /root/repro_03_counts_t5.txt 2>&1
--
-- Fail-closed: aborts when :tenant is not set or the company does not exist.
-- "Active" = current_status NOT IN (VENDIDO, BAJA_MORTANDAD, FINALIZADO, BAJA_DEPURACION_DATOS).
-- Scope: category NOVILLONA or BECERRA (category can lag). A birth_date of 2020-01-01 is the import placeholder = no date.
-- Age in months = calendar-month difference (month precision only; the day is never used). Year-only estimate (legacy number) counts as eligible only if
-- the animal would have >= 15 months even if born in December of that year.
\set ON_ERROR_STOP on
\if :{?tenant}
\else
  \echo 'ERROR: pass -v tenant=<id_company>. Refusing to run without a tenant.'
  \quit
\endif

SELECT CASE WHEN count(*) = 1 THEN 'tenant ok' ELSE 'ERROR: unknown tenant' END AS tenant_check,
       max(company_name) AS company_name
FROM companys WHERE id_company = :tenant;

\echo '=== 1. birth_events ==='
SELECT count(*) AS birth_events,
       count(*) FILTER (WHERE dam_id IS NULL)  AS without_dam_id,
       count(*) FILTER (WHERE calf_id IS NULL) AS without_calf_id,
       count(*) FILTER (WHERE source = 'MOBILE_APP') AS via_agent,
       min(birth_date) AS first_birth, max(birth_date) AS last_birth
FROM birth_events WHERE id_company = :tenant;

\echo '=== 2. Calves with mother_id but NO birth_events row (calf_id link) ==='
SELECT count(*) AS calves_with_mother_no_birth_event
FROM cattle_livestock c
WHERE c.tenant_id = :tenant AND c.mother_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM birth_events b WHERE b.id_company = c.tenant_id AND b.calf_id = c.id);

\echo '=== 3. Female heifers (NOVILLONA) and eligibility by the 15 months OR 300 kg rule ==='
CREATE TEMP VIEW _heifer AS
WITH f AS (
  SELECT l.id, l.numero_fuego, l.birth_date, l.current_weight_kg, l.current_status, l.category,
         substring(l.numero_fuego from '^(\d{2})-\d+-\d{1,2}$')::int AS yy_cur, substring(l.numero_fuego from '^\d{2}-\d+-(\d{1,2})$')::int AS mm_cur, substring(l.numero_fuego from '^(\d{2})\d{2}$')::int AS yy_leg
  FROM cattle_livestock l
  WHERE l.tenant_id = :tenant AND l.category IN ('NOVILLONA','BECERRA')
    AND l.current_status NOT IN ('VENDIDO','BAJA_MORTANDAD','FINALIZADO','BAJA_DEPURACION_DATOS')
), s AS (
  SELECT f.*,
    CASE WHEN yy_cur >= 25 AND mm_cur BETWEEN 1 AND 12 THEN 'CURRENT'
         WHEN yy_leg BETWEEN 5 AND 24 THEN 'LEGACY' END AS shape
  FROM f
), g AS (
  SELECT s.*,
    CASE WHEN birth_date IS NOT NULL AND birth_date <> DATE '2020-01-01' THEN 'REGISTRADA'
         WHEN shape = 'CURRENT' THEN 'ESTIMADA_NUMERO_FUEGO_MES'
         WHEN shape = 'LEGACY'  THEN 'ESTIMADA_NUMERO_FUEGO_ANIO' END AS age_source,
    CASE
      WHEN birth_date IS NOT NULL AND birth_date <> DATE '2020-01-01' THEN
        (extract(year FROM current_date)*12 + extract(month FROM current_date))
        - (extract(year FROM birth_date)*12 + extract(month FROM birth_date))
      WHEN shape = 'CURRENT' THEN
        (extract(year FROM current_date)*12 + extract(month FROM current_date)) - ((2000 + yy_cur)*12 + mm_cur)
      WHEN shape = 'LEGACY' THEN   -- worst case: born in December of that year
        (extract(year FROM current_date)*12 + extract(month FROM current_date)) - ((2000 + yy_leg)*12 + 12)
    END AS age_months_floor
  FROM s
)
SELECT g.*,
  (age_months_floor >= 15) AS by_age,
  (category = 'BECERRA') AS category_possibly_outdated,
  (COALESCE(current_weight_kg,0) >= 300) AS by_weight
FROM g;

-- Everything below is read-only; the session-local view above is the only object created.
SET default_transaction_read_only = on;

SELECT count(*) AS active_novillonas_and_becerras,
       count(*) FILTER (WHERE category = 'BECERRA' AND (by_age OR by_weight)) AS becerras_eligible_category_possibly_outdated,
       count(*) FILTER (WHERE current_status = 'PREÑADA')                              AS already_pregnant,
       count(*) FILTER (WHERE by_age OR by_weight)                                       AS eligible_total,
       count(*) FILTER (WHERE by_age AND age_source IN ('REGISTRADA','ESTIMADA_NUMERO_FUEGO_MES')) AS eligible_by_age_month_precision,
       count(*) FILTER (WHERE by_age AND age_source = 'ESTIMADA_NUMERO_FUEGO_ANIO')     AS eligible_by_year_only_estimate,
       count(*) FILTER (WHERE by_weight)                                                AS eligible_by_weight,
       count(*) FILTER (WHERE by_weight AND NOT COALESCE(by_age,false))                 AS eligible_by_weight_only,
       count(*) FILTER (WHERE age_source IS NULL AND COALESCE(current_weight_kg,0) < 300) AS no_usable_age_and_no_weight,
       count(*) FILTER (WHERE age_source = 'ESTIMADA_NUMERO_FUEGO_ANIO' AND NOT by_age) AS year_only_undecidable,
       count(*) FILTER (WHERE COALESCE(current_weight_kg,0) = 0)                        AS weight_zero
FROM _heifer;

\echo '=== 3b. Informational: BECERRA that already look >= 15 months (category lag) ==='
SELECT count(*) AS becerras_aged_15m_plus
FROM cattle_livestock l
WHERE l.tenant_id = :tenant AND l.category = 'BECERRA'
  AND l.current_status NOT IN ('VENDIDO','BAJA_MORTANDAD','FINALIZADO','BAJA_DEPURACION_DATOS')
  AND ((l.birth_date IS NOT NULL
        AND (extract(year FROM current_date)*12 + extract(month FROM current_date))
          - (extract(year FROM l.birth_date)*12 + extract(month FROM l.birth_date)) >= 15)
    OR (l.birth_date IS NULL AND substring(l.numero_fuego from '^(\d{2})-\d+-\d{1,2}$')::int >= 25 AND substring(l.numero_fuego from '^\d{2}-\d+-(\d{1,2})$')::int BETWEEN 1 AND 12
        AND (extract(year FROM current_date)*12 + extract(month FROM current_date))
          - ((2000 + substring(l.numero_fuego from '^(\d{2})-\d+-\d{1,2}$')::int)*12 + substring(l.numero_fuego from '^\d{2}-\d+-(\d{1,2})$')::int) >= 15));

\echo '=== 4. Weight history: does current_weight_kg have dated history? ==='
SELECT count(*) AS weight_logs, count(DISTINCT w.livestock_id) AS animals_with_logs,
       min(w.log_date) AS first_log, max(w.log_date) AS last_log
FROM cattle_weight_logs w JOIN cattle_livestock l ON l.id = w.livestock_id AND l.tenant_id = :tenant;

\echo '=== 5. Palpation records (cattle_health_logs, event_type = PALPACION) ==='
SELECT count(*) AS palpation_rows, count(DISTINCT h.livestock_id) AS animals_palpated
FROM cattle_health_logs h JOIN cattle_livestock l ON l.id = h.livestock_id AND l.tenant_id = :tenant
WHERE h.event_type = 'PALPACION';

SELECT count(*) AS active_novillonas_with_palpation
FROM _heifer hf
WHERE EXISTS (SELECT 1 FROM cattle_health_logs h WHERE h.livestock_id = hf.id AND h.event_type = 'PALPACION');

\echo '=== 6. Services (cattle_breeding_events) ==='
SELECT count(*) AS breeding_events FROM cattle_breeding_events WHERE tenant_id = :tenant;

-- The method column name is not versioned in the repo: discover it and group by it.
SELECT format('SELECT %I AS method, count(*) AS events FROM cattle_breeding_events WHERE tenant_id = %s GROUP BY 1 ORDER BY 2 DESC',
              column_name, :tenant)
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'cattle_breeding_events'
  AND (column_name ILIKE '%method%' OR column_name ILIKE '%metodo%')
\gexec

\echo '=== 7. Breeding events voided (event_voids) ==='
SELECT count(*) AS voided_breeding_events FROM event_voids
WHERE event_table = 'cattle_breeding_events' AND tenant_id = :tenant;
