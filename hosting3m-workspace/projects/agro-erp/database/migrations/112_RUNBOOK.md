> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: tested on a throwaway LOCAL database only. NOT applied to production.**
> Part 1 (database) is the only part that exists in this pull request. Part 2 (n8n: the reply texts of the sale sub-workflow for the new reasons and for several tickets) and Part 3 (frontend: ticket detail in the sales list) are the next two pull requests; they depend on this one being applied and verified.
> Requires 080, 081, 104 and 105 applied in production. 106-111 are independent of this migration.

# Runbook 112 — palm sales: several concepts per voucher and tonnes

## What it does

One CFDI voucher is one sale. The voucher may carry 1 to 10 concepts (for example one per weighing ticket) in kilograms (`KGM`) or tonnes (`TNE`). The sale stores the totals of the set; the detail per concept is kept as informational data; voiding is per voucher (one row, one void).

| Object | Kind | Notes |
|---|---|---|
| `agri_sale_invoices.concept_count` | column (new) | `smallint NOT NULL DEFAULT 1`, CHECK 1..10 |
| `agri_sale_invoices.ticket_detail` | column (new) | `jsonb NULL`, CHECK: NULL or an array with `concept_count` elements |
| `fn_trg_agri_sale_invoices_detail_guard()` + trigger `trg_agri_sale_invoices_detail_guard` | new, BEFORE INSERT | the detail must match the row: kilograms, amounts (n-1 cents), distinct tickets, accepted units |
| `sp_agri_register_sale(integer, text, jsonb, text, text, text)` | replaced in place | same signature, same privileges and attributes (plpgsql, VOLATILE, no SECURITY DEFINER) |
| `vw_agri_sale_list`, `vw_agri_sale_ui_list` | views | two columns appended at the end: `concept_count`, `ticket_detail` |

Untouched: `sp_agri_void_sale`, `sp_agri_sales_balance`, `vw_agri_sale_summary`, the 104 guard trigger, `crud_models` (no row added or changed), every other table. Existing rows are **not updated** (the table guard forbids it): they keep `concept_count = 1` and `ticket_detail = NULL`; the two views build a one-element detail for them from the row columns.

## Rules as implemented

| Topic | Rule | Reason code when refused |
|---|---|---|
| Concepts | 1 to 10 | `CONCEPT_COUNT` |
| Product key | all concepts the same `ClaveProdServ` (8 digits) | `PRODUCT_KEY`, `PRODUCT_KEY_MIXED` |
| Unit | `KGM` or `TNE` (any case) and the same for all concepts | `UNIT`, `UNIT_MIXED` |
| Quantity and price | positive decimals, up to 6 decimals, per concept | `QUANTITY` |
| Tonnes | quantity x 1000 with exact `numeric` arithmetic; the sale stores kilograms and `unit_code = 'KGM'`; the detail keeps unit, quantity and unit price as in the voucher | |
| Kilograms | the sum of all concepts, below 10^12 | `QUANTITY` |
| Concept amount | `|round(kilograms x price per kilogram x 100) - concept amount| <= 1` cent, per concept | `AMOUNTS_MISMATCH_CONCEPT` |
| Subtotal | `|sum of concept amounts - subtotal| <= n - 1` cents for n concepts: exact for one concept (as before), 1 cent for two, 2 for three | `AMOUNTS_MISMATCH_CONCEPT` (n = 1), `AMOUNTS_MISMATCH_SUBTOTAL` (n > 1) |
| Total | `subtotal - discount + taxes = total`, exact (unchanged); the total is the voucher total | `AMOUNTS_MISMATCH` |
| Price per kilogram | informational: for one KGM concept the voucher price (as before); otherwise `round(subtotal / kilograms, 6)`, before taxes | `AMOUNTS` if it would be zero |
| Ticket | **optional**. Read from each concept description `(ticket N)`; a concept without exactly one recognizable reference has none and the sale is stored with `ticket_warning = true` (never a refusal). `ticket_ref` is the first ticket found | warning `ticket_missing_or_unrecognized` |
| Duplicate tickets | the same ticket (any case) twice in one voucher is refused; a ticket already in another ACTIVE sale of the same company (in `ticket_ref` or in a detail) is a warning | `TICKET_DUPLICATE`; warning `ticket_already_used` |
| Same voucher twice | unchanged: one ACTIVE row per (company, uuid); the second load answers `ALREADY_REGISTERED` | |

Why the ticket works without a reference: the 104 constraint is `ticket_ref IS NOT NULL OR ticket_warning`, and the procedure already stored `ticket_warning = true` when no ticket is found, so a missing ticket never violated it (104 test T3). 112 keeps both and tests the multi-concept and tonne cases without ticket.

The answer `summary` keeps its keys (`folio`, `sale_date`, `buyer_name`, `total_amount`, `quantity_kg`, `unit_price`, `ticket_ref`, `sat_status`) and adds `concept_count`, `tickets` and `source_unit`. New reason codes are answers, never exceptions; the audit trail stores only the code.

## Files

