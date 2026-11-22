> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: tested on a throwaway LOCAL database only. NOT applied to production.**
> Part 1 (database) is the only part that exists in this pull request. Part 2 (n8n) does not apply: this migration touches no workflow, so Part 2 is "nothing to import" (the palm router and the two agent tools are later pull requests). There is no frontend part.
> Requires 080, 081, 083, 092, 104 and 109 applied in production (they are).

# Runbook 111 — palm expenses backed by a received CFDI voucher

## Scope

| Object | Kind | Notes |
|---|---|---|
| `agri_expense_invoices` | table (new) | append-only link voucher ↔ `agri_expenses`; the only change is `ACTIVE → VOID` |
| `agri_expenses` | existing table | **one new constraint** `UNIQUE (id, id_company)` (the id is already the primary key) and **one new AFTER UPDATE trigger** `trg_agri_expenses_void_invoice` |
| `fn_agri_cfdi_category(text)`, `fn_agri_cfdi_unit(text)` | functions (new, IMMUTABLE) | product-key prefix → category code (fuel only), SAT unit key → unit code |
| `fn_agri_expense_invoice_params_hash(...)` | function (new, IMMUTABLE) | preview hash: category, description, date, plantation, lot |
| `fn_trg_agri_expense_invoices_guard()`, `fn_trg_agri_expenses_void_invoice()` | trigger functions (new) | |
| `sp_agri_expense_invoice_draft_create / _preview / _confirm / _register` | functions (new) | the palm counterpart of 092 / 091 |

No existing function is replaced, so there is no drift guard to evaluate; the migration aborts if one of its four procedure names already exists and is not a 111 function. Nothing is registered in `crud_models`. Privileges and attributes follow 091 / 092 / 104: plain plpgsql `VOLATILE`, not `SECURITY DEFINER`, no `search_path`, no `REVOKE` (the workflow role is a superuser). `expense_invoice_drafts` (092) is reused as is.

Behaviour: ADMIN / OWNER of a palm company only (EDITOR keeps manual capture). Only a voucher whose receiver is a company RFC (109 role `EXPENSE`) is accepted; a sale, an ambiguous voucher, a voucher of an unknown receiver or an unavailable classifier is refused with a fixed message and nothing written. SAT must be `VIGENTE`; a company flagged `is_test` also accepts `NO_ENCONTRADO` / `ERROR`, stored as `SKIPPED_TEST`; `CANCELADO` never. The expense is written by `sp_agri_record_expense` in the same transaction. Voiding the expense (`sp_agri_void_expense`) voids the link and frees the UUID.

| File | Purpose |
|---|---|
| `111_palm_expense_invoices.sql` | the change (dry run by default; preconditions; self-check) |
| `111_rollback.sql` | replaces the four procedures with a fail-closed stub (`{status: disabled}`); drops nothing |
| `111_state_check.sql` | `-v expect=before\|applied\|rolled_back`, read-only, fingerprints and attributes |
| `111_tests.sql` | one rolled-back transaction (throwaway database only), 147 assertions |
| `111_mutation_check.sh` | control run plus six mutations, each must make the tests fail |

## Order with 109

Apply 109 first (it is applied). 111 aborts if 109 is missing or is the rollback stub. If 109 is rolled back while 111 is applied, the classifier answers `UNKNOWN` / `DISABLED` and the palm procedures refuse every voucher (`ROLE_UNAVAILABLE`, fail closed). Roll back 111 first when both must go.

## Part 1 — database

### 1.1 Local first (throwaway database, name must contain `test` or `rehearsal`)

Requires 080, 081 (with its unit catalog seed), 083, 091, 092, 104 and 109 applied.

```sh
psql -X -v ON_ERROR_STOP=1 -v expect=before -f 111_state_check.sql      # STATE OK: before
psql -X -v ON_ERROR_STOP=1 -f 111_palm_expense_invoices.sql             # dry run: "111: OK" then ROLLBACK
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 111_palm_expense_invoices.sql
psql -X -v ON_ERROR_STOP=1 -v expect=applied -f 111_state_check.sql     # STATE OK: applied
psql -X -v ON_ERROR_STOP=1 -f 111_tests.sql                             # "111 TESTS: 147 assertions passed (mutation=none)"
bash 111_mutation_check.sh                                              # M0 PASS, M1..M6 DETECTED
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 111_rollback.sql
psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 111_state_check.sql # STATE OK: rolled_back
```

