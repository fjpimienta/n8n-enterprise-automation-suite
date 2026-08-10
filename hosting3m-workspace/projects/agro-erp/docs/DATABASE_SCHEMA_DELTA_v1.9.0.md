# DATABASE_SCHEMA.md — Delta v1.9.0

Aplicar así:
1. **Reemplazar** la entrada de `sp_procesar_salida_ganado` completa (cambió dos veces desde
   que se documentó — validación de arete y de hato libre).
2. **Corregir** la nota sobre `cattle_livestock.rfid_siniiga`/`electronic_rfid` (la realidad
   invirtió la premisa original).
3. **Marcar como deprecada** la entrada de `cattle_tenants`.
4. **Añadir** la sección nueva completa "Regulatory Registry Subsystem" tras "Cattle
   Management Subsystem".
5. **Añadir** las vistas y funciones nuevas a la sección "Views (BI Layer)".

---

## 1. Corrección — `cattle_livestock` (columnas de identificación)

Reemplazar:

```
* `rfid_siniiga` (VARCHAR, UNIQUE) - Secondary Metadata (physical SINIIGA ear tag; loses reliability due to physical loss)
* `electronic_rfid` (VARCHAR, UNIQUE) - Primary Operational Key (rumen bolus / subcutaneous microchip)
```

por:

```
* `rfid_siniiga` (VARCHAR, UNIQUE) - Official SINIIGA ear tag. Format confirmed 2026-07-29:
  10 digits, EE + 4 + 4, where EE is the INEGI state code (07 Chiapas, 27 Tabasco).
  Validated by `fn_has_official_ear_tag()`. ⚠️ In practice this is the identifier that
  actually covers the herd: 262 of 270 animals (97%, verified in production 2026-07-29)
  carry no `electronic_rfid` at all.
* `electronic_rfid` (VARCHAR, UNIQUE) - Documented as the primary operational key (rumen
  bolus / subcutaneous microchip), and is what `sp_procesar_salida_ganado` keys on. In
  practice only 8 of 270 animals carry one. Pending client decision: whether to tag the
  full herd or shift the operational key to `rfid_siniiga`.
* `numero_fuego` (VARCHAR) - Physical brand/iron mark identifier, i.e. the traditional
  fire-branded number, distinct from `brand_id` (ownership brand, see below). Capture is
  NOT uniform across tenants: 100% present in tenant 5 (La Bendición), 0% in tenant 6
  (UPP 54). Do not assume presence when designing sort/search on this field.
* `brand_id` (UUID, FK -> `brand_registrations`, nullable) - Ownership brand. Independent
  of `production_unit_id`: an animal may stand in one holder's unit while belonging to the
  other holder. Inherited automatically from the dam via `fn_inherit_brand_from_mother`
  (trigger on INSERT/UPDATE of `mother_id`/`brand_id`); an explicit value always wins over
  inheritance. Populated for 0 of 270 animals as of 2026-07-29 — no source exists to infer
  it retroactively; requires a physical field pass.
* `mother_id` (UUID, FK -> `cattle_livestock` self-reference, nullable) - Dam. Field
  notebooks record every birth as "parió <dam tag> - <dam fire number> - <calf sex/brand>",
  so lineage exists on paper back to 2023 and is not yet loaded into the database.
* `paddock_id` (UUID, FK -> `production_unit_paddocks`, nullable) - Current paddock.
  Guarded by `fn_guard_livestock_paddock()`: a paddock belongs to exactly one production
  unit, and the trigger rejects assigning it to an animal standing in a different unit.
* `production_unit_id` (UUID, FK -> `production_units`, nullable) - Real FK that replaces
  the free-text `upp_origen` as the authoritative link to a UPP. Guarded by
  `fn_guard_livestock_production_unit()` (fail-closed against cross-tenant assignment).
  `upp_origen` is retained as a denormalized label, kept in sync via migration 023, but is
  no longer the source of truth.
```