| File | Purpose |
|---|---|
| `112_agri_sale_multi_concept.sql` | the change (dry run by default; preconditions; drift guard; post-checks) |
| `112_rollback.sql` | restores the exact 104 procedure (md5 checked); drops nothing |
| `112_state_check.sql` | `-v expect=before\|applied\|rolled_back`, read-only, fingerprints |
| `112_tests.sql` | one rolled-back transaction (throwaway database only), 123 assertions, includes the rollback and the re-apply |
| `112_static_check.sh` | no `DROP` / `TRUNCATE` / `DELETE` statement, signature intact, no `crud_models` change, stub word absent, drift guard present |
| `105_state_check.sql` | updated in this pull request: it now accepts the view with the two appended columns |

## Part 1 — database

### 1.1 Local first (throwaway database, name must contain `test` or `rehearsal`)

Requires 080, 081, 104 and 105 applied (the tests include 104 and 105 when they are missing).

```sh
bash 112_static_check.sh                                                      # all OK
psql -X -v ON_ERROR_STOP=1 -v expect=before -f 112_state_check.sql            # STATE OK: before
psql -X -v ON_ERROR_STOP=1 -f 112_agri_sale_multi_concept.sql                 # dry run: "112: OK" then ROLLBACK
psql -X -v ON_ERROR_STOP=1 -f 112_tests.sql                                   # "112 TESTS: 123 assertions passed"
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 112_agri_sale_multi_concept.sql
psql -X -v ON_ERROR_STOP=1 -v expect=applied -f 112_state_check.sql           # STATE OK: applied
psql -X -v ON_ERROR_STOP=1 -v expect=applied -f 105_state_check.sql           # STATE OK: applied (accepts the appended columns)
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 112_rollback.sql
psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 112_state_check.sql       # STATE OK: rolled_back
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 112_agri_sale_multi_concept.sql   # re-apply (idempotent)
```

The FINGERPRINTS block of `112_state_check.sql` must be identical in "before", "applied" and "rolled_back". The local `hosting3m_db` is not a clean base: use a database restored from a dump (see `workflows/09-MCP-Agent-Cattle/v6/repro-phase5/rehearsal/README.md`).

### 1.2 Production (only after 1.1 passes)

1. **Before:** `psql -X -v ON_ERROR_STOP=1 -v expect=before -f 112_state_check.sql` → `STATE OK: before`. Also `104_state_check.sql -v expect=applied` and `105_state_check.sql -v expect=applied`. Save the output.
2. **Drift check (read-only):** the migration replaces the procedure only if its live text is the repository 104 text. Compare, on the production database,
   `SELECT md5(pg_get_functiondef('public.sp_agri_register_sale(integer,text,jsonb,text,text,text)'::regprocedure));` → must print `425229fb6036884d5c5dcd7527d7c674` (same PostgreSQL major version as the local run). If it differs, **stop**: the migration aborts by itself with `ABORT 112 (drift)` and nothing is changed; incorporate the live text into the repository first.
3. **Backup:** the migration alters one table and replaces one procedure; take the standard `pg_dump -Fc` first, kept outside the repository with restricted permissions.
4. **Dry run:** `psql -X -v ON_ERROR_STOP=1 -f 112_agri_sale_multi_concept.sql` → `112: OK` and `DRY RUN ... rolled back`.
5. **Apply:** `psql -X -v ON_ERROR_STOP=1 -v apply=true -f 112_agri_sale_multi_concept.sql` → `*** 112 COMMITTED ***`. The two columns are added with constant defaults (no table rewrite on PostgreSQL 11 or later); the two CHECK constraints scan the table once.
6. **After:** `112_state_check.sql -v expect=applied` → `STATE OK: applied`; the FINGERPRINTS block must equal the one of step 1. Also `105_state_check.sql -v expect=applied` and `104_state_check.sql -v expect=applied`. Save the output.
7. **Behaviour check on TEST company 10 only** (never any other company), inside `BEGIN ... ROLLBACK`, with synthetic vouchers. The issuer RFC of the company is read into a psql variable and never printed; replace `<admin e-mail>` with an ADMIN of company 10.

   ```sql
   BEGIN;
   \set co 10
   \set mail '<admin e-mail>'
   SELECT rfc AS own_rfc FROM company_issuer_rfcs WHERE id_company = :co AND is_active ORDER BY rfc LIMIT 1 \gset
   SELECT repeat('b', 64) AS sha, :co || '/2026/11/' || repeat('b', 64) || '.xml' AS path, upper(gen_random_uuid()::text) AS u1, upper(gen_random_uuid()::text) AS u2,
          to_char(fn_agri_today_cdmx() - 1, 'YYYY-MM-DD') || 'T08:49:01' AS issued \gset
   -- two kilogram concepts (100 kg at 10.00 each): must answer OK with 200 kg and 2 concepts. The tonne case (9.1 t at 4011.00 per tonne = 36500.10) is covered by 112_tests.sql.
   SELECT 'two KGM concepts' AS probe, r ->> 'status' AS status, r -> 'summary' ->> 'quantity_kg' AS kg, r -> 'summary' ->> 'concept_count' AS concepts
     FROM (SELECT sp_agri_register_sale(:co, :'mail',
             jsonb_build_object('tipoComprobante', 'I', 'uuid', :'u1', 'folio', 'T1', 'fechaEmision', :'issued', 'fechaTimbrado', :'issued',
               'emisor', jsonb_build_object('rfc', :'own_rfc', 'nombre', 'PRUEBA'), 'receptor', jsonb_build_object('rfc', 'XEXX010101000', 'nombre', 'PRUEBA'),
               'moneda', 'MXN', 'formaPago', '03', 'metodoPago', 'PUE', 'subtotalCents', 200000, 'descuentoCents', 0, 'totalCents', 200000,
               'traslados', '[]'::jsonb, 'retenciones', '[]'::jsonb, 'sourceSha256', :'sha',
               'conceptos', jsonb_build_array(
                 jsonb_build_object('claveProdServ', '50307008', 'claveUnidad', 'KGM', 'cantidad', '100', 'valorUnitario', '10.00', 'descripcion', 'Prueba (ticket 1)', 'importeCents', 100000),
                 jsonb_build_object('claveProdServ', '50307008', 'claveUnidad', 'KGM', 'cantidad', '100', 'valorUnitario', '10.00', 'descripcion', 'Prueba (ticket 2)', 'importeCents', 100000))),
             'VIGENTE', :'path', :'sha') AS r) q;
   -- expect OK / 200 / 2
   SELECT (SELECT count(*) FROM agri_sale_invoices WHERE uuid IN (:'u1', :'u2')) AS rows_inside_the_transaction;   -- expect 1
   ROLLBACK;
   SELECT (SELECT count(*) FROM agri_sale_invoices WHERE uuid IN (:'u1', :'u2')) AS rows_after_rollback;           -- expect 0
   ```

   If company 10 has no active issuer RFC the first `\gset` leaves the variable undefined and the call answers `ISSUER_RFC_NOT_CONFIGURED`: that is a platform decision, not a failure of the migration. Use `psql` with a role that may call the procedure, as in the earlier runbooks.