`111_tests.sql` and `111_mutation_check.sh` run from this directory (they include the 109 and 111 files) and work before or after 111 is applied. If the database is in a container, copy the `109_*` and `111_*` files into one directory of the container and set `PSQL="docker exec -i -w <dir> <container> psql -U <user> -d <throwaway database>"` for the mutation script. The tests print no errors on success; only a line starting with `FAIL [` or a non-zero exit code is a failure.

### 1.2 Production (only after 1.1 passes)

1. **Before:** `psql -X -v ON_ERROR_STOP=1 -v expect=before -f 111_state_check.sql` → `STATE OK: before`. Save the output. Also confirm 109 is applied (`109_state_check.sql -v expect=applied`) and that the unit catalog has the rows `KG`, `L`, `PZA`, `SERVICIO`:
   `SELECT unit_code FROM agri_unit_catalog WHERE unit_code IN ('KG','L','PZA','SERVICIO') AND is_active;` → 4 rows.
2. **Backup:** the migration creates objects and one constraint / trigger on `agri_expenses`; take the standard `pg_dump -Fc` first (rule: a backup step before any production change).
3. **Dry run:** `psql -X -v ON_ERROR_STOP=1 -f 111_palm_expense_invoices.sql` → `111: OK` and `DRY RUN ... rolled back`.
4. **Apply:** `psql -X -v ON_ERROR_STOP=1 -v apply=true -f 111_palm_expense_invoices.sql` → `*** 111 COMMITTED ***`. (The `UNIQUE (id, id_company)` on `agri_expenses` builds an index on that table; it is small, but run it outside a heavy period.)
5. **After:** `psql -X -v ON_ERROR_STOP=1 -v expect=applied -f 111_state_check.sql` → `STATE OK: applied`. Save the output; the md5 of each function must equal the ones recorded in the local run of 1.1 on the same PostgreSQL major version (`pg_get_functiondef` is produced by the server; on another major version compare the function bodies instead). Expected: `link_table`, `void_trigger`, `expenses_unique` true; `models_in_crud_models` 0.
6. **Behaviour check on TEST company 10 only** (never any other company), inside `BEGIN ... ROLLBACK`, with a synthetic voucher. The company RFC is read into a psql variable and **never printed**; replace `<member e-mail>` with an ADMIN or OWNER of company 10 (do not paste it anywhere shared). The foreign RFC and the UUIDs are made up. Everything, including the confirmed registration and its void, is rolled back.

   ```sql
   BEGIN;
   \set co 10
   \set mail '<member e-mail>'
   SELECT rfc AS own_rfc FROM company_issuer_rfcs WHERE id_company = :co AND is_active ORDER BY rfc LIMIT 1 \gset
   SELECT repeat('a', 64) AS sha, :co || '/2026/10/' || repeat('a', 64) || '.xml' AS path, 'TEX010101EX1' AS other_rfc,
          upper(gen_random_uuid()::text) AS u_sale, upper(gen_random_uuid()::text) AS u_exp,
          to_char(fn_agri_today_cdmx() - 5, 'YYYY-MM-DD') || 'T08:49:01' AS issued \gset
   -- sale: the company is the issuer -> not_an_expense / ROLE_SALE, nothing written
   SELECT 'sale' AS probe, r ->> 'status' AS status, r ->> 'code' AS code
     FROM (SELECT sp_agri_expense_invoice_register(:'co', :'mail',
             jsonb_build_object('uuid', :'u_sale', 'serie', 'T', 'folio', '1', 'fechaEmision', :'issued', 'fechaTimbrado', :'issued',
               'emisor', jsonb_build_object('rfc', :'own_rfc', 'nombre', 'PRUEBA'), 'receptor', jsonb_build_object('rfc', :'other_rfc', 'nombre', 'PRUEBA'),
               'moneda', 'MXN', 'tipoComprobante', 'I', 'subtotalCents', 1000, 'descuentoCents', 0, 'totalCents', 1000, 'traslados', '[]'::jsonb,
               'retenciones', '[]'::jsonb, 'sourceSha256', :'sha',
               'conceptos', jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'claveUnidad', 'LTR', 'cantidad', '1', 'importeCents', 1000)))::text,
             :'path', 'VIGENTE', NULL, NULL, NULL, NULL, NULL, 'true') AS r) q                        -- expect not_an_expense / ROLE_SALE
   UNION ALL
   -- expense, unconfirmed: preview, nothing written
   SELECT 'expense preview', r ->> 'status', r #>> '{summary,category_code}'
     FROM (SELECT sp_agri_expense_invoice_register(:'co', :'mail',
             jsonb_build_object('uuid', :'u_exp', 'serie', 'T', 'folio', '2', 'fechaEmision', :'issued', 'fechaTimbrado', :'issued',
               'emisor', jsonb_build_object('rfc', :'other_rfc', 'nombre', 'PRUEBA'), 'receptor', jsonb_build_object('rfc', :'own_rfc', 'nombre', 'PRUEBA'),
               'moneda', 'MXN', 'tipoComprobante', 'I', 'subtotalCents', 1000, 'descuentoCents', 0, 'totalCents', 1000, 'traslados', '[]'::jsonb,
               'retenciones', '[]'::jsonb, 'sourceSha256', :'sha',
               'conceptos', jsonb_build_array(jsonb_build_object('claveProdServ', '15101505', 'descripcion', 'Diesel', 'claveUnidad', 'LTR', 'cantidad', '1', 'importeCents', 1000)))::text,
             :'path', 'VIGENTE', NULL, NULL, NULL, NULL, NULL, 'false') AS r) q;                       -- expect preview / COMBUSTIBLE
   SELECT (SELECT count(*) FROM agri_expense_invoices WHERE uuid IN (:'u_sale', :'u_exp')) AS links_written;   -- expect 0
   ROLLBACK;
   ```

   Expected: `sale` → `not_an_expense` / `ROLE_SALE`; `expense preview` → `preview` / `COMBUSTIBLE` (the category depends on the fuel product-key family, see Risks); `links_written = 0`. If company 10 has no active issuer RFC, the first `\gset` leaves the variable undefined and the script fails: stop and report; do not insert one just to test. Optionally repeat the second probe with the last argument `'true'` and then `SELECT sp_agri_void_expense(:co, <expense_id>, 'prueba', :'mail')` to see the link voided — inside the same transaction, before the `ROLLBACK`. Do not run any of this for a real company.
