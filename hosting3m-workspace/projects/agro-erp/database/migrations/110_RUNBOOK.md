> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: tested on a throwaway LOCAL database only. NOT applied to production.**
> Part 1 (database) is the only part that exists in this pull request. Part 2 (n8n) does not apply: this migration touches no workflow, so Part 2 is "nothing to import". There is no frontend part.
> Requires 109 applied in production (it is).

# Runbook 110 — expense registration only accepts vouchers received by the company

## Scope

| Object | Kind | Notes |
|---|---|---|
| `sp_expense_invoice_register(text × 9)` | function (replaced, same signature) | role gate between the invoice parsing and the receiver-RFC lookup; everything else is the 093 text unchanged |
| `sp_company_tax_id_set(text × 5)` | function (replaced, same signature) | refuses the generic SAT RFCs (`XAXX010101000`, `XEXX010101000`) |

Nothing else changes: no table, trigger, view, data or `crud_models` row; `sp_expense_invoice_preview` / `_confirm` / `_draft_create` are untouched. Attributes are exactly those of the functions they replace (plain plpgsql, `VOLATILE`, not `SECURITY DEFINER`, no `search_path`, no `REVOKE`; the workflow role is a superuser). The migration does not touch privileges.

A generic-RFC row that already exists (for example the one inserted by `091_seed_qa_company3.sql` for test company 3) stays valid and is not touched by 110.

Behaviour:

| Classifier answer (109) | Result of `sp_expense_invoice_register` (preview and confirm) |
|---|---|
| `EXPENSE` | unchanged (093 flow) |
| `UNKNOWN` / `NEITHER` | unchanged (093 flow: unknown receiver → ADMIN/OWNER preview with `rfc_new`, EDITOR `rfc_not_registered`) |
| `SALE` | `{status: not_an_expense, code: ROLE_SALE, message}`, nothing written, no RFC created |
| `AMBIGUOUS` | `{status: not_an_expense, code: ROLE_AMBIGUOUS, message}`, nothing written |
| anything else: other `UNKNOWN` reasons, `NULL`, an exception of the classifier, the 109 rollback stub | `{status: not_an_expense, code: ROLE_UNAVAILABLE, message}`, fail closed, nothing written |

The messages are fixed Spanish texts: no RFC, UUID, name or amount. A generic receiver RFC on the 093 auto-register branch answers `rfc_generic` with a fixed text and writes nothing. A generic row that already exists keeps working and can be deactivated, never reactivated.
`sp_expense_invoice_preview` returns the register result unchanged (plus `draft_id`) and marks the draft as previewed only for `status = preview`; `sp_expense_invoice_confirm` marks the draft as consumed only for `recorded` / `duplicate`. A `not_an_expense` answer therefore leaves the draft untouched.

| File | Purpose |
|---|---|
| `110_expense_invoice_role_gate.sql` | the change (dry run by default; drift guard; preconditions; self-check) |
| `110_rollback.sql` | restores the exact 093 / 091 function bodies (no DROP) |
| `110_state_check.sql` | `-v expect=before\|applied\|rolled_back`, read-only, md5 of the two functions and their attributes |
| `110_tests.sql` | one rolled-back transaction (throwaway database only), 84 assertions |
| `110_mutation_check.sh` | control run plus four mutations, each must make the tests fail |

## Order with 109 (important)

* **Apply:** 109 first (already applied), then 110. 110 aborts if 109 is missing or is the rollback stub.
* **Roll back:** **110 first, then 109.** If 109 is rolled back while 110 is applied, the classifier answers `UNKNOWN` / `DISABLED` and registration refuses every voucher (`ROLE_UNAVAILABLE`, fail closed) until one of the two is restored.

## Drift guard and the md5 constants

Both functions are replaced only if the live text is the repository text or already the 110 text. The constants are the `md5(pg_get_functiondef(...))` of the functions as created by the repository chain, obtained like this on a throwaway database (PostgreSQL 15.4):

```sh
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 091_expense_invoices.sql
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 092_expense_invoice_drafts.sql
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 093_auto_receptor_rfc.sql
psql -X -Atc "SELECT proname, md5(pg_get_functiondef(oid)) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN ('sp_expense_invoice_register', 'sp_company_tax_id_set') ORDER BY 1"
```