## 2. Corrección — `sp_procesar_salida_ganado` (reemplazar entrada completa)

```
### `sp_procesar_salida_ganado(p_electronic_rfid)`
* **Purpose:** Business rule enforcement for livestock checkout (sale).
* **Signature and invocation unchanged since v1.0.0:** `SELECT sp_procesar_salida_ganado(rfid)`.
* **Mechanism (as of migration 024, 2026-07-29):**
  * `FOR UPDATE` row-level locking on `cattle_livestock`, unchanged since v1.0.0.
  * **Hard errors** (`RAISE EXCEPTION`, `ERRCODE` P0002/P0001): RFID not registered, or
    already `VENDIDO`.
  * **Regulatory rejections** (`success:false`, no exception — lets the n8n gateway
    distinguish a business rejection from a real data error), evaluated in this order:
    1. **Official ear tag missing** (`fn_has_official_ear_tag(rfid_siniiga)` false).
       NOM-001-SAG/GAN-2015 requires the SINIIGA tag for any movement; this check was
       ABSENT until migration 024 — the routine used to authorize illegal exits.
    2. **TB/BR not covered.** The 60-day window is the validity of a LOT TEST only
       (`tb_test_date`/`br_test_date`). A production unit with a current entry in
       `herd_free_certificates` for that disease (`fn_is_herd_free`) is exempt from the
       60-day check entirely — a herd-free certificate is valid for 12-24 months.
       This exemption did NOT exist before migration 024: the routine used to reject
       legitimate sales from a certified herd.
  * **On success:** sets `current_status = 'VENDIDO'`, clears both `upp_origen` AND
    `production_unit_id`, and inserts a `VENTA` row into `historico_movimientos`. Returns
    `tb_herd_free`/`br_herd_free` flags alongside the result for transparency.
* **Compensating reversal:** if a row is mistakenly marked `VENDIDO` (e.g. a test run
  against production), restore the animal by hand and insert a `REVERSION` row in
  `historico_movimientos` (added to the CHECK in migration 025) — never delete the
  original `VENTA` row. The audit table is append-only.
```

## 3. Marcar `cattle_tenants` como deprecada

Añadir al final de esa entrada:

```
* ⚠️ **DEPRECATED (migration 010, 2026-07-27).** Single row, generic RFC
  (`XAXX010101000`), zero foreign keys referencing it in the entire schema. Not dropped
  (production-safety guardrail): retained read-only. Meta-CRUD model downgraded to
  `{SELECT,GETONE,GETALL}`, `allowed_roles_insert/update/delete = NONE`. `org_type` was
  migrated to `companys.org_type` (CHECK: GANADERO/UNION/GOBIERNO, nullable for
  non-livestock tenants).
```

## 4. Nueva sección — pegar tras "Cattle Management Subsystem"

