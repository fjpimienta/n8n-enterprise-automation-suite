> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: tested on a throwaway LOCAL database only. NOT applied to production.**
> Part 1 (database) is the only part that exists in this pull request. Part 2 (n8n) does not apply: this migration touches no workflow, so Part 2 is "nothing to import".
> There is no frontend part: nothing in the application calls the new functions yet (the gate in `sp_expense_invoice_register` and the n8n router are later pull requests).

# Runbook 109 — classify a CFDI voucher as sale or expense by RFC role

## Scope

| Object | Kind | Notes |
|---|---|---|
| `fn_classify_cfdi_role_detail(integer, text, text)` | function (new) | `jsonb`, STABLE, read-only; codes and booleans only, never an RFC |
| `fn_classify_cfdi_role(integer, text, text)` | function (new) | `text`, the role only |
| `sp_cfdi_classify(text, text, text, text)` | function (new) | tenant + user e-mail + RFCs; checks the active membership first; the only entry point for n8n |

Nothing existing is altered, replaced or dropped (091 / 092 / 093 / 104 procedures untouched). No table, trigger, view or data is changed and nothing is registered in `crud_models`.
Privileges: the three functions are revoked from `PUBLIC`. As in 099 / 102 no `GRANT` is issued, because `n8n_user` is a PostgreSQL superuser; if that ever changes, grant `EXECUTE` on `sp_cfdi_classify` only.

| File | Purpose |
|---|---|
| `109_cfdi_role_classifier.sql` | the change (dry run by default; preconditions; self-check) |
| `109_rollback.sql` | replaces the three functions with a fail-closed stub (`UNKNOWN` / `DISABLED`); drops nothing |
| `109_state_check.sql` | `-v expect=before\|applied\|rolled_back`, read-only, fingerprints and privileges |
| `109_tests.sql` | one rolled-back transaction (throwaway database only), 53 assertions |
| `109_mutation_check.sh` | control run plus five mutations, each must make the tests fail |

## Part 1 — database

### 1.1 Local first (throwaway database, name must contain `test` or `rehearsal`)

```sh
psql -X -v ON_ERROR_STOP=1 -v expect=before -f 109_state_check.sql      # STATE OK: before
psql -X -v ON_ERROR_STOP=1 -f 109_cfdi_role_classifier.sql              # dry run: "109: OK" then ROLLBACK
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 109_cfdi_role_classifier.sql
psql -X -v ON_ERROR_STOP=1 -v expect=applied -f 109_state_check.sql     # STATE OK: applied
psql -X -v ON_ERROR_STOP=1 -f 109_tests.sql                             # "109 TESTS: 53 assertions passed (mutation=none)"
bash 109_mutation_check.sh                                              # M0 PASS, M1..M5 DETECTED
```

Requires 080, 091 and 104 applied (the migration aborts otherwise).

### 1.2 Production (only after 1.1 passes)

1. **Before:** `psql -X -v ON_ERROR_STOP=1 -v expect=before -f 109_state_check.sql` → `STATE OK: before`. Save the output. Confirm 080, 091 and 104 are applied (the migration's own precondition also checks it).
2. **Backup:** the migration only creates functions, but take the standard `pg_dump -Fc` anyway (rule: a backup step before any production change).
3. **Dry run:** `psql -X -v ON_ERROR_STOP=1 -f 109_cfdi_role_classifier.sql` → `109: OK` and `DRY RUN ... rolled back`.
4. **Apply:** `psql -X -v ON_ERROR_STOP=1 -v apply=true -f 109_cfdi_role_classifier.sql` → `*** 109 COMMITTED ***`.
5. **After:** `psql -X -v ON_ERROR_STOP=1 -v expect=applied -f 109_state_check.sql` → `STATE OK: applied`. Record the three `md5` values, they must equal the ones recorded in the local run of 1.1 (same PostgreSQL major version; if the version differs, compare the function bodies instead of the md5).
   Expected privileges: `public_can_execute = f` on all three; `classifier_models_in_crud_models = 0`.
6. **Behaviour check, test companies only** — test company **3** (livestock) and test company **10** (palm). Never use any other company. Run as the workflow role. The RFCs are read from the tables into psql variables and are **not printed**; only the role and reason are shown. Replace `<member e-mail>` with a member of that test company (do not paste it anywhere shared).

   ```sql
   \set co 3
   SELECT (SELECT rfc FROM company_tax_ids WHERE id_company = :co AND is_active ORDER BY rfc LIMIT 1) AS own_rfc,
          'XEXX010101000' AS other_rfc \gset
   SELECT 'issuer own'   AS probe, sp_cfdi_classify(:'co', '<member e-mail>', :'own_rfc', :'other_rfc') AS answer   -- expect role SALE
   UNION ALL SELECT 'receptor own', sp_cfdi_classify(:'co', '<member e-mail>', :'other_rfc', :'own_rfc')           -- expect role EXPENSE
   UNION ALL SELECT 'neither',      sp_cfdi_classify(:'co', '<member e-mail>', :'other_rfc', :'other_rfc')         -- expect UNKNOWN / NEITHER
   UNION ALL SELECT 'not a member', sp_cfdi_classify(:'co', 'nobody@example.invalid', :'own_rfc', :'other_rfc');   -- expect UNKNOWN / FORBIDDEN
   ```

   Repeat with `\set co 10` (palm: if it has no row in `company_tax_ids`, take `company_issuer_rfcs` instead). Expected `company_domain`: `LIVESTOCK` for 3 and `PALM` for 10. If a company has no active RFC the first probe returns `UNKNOWN`: stop and report, do not insert one just to test.
   Do not run the probes for any real company.
7. **Privilege check:** `SELECT has_function_privilege('public', 'public.sp_cfdi_classify(text,text,text,text)', 'EXECUTE');` → `f`.

### 1.3 Rollback

```sh
psql -X -v ON_ERROR_STOP=1 -f 109_rollback.sql                 # dry run
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 109_rollback.sql   # commit
psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 109_state_check.sql
```

The three functions stay (later objects may call them) and answer `UNKNOWN` / `DISABLED`. Re-applying `109_cfdi_role_classifier.sql` restores the classifier. No data is touched in either direction.

## Part 2 — n8n

Nothing to import. The n8n router and the SQL gate of `sp_expense_invoice_register` are separate pull requests (they depend on this one being applied and verified).

## Part 3 — frontend

Not part of this pull request. Only after Part 1 is verified in production may this pull request reach `main`.

## Risks

* The functions are new and unused: the worst case of a defect is a wrong answer in a later consumer, which is why the consumers come in separate pull requests.
* Classification is only as good as the active RFC set of each company. An empty set answers `UNKNOWN` with `own_set_empty = true`; the detail never contains an RFC.
* If the workflow role stops being a superuser, grant `EXECUTE` on `sp_cfdi_classify` only.
