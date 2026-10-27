-- repro_02_numero_fuego.sql  (READ-ONLY, per tenant)
-- Measures the shapes of numero_fuego and how well the age parsed from it agrees with real birth_date.
--
--   psql -v ON_ERROR_STOP=1 -X -v tenant=5 -d hosting3m_db -f repro_02_numero_fuego.sql > /root/repro_02_numero_fuego_t5.txt 2>&1
--
-- Needs a session that is NOT read-only at start (it creates a session-local TEMP view); it switches itself to read-only afterwards.
-- Fail-closed: aborts when :tenant is not set or the company does not exist.
-- Parser spec (draft, becomes fn_estimate_birth_from_fire_number in Phase 1):
--   CURRENT  ^(\d{2})-(\d+)-(\d{1,2})$   YY >= 25, month 1..12            -> year 2000+YY, month, precision MONTH
--   LEGACY   ^\d{4}$                     YY 05..24 (first two digits)      -> year 2000+YY, NO month, precision YEAR
--   anything else (spaces, suffixes such as '08-4 P', dashed with YY < 25, other lengths) -> OTHER, not parsed.
-- UNCONFIRMED_SHAPE (5 digits; 4 digits with YY >= 25) and NO_YEAR_ENCODING (3 digits) are reported, never parsed.
-- Year sanity: year <= current year and year >= 2005 (assumption, see open questions).
\set ON_ERROR_STOP on
\if :{?tenant}
\else
  \echo 'ERROR: pass -v tenant=<id_company>. Refusing to run without a tenant.'
  \quit
\endif

SELECT CASE WHEN count(*) = 1 THEN 'tenant ok' ELSE 'ERROR: unknown tenant' END AS tenant_check,
       max(company_name) AS company_name
FROM companys WHERE id_company = :tenant;

CREATE TEMP VIEW _fire AS
WITH base AS (
  SELECT l.id, l.numero_fuego, l.birth_date, l.category, l.current_status,
         substring(l.numero_fuego from '^(\d{2})-\d+-\d{1,2}$')::int AS yy_cur, substring(l.numero_fuego from '^\d{2}-\d+-(\d{1,2})$')::int AS mm_cur, substring(l.numero_fuego from '^(\d{2})\d{2}$')::int AS yy_leg
  FROM cattle_livestock l
  WHERE l.tenant_id = :tenant
), shaped AS (
  SELECT b.*,
    CASE
      WHEN yy_cur >= 25 AND mm_cur BETWEEN 1 AND 12 THEN 'CURRENT'
      WHEN yy_leg BETWEEN 5 AND 24                  THEN 'LEGACY'
      WHEN numero_fuego IS NULL OR btrim(numero_fuego) = '' THEN 'EMPTY'
      WHEN yy_cur IS NOT NULL                       THEN 'DASHED_REJECTED'
      -- Unconfirmed by the client: never parsed until confirmed (extend here when they are).
      WHEN numero_fuego ~ '^\d{5}$'                 THEN 'UNCONFIRMED_SHAPE'   -- e.g. 19102 (YY + 3-digit consecutive?)
      WHEN yy_leg >= 25                             THEN 'UNCONFIRMED_SHAPE'   -- e.g. 2534 (current format without dashes?)
      WHEN numero_fuego ~ '^\d{3}$'                 THEN 'NO_YEAR_ENCODING'    -- e.g. 375 (bulls)
      WHEN yy_leg IS NOT NULL                       THEN 'FOUR_DIGITS_REJECTED'
      ELSE 'OTHER'
    END AS shape
  FROM base b
)
SELECT s.id, s.numero_fuego, s.birth_date, s.category, s.current_status, s.shape,
  CASE s.shape WHEN 'CURRENT' THEN 2000 + yy_cur WHEN 'LEGACY' THEN 2000 + yy_leg END AS est_year,
  CASE s.shape WHEN 'CURRENT' THEN mm_cur END AS est_month
FROM shaped s;

-- Everything below is read-only; the session-local view above is the only object created.
SET default_transaction_read_only = on;

\echo '=== 1. Counts by shape ==='
SELECT shape, count(*) AS animals FROM _fire GROUP BY shape ORDER BY animals DESC;