7. **Privileges unchanged:** `111_state_check.sql` prints `public_can_execute` and `security_definer` for the four procedures; they must match the local run.

### 1.3 Rollback

```sh
psql -X -v ON_ERROR_STOP=1 -f 111_rollback.sql                 # dry run
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 111_rollback.sql   # commit
psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 111_state_check.sql
```

The four procedures keep their signatures and answer `{status: disabled}` (nothing written). The link table, its rows, the helper functions and the void trigger stay: expenses registered while 111 was applied remain valid, and voiding one of them still voids its link. Re-applying `111_palm_expense_invoices.sql` restores the procedures. Nothing is dropped, deleted or truncated.

## Part 2 — n8n

Nothing to import. The palm router, the draft creation call and the two agent tools (`preview` / `confirm` of the palm company) are separate pull requests that depend on this one being applied and verified. The parser must be called with the `sale` profile for these vouchers: without it the voucher has no `formaPago` and no `claveUnidad`, so the cash warning and the quantity and unit are simply not produced (nothing fails).

## Part 3 — frontend

Not part of this pull request. Only after Part 1 is verified in production may this pull request reach `main`.

## Risks

* **Fuel product keys.** The category map is seeded with the `1510` product-key prefix only; the exact SAT family is marked `TODO(verify)` in `fn_agri_cfdi_category`. A voucher whose keys are not mapped gets a preview that lists the company categories and asks; nothing is invented. Adding a family is one line.
* **Palm RFCs are platform-managed.** A company that has no active issuer RFC row cannot register anything here (every voucher is `ROLE_UNKNOWN`). There is no self-registration.
* **Quantity and unit** are filled only for a single-concept voucher with a mapped unit; the rest of the quantity information stays in the voucher stored in the link table.
* **The link table is the record of the voucher**, not a copy of the expense: the expense stays editable only by voiding it (as before).
* A company with two palm companies sharing the same receiver RFC can register the same CFDI in both (the uniqueness is per company, like 091); the RFCs are platform-managed, so this is a platform decision.
