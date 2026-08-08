-- Migration 035: PSG license for Pedro Aguilar Reséndez (Tabasco, "Predio de Repasto").
--
-- SOURCE: SEDAFOP credential supplied 2026-08-05, distinct from Pedro's earlier "Productor"
-- credential (already loaded, state registry P01-27-009-01462). This one is labeled
-- "PREDIO DE REPASTO" with a different state registry (P14-27-009-03692) and the PSG
-- code printed on the back: 27-009-0514-P14.
--
-- issued_at deliberately NULL: the credential shows two dates ("Registro: 009 L-H155
-- REVERSO 2015" and "Fecha de expedición: 04.02.2020") and the client explicitly asked to
-- leave it unset for now rather than guess which one is the license's actual issue date.
-- fn_psg_validity_status() already handles a NULL issued_at by returning 'UNKNOWN'
-- (see migration 014) — this is the intended, correct state for genuinely unconfirmed data,
-- not a workaround.
BEGIN;

INSERT INTO public.psg_licenses
    (id_company, producer_id, psg_code, state_name, municipality_name,
     issuing_window, issued_at, notes)
SELECT c.id_company, p.id, '27-009-0514-P14', 'Tabasco', 'Jalapa',
       'SEDAFOP - Predio de Repasto', NULL,
       'Credencial "Predio de Repasto" (distinta de la credencial "Productor" ya cargada). '
       || 'Registro estatal P14-27-009-03692. Fecha de emisión pendiente de confirmar: '
       || 'la credencial trae "2015" (año de registro) y "04.02.2020" (fecha de expedición '
       || 'de la tarjeta) sin que quede claro cuál corresponde a la vigencia real del PSG.'
  FROM public.companys c
  LEFT JOIN public.livestock_producers p
         ON p.id_company = c.id_company AND p.producer_role = 'TITULAR'
 WHERE c.company_name = 'UPP 54'
   AND NOT EXISTS (
        SELECT 1 FROM public.psg_licenses pl
         WHERE pl.id_company = c.id_company AND pl.psg_code = '27-009-0514-P14');

COMMIT;
