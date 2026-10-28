# Reproduction tracking — Phase 0 discovery (read-only)

Branch: `feat/reproduction-tracking` (from `develop`). Status: **Phase 0 updated with tenant 5 measurements and the owner's decisions; Phase 1 not started; no migration written.**
Nothing here was run against any database. The three SQL scripts in `database/discovery/` are for the user to run
(LOCAL first, then the server). They have **not been executed or syntax-tested by the author** (no local PostgreSQL run was
possible in this session) — run `repro_01` and `repro_02` on LOCAL first and send back any error.

## Update 2026-10-27 — tenant 5 (UPP La Bendición) measurements and decisions

Source of the numbers: the owner's summary of `out_repro_02/03`, `repro_extra`, `repro_extra2` (tenant 5). **The output files themselves were not
available in this session**, so figures below are as reported by the owner and have not been re-derived by me.
Rules (15 months / 300 kg, the two numero_fuego conventions) come **from the client, not from data**: nothing in tenant 5 validates them.

### Measured facts (tenant 5, 450 animals)
- `birth_date`: 214 = import placeholder `2020-01-01`, 197 = NULL, 39 = other value. The earlier 35.9% year agreement was an artifact of the placeholder.
- Of the 39: 34 are calves/heifers loaded 2026-10-17 **without numero_fuego**, birth day always 09 (2026-05-09, 2026-04-09...). Month plausible, **day unreliable** → age at month precision only.
- No animal has the current format `YY-CC-M`; neither convention can be validated against real dates in this tenant. Every derived age carries its source and precision.
- 3-digit numbers (375, 377, 383) are bulls with no year encoding. Values with spaces/suffixes, `S/N`, 1–2 digits and `20199-84` stay unparsed.
- Herd: 401 VACA (117 VACÍA, 82 PREÑADA, 202 ACTIVO), 2 NOVILLONA, 1 BECERRA, 31 BECERRO, 9 NOVILLO, 4 TORO. 1 `birth_events` row, 0 `cattle_breeding_events`, 214 palpations in 214 animals (a single round).

### Decisions recorded (owner)
| | Decision | Effect on the design |
|---|---|---|
| A | `birth_date = 2020-01-01` means "no date" | `effective_birth` falls back to the numero_fuego estimate; no other registered date is certain beyond month precision. |
| B | Legacy `YYCC`: year = first two digits, no month. All legacy years ≤ 2024 → ≥ 15 months by year alone | `REQUIERE_REVISION_FISICA` **removed from the design**; `age_precision = YEAR_ONLY` stays as a label. |
| C | Unconfirmed shapes: 5 digits (`19102`, `21116`) and 4 digits with YY ≥ 25 (`2534`, `2553`, `2571`); `2963` matches neither | Classified `UNCONFIRMED_SHAPE`, **not parsed**. The parser is a single table of (regex, year/month extraction) so a confirmed shape is one added row, not a rewrite. |
| D | `repro_condition` / `static_cause` | Side table keyed by the palpation `cattle_health_logs` row (not `medicines_json`). |
| E | Eligibility scope | Females `NOVILLONA` **or** `BECERRA` at ≥ 15 months or ≥ 300 kg; flag `category_possibly_outdated` for BECERRA; category is never changed automatically. |
| F | Phase 2 proposals | `list_open_cows` and untagged-calf numbering: specified below, not built, need approval. |
| G | Migration number | Owner verifies that 084 is free (`git ls-tree` on develop and open branches); I do not assume it. |

### Script changes made now (still read-only; syntax not executed by me)
- `repro_02_numero_fuego.sql`: agreement excludes `2020-01-01`, is reported per format, adds a birth_date quality block (placeholder / NULL / real / day-9), classifies `UNCONFIRMED_SHAPE` and `NO_YEAR_ENCODING`. It creates a session-local TEMP view, so it must start in a session that is **not** `default_transaction_read_only`; it switches itself to read-only after creating the view.
- `repro_03_counts.sql`: scope = `NOVILLONA` + `BECERRA`, placeholder date ignored, `category_possibly_outdated` flag, month-precision age.

### Open questions: status after the owner's answers
| # | Question | Status |
|---|---|---|
| 1 | Migration number | **Answered** — 084 free; one number per phase (084, 085, 086, 087). |
| 2 | `repro_01` output | **Answered** — read; see "Real behaviour of the four procedures". |
| 3 | Palpation storage | **Answered** — D, side table. |
| 4 | Year floor (2005) | **Answered** — 2005 is fine (tenant 5 legacy years 2011–2024). |
| 5 | BECERRA ≥ 15 months | **Answered** — E. |
| 6 | Year-only review bucket | **Answered** — B, bucket removed. |
| 7 | Weight validity | **Answered** — valid only if `current_weight_kg > 0`; last `cattle_weight_logs.log_date` flags stale data. |
| 8 | Phase 2b recipients and frequency | **Undecided** — Phase 2b stays spec only. |
| 9 | Tenants in scope | **Answered** — only tenant 5 for now (code stays tenant-parameterised). |
| 11 | `condicion_utero` → `repro_condition` | **Answered** — per-tenant code mapping table, raw code kept (see "Phase 3 design — repro_condition"). |
| 12 | Membership inside `sp_register_birth_event` / `sp_log_breeding_event` | **Approved in principle, pending the caller list** (below) — applies in phase 4, not before the owner approves the list. |
| 13 | Birth idempotency | **Answered** — only exact retries are skipped; same dam + date + sex returns `possible_duplicate`. |
| 14 | Void of a service linked to a birth | **Answered** — refuse with a clear message. |
| 15 | Parser details | **Answered** — (a) `VACIA` prefix is the separate `resultado` column; (b) free words map to the condition with `mapping_status='EXPLICIT'`; (c) `UNE/NR` stays NULL. |
| 10 | Fiscal math | None touched. |

### Phase 2 proposals (specified, NOT built, need approval)
**`list_open_cows`** — females with `category = 'VACA'`, `current_status = 'VACÍA'`, tenant-scoped, with **no non-voided `cattle_breeding_events` row in the last N days** (`N` in `repro_settings`, default 60 — to confirm). Per row: identifiers (arete/fuego/RFID), UPP/lot, last palpation date and result, days since last service (NULL = never), and a flag for last palpation `repro_condition` once Phase 3 exists. Paginated (default 50), ordered by days open descending. Read-only, membership + `fn_reject_palm_company`. Tenant 5 today: 117 candidates and 0 services ever, so the list would initially equal the 117 VACÍA cows.

**Numbering the 32 untagged calves** (34 loaded without numero_fuego, minus those already tagged; the owner says 32) — proposal in three safe steps, no automatic assignment:
1. `list_untagged_calves` (read-only): calves with all three identifiers NULL, with dam (via `mother_id`), sex, birth month, UPP/lot.
2. Staff report through the chat "al becerro de la vaca X le pusimos fuego 26-12-4" → `assign_calf_identifier`, a thin wrapper around the existing `update_livestock_tag` rules (uniqueness inside the tenant, history in `cattle_identifier_history`, chat confirmation). The calf is resolved by dam + sex (ambiguity error if the dam has more than one untagged calf of that sex — never guess).
3. The new burned number is validated against the 15-month eligibility parser only for labeling; the birth month in the number (`YY-CC-M`) is compared with the registered month and a mismatch is returned as a `warning`, never blocking.
`electronic_rfid` is captured at the same step when available (data-capture principle).

### Real behaviour of the four procedures (from `out_repro_01_definitions.txt`, section E, read 2026-10-27)

