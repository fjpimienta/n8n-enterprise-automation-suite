-- Migration 005: Agrega NOVILLONA al CHECK de cattle_livestock.category (jerarquía
-- Becerra -> Novillona -> Vaca confirmada por el cliente). category es VARCHAR + CHECK,
-- no un ENUM nativo, por lo que el fix es DROP + ADD CONSTRAINT (mismo patrón que la
-- migración 001 usó para agregar CUARENTENA a current_status).
BEGIN;

ALTER TABLE public.cattle_livestock
    DROP CONSTRAINT cattle_livestock_category_check;

ALTER TABLE public.cattle_livestock
ADD CONSTRAINT cattle_livestock_category_check
CHECK (
    category IN (
        'VACA','TORO','NOVILLO','NOVILLONA','BECERRA','BECERRO',
        'BUFALA','BUFALO','BUCERRO','BUCERRA','BORREGO','BORREGA'
    )
);

COMMIT;