| Function | Repository chain (091 / 093) | 110 text |
|---|---|---|
| `sp_company_tax_id_set` | `e89f615ed99bae63adb6d53554819789` | `f7cec648615c6741f166d9356f0530c9` |
| `sp_expense_invoice_register` | `0612086a244911ac15c47a5405f7ac0b` | `acbeeb49f222d36de95f8db2be3cd4be` |

`pg_get_functiondef` is produced by the server, so the md5 can differ between PostgreSQL major versions. If the production server is another major version, recompute the two "repository chain" values by applying 091..093 on a throwaway database **of that version** and compare; do not edit the guard to make it pass. If production differs from the repository, the migration aborts and nothing is changed: find out why before doing anything else (the standard rule of this suite: compare production with `main` by fingerprint before changing it).

## Part 1 — database

### 1.1 Local first (throwaway database, name must contain `test` or `rehearsal`)

Requires 080, 084, 091, 092, 093, 104 and 109 applied, with 091..093 at their repository text.

```sh
psql -X -v ON_ERROR_STOP=1 -v expect=before -f 110_state_check.sql      # STATE OK: before
psql -X -v ON_ERROR_STOP=1 -f 110_expense_invoice_role_gate.sql         # dry run: "110: OK" then ROLLBACK
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 110_expense_invoice_role_gate.sql
psql -X -v ON_ERROR_STOP=1 -v expect=applied -f 110_state_check.sql     # STATE OK: applied
psql -X -v ON_ERROR_STOP=1 -f 110_tests.sql                             # "110 TESTS: 84 assertions passed (mutation=none)"
bash 110_mutation_check.sh                                              # M0 PASS, M1..M4 DETECTED
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 110_rollback.sql
psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 110_state_check.sql # STATE OK: rolled_back
```

`110_tests.sql` starts from the repository 091 / 093 text, so run it before applying 110 (or after `110_rollback.sql`); `091_tests.sql`, `092_tests.sql`, `093_tests.sql` and `109_tests.sql` also pass with 110 applied.
The tests print a few expected errors (the drift guard and the 109-stub precondition aborting inside a savepoint); only a line starting with `FAIL [` or a non-zero exit code is a failure.
`110_tests.sql` and `110_mutation_check.sh` run from this directory (they include the 109 and 110 files). If the database is in a container, copy the `109_*` and `110_*` files into one directory of the container and set `PSQL="docker exec -i -w <dir> <container> psql -U <user> -d <throwaway database>"` for the mutation script.

### 1.2 Production (only after 1.1 passes)

1. **Before:** `psql -X -v ON_ERROR_STOP=1 -v expect=before -f 110_state_check.sql` → `STATE OK: before` (this is the production text equal to the repository chain). Save the output. If it fails, **stop**: the live functions are not the repository ones.
   Also confirm 109 is applied (`109_state_check.sql -v expect=applied`).