\echo '=== 2. Distinct patterns of the non-parsed values (digits -> 9, letters -> A) with examples ==='
SELECT shape,
       regexp_replace(regexp_replace(numero_fuego, '[0-9]', '9', 'g'), '[A-Za-z]', 'A', 'g') AS pattern,
       count(*) AS animals,
       (array_agg(DISTINCT numero_fuego))[1:5] AS examples
FROM _fire
WHERE shape IN ('OTHER','DASHED_REJECTED','FOUR_DIGITS_REJECTED','UNCONFIRMED_SHAPE','NO_YEAR_ENCODING')
GROUP BY 1, 2
ORDER BY animals DESC;

\echo '=== 3. Estimated-year distribution (parsed shapes only) ==='
SELECT shape, est_year, count(*) AS animals
FROM _fire WHERE shape IN ('CURRENT','LEGACY') GROUP BY 1, 2 ORDER BY 1, 2;

\echo '=== 4. Implausible years (future or before 2005) ==='
SELECT shape, est_year, count(*) FROM _fire
WHERE shape IN ('CURRENT','LEGACY') AND (est_year > extract(year FROM current_date) OR est_year < 2005)
GROUP BY 1, 2;

\echo '=== 5. Duplicated numero_fuego within the tenant (value, copies) ==='
SELECT numero_fuego, count(*) AS copies
FROM _fire WHERE shape <> 'EMPTY' GROUP BY 1 HAVING count(*) > 1 ORDER BY copies DESC, 1 LIMIT 50;

\echo '=== 6a. birth_date quality: import placeholder 2020-01-01 is treated as NO DATE ==='
SELECT count(*) AS animals,
       count(*) FILTER (WHERE birth_date IS NULL)             AS null_date,
       count(*) FILTER (WHERE birth_date = DATE '2020-01-01') AS placeholder_2020_01_01,
       count(*) FILTER (WHERE birth_date IS NOT NULL AND birth_date <> DATE '2020-01-01') AS real_date,
       count(*) FILTER (WHERE birth_date IS NOT NULL AND birth_date <> DATE '2020-01-01' AND shape IN ('EMPTY')) AS real_date_without_fire_number,
       count(*) FILTER (WHERE birth_date IS NOT NULL AND birth_date <> DATE '2020-01-01' AND extract(day FROM birth_date) = 9) AS real_date_day_9
FROM _fire;

\echo '=== 6b. Agreement with a REAL birth_date (placeholder excluded), per format ==='
-- Month agreement is only meaningful for CURRENT. Day is never compared (unreliable).
SELECT shape,
       count(*)                                                                 AS with_real_date,
       count(*) FILTER (WHERE est_year = extract(year FROM birth_date))          AS year_agree,
       round(100.0 * count(*) FILTER (WHERE est_year = extract(year FROM birth_date)) / NULLIF(count(*),0), 1) AS year_agree_pct,
       count(*) FILTER (WHERE est_month IS NOT NULL)                            AS month_comparable,
       count(*) FILTER (WHERE est_month = extract(month FROM birth_date))        AS month_agree,
       round(100.0 * count(*) FILTER (WHERE est_month = extract(month FROM birth_date))
             / NULLIF(count(*) FILTER (WHERE est_month IS NOT NULL),0), 1)       AS month_agree_pct,
       count(*) FILTER (WHERE est_year IS NOT NULL AND abs(est_year - extract(year FROM birth_date)) = 1) AS year_off_by_one
FROM _fire
WHERE shape IN ('CURRENT','LEGACY') AND birth_date IS NOT NULL AND birth_date <> DATE '2020-01-01'
GROUP BY shape;

\echo '=== 7. Disagreeing rows (up to 30, identifiers only) ==='
SELECT shape, numero_fuego, birth_date, est_year, est_month
FROM _fire
WHERE shape IN ('CURRENT','LEGACY') AND birth_date IS NOT NULL AND birth_date <> DATE '2020-01-01'
  AND (est_year <> extract(year FROM birth_date)
       OR (est_month IS NOT NULL AND est_month <> extract(month FROM birth_date)))
ORDER BY birth_date LIMIT 30;

\echo '=== 8. Coverage: animals with no real birth_date by usable estimate ==='
SELECT (birth_date IS NOT NULL) AS has_real_date, shape, count(*) FROM _fire GROUP BY 1, 2 ORDER BY 1 DESC, 3 DESC;