```markdown
## 🏛️ Regulatory Registry Subsystem (SENASICA-SINIIGA)

Introduced in v1.9.0 to model the client's real padrón: N production units per tenant,
two title holders, two independent ownership brands, and the SENASICA-SINIIGA compliance
lifecycle. Deployed to production 2026-07-27 through 2026-07-29 (migrations 010-030).

### `livestock_producers` (Producer / Holder)
* `id` (UUID, PK), `id_company` (INT, FK -> `companys`, `ON DELETE CASCADE`)
* `full_name`, `producer_role` (TITULAR / SOCIO / REPRESENTANTE)
* `curp_enc`/`rfc_enc` (BYTEA, pgcrypto) + `curp_hash`/`rfc_hash` (SHA-256, equality lookup
  without decrypting). Written exclusively via `sp_upsert_producer_pii()`.
* **Deliberately replicated per tenant, not global.** The same physical person (confirmed:
  both Alejandro and Pedro Aguilar Reséndez hold title across multiple tenants) gets one
  row per tenant. A shared global producer row would be a cross-tenant PII leak by design.
* Partial unique index: exactly one active TITULAR per tenant.

### `production_units` (UPP)
* `upp_code` (CHECK `^\d{2}-\d{3}-\d{4}-\d{3}$`), unique among active units.
* `state_code`/`municipality_code` — GENERATED from `upp_code` (INEGI encoding). Read-only.
* `total_surface_ha`, `is_partial_surface` (constancia distinguishes "Total" from "Parcial").
* `surface_matrix` (JSONB, GIN) — verbatim SENASICA grid `[riego,temporal] × 6 conceptos`.
  Never normalized/corrected: real constancias are internally inconsistent (Santa Lucía
  declares 42.00 ha total with every concept cell at 0.00) and a sum-CHECK would reject the
  client's own official document.
* `grazing_surface_ha` — GENERATED (agostadero + praderas + cultivos forrajeros).
  ⚠️ Currently 0.00 for all 4 loaded units (either NULL matrix or all-zero grid): treat as
  "not available" in any UI, never as a literal zero divisor for stocking-rate math.
* `registry_status` (ACTIVA/BLOQUEADA/SUSPENDIDA/BAJA) — distinct from `is_active`.
  BLOQUEADA means the unit exists and its history stays queryable but cannot move
  livestock (client-confirmed real state for Santa Lucía, 2026-07-29).
* `fire_brand_patent` — links to `brand_registrations` by patent number where known
  (e.g. UPP 27-009-4146-002 carries patent 155, matching brand `R`'s municipal registry).

### `psg_licenses` (Prestador de Servicios Ganaderos)
* Belongs to the **person**, not the predio — operational, gates livestock movement.
* `psg_code` (CHECK `^\d{2}-\d{3}-\d{4}-P\d{2}$`), unique **per tenant** (deliberate: the
  same PSG legitimately replicates across a titular's several tenants).
* `expires_at` nullable — constancias print no expiry; resolved via `fn_psg_validity_status()`
  with a per-tenant default window (`companys.metadata->>'psg_validity_months'`, default 12).

### `compliance_certificates` (Folio History) — append-only
* `certificate_type` (PGN_UPP_REGISTRATION / PGN_UPP_UPDATE / PGN_PSG_UPDATE).
* CHECK `num_nonnulls(production_unit_id, psg_license_id) = 1`.
* No UPDATE/DELETE: a re-issued constancia is a new row, never an edit.

### `compliance_documents` (File Custody) — append-only
* Polymorphic (`entity_type` + `entity_id`, no FK — integrity enforced at the write path).
* `storage_key` (external object, outside the web root), `sha256_hash` (integrity proof).
* Resolved only via an authenticated endpoint validating `id_company` against
  `user_companies`. **0 files archived as of 2026-07-29** — structure exists, nothing loaded.

### `livestock_census_snapshots` (Declared Census) — append-only
* Point-in-time declared headcount from a constancia. Reconciliation against
  `cattle_livestock` is deliberately **out of scope** (client decision): declared and
  biometric inventory diverge for legitimate reasons (unregistered births, capture lag).

### `herd_free_certificates` (Dictamen de Hato Libre)
* Scoped to the **production unit** (the whole herd is certified as a unit), one row per
  `disease` (TB / BR — issued and expire independently).
* Consulted by `sp_procesar_salida_ganado` (migration 024) as the exemption path for the
  60-day lot-test window. **0 certificates loaded as of 2026-07-29** — this is the single
  largest driver of the low movement-readiness figure (5/270 animals).

### `brand_registrations` (Fierro Marcador) — GLOBAL catalog, not tenant-scoped
* A registered branding iron is publicly filed with the state (SEDAFOP in Tabasco), and the
  client requires **consolidated financial reporting by brand across tenants** — the reason
  this catalog is deliberately global, unlike the tenant-scoped registry tables above.
* `owner_curp_enc`/`owner_curp_hash` — same encrypt-and-hash pattern as `livestock_producers`.
* Confirmed real state (2026-07-29): brand `R` (rancho brand, titular Pedro, state registry
  P01-27-009-01462) is fully documented; brand `aR` (Alejandro's own title) is registered
  with the state but its credential has not been supplied — row exists, marked incomplete.
* `fn_apply_birth_brand_inheritance()` resolves the brand on a `birth_events` row from
  either a resolved `dam_id` or a free-text `dam_fire_number` match, so capture from a field
  notebook does not require the dam to already be linked.

### `production_unit_paddocks` (Potreros)
* Scoped to a `production_unit_id`: "potrero 2" only means something inside its own UPP.
* `cattle_livestock.paddock_id` tracks current location only — no occupancy history yet
  (paddock rotation is a larger feature, out of scope for v1.9.0).

### `birth_events` (Parto)
* Mirrors the field-notebook shape exactly: `dam_ear_tag`/`dam_fire_number` as **free text**
  (deliberately not a hard FK — dams may lack a tag, and the client confirmed fire numbers
  can repeat by capture error), `calf_sex`, `calf_brand_id` (defaults via inheritance),
  `calf_id` **nullable** because the calf is born untagged and linked only later, once
  ear-tagged (notebooks show this as a separate event, sometimes weeks after birth).
* `dam_id` (nullable FK) is filled in once a human disambiguates the free-text reference
  against the herd — never inferred automatically on a duplicate fire number.
* Source for backfill: field notebooks (2023-2026) and `PARTOS_2020_LB.xlsx` (417 births,
  not yet loaded).

### `cattle_movement_rules` (DRAFT — NOT DEPLOYED)
* Global catalog of permitted UPP↔PSG movements. Every row ships with `is_confirmed = false`
  and nothing enforces it. Created in migration 020 but never executed in any environment:
  six operational questions remain open (individual animal vs. batch, cross-tenant movement,
  zone sanitary-status source, what happens when the destination doesn't use the system,
  PSG validity at movement date vs. capture date, atomic vs. destination-acknowledgement flow).
```