8. **Privileges unchanged:** compare `has_function_privilege` and `prosecdef` of `sp_agri_register_sale` with the values saved in step 1 (the local run shows the same values: plpgsql, VOLATILE, not SECURITY DEFINER).

### 1.3 Rollback

```sh
psql -X -v ON_ERROR_STOP=1 -f 112_rollback.sql                 # dry run
psql -X -v ON_ERROR_STOP=1 -v apply=true -f 112_rollback.sql   # commit
psql -X -v ON_ERROR_STOP=1 -v expect=rolled_back -f 112_state_check.sql
```

The procedure goes back to the exact 104 text (one KGM concept per voucher; several concepts and tonnes are refused again with `CONCEPT_COUNT` / `UNIT`). The two columns, their constraints, the detail trigger, the view columns and every sale registered while 112 was applied stay: those sales keep their quantity and totals, are still listed and can still be voided. Re-applying `112_agri_sale_multi_concept.sql` restores the new rules. If 104 itself is rolled back later, its own rollback replaces the procedure with its stub.

## Part 2 — n8n

Not part of this pull request. The sale sub-workflow (`v6/palm sale from xml`) needs no change to keep working: it passes the whole parsed voucher to the procedure, the answer keeps its keys, and a reason code it does not know is shown with its generic text ("datos del comprobante no válidos"). A later pull request adds the reply texts for the new reasons and for several tickets; it is imported through the n8n UI with the backup and fingerprint comparison of the root `CLAUDE.md`.

## Part 3 — frontend

Not part of this pull request (sales list and detail with the number of tickets and the per-ticket detail). It reads `concept_count` and `ticket_detail` from the existing `agri_sales` model; whether the gateway returns the appended view columns without a model change is to be confirmed in that pull request, in LOCAL, before it is written.

## Risks and open points

* **Price definition.** The informational price per kilogram is `subtotal / kilograms` (before taxes), consistent with the single-concept price. With a 0% tax rate it equals `total / kilograms`; with a tax or a discount it is lower than the total divided by the kilograms. Confirm with the owner that the pre-tax value is the one to show.
* **Tolerance of `n - 1` cents** is derived from rounding (each concept amount is rounded to cents on its own, the subtotal once). It has been exercised with invented values only; a sample of real-shaped vouchers should be checked locally (never committed) before production use.
* **Existing rows** keep `ticket_detail = NULL`; any consumer that reads the table directly (not through the two views) must treat NULL as "one concept, taken from the row columns".
* **cfdi-service** returns at most 20 concepts and does not report that it truncated. A voucher with more than 20 reaches the procedure with 20 and is refused on its amounts or on the count (never registered partially).
* **Concept-level discounts** are not part of the parsed voucher; concept amounts are gross, as before.
* **Plantation and lot** are not set by the chat route today (NULL), so one sale cannot mix lots; unchanged.
* **Re-running 105** after 112 is not supported (its `CREATE OR REPLACE VIEW` cannot drop the two appended columns); its rollback and its state check are.