2. **Backup:** the migration only replaces two functions, but take the standard `pg_dump -Fc` first (rule: a backup step before any production change).
3. **Dry run:** `psql -X -v ON_ERROR_STOP=1 -f 110_expense_invoice_role_gate.sql` → `110: OK` and `DRY RUN ... rolled back`.
4. **Apply:** `psql -X -v ON_ERROR_STOP=1 -v apply=true -f 110_expense_invoice_role_gate.sql` → `*** 110 COMMITTED ***`.
5. **After:** `psql -X -v ON_ERROR_STOP=1 -v expect=applied -f 110_state_check.sql` → `STATE OK: applied`. Save the output; the two md5 must equal the "110 text" column above (same PostgreSQL major version).
6. **Behaviour check on TEST company 3 only** (never any other company), inside `BEGIN ... ROLLBACK`, with a synthetic voucher. The company RFC is read into a psql variable and **never printed**; replace `<member e-mail>` with an ADMIN of company 3 (do not paste it anywhere shared). The synthetic RFC and UUID are made up.

   ```sql
   BEGIN;
   \set co 3
   \set mail '<member e-mail>'
   SELECT rfc AS own_rfc FROM company_tax_ids WHERE id_company = :co AND is_active ORDER BY rfc LIMIT 1 \gset
   SELECT repeat('a', 64) AS sha, :co || '/2026/10/' || repeat('a', 64) || '.xml' AS path, 'TEX010101EX1' AS other_rfc,
          upper(gen_random_uuid()::text) AS u1, upper(gen_random_uuid()::text) AS u2 \gset
   -- (the voucher JSON below is built from the variables; nothing is printed except the status columns)
   SELECT 'sale' AS probe,
          r ->> 'status' AS status, r ->> 'code' AS code
     FROM (SELECT sp_expense_invoice_register(:'co', :'mail',
             jsonb_build_object('uuid', :'u1', 'serie', 'T', 'folio', '1', 'fechaEmision', '2026-10-30T08:49:01', 'fechaTimbrado', '2026-10-30T08:49:13',
               'emisor', jsonb_build_object('rfc', :'own_rfc', 'nombre', 'PRUEBA'), 'receptor', jsonb_build_object('rfc', :'other_rfc', 'nombre', 'PRUEBA'),
               'moneda', 'MXN', 'subtotalCents', 1000, 'descuentoCents', 0, 'totalCents', 1000, 'traslados', '[]'::jsonb, 'retenciones', '[]'::jsonb,
               'sourceSha256', :'sha')::text,
             'COMBUSTIBLE', 'prueba', '2026-10-30', :'path', 'VIGENTE', 'true') AS r) q                    -- expect not_an_expense / ROLE_SALE
   UNION ALL
   SELECT 'expense', r ->> 'status', r ->> 'code'
     FROM (SELECT sp_expense_invoice_register(:'co', :'mail',
             jsonb_build_object('uuid', :'u2', 'serie', 'T', 'folio', '2', 'fechaEmision', '2026-10-30T08:49:01', 'fechaTimbrado', '2026-10-30T08:49:13',
               'emisor', jsonb_build_object('rfc', :'other_rfc', 'nombre', 'PRUEBA'), 'receptor', jsonb_build_object('rfc', :'own_rfc', 'nombre', 'PRUEBA'),
               'moneda', 'MXN', 'subtotalCents', 1000, 'descuentoCents', 0, 'totalCents', 1000, 'traslados', '[]'::jsonb, 'retenciones', '[]'::jsonb,
               'sourceSha256', :'sha')::text,
             'COMBUSTIBLE', 'prueba', '2026-10-30', :'path', 'VIGENTE', 'false') AS r) q;                  -- expect preview (unconfirmed: it writes nothing)
   SELECT (SELECT count(*) FROM expense_invoices WHERE uuid IN (:'u1', :'u2')) AS invoices_written;       -- expect 0
   ROLLBACK;
   ```

   Expected: `sale` → `not_an_expense` / `ROLE_SALE`; `expense` → `preview` (the second call is **unconfirmed**, so it persists nothing even without the `ROLLBACK`); `invoices_written = 0`. If company 3 has no active RFC the first `\gset` leaves the variable undefined and the script fails: stop and report, do not insert one just to test. Do not run this for any real company. (Company 3's QA RFC `XAXX010101000`, if present, keeps working: 110 does not touch existing rows.)
7. **Privileges unchanged:** `110_state_check.sql` prints `public_can_execute` and `security_definer` for both functions; they must be the same as in the saved "before" output.

### 1.3 Rollback

```sh
psql -X -v ON_ERROR_STOP=1 -f 110_rollback.sql                 # dry run
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 110_rollback.sql   # commit
psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 110_state_check.sql
```

The rollback restores the exact 093 `sp_expense_invoice_register` and 091 `sp_company_tax_id_set` bodies (verbatim copies; it checks the md5 afterwards) and drops nothing. It refuses to run if a live function is neither the 110 text nor the 091 / 093 text (running it twice is a no-op). Vouchers and RFC rows written while 110 was applied stay. **Roll back 110 before 109.**

## Part 2 — n8n

Nothing to import. The agent tools already pass the status through: `preview_expense_invoice` and `register_expense_invoice` return the procedure result and the agent explains the `message` of any status it does not know (their tool descriptions say "cualquier otro status, explícale el mensaje"). A later pull request can mention `not_an_expense` in the tool descriptions and add the router; neither is needed for 110 to be safe, because the check lives in SQL.

## Part 3 — frontend

Not part of this pull request. Only after Part 1 is verified in production may this pull request reach `main`.

## Risks

* If production's functions differ from the repository, the migration aborts (by design). Nothing is overwritten.
* If the classifier is unavailable, registration refuses everything (fail closed) until it is back; the message tells the user to retry or contact the administrator.
* The own-RFC set decides the answer: a voucher issued by a company whose own RFC was never registered looks like an unknown one (`UNKNOWN` / `NEITHER`) and keeps the 093 flow.
* A company that registered a generic RFC before 110 keeps it (QA company 3); a sale to the public in general from such a company is classified `AMBIGUOUS` (still refused).