## 5. Añadir a "Views (BI Layer)"

```markdown
### `vw_upp_compliance_status` (20 columns)
Server-computed `update_status` (OK/WARNING/EXPIRED/UNKNOWN) from `last_update_at`, with
per-tenant thresholds via `companys.metadata` (defaults 300/365 days). Also exposes
`has_surface_inconsistency` and `active_head_in_system` (live count from `cattle_livestock`).

### `vw_psg_compliance_status` (16 columns)
`effective_expires_at` / `validity_status` resolved via `fn_psg_validity_status()`.

### `vw_livestock_movement_readiness`
Per-animal eligibility: `has_official_tag` + (`tb_herd_free` OR `tb_lot_test_valid`) +
(`br_herd_free` OR `br_lot_test_valid`) → `is_movable`. Does NOT evaluate zone sanitary
status, REEMO/CZM documents, or destination type — those remain unmodelled pending the
movement-rules definition.

### `vw_livestock_by_brand`
Head count and biomass by `brand_id` × tenant × production unit × category. Animals with
`brand_id IS NULL` are excluded on purpose — an unassigned brand is missing data, not a
fourth owner. **Currently empty**: 0 of 270 animals have a brand assigned.

### `vw_duplicate_fire_numbers`
Alert, not a constraint. Surfaces `numero_fuego` values repeated within the same tenant —
the client confirmed this can happen by capture error and must be reviewable, never rejected
outright.

### `vw_birth_events_summary`
Read model for the birth log; `calf_tagged` distinguishes calves already linked to a
`cattle_livestock` row from those still identified only by the birth record.

### `vw_cattle_livestock_std` / `vw_cattle_expenses_std` / `vw_historico_movimientos_std`
Transitional compatibility shims exposing both `tenant_id` and `id_company` side by side,
pending the eventual column rename once no consumer reads `tenant_id`.

⚠️ **Contract note (all views above, and any future one registered in `crud_models`):**
must expose `created_at` — the n8n gateway's default `getall` ordering depends on it and
its absence fails at runtime, not at deploy time (see CLAUDE.md, Contrato Meta-CRUD).
```
