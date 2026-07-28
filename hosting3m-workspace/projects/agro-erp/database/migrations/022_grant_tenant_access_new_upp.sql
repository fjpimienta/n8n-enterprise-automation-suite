-- Migration 022: Grants tenant access for the companies created by migration 019.
--
-- Migration 019 created two tenants (UPP Santa Lucía, UPP San Pedro) but did not create the
-- matching rows in user_companies, so both were born ORPHANED: no user could administer them
-- and they never appeared in the Context Switcher. Fixed by hand in production on 2026-07-27;
-- this migration versions that fix so a from-scratch deployment reproduces it.
--
-- RULE TO CARRY FORWARD: any migration that creates a tenant must also grant access to it.
-- A tenant without a user_companies row is invisible to the application even though every
-- query against it succeeds.
--
-- The grantee is the holder named on all three SENASICA constancias, who already had ADMIN
-- access to companies 5, 6 and 7. Change the email below if a different administrator applies.
BEGIN;

INSERT INTO public.user_companies (email, id_company, role, is_active)
SELECT 'aguilar.resendez@hotmail.com', c.id_company, 'ADMIN', true
  FROM public.companys c
 WHERE c.company_name IN ('UPP Santa Lucía y Anexo Nuevo Horizonte 2', 'UPP San Pedro')
   AND EXISTS (SELECT 1 FROM public.users u WHERE u.email = 'aguilar.resendez@hotmail.com')
   AND NOT EXISTS (
        SELECT 1 FROM public.user_companies uc
         WHERE uc.email = 'aguilar.resendez@hotmail.com'
           AND uc.id_company = c.id_company);

COMMIT;