| | `sp_register_birth_event` (13 params) | `sp_log_breeding_event` | `sp_log_palpation_event` | `sp_void_event` |
|---|---|---|---|---|
| **Tenant / membership check** | **None inside the SP.** Only `p_id_company` scoping (`dam_id`, ear tag, fire number, lot are all filtered by it). Membership + `fn_reject_palm_company` exist only in the n8n tool. | **None inside the SP**; same, tool only. Animal lookup is tenant-scoped. | **Yes, inside**: active `user_companies` + `users` match on `p_user_email`, else `P0001`. No palm check inside (tool has it). | **None inside** (the voider's email is not validated); tenant scoping via `tenant_id` of the event table. Tool does membership + palm check. |
| **Effect on `current_status`** | Dam only: `PREÑADA → VACÍA`; any other status untouched, with `dam_status_warning`. Calf created `ACTIVO`, category by species+sex, `business_model='CRIA'`. | **None.** A service never marks the dam. | **Always `SET current_status = p_result`** (`PREÑADA`/`VACÍA`) on any non-blocked animal. | None (never reverts anything). |
| **Idempotency** | **None.** A retry creates a second calf and a second `birth_events` row. | **None.** No unique index; a retry duplicates the service. | Same animal + `PALPACION` + identical generated `description` created in the last 5 minutes → `duplicate_skipped:true`. Not date-based. | `UNIQUE (event_table, event_id)` + explicit check → `P0017` on repeat. |
| **Identifier resolution** | Dam by `dam_id`, else ear tag **or** (ELSE) fire number — if the ear tag is given and finds nothing, fire number is not tried. Several matches → dam stays NULL, the birth is **still registered unlinked** with a warning (no ambiguity error). | rfid/siniiga/fuego, **all statuses**: 0 → `P0002`, >1 → `P0004` (sold animals with the same fire number cause ambiguity). | Same triple, 0 → `P0002`, >1 → `P0003`. Blocks `VENDIDO, BAJA_MORTANDAD, FINALIZADO, BAJA_DEPURACION_DATOS` (`P0006`). | By UUID + tenant. |
| **Validations missing** | Dam sex/category/status, calf-date plausibility, duplicate birth for the same dam/date. | Female check, **sire existence/sex/tenant**, `semen_batch` for AI, future date, duplicates. Blocks only `VENDIDO`, `BAJA_MORTANDAD`. | Sex/category (a **TORO** can be set to `VACÍA`), date vs. newer palpations. | Event type specifics. |
| **Stores** | `birth_events` (incl. `species`), calf row, optional `cattle_weight_logs` (`BIRTH_EVENT`), `source='MOBILE_APP'`. No `reported_by_email` column. | `cattle_breeding_events`: `sire_identifier` is **free text**, `estimated_due_date` = date + 283 d for `BOVINO`. | `cattle_health_logs`: `description` text and `medicines_json = {result, gestation_days, technician_name}`; `event_date` = given date or now. | `event_voids` row only. |

**Void reversal by event type (today):** only `cattle_breeding_events`, `cattle_deworming_events`, `cattle_castration_events` can be voided, and only by hiding the row (readers filter `event_voids`). Voiding a **breeding** event needs no revert (it never changed status). **Births and palpations cannot be voided at all** (`birth_events` and `cattle_health_logs` are not in the whitelist and `birth_events` has no `tenant_id` column, which the dynamic `SELECT ... tenant_id = $2` requires); a wrong palpation keeps its `current_status` effect. Future empadre rows must use a `tenant_id` column (or the SP needs per-table tenant column mapping).

### Discrepancies with what I inferred in the first version of this document
1. **Palpation JSON keys in production are Spanish** (`resultado`, `dias_gestacion`, `condicion_utero`; 290 rows DB-wide), but `sp_log_palpation_event` writes English keys (`result`, `gestation_days`, `technician_name`) and `vw_cattle_kpi` (migration 061) reads the English ones. So the 214 bulk-loaded palpations in tenant 5 are **invisible** to `last_palpation_result`, while chat-logged ones are visible. `list_palpation_due` and the dam history must therefore read both key sets (`COALESCE(medicines_json->>'result', medicines_json->>'resultado')`) and use `event_date`. `condicion_utero` already exists as a field: ask the client whether it should map to `repro_condition` (Q11).
2. **The SPs have no membership check except palpation** — I had assumed the tool-level checks covered them; any new SP must validate membership itself (fail-closed), and I recommend adding it to the hardened breeding SP.
3. **Gestation days use species names that do not match the rest of the system**: breeding looks for `EQUINO`, `OVINO`, `CAPRINO`, `PORCINO`, whereas birth/catalog use `EQUIDO`, `BORREGO`, `BUFALO`. For those species `estimated_due_date` is NULL today. Bovine (283 d) is fine, which is all tenant 5 has.
4. **Birth with ambiguous dam does not fail**; it registers an orphan calf and warns. I had assumed an ambiguity error.
5. **Palpation sets the status even from `ACTIVO`** (and for bulls), not only `PREÑADA↔VACÍA`. Status coherence for Phase 4 must account for that (e.g. a TORO `VACÍA`).
6. **`birth_events.species` exists in production** but is not in migration 030 (repo drift); the dam-reference CHECK also differs (BORREGO exception). `schema.sql` is stale, as CLAUDE.md warns.
7. **`cattle_breeding_events` and `birth_events` are not in `crud_models`**; only `cattle_health_logs` and `cattle_weight_logs` are. New reads go through SPs, as planned.
8. **Weight trigger** sets `current_weight_kg = NEW.weight_kg` on every insert regardless of `log_date`: a back-dated weigh-in overwrites a newer weight. For stale-data flags I will read the latest `cattle_weight_logs.log_date`, not trust `current_weight_kg` alone.
9. `cattle_breeding_events` FK to `cattle_livestock` has no ON DELETE action and there is no FK to `companys`.

### Tenant 5 results (real, from the output files; these ran the OLD scripts — placeholder not excluded)
- Shapes: LEGACY 357, OTHER 55 (5-digit 33, 3-digit 7, `S/N` 4, 1-digit 3, `NN-N P` 3, `YYYY-N P` 2, 2-digit 2, `20199-84` 1), EMPTY 34, 4-digit with YY ≥ 25 (`2534`, `2553`, `2571`, `2963`) 4. No `YY-CC-M`. Legacy years 2011–2024, none implausible. **Many duplicated numero_fuego** (2010, 2011, 2012 and `S/N` ×4; dozens ×2–3): any identifier lookup by fire number can be ambiguous, which the SPs report as an error — tools must offer the disambiguation by category/lot.
- Birth events: 1 (2026-09-15, via agent). Calves with mother and no birth event: 0. Breeding events: 0. Palpations: 214 rows in 214 animals; active NOVILLONA 2 (1 eligible by age at month precision, 0 by weight; both have no palpation). BECERRA ≥ 15 months: 0. Weight logs: 19 rows in 13 animals (2026-05-22 → 2026-09-16), so almost no animal has a usable weight.
- Year agreement 35.9% (66/184) was the placeholder artifact; rerun the updated `repro_02` to get the clean figure (expect `with_real_date` ≈ 39 minus animals without fire number → small sample, mostly non-parseable).

### Phase 4 design (no code), based on the real bodies
Migration numbers: **084 = Phase 1**, 085 = Phase 2, 086 = Phase 3, 087 = Phase 4, 088 = Phase 5 DB parts if any. Each: `NNN_<name>.sql`, `NNN_rollback.sql`, `NNN_state_check.sql`, `NNN_tests.sql`, plus `NNN_RUNBOOK.md` with the ⛔ box when n8n is involved (same naming as 083).

1. **`sp_log_breeding_event` hardening** (`CREATE OR REPLACE`, signature unchanged so the live n8n tool keeps working; rollback = re-create the body from the section E dump, saved as `087_rollback.sql`):
   - membership check inside (active `user_companies` for `p_registered_by_email`) + `fn_reject_palm_company`; every lookup by tenant;
   - dam must be female (category `VACA`/`NOVILLONA`/`BECERRA`) and not in the existing blocked statuses (extend to `FINALIZADO`, `BAJA_DEPURACION_DATOS`, matching palpation); resolution restricted to non-sold animals first, ambiguity error naming candidates;
   - sire (when `sire_identifier` given): resolve with the same triple, **same tenant, male (`TORO`, `BECERRO_TORETE`), active**, exactly one; ambiguity/none → error; store the resolved sire UUID in a **new nullable column `sire_livestock_id`** (keep `sire_identifier` text as typed);
   - `INSEMINACION_ARTIFICIAL` requires `semen_batch` (sire optional); `MONTA_NATURAL` requires sire;
   - future date rejected; idempotency: same dam + `breeding_date` + `method` among non-voided events → `duplicate_skipped:true` returning the existing id (same style as palpation, but date-based instead of 5 minutes); partial unique index `(livestock_id, breeding_date, method)` cannot be used because voided events must be allowed again, so the check is in the SP (+ advisory lock on the dam id to avoid races);
   - gestation by a species map that includes `EQUIDO`, `BORREGO`, `BUFALO` (values to confirm with the client; bovine unchanged at 283);
   - still no change to `current_status` (a service does not prove pregnancy).
2. **`sp_register_birth_event` reconciliation** (same 13-parameter signature; new optional behaviour only):
   - inside the SP: membership of `p_reported_by_email` (when provided, else rely on the tool) — decision Q12;
   - idempotency (Q13, owner): twins are legitimate, so a same dam + date + sex is **not** skipped; the SP returns `possible_duplicate:true` with the existing birth(s) and writes nothing, so the agent asks the user, and a confirmed second birth is sent again with an explicit flag. Only an **exact retry** (same dam, date, sex, birth weight and notes within 5 minutes) is skipped automatically (`duplicate_skipped:true`, existing ids returned);
   - find the dam's **open service**: latest non-voided `cattle_breeding_events` of that dam with `breeding_date` between `birth_date − 320 d` and `birth_date − 240 d` and not yet linked; link through a **new nullable `cattle_breeding_events.birth_event_id`** (unique where not null) set in the same transaction; return `matched_service {id, date, method, sire_identifier, sire_livestock_id}`; none → register anyway with `no_open_service:true`;
   - ambiguity: keep the current behaviour (orphan calf + warning) but also return `dam_ambiguous:true` and the candidates, so the agent can ask; no automatic guess;
   - status: keep `PREÑADA → VACÍA`; a dam in `ACTIVO` stays `ACTIVO` with the existing warning.
3. **`sp_void_event` extension:** add the new empadre table to the whitelist (it must have a `tenant_id` column); add the membership check of `p_voided_by_email`; **voiding a breeding event that is linked to a birth is refused** with a clear Spanish message (Q14, owner) — to void it, the link must be resolved first by a person. Still no side-effect reversal. Births and palpations remain non-voidable unless approved separately (a palpation void would need the previous status, which `sp_log_palpation_event` does not record).
4. **`get_dam_reproductive_history`** `(p_tenant_id, p_user_email, p_identifier)`: membership + palm check; dam resolved with the triple, ambiguity error; one jsonb with chronological `timeline[]`: empadre entry, services (non-voided, with sire and linked birth), palpations (both JSON key sets, result, months, `repro_condition`, date), births (via `dam_id`, with calf identifiers); read-only.
5. **Tests per migration:** parser units, idempotency (retry returns `duplicate_skipped`, one row), sire in another tenant → error, sire female → error, user of company A on company B → zero rows and an error, palm company → `P0094`, void then re-register allowed, rollback leaves old behaviour (state_check asserts function-body fingerprints equal the section E dump).
6. **Tenant 5 test data:** 0 services and 1 birth exist, so reconciliation is tested with synthetic rows in a LOCAL throwaway database; nothing is written to production by me.

.

### Phase 3 design — `repro_condition` (final for Q11, owner 2026-10-27)
**`condicion_utero` is never copied into `repro_condition`.** In tenant 5 it holds veterinarian codes; the raw value stays untouched in `cattle_health_logs.medicines_json`. Observed values (tenant 5): `VACIA/UNE` 104, `PREÑADA/N/A` 90, `VACIA/UTCL2/OI` 4, `UTCL2/OD` 4, `No apto` 3, `RP` 2, `UTCL1/OD` 2, `UTCL1/OI` 1, `UTC2/OD` 1, `UTCL3/OD` 1, `UNE/NR` 1, `Matriz ocupada` 1.

**Objects (migration 086, one rollback/state_check/tests set):**
- `repro_condition_codes(id_company NOT NULL, code, repro_condition CHECK IN ('CICLANDO','ESTATICA','OTRO') NULL, meaning text, source, confirmed_by, confirmed_at, PK (id_company, upper(code)))`. Per tenant; writes ADMIN only (via SP); reads membership-checked.
- `palpation_repro_details(health_log_id PK/FK cattle_health_logs, id_company NOT NULL, raw_code text, repro_condition NULL, ovary_side NULL CHECK IN ('OI','OD'), static_cause text NULL, mapping_status CHECK IN ('MAPPED','UNMAPPED','EXPLICIT','NOT_APPLICABLE'))`. `repro_condition` only allowed when the palpation result is VACÍA/VACIA (CHECK enforced through the SP, since the result lives in the log). Append-only; one row per log.
- `fn_parse_uterine_code(text)` IMMUTABLE: trims, case/accent-insensitive; `N/A` and empty → NOT_APPLICABLE; splits on `/`; leading tokens that are a result word (`VACIA`, `PREÑADA`) are skipped; `OI`/`OD` are extracted as `ovary_side` (raw detail, not part of the condition); the first remaining token is the lookup key; **any other remaining token that is neither a side marker nor a mapped code makes the whole value UNMAPPED** (this is why `UNE/NR` stays NULL although `UNE` is mapped). Never raises.
- Lookup is always `WHERE id_company = <tenant>`; a code absent from the table → stored raw, `repro_condition` NULL, `mapping_status='UNMAPPED'`; never an error and never a guessed class.
- Read-only `list_unmapped_uterine_codes` (membership + palm checked): distinct raw codes with counts and last date for the tenant, so the vets can complete the table.

**Tenant 5 seed (separate file `086_seed_tenant5_uterine_codes.sql`, reviewable, applied only by the owner; it will be written together with 086, not before):**
| code | meaning (vet-confirmed) | repro_condition |
|---|---|---|
| UNE | Útero Normal Estático (anestro / inactivo) | ESTATICA |
| UTCL1 | útero con cuerpo lúteo temprano | CICLANDO |
| UTCL2 | útero con cuerpo lúteo maduro | CICLANDO |
| UTCL3 | cuerpo lúteo tardío / en regresión | CICLANDO |

Deliberately **without a condition** (ambiguous vet answers): `RP`, `UTC2`, `NR` (hence `UNE/NR`), `No apto`, `Matriz ocupada` → registered by the seed as known-but-pending rows (NULL condition, see "Phase 3 delivered"), so they remain UNMAPPED. `OI`/`OD` = presumably left/right ovary (to confirm; informational only).

**Query rules for every palpation read (`list_palpation_due`, history, dam timeline):**
- `cattle_health_logs` has no tenant column: always `JOIN cattle_livestock l ON l.id = h.livestock_id AND l.tenant_id = <tenant>`; the two new tables carry their own `id_company` and are filtered by it as well.
- Result spelling: the bulk-loaded rows store `VACIA` (no accent), the procedure writes `VACÍA`. Normalize both sides (`translate`/`unaccent`, upper) in every comparison; read both key sets: `COALESCE(medicines_json->>'result', medicines_json->>'resultado')`, `COALESCE(...'gestation_days', ...'dias_gestacion')`; date from `event_date`.
- Existing `sp_log_palpation_event` semantics unchanged (result PREÑADA/VACÍA, status mapping, English keys). The batch parser fills `palpation_repro_details` from `raw_diagnosis` tokens through the same `fn_parse_uterine_code` (e.g. `VACÍA UTCL2/OI` → `VACÍA`, raw `UTCL2/OI`, CICLANDO, side `OI`, `mapping_status='MAPPED'`). **Explicit free words** typed by staff (`ciclando`, `estática`/`estatica`, case and accent insensitive) map straight to `CICLANDO` / `ESTATICA` with `mapping_status='EXPLICIT'` (Q15b, owner); veterinarian codes always go through the per-tenant table (`MAPPED` / `UNMAPPED`); `mapping_status` therefore allows `MAPPED, UNMAPPED, EXPLICIT, NOT_APPLICABLE`. `UNE/NR` stays NULL until `NR` is confirmed.

Q15 is closed (see the question table). The parser still tolerates a `VACIA/` prefix inside the stored value.

### Q12 — callers of `sp_register_birth_event` and `sp_log_breeding_event` (grep of the repo and all exported workflows, 2026-10-27)
Searched: every `*.json` (n8n exports), `*.sql`, `*.py`, `*.ts`, `*.js`, `*.sh`, docs. Exports are the repo's `main`/`develop` copies, **not** the live n8n; production can differ (CLAUDE.md: compare by fingerprint).

| # | Caller | Procedure | Passes a user e-mail? |
|---|---|---|---|
| 1 | `v6/MCP Server Cattle` → tool `register_birth_event` | `sp_register_birth_event` (13 params) | **Yes** — `p_reported_by_email` from the mandatory `reported_by_email`; the tool also requires an active membership for that e-mail |
| 2 | `v6/MCP Server Cattle` → tool `log_breeding_event` | `sp_log_breeding_event` | **Yes** — `p_registered_by_email`, mandatory; the tool requires an active membership for it |
| 3 | `v6/CRUD` (`workflows/06-dynamic-crud-engine/v6/v6-crud.json`, node *Build Query*, `spConfigByModel['sp_register_birth_event']`) | `sp_register_birth_event` | **No** — `paramOrder` is `calf_sex, species, dam_id, dam_ear_tag, dam_fire_number, birth_date, lot_id, production_unit_id, paddock_id, birth_weight_kg, notes` (11 + tenant at position 0 = 12 arguments: **corrected 2026-10-28** - production has only the 13-parameter function, and a 12-argument call resolves to it because `p_reported_by_email` has a default). No `reported_by_email` is passed by the gateway. |
| 4 | Frontend (`projects/agro-erp/src`) | — | No call: only a model file mentions `birth_events` (event log type) |
| 5 | Migrations / loader scripts | — | None call either procedure |
| 6 | Anything run by hand in `psql` on the server | unknown | Cannot be searched from the repo |

**Not verifiable from the repo — please run on the server (read-only) before approving:**
```sql
SELECT model_name, table_name, operation_type, allowed_roles_insert FROM crud_models
 WHERE table_name ILIKE '%birth%' OR table_name ILIKE '%breeding%' OR model_name ILIKE '%birth%' OR model_name ILIKE '%breeding%';
SELECT oid::regprocedure FROM pg_proc WHERE proname = 'sp_register_birth_event';
```
If a gateway model exists for caller 3, adding the membership check to the 13-parameter overload does **not** break it (**corrected 2026-10-28:** there is no 12-parameter overload in production; the gateway's 12-argument call resolves to the 13-parameter function, which therefore stays unguarded on that path - handled by migration 089, which disables the gateway model, and by the legacy NULL-e-mail path being documented). **Only callers 1 and 2 pass an e-mail; caller 3 does not.** Nothing is changed in phase 1.

### Backlog (out of scope of these phases — recorded, NOT fixed)
1. **Spanish-key palpations are invisible to `vw_cattle_kpi`:** bulk-loaded rows use `resultado`/`dias_gestacion`/`condicion_utero`; the view (061) reads `result`/`gestation_days`, so `last_palpation_result` and `current_gestation_days` are NULL for them (214 rows in tenant 5).
2. **`sp_log_palpation_event` can set `VACÍA`/`PREÑADA` on any non-blocked animal**, including bulls and `ACTIVO` animals of any category, and on a back-dated palpation it overwrites a newer status.
3. **The weight trigger ignores `log_date`:** `update_current_weight()` sets `current_weight_kg = NEW.weight_kg` on every insert, so a back-dated weigh-in overwrites a newer weight.
4. **The EXISTING `log_palpation_event_batch` still stores any diagnosis without a "PRE…ADA" word as `VACÍA`** (a typo or a note such as `DCL1 PROBABLE` becomes an empty cow). Not fixed (that tool is untouched); the phase 3 wrapper no longer does this (see decision 6).
5. **`sp_log_palpation_event` validates no date** (a future or years-old `p_palpation_date` is accepted) **and compares the e-mail case-sensitively** while `fn_repro_ctx` ignores case. The phase 3 wrapper validates the date itself (not future, at most 365 days back) and passes the stored spelling of the e-mail.
6. **Deleting an animal that has palpation details is blocked** (FK without cascade + append-only `palpation_repro_details`, same as the empadre tables). Test-data cleanup of a palpated animal must account for it (the throwaway-database tests are rolled back, so they are unaffected).
7. **The 214 bulk-loaded palpations of tenant 5 have no `palpation_repro_details` row** (no backfill in phase 3: it is a data write for the owner to decide). Their raw `condicion_utero` is read directly by `list_unmapped_uterine_codes`; `vw_cattle_kpi` still ignores them (item 1).
8. **Re-confirming a code overwrites the mapping without history:** `sp_repro_condition_code_set` updates the `repro_condition_codes` row in place (only the last `confirmed_by` / `confirmed_at` survive), so who mapped what, and what a code meant before, is lost. Stored palpations are unaffected (snapshots), but the mapping itself has no audit trail. Add an append-only mapping history if the vets change answers.
9. **`sp_register_birth_event` can leave a birth that cannot be corrected:** births cannot be voided (`birth_events` is not in `sp_void_event`'s whitelist and has no `tenant_id`), and a wrong calf / dam status stays. After 088 a service linked to a birth cannot be voided either, so a wrong link is fixed by a person with SQL, not by a tool.
10. **Fail closed on a NULL e-mail in `sp_register_birth_event` once migration 089 is applied and a review period shows no NULL callers** (owner decision, 2026-10-28). Until then the legacy NULL path stays open on purpose; the monitoring query is in `087_RUNBOOK.md` (births with `reported_by_email IS NULL`).
11. **The legacy dam resolution is unchanged and weak:** by ear tag it looks only at `rfid_siniiga` (never `electronic_rfid`), and an ambiguous or unknown dam registers an ORPHAN calf with a warning. `sp_repro_register_birth` is the checked path; the old tool still takes the old route until the prompts (phase 5) switch.
12. **`sp_log_breeding_event` still has no female check** (sex / category of the animal that is served) and its sire stays free text in the table; only the sire's resolution, the bull-category check and the warnings were added.
13. **A sire of ANOTHER company cannot be rejected, only warned (`sire_not_resolved`):** telling "a bull of company B" from "an unknown name" needs a cross-company lookup, which would reveal that an identifier exists in another tenant. Deliberately not done.
14. **`birth_events.reported_by_email` is stored as the caller wrote it (case kept)**, while the historical tables store it lower-cased; compare case-insensitively.
15. ✅ **DONE in 090 (owner decision):** a bare uterine code with no explicit result word (`UTC2`, `UNE`, `UTCL1-3`, `RP`, `NO APTO`, any known code) on an animal whose status is PREÑADA is now rejected (`NEEDS_EXPLICIT_RESULT`, and so the whole batch); the user restates it with an explicit result. `NR` alone is not rejected (it infers nothing).
16. **The imported `MATRIZ OCUPADA` row of tenant 5 contradicts its meaning** (stored `resultado = VACIA`, the animal is `VACÍA`, but the code means pregnant). Phase 3b only DISPLAYS it (`palpation_code_contradicts_result` in the dam history); nothing is corrected. A correction procedure with audit (previous status kept) is in the backlog.
17. **The meanings of NR, RP, NO APTO and MATRIZ OCUPADA were confirmed by the ranch foreman, not by a veterinarian.** The 090 seed records it (`source = SEED_090_FOREMAN_CONFIRMED`, `confirmed_by = 'capataz (sin confirmacion veterinaria)'`) and `list_unmapped_uterine_codes.meanings_configured` shows it. Ask the veterinarians to confirm.
18. **`NR` after a slash (`UNE/NR`) is unconfirmed:** the palpation is real, the condition stays NULL and the token is reported in `composite_unconfirmed`. Only ONE such row exists in tenant 5. The foreman will be asked what NR means in that position; do not derive ESTATICA from it meanwhile.
19. **`NR` alone leaves no record:** the line is validated and answered (`not_examined`), but nothing is stored, so the history never shows "not examined on date X". If the ranch wants that history it needs its own append-only table (not built).
20. **Meanings can only be set by SQL (the seed file):** there is no procedure for an ADMIN to give a meaning to a code, and `sp_repro_condition_code_set` refuses to give a condition to a code that has one.
21. **The RP birth window (90 days, symmetric around the palpation date) is an assumption** of phase 3b; adjust `v_birth_win` in the wrapper if the ranch defines "recién parida" differently.
22. **After 090 the older state checks (086, 088) report a different `phase3_palpation_functions` fingerprint** (the 7 replaced bodies); that is expected. `090_state_check.sql` asserts them on their own `BODY_*` lines.

### Phase 1 delivered (migration 084) — review notes
- **Files:** `database/migrations/084_repro_births_age.sql`, `084_rollback.sql`, `084_state_check.sql`, `084_tests.sql`, `084_RUNBOOK.md`; n8n: `workflows/09-MCP-Agent-Cattle/v6/repro-phase1/` (`repro_phase1_tools.json`, `README.md`); `.gitignore` gains one exception for `database/discovery/*.sql` (migrations already had theirs). **None of the SQL was executed by the author** (no database was available to the assistant); run `084_tests.sql` on LOCAL / a throwaway copy first.
- **Deviation from the brief:** `fn_estimate_birth_from_fire_number` is **STABLE, not IMMUTABLE**, because "year not in the future" depends on today's date; declaring it IMMUTABLE would be wrong (cached plans / expression indexes would go stale). The pure structural classifier `fn_fire_number_shape` is IMMUTABLE and holds every rule except the future test.
- **Return convention:** expected conditions are answers (`ok`, `not_found`, `ambiguous` + candidates, `invalid`); a non-member, an unknown tenant, an empty/invalid tenant or e-mail, and a palm company **raise** (`P0001` / `P0094`), so company A never gets rows or a status for company B.
- **Scope of `identifier_quality_report`:** animals still in the herd (not `VENDIDO`, `BAJA_MORTANDAD`, `FINALIZADO`, `BAJA_DEPURACION_DATOS`). `rfid_siniiga` and `electronic_rfid` are `UNIQUE` **globally**, not per tenant (observed in `repro_01`), which is why `''` collides. The `''` → NULL trigger stays a separate later migration (not written).
- **Not done in phase 1 by design:** no change to the four existing procedures; no backfill of historical births (`list_unregistered_historical_births` only reports); tools are not yet in the agent prompts (phase 5).

### Phase 2 delivered (migration 085, empadre) — review notes
- **Files:** `database/migrations/085_repro_empadre.sql`, `085_rollback.sql`, `085_state_check.sql`, `085_tests.sql`, `085_RUNBOOK.md`; n8n: `workflows/09-MCP-Agent-Cattle/v6/repro-phase2/` (`repro_phase2_tools.json`, 7 nodes, `README.md`). **None of the SQL was executed by the author** (no database available to the assistant); run `085_tests.sql` on a throwaway database first (runbook, "Test database"). 085 **requires 084** (it aborts without it); 084 is not applied in production yet, so production order is 084 → 085.
- **Objects:** tables `repro_empadre_config` (PK `id_company`; no row = defaults 15 months / 300 kg), `repro_empadre_entries` and `repro_empadre_voids` (both append-only, `id_company` on every row, company guard triggers); functions `sp_repro_empadre_get_config`, `sp_repro_empadre_set_config` (ADMIN only, **not an agent tool**), `sp_repro_list_heifers_eligible_for_empadre`, `sp_repro_log_empadre_entry`, `sp_repro_log_empadre_entry_batch`, `sp_void_empadre_entry`, `sp_repro_list_empadre_entries` (added: without it an entry could not be found to void), `sp_repro_list_open_cows`. `sp_void_event` and the three other pre-existing procedures are untouched (state check fingerprints them).
- **Assumptions I had to make (please confirm or correct):**
  1. *"Active empadre"* needs an end. There is no exit event yet, so an entry counts as active for `empadre_window_days` (default **90**, per-company, ADMIN-editable) after its `entry_date`, unless voided. After that the heifer is eligible again if still unpregnant.
  2. Two extra per-company settings besides the two asked for: `weight_stale_days` (default **60**: a weight whose last weigh-in is older, or has no weigh-in date, is flagged `weight_stale`; it still counts) and `empadre_window_days` (above).
  3. *Bull* = a `TORO` or `BECERRO_TORETE` (BOVINO) of the same company, not sold / dead. A `NOVILLO` (castrated) is not a bull. The bull is optional; method is optional (`MONTA_NATURAL` / `INSEMINACION_ARTIFICIAL`).
  4. Logging accepts `NOVILLONA`, `BECERRA` and also `VACA` (open cows are the natural next list); for a `VACA` the heifer thresholds do not apply (`NO_APLICA`, no warning). Eligibility lists remain `NOVILLONA` + `BECERRA` only.
  5. *Active, not PREÑADA* = status not in `VENDIDO`, `BAJA_MORTANDAD`, `FINALIZADO`, `BAJA_DEPURACION_DATOS`, `PREÑADA`. `EN_TRANSITO`, `CUARENTENA`, `RIESGO`, `DESARROLLO` stay in the lists (their status is returned).
  6. *Any active member may log and void* (staff report through the chat), including `CUSTOMER`. Role "Solo lectura" is only enforced in the agent in a later phase (Rule 17); if `CUSTOMER` must not log, it is a one-line check.
  7. A retry is "same heifer + same entry date + same bull, not voided" (no 5-minute window); the same heifer with other data while an empadre is active answers `ALREADY_IN_EMPADRE` (void the old one first).
  8. Entry dates use the Mexico City calendar day; future dates and dates older than 365 days are refused.
  9. `list_open_cows` considers `VACA` and `NOVILLONA` with status `VACÍA`; a cow already in an active empadre is **not hidden**, it is flagged `in_active_empadre`.
- **Warnings (never block):** `BELOW_THRESHOLDS`, `NO_DATA`, `WEIGHT_STALE`; stored in `repro_empadre_entries.warning_code / warning` and returned. Blocks only on: unknown / ambiguous animal, not a bovine female, sold / dead, `PREÑADA`, bad bull, already in empadre, bad date.
- **Known limitation inherited from the backlog:** the weigh-in date shown is the latest `cattle_weight_logs.log_date`, but `current_weight_kg` is the last INSERTED weight (the trigger ignores `log_date`), so after a back-dated weigh-in the two can disagree.

### Phase 2b — weekly empadre alert (SPEC ONLY, not built)
- `notify_enabled` exists per company and is held `false` by a CHECK constraint (`ck_empadre_cfg_notify_off`); phase 2b replaces that constraint when it is built. No workflow, no recipients, no schedule exist.
- Suggested default (not decided): weekly, Monday 08:00 `America/Mexico_City`, recipients = the company's active `ADMIN` members from `user_companies.role` (never `users.role`), one message per company, no message when `eligible_total = 0`.
- Content: the same data as `list_heifers_eligible_for_empadre` (counts by trigger EDAD / PESO / AMBAS, the first N heifers, `sin_datos` count, stale-weight count), generated by the database (a function returning the text), not by the model. Channel (e-mail like the sale-order notification, or WhatsApp) to be decided. Recipients and frequency are **owner decisions, pending**.

### Phase 3 delivered (migration 086, palpation condition) — review notes
- **Files:** `database/migrations/086_repro_palpation.sql`, `086_rollback.sql`, `086_state_check.sql`, `086_tests.sql`, `086_RUNBOOK.md`, `086_seed_tenant5_uterine_codes.sql` (separate, owner only); n8n: `workflows/09-MCP-Agent-Cattle/v6/repro-phase3/` (`repro_phase3_tools.json`, `README.md`). **None of the SQL was executed by the author** (no database was available to the assistant); run `086_tests.sql` on a throwaway database first.
- **Backlog items 1–3 requested for this phase were already recorded in phase 0** (Spanish-key palpations invisible to `vw_cattle_kpi`; palpation can set VACÍA on bulls / ACTIVO animals; weight trigger ignores `log_date`); I added items 4–7 found while building it. Nothing of the backlog is fixed.
- **Existing procedures untouched:** `sp_log_palpation_event`, `log_palpation_event`, `log_palpation_event_batch` keep their fingerprints (the state check prints `sp_log_palpation_event_only`). The new `sp_repro_log_palpation_batch` validates everything first (nothing written on any problem: `rejected` + `issues`), then calls the existing procedure once per item and writes the details row in the same call/transaction. "Same statement" is therefore "same function call".
- **Deviations / decisions to confirm:**
  1. `fn_parse_uterine_code(text, integer DEFAULT NULL)`: the brief says `(text)`, but the per-company lookup needs the company. Called with one argument it only knows the explicit words. The pure tokenising is `fn_uterine_split` (IMMUTABLE).
  2. Several known tokens with **different** conditions (`UNE/UTCL1`) make the value UNMAPPED (unspecified in the brief; fail-safe). Several known tokens with the **same** condition map (`UTCL1/UTCL2`). Both OI and OD present → `ovary_side` NULL.
  3. `stale_import_date` requires at least **10** palpations in the company before it can be true (otherwise 2 palpations of one real session would be flagged); the brief said only "more than 50%".
  4. `list_palpation_due` includes females in empadre (window of `repro_empadre_config`, default 90 days) or `PREÑADA`, **including never-palpated ones first** (`never_palpated`), and compares the last palpation of any result with `N` (90–120). An empadre heifer palpated *before* her entry is still listed (`palpated_after_empadre_entry = false` tells them apart).
  5. `list_upcoming_calvings`: estimate = last PREÑADA palpation date + (283 − its gestation days) when the gestation is 1–283; otherwise last non-voided service + 283; BOVINO only (species names in the breeding procedure do not match the rest). Buckets: `upcoming` (0..N days), `overdue` (1–60 days past), `stale_data` (> 60 days past, never upcoming / overdue), `no_estimate`. `status_conflict` marks a PREÑADA cow whose newest palpation is VACÍA.
  6. **Decision applied (owner, after two reviews): the wrapper never defaults an unrecognised diagnosis to `VACÍA`, and never accepts a bare token by its shape.** `fn_repro_diagnosis_kind` accepts a diagnosis only if, accent- and case-insensitively, it contains a PREÑADA word (`PREN?ADA`), a VACIA word or an explicit word (ciclando / estática), **or** every code token of it already exists in `repro_condition_codes` for the company (any row, including one with a NULL condition = known but pending veterinarian confirmation). With a PREÑADA / VACIA word, unknown tokens are accepted and stored UNMAPPED. Everything else (`PREÑDA`, `ok`, `pre`, random text, an unknown bare code, a compound with one unknown part such as `UNE/NR` while `NR` has no row, `N/A`, empty) is rejected per item as `DIAGNOSIS_UNRECOGNIZED`; PREÑADA with a VACIA or explicit word is `DIAGNOSIS_CONFLICT`. The earlier "looks like a code" shape rule was removed. Table change that follows: `repro_condition`, `confirmed_by` and `confirmed_at` are nullable (a CHECK keeps a confirmed condition tied to who and when); `list_unmapped_uterine_codes` still lists pending codes, now with `known_pending`, and `confirmed` returns only confirmed rows; an ADMIN confirming a pending code answers `updated` with `previous_condition` NULL. The wrapper also adds lower-case `meses` and `NN dias` for gestation, and refuses a repeated animal in the batch, an animal sold / dead and an ambiguous identifier (the existing tool raised an error for the last two).
  7. Any active member can log (same as the existing palpation tools), including CUSTOMER; only an ADMIN can confirm a code (`sp_repro_condition_code_set`, no n8n tool). Re-mapping overwrites the mapping row (`confirmed_by` / `confirmed_at` of the last change); stored palpations are snapshots. There is no mapping history table.
  8. `repro_condition_codes` has no delete trigger (it is configuration, and the seed undo deletes by exact key); `palpation_repro_details` is append-only.
- **Seed:** UNE → ESTATICA; UTCL1, UTCL2, UTCL3 → CICLANDO for company 5, `source = SEED_086_VET_CONFIRMED`, plus `RP`, `UTC2`, `NR`, `NO APTO`, `MATRIZ OCUPADA` as known-but-pending rows (NULL condition / confirmed_by / confirmed_at, source `pending veterinarian confirmation`). `ON CONFLICT DO NOTHING`, dry run by default, requires `-v confirmed_by=` (used for the 4 confirmed rows only).

### Phase 4 delivered (migrations 087, 088, 089) — review notes
- **Files:** `database/migrations/087_repro_births.sql` (+ `_rollback`, `_state_check`, `_tests`, `087_RUNBOOK.md`), `088_repro_services.sql` (+ same set), `089_disable_nacimiento_gateway.sql` (+ same set; **optional and independent**); n8n: `workflows/09-MCP-Agent-Cattle/v6/repro-phase4/` (`repro_phase4_tools.json`, `README.md`, 8 tools). **None of the SQL was executed by the author** (no database was available to the assistant); run each `*_tests.sql` on a throwaway database first. The agent prompts are NOT edited (phase 5).
- **Verified before writing (owner's read-only production queries, 2026-10-28):** `sp_register_birth_event` has ONE overload (13 parameters); the md5s of `pg_get_functiondef` of the three procedures (`8eaf6f52…` / `2c1ff0ad…` / `c81f6fae…`) equal the md5 of the bodies dumped in `out_repro_01_definitions.txt` (reconstructed byte for byte, so that dump IS production). Every migration that replaces one of them **aborts if the live md5 differs** (or if it already carries the migration's marker, so re-applying works); the rollbacks restore the original text and the state checks assert its md5. Callers: `sp_log_breeding_event` and `sp_void_event` are reached only by the MCP tools `log_breeding_event` / `void_event` (both already require a matching active membership; no gateway model, no frontend), so both now fail closed on a NULL / non-member e-mail. `sp_register_birth_event` is reached by the MCP tool and by the gateway model `nacimiento` (crud_models id 70, no e-mail) - hence 089 and the documented legacy NULL path.
- **Places that assumed the 12-parameter overload (reported and corrected in this branch):** `docs/reproduction-discovery.md` (the Q12 table, its follow-up paragraph and the "Palpation / birth" note), `CLAUDE.md` Rule 11 and `docs/DATABASE_SCHEMA.md` ("Birth Subsystem"). No 084 / 085 / 086 state check, test or migration assumes it: they fingerprint `sp_register_birth_event` by NAME across all overloads, which is correct for a database with only the 13-parameter one; the 087 state check also fingerprints any other overload separately.
- **Design choices to confirm:**
  1. Split into 087 (births, historical births, config), 088 (service link, hardened `sp_log_breeding_event` / `sp_void_event`, dam history), 089 (gateway), each with its own rollback and state check.
  2. **One writer for births:** `sp_repro_register_birth` and the block register validate (`fn_repro_birth_check_line`) and then call the legacy `sp_register_birth_event` with the resolved dam id. The identical-twin `force` is passed to the legacy retry check through the transaction-local setting `app.repro_force_birth` (reset on exit and on error), the same pattern as `app.identifier_change_reason`.
  3. **Legacy retry key** (owner refinement): company + dam + date + calf sex + birth weight (`IS NOT DISTINCT FROM`, the weight is read from the calf's `BIRTH_EVENT` weight log) within 5 minutes; a dam that was not resolved cannot be retried (no key).
  4. **New function validations beyond the legacy one:** species BOVINO / BORREGO / BUFALO / EQUIDO; calf sex; date not future and at most 365 days back (older = historical births); weight in (0, 150] kg; lot, production unit and paddock must belong to the company (the legacy one checked only the lot); the dam must be active, of the same species and, for bovines, VACA / NOVILLONA / BECERRA.
  5. **`possible_duplicate`:** window per company (`repro_births_config`, default 240, ADMIN-editable 30-730); registered births count by date; historical births count when DAY or MONTH (range overlap), not YEAR, never voided. Identical twins and any "another real birth" go through `force`. `force` also bypasses the exact-retry check.
  6. **Blocks:** at most 50 lines; no per-line force; a line that is ambiguous / not_found / possible_duplicate / invalid, or a dam repeated inside the block, makes the whole register answer `rejected` with per-line detail and write nothing; `duplicate_skipped` lines are skipped, not rejected. The register validates twice (the second time under advisory locks taken in dam-id order) and never uses a preview.
  7. **Historical births:** `calf_sex` NOT NULL with a MACHO / HEMBRA check, a `source` check without HISTORICAL_NOTEBOOK and the dam-reference check make `birth_events` unfit, so they have their own append-only tables (+ voids). MONTH / YEAR store the first day of the period; idempotency key = dam + date + precision + calf sex (`IS NOT DISTINCT FROM`) + `litter_position`; not in the future, no lower bound; the dam may have any status (returned as information).
  8. **Service link:** exactly one non-voided, not-yet-linked service of the dam inside the species window (BOVINO 283 [238, 328]; OVINO = BORREGO 152 [132, 172]; EQUINO = EQUIDO 340 [295, 385]; BUFALO 310 [280, 340]); otherwise unlinked with a reason. The guard trigger accepts exactly one UPDATE (NULL -> a birth of the same dam and company, once). The linker is called from the legacy procedure (so every birth path links, including the MCP tool) and a failure of the linker never undoes the birth. No backfill. A person can still link an out-of-window service by hand (the trigger allows it for the same dam and company).
  9. **`sp_log_breeding_event` / `sp_void_event` answer rejections as `{success:false, ...}` (not SQL errors)** for sire ambiguous / not a bull / the female herself, and for a service linked to a birth: the existing tools' descriptions only talk about errors, so phase 5 must teach the prompts to relay `message` / `candidates` / `warnings` (written in `repro-phase4/README.md`).
  10. **089:** keeps row 70 (a missing row would reopen the *Can Register Model* path), sets `allowed_ops = '{}'` and the four roles to `'NONE'`, backs the whole original row up in an append-only table and restores it exactly (the rollback compares the whole row and aborts on any difference). Pre-checks are in `089_RUNBOOK.md` (executions mentioning the model in 90 days, **plus the oldest retained execution and the retention settings**, plus the birth source distribution: all 23 rows are `MOBILE_APP`, which both the gateway and the MCP tool write).
  11. `get_dam_reproductive_history` caps every section at 200 rows (flag `sections_truncated_at_200`) and reports: stale import date (company flag and per palpation), services older than the gestation window still unlinked, births without a linked service, palpations with an unmapped code, and a PREÑADA / VACÍA status that disagrees with the newest palpation.
  12. Any active member can register, force and void (as in earlier phases, CUSTOMER included); only an ADMIN changes the window.

### Phase 3b delivered (migration 090, vet-code semantics) — review notes
- **Files:** `database/migrations/090_repro_vet_code_semantics.sql`, `090_rollback.sql`, `090_state_check.sql`, `090_tests.sql`, `090_RUNBOOK.md`, `090_seed_tenant5_vet_code_meanings.sql` (separate, owner only). 086 and 088 are NOT edited: 090 replaces 7 live bodies with `CREATE OR REPLACE` (same signatures) behind md5 guards. **None of the SQL was executed by the author** (the assistant has no database); run `090_tests.sql` on a throwaway database first.
- **Confirmed meanings (ranch foreman, not a veterinarian):** MATRIZ OCUPADA = pregnant (fixed PREÑADA phrase, for every company); NR = not examined; RP = recién parida; NO APTO = unfit for breeding; UTC2 = general uterine tone, NOT ciclando (stays known-pending); OI / OD and N/A unchanged (N/A is still "no code").
- **The one DDL change:** `repro_condition_codes.meaning` (nullable, CHECK in NOT_EXAMINED / POSTPARTUM / UNFIT, and a CHECK that a code with a meaning has a NULL condition). Approved by the owner; no default, no rewrite, no rows written by the migration.
- **What was wrong in 086 (found by reading it):** with the 086 seed applied, a bare `MATRIZ OCUPADA`, `NR`, `RP`, `NO APTO` or `UTC2` was accepted as kind `CODE` and written as an inferred **VACÍA** (status flipped); without the seed they were rejected. So `MATRIZ OCUPADA` could turn a pregnant cow VACÍA and `NR` flipped a cow that was not examined. Production never had the seed (LOCAL only).
- **New behaviour:** `MATRIZ OCUPADA` → PREÑADA (conflict with VACIA / explicit word / RP / NO APTO); `NR` alone → validated, then `line_status: not_examined`, nothing written, other lines processed, an only-NR batch answers `recorded` with `written: 0`; `NR` inside `UNE/NR` unchanged; `RP` / `NO APTO` → VACÍA with `vet_flag`, condition NULL, `NOT_APPLICABLE`, wording kept, category untouched, **and ANY code-only line (a code without an explicit result word) on a PREÑADA animal is rejected (`NEEDS_EXPLICIT_RESULT`, owner decision) so a pregnancy is never erased silently**; RP with no registered birth within 90 days → `rp_without_registered_birth`.
- **Read tools:** `list_palpation_due`, `list_upcoming_calvings` and the dam history show `last_palpation_code` / `vet_flag`; the dam history adds `palpation_code_contradicts_result` and `palpations_with_vet_flag`; `list_unmapped_uterine_codes` adds `known_meanings`, `composite_unconfirmed`, `meanings_configured` and no longer reports the known meanings as unknown.
- **md5 verification:** the owner's 7 LOCAL md5s of the 086 / 088 bodies were reproduced exactly from the repo files (by rebuilding `pg_get_functiondef` text), so the LOCAL database was not edited by hand and the guards use those values.
- **Backlog:** items 16–22 added; item 15 (guard for every bare code) was done in 090 itself. Seed order (owner): in the phase 5 production runbook the 086 seed and the 090 seed run back to back BEFORE the palpation tools are connected to the agents; locally the 090 seed runs right after 090. The 90-day RP window (symmetric) is a documented assumption.

### Phase 5 — tool inventory (agent tools of phases 1-4 and 3b)
All 24 nodes live in `workflows/09-MCP-Agent-Cattle/v6/repro-phase{1..4}/repro_phase*_tools.json` and are added to `v6_MCP_Server_Cattle.json` by `repro-phase5/add_repro_tools.py`. Every one takes `tenant_id` and `user_email` from `$fromAI` (same level as the 29 existing tools; the database validates membership, Rule 6). NIVEL: 1 = read, no confirmation; 2 = routine write, no confirmation; 3 = summary and an explicit "Sí" in the next turn. Roles: every role may capture these events (including CUSTOMER); only death and sale requests need ADMIN authorization, as today.

| Phase | Tool (= node name) | SQL function | Read / write | NIVEL | Prompts that list it |
|---|---|---|---|---|---|
| 1 | `list_births` | `sp_repro_list_births` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 1 | `get_dam_birth_history` | `sp_repro_dam_birth_history` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 1 | `get_births_summary` | `sp_repro_births_summary` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 1 | `list_unregistered_historical_births` | `sp_repro_list_unregistered_historical_births` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 1 | `identifier_quality_report` | `sp_repro_identifier_quality_report` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 2 | `get_empadre_config` | `sp_repro_empadre_get_config` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 2 | `list_heifers_eligible_for_empadre` | `sp_repro_list_heifers_eligible_for_empadre` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 2 | `log_empadre_entry` | `sp_repro_log_empadre_entry` | WRITE | 2 | chat + WhatsApp (node `AI Agent`) |
| 2 | `log_empadre_entry_batch` | `sp_repro_log_empadre_entry_batch` | WRITE | 2 | chat + WhatsApp (node `AI Agent`) |
| 2 | `void_empadre_entry` | `sp_void_empadre_entry` | WRITE | 3 | chat + WhatsApp (node `AI Agent`) |
| 2 | `list_empadre_entries` | `sp_repro_list_empadre_entries` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 2 | `list_open_cows` | `sp_repro_list_open_cows` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 3 | `log_palpation_with_condition` | `sp_repro_log_palpation_batch` | WRITE | 2 | chat + WhatsApp (node `AI Agent`) |
| 3 | `list_palpation_due` | `sp_repro_list_palpation_due` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 3 | `list_upcoming_calvings` | `sp_repro_list_upcoming_calvings` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 3 | `list_unmapped_uterine_codes` | `sp_repro_list_unmapped_uterine_codes` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 4 | `register_birth_checked` | `sp_repro_register_birth` | WRITE | 2 | chat + WhatsApp (node `AI Agent`) |
| 4 | `births_batch_preview` | `sp_repro_births_batch_preview` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 4 | `births_batch_register` | `sp_repro_births_batch_register` | WRITE | 3 | chat + WhatsApp (node `AI Agent`) |
| 4 | `register_historical_birth` | `sp_repro_register_historical_birth` | WRITE | 3 | chat + WhatsApp (node `AI Agent`) |
| 4 | `void_historical_birth` | `sp_repro_void_historical_birth` | WRITE | 3 | chat + WhatsApp (node `AI Agent`) |
| 4 | `list_historical_births` | `sp_repro_list_historical_births` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 4 | `get_births_config` | `sp_repro_births_get_config` | read | 1 | chat + WhatsApp (node `AI Agent`) |
| 4 | `get_dam_reproductive_history` | `sp_repro_get_dam_history` | read | 1 | chat + WhatsApp (node `AI Agent`) |

**Not exposed to the agent (no node):** `sp_repro_condition_code_set`, `sp_repro_empadre_set_config`, `sp_repro_births_set_config` (SQL / ADMIN only).

**Leave the dictionary, keep the node (rollback path):** `register_birth_event` (replaced by `register_birth_checked`) and `log_palpation_event_batch` (replaced by `log_palpation_with_condition`). Their node `toolDescription` (only that) now starts with `OBSOLETA: no la uses. Usa <replacement>.`. `log_palpation_event` (single) stays in the dictionary, for an explicit result WITHOUT a code; with a vet code even a single animal goes through `log_palpation_with_condition` with ONE element.
- What the two legacy nodes call (read from the MCP export): `register_birth_event` → `sp_register_birth_event` (13 parameters), resolving lot / UPP names with a partial `ILIKE … LIMIT 1` and no ambiguity check; `log_palpation_event_batch` → `sp_log_palpation_event` once per animal, turning any text without a `PRE…ADA` word into VACÍA. **That batch can overwrite a PREÑADA animal with VACÍA and has no `NEEDS_EXPLICIT_RESULT` guard** (the guard is in `sp_repro_log_palpation_batch`, i.e. the wrapper); the single `log_palpation_event` needs an explicit result from the model.

**Existing tools whose answers changed** (the tools themselves were not edited; the prompts must relay the new answers):

| Tool | Changed by | What it answers now |
|---|---|---|
| `log_breeding_event` | 088 | Rejections are ANSWERS, not SQL errors: `{success:false, status:'ambiguous', candidates}` (several sires/females match), `{success:false, status:'rejected', message}` (the sire is not a TORO / BECERRO_TORETE, or is the female herself); warnings `sire_not_resolved` (the sire name matches no animal of the company; kept as free text) and `semen_batch_missing` (artificial insemination without batch); exact retry within 5 minutes → `{success:true, duplicate_skipped:true}`. A NULL / non-member e-mail raises (`P0001`). |
| `void_event` | 088 | A service linked to a birth answers `{success:false, status:'rejected', code:'LINKED_TO_BIRTH', birth_event_id}`; a non-member / NULL e-mail raises (`P0001`). |
| `register_birth_event` (legacy, leaves the dictionary) | 087 | An exact retry answers `{success:true, duplicate_skipped:true, …}`; adds `service_link` (`linked` / `no_candidate` / `ambiguous`); a non-member e-mail raises. Replaced in the dictionary by `register_birth_checked`. |
| `log_palpation_event_batch` (legacy, leaves the dictionary) | — | Unchanged (still defaults any text without a PRE…ADA word to VACÍA: backlog 4). Replaced by `log_palpation_with_condition`. |
| `log_palpation_with_condition` (new wrapper, 086 + 090) | 090 | `status: recorded | rejected | invalid`; `rejected` carries `issues[]` per line (`NEEDS_EXPLICIT_RESULT` / `line_status: needs_explicit_result`, `DIAGNOSIS_CONFLICT`, `DIAGNOSIS_UNRECOGNIZED`, …) and nothing is written; `recorded` carries `results[]` with `line_status` (`recorded` / `duplicate_skipped`), `vet_flag`, `rp_without_registered_birth`, and `not_examined_lines[]` (`line_status: not_examined`) for NR alone. Full reference with one example each: `database/migrations/090_RUNBOOK.md`, last section. |
| `list_lots` | Phase 5 | **Two NEW keys per row, `lot_id` and `production_unit_id`** (additive, read-only, same tenant filter; no key removed or renamed). The agent uses them internally to pass `lot_id` / `production_unit_id` to `register_birth_checked` and never shows them (A6). |

**Backlog added in phase 5**
23. **Inject `tenant_id` and the e-mail from the trusted context instead of letting the model fill them, for ALL MCP tools** (a later phase). Today the 29 + 24 tools take them from `$fromAI` (Rule 6); the database validates membership, but the prompt is the only thing that makes the model copy the verified values.
24. **Delete the `register_birth_event` node and its dictionary text** from the MCP server once the checked births tool is verified in production (it stays now as the rollback path of 087).
25. **Delete the `log_palpation_event_batch` node** from the MCP server after the rollout is verified (same reason; replaced by `log_palpation_with_condition`).
26. **QA leaves residue in company 3 (the test company):** births, empadre entries and historical births are append-only; the QA events cannot be deleted. Fixture rows carry a QA marker in their identifiers.
27. **Measure tool selection on `gpt-4.1-mini` with ~51 tools:** the rollout requires at least 90 % first-try correct tool choice in the QA; if not met, trim the dictionary or move the agent to a stronger model (see `REPRO_PRODUCTION_RUNBOOK.md`).

### Git (decided 2026-10-27)
Migrations were already excepted in `.gitignore` (line 35); only `database/discovery/*.sql` was missing. Prepared as **its own `chore` commit, before the feature commits** (one-line change in `.gitignore`); `database/discovery/out/` stays excluded by `.git/info/exclude` and must never be committed. Exact commands are in the hand-over message.

## 0. Corrections to the brief (names that differ from the real schema)

| Brief says | Repo/production says | Source |
|---|---|---|
| table `breeding_events` | **`cattle_breeding_events`** (columns keyed by `tenant_id`, not `id_company`) | `DATABASE_SCHEMA.md` (v1.16.0 section), `v6/MCP Server Cattle` |
| "palpation table(s)" / `sp_log_palpation_event` writing a palpation table | There is **no palpation table**. A palpation is a row in **`cattle_health_logs`** with `event_type = 'PALPACION'`; result and gestation days live in `medicines_json` (`vw_cattle_kpi` reads `last_palpation_result` / `current_gestation_days` from it, migration 061) | migration 061, `DATABASE_SCHEMA.md` |
| `birth_events.dam_id/calf_id/birth_date/calf_sex` | Correct, plus `id_company` (not `tenant_id`) and free-text `dam_ear_tag`, `dam_fire_number` | migration 030 |
| female categories "novillona/vaquilla/vaca" | `VAQUILLA` does not exist; it maps to **`NOVILLONA`** (CLAUDE.md line 155) | migration 005 |

Phase 3 therefore adds `repro_condition` to the palpation record = `cattle_health_logs` (or its `medicines_json`), not a new table. Open question Q3.

## a) Definitions — what the repo proves, and what it does not

### `birth_events` (migration 030, definition in repo)
Columns: `id uuid PK`, `id_company int NOT NULL` (FK companys, cascade), `production_unit_id`, `paddock_id`, `dam_ear_tag varchar(100)`,
`dam_fire_number varchar(50)`, `dam_id uuid` (FK cattle_livestock, SET NULL), `calf_sex varchar(10) NOT NULL`, `calf_brand_id`, `calf_id uuid`
(FK cattle_livestock, SET NULL, nullable — calf is born untagged), `birth_date date NOT NULL`, `source varchar(20) NOT NULL default 'FIELD_NOTEBOOK'`, `notes`, `created_at`.
Checks: `calf_sex IN ('MACHO','HEMBRA')`; `source IN ('FIELD_NOTEBOOK','SPREADSHEET_IMPORT','MANUAL','MOBILE_APP')`;
`dam_id OR dam_ear_tag OR dam_fire_number` must be non-null. A unique index on `calf_id` (when set) exists (line 152, "a calf can only be born once").
**No link to a breeding event** (no `breeding_event_id`). Fire numbers may repeat, so `dam_id` is only filled when a human disambiguates.
Not in this file: `reported_by_email`, `birth_weight` (birth weight goes to `cattle_weight_logs`, `source_device='BIRTH_EVENT'`).
Voiding: `birth_events` is **not** in the `void_event` whitelist.

### `sp_register_birth_event` (13-parameter overload; body NOT in repo — behaviour from `DATABASE_SCHEMA.md` and the MCP tool)
Parameters: `p_id_company, p_calf_sex, p_species, p_dam_id, p_dam_ear_tag, p_dam_fire_number, p_birth_date, p_lot_id, p_production_unit_id, p_paddock_id, p_birth_weight_kg, p_notes, p_reported_by_email`.
Returns jsonb. Creates the calf in `cattle_livestock` (category by species+sex: BOVINO MACHO→BECERRO, HEMBRA→BECERRA, ...), sets `mother_id`,
inserts `birth_events` (`source='MOBILE_APP'`), optional `cattle_weight_logs`. **Dam status: PREÑADA → VACÍA** on birth; any other status is left alone and the SP says so.
Location priority: explicit lot > dam's lot/UPP > `p_production_unit_id`. **Not linked to any `cattle_breeding_events` row.**
~~A 12-parameter overload also exists in production (without `p_lot_id`).~~ **Corrected 2026-10-28 (read-only query on the production server): only the 13-parameter function exists.** The 12-parameter version described in older notes (`DATABASE_SCHEMA.md`, `CLAUDE.md` Rule 11) is not there.

### `cattle_breeding_events` and `sp_log_breeding_event` (**definition NOT in repo**)
Docs only say "observed columns": `livestock_id`, `tenant_id`, `breeding_date`, method, sire, estimated calving date, notes; whitelisted in `event_voids`.
The MCP tool calls `sp_log_breeding_event(animal_identifier varchar, tenant int, breeding_date date, method varchar, sire_identifier varchar, semen_batch varchar, registered_by_email varchar, notes text)` and wraps it in the membership check + `fn_reject_palm_company`.
Method values (per brief): `MONTA_NATURAL`, `INSEMINACION_ARTIFICIAL`. Effect on `current_status`: **unknown** until `repro_01` section E is read. Sire validation (exists / male / same tenant): **unknown**. Duplicate protection: **unknown**.

### Palpation: `sp_log_palpation_event` (**definition NOT in repo**)
Signature from the tool: `(p_tenant_id int, p_user_email text, p_animal_identifier text, p_result text, p_gestation_days int, p_technician_name text, p_notes text, p_palpation_date date)`, returns a row set (the batch tool merges `to_jsonb(r)`, and the PRs mention a `duplicate_skipped` outcome).
Stores into `cattle_health_logs` (`event_type='PALPACION'`, `medicines_json`); result only `PREÑADA` or `VACÍA`. `CLAUDE.md` rule 13 says the `event_date` fallback is `CURRENT_TIMESTAMP`. Mapping to `cattle_livestock.current_status` (PREÑADA/VACÍA) is stated in the brief; **exact JSON keys, status update and duplicate rule must be read from the real function** (`repro_01` sections E and F).
`log_palpation_event_batch` parses `raw_diagnosis` inline in SQL: `ILIKE 'PRE%ADA%'` → PREÑADA else VACÍA; months via `(\d+)\s*MES` × 30 days; the raw text goes to `notes`. Note: "VACÍA CICLANDO" / "VACÍA ESTÁTICA" already fall in the `ELSE 'VACÍA'` branch, so Phase 3 does not change result semantics.

### `event_voids` / `sp_void_event`
`sp_void_event(event_table varchar, event_id uuid, tenant int, voided_by varchar, reason text)`; whitelist of exactly 3 tables, `UNIQUE (event_table, event_id)`, **does not revert side effects** on `cattle_livestock`. Extending it for the new empadre table means editing the whitelist inside the function body (not in repo) — needs the real `pg_get_functiondef` first.

**Action for the user:** run `database/discovery/repro_01_definitions.sql` (read-only) and send back the `.txt`. Every Phase 1+ migration that replaces one of these functions must be based on that output, not on this inferred summary (CLAUDE.md rule 7: `schema.sql` is stale — it still shows a `cattle_livestock.category` CHECK with 5 values).

## b) Female categories and how they are assigned

- `cattle_livestock.category` is `varchar` + CHECK (not an enum). Female bovine values: **`BECERRA`** (calf) → **`NOVILLONA`** (heifer) → **`VACA`** (cow). Buffalo/sheep/equine equivalents exist but are out of scope.
- `cattle_lifestage_catalog` (global, no tenant): `BECERRA→NOVILLONA` at 7 months (age only), `NOVILLONA→VACA` at 19 months **plus** weight check (`requiere_validacion_peso`). The catalog "triggers a review, never promotes by itself" (CLAUDE.md rule 9). I found **no job in the repo that applies it automatically** — category is set at load/birth (`sp_register_birth_event` creates `BECERRA`) and by humans. So category can lag behind age (see Q5).
- A heifer ≥15 months can still be `BECERRA` in the data; `list_heifers_eligible_for_empadre` as specified (active `NOVILLONA` only) would miss them. `repro_03` section 3b counts them.

## c) `current_weight_kg`: dated or latest value only?

Both. `cattle_weight_logs(livestock_id, weight_kg, log_date, source_device, created_at)` keeps dated history (no tenant column — tenant isolation must join `cattle_livestock`), and `cattle_livestock.current_weight_kg` is set by an AFTER INSERT trigger `update_current_weight()` ("exact reflection of the latest log"). Unverified: whether the trigger picks the latest by `log_date` or simply the last inserted (a back-dated weigh-in could overwrite a newer weight). Many animals have weight `0` (never weighed), so `0` must be treated as "no data", not as "light". For the weight rule we will use `current_weight_kg > 0` and, in Phase 2, expose the weight date from `cattle_weight_logs` (last log) next to it.

## d) numero_fuego parser spec and measurement

| Shape | Regex | Parsed | Precision |
|---|---|---|---|
| CURRENT (2025 onward) | `^(\d{2})-(\d+)-(\d{1,2})$`, YY ≥ 25, month 1–12 | year 2000+YY, consecutive, month | `MONTH` |
| LEGACY (before 2025) | `^\d{4}$`, YY 05–24 | year 2000+YY, consecutive; **month NULL, never inferred** | `YEAR` |
| OTHER | everything else: spaces/suffixes (`08-4 P`, `2011-1 P`), dashed with YY < 25, other lengths, 4 digits with YY ≥ 25 or < 05 | not parsed → NULL | — |

Year plausibility: not in the future, ≥ 2005 (assumption, Q4). Month outside 1–12 → NULL, never an exception. NULL/empty → NULL.
Expected results (to become unit tests in Phase 1): `26-45-4` → 2026/4/MONTH; `2097` → 2020/NULL/YEAR; `1342` → 2013/NULL/YEAR; `26-45-0`, `26-45-13` → NULL; `08-4 P`, `2011-1 P`, `24-10-2` (YY<25), `2599`, `9999`, `''`, NULL → NULL; `35-1-1` (future) → NULL; `26-45-4 ` (trailing space) → NULL (no trimming, no guessing).

Measurement: `database/discovery/repro_02_numero_fuego.sql -v tenant=<id>` reports shape counts, pattern/example table for the non-parsed values, year distribution, implausible years, duplicates, and for animals with a real `birth_date` the year agreement (both formats) and month agreement (CURRENT only), plus a list of disagreeing rows. **Numbers: see the 2026-10-27 update — tenant 5 has no CURRENT-format animals and its birth dates are mostly the placeholder, so neither rule can be validated from data there.** Gate: if year agreement is low (suggest < 90%) nothing is built on the rule (Phase 1 stops).

## e) Baseline counts

`database/discovery/repro_03_counts.sql -v tenant=<id>` answers, per tenant: `birth_events` count (with/without `dam_id`, `calf_id`, via agent); calves with `mother_id` and no `birth_events` row; active `NOVILLONA` eligible by age (month precision), by year-only estimate, by weight, by weight only, undecidable, with no data; palpation rows/animals; `cattle_breeding_events` total and by method (column auto-discovered); voided services. Run for each real tenant (e.g. 5, 6, 3) and send the `.txt`s. The scripts abort without `-v tenant` or with an unknown company.

**Superseded by decision B (2026-10-27): `REQUIERE_REVISION_FISICA` is removed.** Original finding: every legacy number is `≤ 2024`, so today the worst case (born December 2024) is already ≥ 22 months. Under the rule "year-only counts only if eligible even if born in December", **all legacy heifers are eligible and `REQUIERE_REVISION_FISICA` will always be empty** (until the rule is changed). Conversely, a legacy-numbered animal still classified as `NOVILLONA` is probably older than a heifer should be (category lag, Q5). The rule is implementable as written; the review bucket would only become meaningful if the year-only test is inverted or the threshold raised.

## f) Proposed design and open questions

### Design (summary)
- **Phase 1 (read-only):** `fn_estimate_birth_from_fire_number(text)` IMMUTABLE → `(year, month, month_reliable, precision)`; view `vw_animal_effective_birth` (real date wins, else estimate, never written back); query functions as `sp_repro_*(p_tenant, p_user_email, ...)` returning jsonb, each starting with `fn_reject_palm_company` + active-membership check, every table access filtered by tenant. Migration `084` (`074/075–079` are reserved; `083` is the latest, so `084` is the next free after confirming Q1), with `084_rollback.sql`, `084_state_check.sql`, `084_tests.sql`. No `DROP`/`TRUNCATE`: rollback = `CREATE OR REPLACE` of the previous behaviour or disabling new objects. The `electronic_rfid '' → NULL` trigger is a separate later migration.
- **Phase 2:** `repro_settings` (PK `id_company`, ADMIN-only writes, defaults 15 / 300, `notify_enabled`, `recipients`), `empadre_entries` (append-only, voidable through an extended `sp_void_event` whitelist, unique on heifer+date for idempotency), `empadre_alert_notified` marker table; entry tools return `warning` when the heifer is below both thresholds. Phase 2b workflow shipped as disabled JSON.
- **Phase 3–5:** as in the brief, adjusted by Q3 (palpation storage) and the real function bodies.

### Open questions (need your answer or server output)
1. **Migration number:** repo has up to 083 and gaps 075–079 (reserved for platform admins). Confirm `084` is free on the server (`ls`, and `schema_migrations` if used).
2. **Server output** of `repro_01` (function bodies, columns, constraints, triggers) — without it Phase 4 changes to `sp_register_birth_event` / `sp_log_breeding_event` / `sp_log_palpation_event` cannot be written safely.
3. **Palpation storage:** since there is no palpation table, may `repro_condition` / `static_cause` go (a) as keys inside `medicines_json` of the `PALPACION` row (no DDL, but not queryable/indexable), or (b) a new side table `palpation_repro_details(health_log_id, id_company, repro_condition, static_cause)` (proper columns, CHECK, no change to `cattle_health_logs`)? I recommend (b).
4. **Plausible-year floor:** 2005 as minimum birth year OK, or older cattle exist (legacy `YY≥25` like `9805` would be 1998)?
5. **Heifers still labelled `BECERRA` that are ≥ 15 months:** include them in `list_heifers_eligible_for_empadre` (as a separate flagged list) or only active `NOVILLONA`? And should `NOVILLONA` also include animals that should already be `VACA` (never calved, though)?
6. **Year-only rule consequence** (section e): keep as specified (all legacy eligible, empty review bucket) or define the review bucket differently (e.g. legacy animals older than N years that never calved)?
7. **Weight date:** treat `current_weight_kg > 0` as valid regardless of age of the reading, or require a weigh-in within N days?
8. **Phase 2b:** recipients (users of the company with role ADMIN/EDITOR? specific phone numbers?) and frequency (suggested weekly, Monday 08:00 America/Mexico_City).
9. **Which tenants** are in scope (5 "La Bendición", 6 "UPP 54", test tenant 3 "Rancho El Palomar"); palm companies are always rejected by `fn_reject_palm_company`.
10. **Fiscal math:** none involved so far; if any phase touches it I will stop and ask.

## Files delivered in this phase
- `docs/reproduction-discovery.md` (this file)
- `database/discovery/repro_01_definitions.sql`, `repro_02_numero_fuego.sql`, `repro_03_counts.sql` (read-only)

Server commands (user runs them; all output to `.txt`, no write access needed):
```bash
cd /path/to/hosting3m-workspace/projects/agro-erp/database/discovery
psql -v ON_ERROR_STOP=1 -X -d hosting3m_db -f repro_01_definitions.sql > /root/repro_01_definitions.txt 2>&1
for t in 3 5 6; do
  psql -v ON_ERROR_STOP=1 -X -v tenant=$t -d hosting3m_db -f repro_02_numero_fuego.sql > /root/repro_02_numero_fuego_t$t.txt 2>&1
  psql -v ON_ERROR_STOP=1 -X -v tenant=$t -d hosting3m_db -f repro_03_counts.sql      > /root/repro_03_counts_t$t.txt 2>&1
done
```
No backup is needed for these (read-only; the only object created is a session-local temp view).
