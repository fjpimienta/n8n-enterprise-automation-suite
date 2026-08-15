# 🗄️ Database Schema & Baseline (v2)

**Historial de versiones documentado en este archivo:**
- Línea base (`v2`) — Cattle Management Subsystem original
- v1.9.0 (2026-07-27 a 2026-07-29) — Regulatory Registry Subsystem; corrección de
  `cattle_livestock` (identificación) y `sp_procesar_salida_ganado`
- v1.10.0 (2026-08-10 a 2026-08-14) — Movement Subsystem; Identifier History Subsystem;
  extensión de `compliance_certificates`

> ⚠️ **Nota de higiene de documentación (2026-08-14):** el `schema.sql` versionado en el
> repo **no refleja ninguna tabla ni columna de v1.10.0** (verificado: cero coincidencias
> para `cattle_identifier_history`, `requires_gbg_certificate`,
> `cattle_movement_event_health_certs`, `chk_normative_type_fixed_mapping`,
> `compliance_certificates_type_subject_check`). Regenerar con `pg_dump --schema-only`
> contra producción antes de usarlo como referencia de diagnóstico — mismo patrón de
> desactualización ya señalado en `CLAUDE.md`, regla 6, y van tres veces.

## 📌 Core Directives
* **RDBMS:** PostgreSQL
* **Security:** Tenant isolation via `tenant_id` (`companys.id_company`).
* **Primary Keys:** UUID v4 default for high-concurrency environments.

## 🏗️ Cattle Management Subsystem

### `cattle_livestock` (Core Entity)
Registry of biomass with embedded compliance rules.
* `id` (UUID, PK)
* `tenant_id` (INT, FK -> `companys`)
* `rfid_siniiga` (VARCHAR, UNIQUE) - Official SINIIGA ear tag. Format confirmed 2026-07-29:
  10 digits, EE + 4 + 4, where EE is the INEGI state code (07 Chiapas, 27 Tabasco).
  Validated by `fn_has_official_ear_tag()`. ⚠️ In practice this is the identifier that
  actually covers the herd: 262 of 270 animals (97%, verified in production 2026-07-29)
  carry no `electronic_rfid` at all. *(corregido en v1.9.0 — la premisa original decía lo
  contrario)*
* `electronic_rfid` (VARCHAR, UNIQUE) - Documented as the primary operational key (rumen
  bolus / subcutaneous microchip), and is what `sp_procesar_salida_ganado` keys on. In
  practice only 8 of 270 animals carry one. Pending client decision: whether to tag the
  full herd or shift the operational key to `rfid_siniiga`. *(corregido en v1.9.0)*
* `numero_fuego` (VARCHAR) - Physical brand/iron mark identifier, i.e. the traditional
  fire-branded number, distinct from `brand_id` (ownership brand, see below). Capture is
  NOT uniform across tenants: 100% present in tenant 5 (La Bendición), 0% in tenant 6
  (UPP 54). Do not assume presence when designing sort/search on this field. *(añadido en
  v1.9.0)*
* `brand_id` (UUID, FK -> `brand_registrations`, nullable) - Ownership brand. Independent
  of `production_unit_id`: an animal may stand in one holder's unit while belonging to the
  other holder. Inherited automatically from the dam via `fn_inherit_brand_from_mother`
  (trigger on INSERT/UPDATE of `mother_id`/`brand_id`); an explicit value always wins over
  inheritance. Populated for 0 of 270 animals as of 2026-07-29 — no source exists to infer
  it retroactively; requires a physical field pass. *(añadido en v1.9.0)*
* `mother_id` (UUID, FK -> `cattle_livestock` self-reference, nullable) - Dam. Field
  notebooks record every birth as "parió <dam tag> - <dam fire number> - <calf sex/brand>",
  so lineage exists on paper back to 2023 and is not yet loaded into the database. *(añadido
  en v1.9.0)*
* `paddock_id` (UUID, FK -> `production_unit_paddocks`, nullable) - Current paddock.
  Guarded by `fn_guard_livestock_paddock()`: a paddock belongs to exactly one production
  unit, and the trigger rejects assigning it to an animal standing in a different unit.
  *(añadido en v1.9.0)*
* `production_unit_id` (UUID, FK -> `production_units`, nullable) - Real FK that replaces
  the free-text `upp_origen` as the authoritative link to a UPP. Guarded by
  `fn_guard_livestock_production_unit()` (fail-closed against cross-tenant assignment).
  `upp_origen` is retained as a denormalized label, kept in sync via migration 023, but is
  no longer the source of truth. *(añadido en v1.9.0)*
* `business_model` (ENUM: CRIA, ENGORDA, REPRODUCCION)
* `category` (ENUM: VACA, TORO, NOVILLO, BECERRA, BECERRO, BUFALA, BUFALO, BUCERRO, BUCERRA, BORREGO, BORREGA)
* `current_status` (ENUM: ACTIVO, EN_TRANSITO, VENDIDO, BAJA_MORTANDAD, PREÑADA, VACÍA, DESARROLLO, RIESGO, FINALIZADO, CUARENTENA)
* `birth_date` (DATE)
* `current_weight_kg` (NUMERIC 10,2) - Auto-updated via trigger.
* `metadata` (JSONB) - Flexible attribute bag for vertical-specific data not worth normalizing.
* `species` (VARCHAR, Default: 'BOVINO')
* `upp_origen` (VARCHAR) - Origin ranch / cost center (e.g. "UPP La Bendición"). Automatically set to `NULL` on exit (`VENDIDO`) by `sp_procesar_salida_ganado`.
* `tb_test_date` / `br_test_date` (DATE) - Compliance metrics. Regulatory validity window: 60 days.

### `cattle_weight_logs` (Telemetry)
* `id` (UUID, PK)
* `livestock_id` (UUID, FK -> `cattle_livestock`, `ON DELETE CASCADE`)
* `weight_kg` (NUMERIC 10,2) - Triggers `update_current_weight()` on insert.
* `log_date` (TIMESTAMP)
* `source_device` (VARCHAR) - Identifies the originating scale/RFID reader (IoT ingestion).

### `cattle_health_logs` (Sanitary Events)
* `id` (UUID, PK)
* `livestock_id` (UUID, FK -> `cattle_livestock`, `ON DELETE CASCADE`)
* `event_type` (VARCHAR) - e.g. `PALPACION`, vaccination, diagnosis.
* `description` (TEXT)
* `medicines_json` (JSONB) - Non-relational dosage/treatment payload.
* `event_date` (TIMESTAMP)
* Immutable by design: exposed via Meta-CRUD as `SELECT, INSERT, GETALL` only (no `UPDATE`/`DELETE`, for audit integrity).

### `cattle_expenses` (Opex Tracking)
* `id` (UUID, PK)
* `tenant_id` (INT, FK -> `companys`)
* `livestock_id` (UUID, FK -> `cattle_livestock`, `ON DELETE SET NULL`)
* `health_event_id` (UUID, FK -> `cattle_health_logs`, `ON DELETE SET NULL`) - Optional link to the sanitary event that generated the cost.
* `expense_date` (DATE), `category` (VARCHAR), `amount` (NUMERIC 12,2), `quantity` (NUMERIC 10,2), `unit_measure` (VARCHAR), `description` (TEXT), `receipt_url` (TEXT)

### `cattle_task_evidence` (Field Audit Trail)
* `id` (UUID, PK)
* `livestock_id` (UUID, FK -> `cattle_livestock`, `ON DELETE SET NULL`)
* `task_name` (VARCHAR), `evidence_url` (TEXT)
* `status` (ENUM: PENDIENTE, COMPLETADO, RECHAZADO)
* `uploaded_by` (VARCHAR)

### `cattle_tenants` (Ranch / Organization Catalog)
* `id` (UUID, PK)
* `tax_id` (VARCHAR), `name` (VARCHAR)
* `org_type` (ENUM: GANADERO, UNION, GOBIERNO)
* Reserved for `ADMIN`-only writes; `SELECT` open to `ADMIN, EDITOR`.
* ⚠️ **DEPRECATED (migration 010, 2026-07-27).** *(añadido en v1.9.0)* Single row, generic RFC
  (`XAXX010101000`), zero foreign keys referencing it in the entire schema. Not dropped
  (production-safety guardrail): retained read-only. Meta-CRUD model downgraded to
  `{SELECT,GETONE,GETALL}`, `allowed_roles_insert/update/delete = NONE`. `org_type` was
  migrated to `companys.org_type` (CHECK: GANADERO/UNION/GOBIERNO, nullable for
  non-livestock tenants).

### `historico_movimientos` (Movement Audit Log)
* `id` (UUID, PK)
* `livestock_id` (UUID, FK -> `cattle_livestock`)
* `electronic_rfid` (VARCHAR)
* `tenant_id` (INT)
* `tipo_movimiento` (ENUM: VENTA, BAJA_MORTANDAD, TRASLADO)
* `upp_origen_anterior` (VARCHAR) - Snapshot of the ranch of origin at the moment of the movement.
* `fecha_registro` (TIMESTAMP)
* Write-only side effect of `sp_procesar_salida_ganado` (`VENTA` case); not exposed as a direct Meta-CRUD model.

### `agriculture_telemetry` (Agriculture Module - Hybrid Table)
* `id` (UUID, PK)
* `tenant_id` (INT, FK -> `companys`)
* `zone_name` (VARCHAR), `activity_type` (VARCHAR)
* `execution_date` (TIMESTAMP)
* `telemetry_data` (JSONB, GIN-indexed) - Drone/sensor payloads without a rigid schema.
* Not yet registered in `crud_models`; reserved for the Agriculture domain rollout.

---

## 🏛️ Regulatory Registry Subsystem (SENASICA-SINIIGA)

*Añadido en v1.9.0.* Introduced to model the client's real padrón: N production units per tenant,
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

### `compliance_certificates` (Folio History) — append-only, extended migrations 044/046

*Extendido en v1.10.0 — reemplaza la entrada original de v1.9.0.*

* `certificate_type` — 8 values total: the original 3 unit-registration types
  (`PGN_UPP_REGISTRATION`/`PGN_UPP_UPDATE`/`PGN_PSG_UPDATE`) plus 5 movement-document types
  added in migration 044: `REEMO_TRANSIT_GUIDE`, `CZM_MOVEMENT_CERTIFICATE`,
  `GBG_TREATMENT_CERTIFICATE`, `STATE_INTRODUCTION_PERMIT`, `OWNERSHIP_TRANSFER_LETTER`
  (cesión de derechos — used for same-owner interstate UPP-to-UPP movements per a March 2026
  SCJN ruling, Controversia Constitucional 216/2025, that removed some state-level movement
  *permit* requirements but left property/possession documentation requirements intact; that
  ruling's general applicability beyond the Nayarit case it addressed is a legal question
  outside this schema's scope — the client independently confirmed the Tabasco/Chiapas state
  introduction permit is still required in current practice regardless).
* `movement_event_id` (UUID, FK -> `cattle_movement_events`, nullable, migration 044) — links
  a certificate to the specific movement it supports.
* `expires_at` (TIMESTAMPTZ, nullable, migration 044) — every movement-document type observed
  in real examples carries a short validity window, typically 5 days from issuance.
* **Subject constraints, corrected in migration 046** (the original migration-044 rollout had
  a real gap, not merely an unenforced one):
  * `compliance_certificates_single_subject_check`: widened from
    `num_nonnulls(production_unit_id, psg_license_id) = 1` to
    `num_nonnulls(production_unit_id, psg_license_id, movement_event_id) = 1`. Before this
    fix, it was **impossible** to insert any movement-document type at all without also
    forcing an unrelated `production_unit_id`/`psg_license_id` — a blocking bug present from
    044 through 046, not caught until the follow-up review.
  * `compliance_certificates_type_subject_check` (new, 046): ties each `certificate_type` to
    its correct subject — the 3 `PGN_*` types must use `production_unit_id`/`psg_license_id`
    (never `movement_event_id`); the 5 movement-document types must use `movement_event_id`
    exclusively.
* No UPDATE/DELETE: a re-issued constancia is a new row, never an edit.

### `compliance_documents` (File Custody) — append-only
* Polymorphic (`entity_type` + `entity_id`, no FK — integrity enforced at the write path).
* `storage_key` (external object, outside the web root), `sha256_hash` (integrity proof).
* Resolved only via an authenticated endpoint validating `id_company` against
  `user_companies`. **0 files archived as of 2026-07-29** — structure exists, nothing loaded.
* El servicio de almacenamiento que respalda esta tabla (`upload-file`) se endureció con
  autenticación JWT/`INTERNAL_SECRET` en v1.10.0 — ver `ARCHITECTURE.md`, sección "File
  Storage Security", para el detalle. Sin cambios de esquema en esta tabla por ese trabajo.

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
* **Registered in `crud_models` as of migration 045** *(añadido en v1.10.0)* (existed in
  schema since migration 024 but was never exposed via Meta-CRUD before — the frontend could
  not read or write it until this). `is_active` toggling restricted to `ADMIN` only (not
  `EDITOR`), since deactivating a sanitary certificate is a sensitive action.
* Linked to specific movements via the bridge table `cattle_movement_event_health_certs`
  (see Movement Subsystem below), not a direct FK — the same certificate legitimately
  supports multiple movements during its validity window. *(añadido en v1.10.0)*

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

### `cattle_movement_rules`
* **Ver la sección "Movement Subsystem" más abajo.** *(nota añadida en v1.10.0 — esta tabla
  vivía documentada aquí como borrador sin desplegar; la entrada completa y actualizada
  ahora vive junto al resto del subsistema de movimientos para no duplicar contenido.)*

---

## 🚚 Movement Subsystem (SENASICA-REEMO, migrations 020, 039–046, 048–049)

*Añadido en v1.10.0.* Models real livestock movements — UPP↔UPP, UPP↔PSG, PSG↔PSG — and the compliance-document
chain that supports an interstate movement. Complements the Regulatory Registry Subsystem
above; a movement changes *where* an animal is, the registry subsystem records *who* is
certified to hold it there.

### `cattle_movement_rules` (Policy Catalog) — restructured, migration 042
* `id` (UUID, PK), no `id_company` (global policy, applies to all tenants equally).
* `origin_type`/`destination_type` (`UPP`/`PSG`, destination also allows `RASTRO`/
  `EXPORTACION`), `is_interstate` (BOOLEAN) — together form the natural key
  (`UNIQUE (origin_type, destination_type, is_interstate)`), 16 rows total.
* `is_allowed`, `requires_valid_psg`, `requires_health_tests`, `requires_gbg_certificate`
  (renamed from `requires_oirsa_certificate`, migration 044), `requires_introduction_permit`,
  `requires_destination_ack`, `is_confirmed` (BOOLEAN each).
* `is_confirmed = false` is the fail-closed default; any future enforcement layer must treat
  it as "rule unavailable", never as an implicit allow (original design intent, migration
  020, unchanged through every subsequent revision).
* Current data: `PSG→UPP` (both interstate variants) fully confirmed and disallowed. 12 other
  `UPP`/`PSG` combination rows have real values stored but `is_confirmed = false`, pending
  client sign-off on `requires_destination_ack` specifically. 4 `RASTRO`/`EXPORTACION` rows
  remain draft in full (values and confirmation both unconfirmed).
* Original draft (migration 020, "DRAFT — NOT DEPLOYED") shipped with six open operational
  questions. Two are now closed by design: individual animal vs. batch (see
  `cattle_movement_event_animals` below — same mechanism handles both) and PSG validity
  semantics (see `requires_valid_psg` note below). Four remain genuinely open, tracked in
  `INVENTARIO_COMPLETITUD.md`.
* **`requires_valid_psg` vs. `requires_health_tests` — documented, not redundant** (migration
  048, `COMMENT ON COLUMN` only, no data change): `requires_valid_psg` means the PSG
  facility's *own operating license* must be current
  (`psg_facilities.psg_license_id -> psg_licenses.expires_at`); `requires_health_tests` means
  the *animal's* TB/BR status must be current. Both were set identically for every confirmed
  row in migration 042 under the working assumption they were the same concept — now known to
  be two different checks that happen to coincide on today's confirmed rows, not verified
  independently against real documents yet.
* **`requires_gbg_certificate`**: whether a GBG (Gusano Barrenador del Ganado)
  treatment/inspection constancia is required — a DINESA-emergency-measure prerequisite for
  CZM issuance (DOF, Dec 2, 2025; Chiapas and Tabasco are SENASICA-listed maximum-risk
  zones), confirmed applicable to interstate movements. Independently web-verified during
  design, not solely client-asserted.

### `psg_facilities` (PSG as a physical location) — migration 039
* `id` (UUID, PK), `id_company` (INT, tenant-scoped, unlike the policy catalog above)
* `psg_license_id` (UUID, FK -> `psg_licenses`, nullable) — links the physical facility to
  its operating license; the two are related but distinct concepts.
* `name`, `location`, `notes`, `created_at`.

### `external_destinations` (Third-party / non-tenant destinations) — migration 039, extended 041/049
* `id` (UUID, PK), `id_company` (INT)
* `destination_type` (`THIRD_PARTY_RANCH`/`BUYER`/`SLAUGHTERHOUSE`/`EXPORT`/`OTHER`) — the
  *commercial* classification.
* `normative_type` (`UPP`/`PSG`/`RASTRO`/`EXPORTACION`, migration 041, `NOT NULL`) — the
  *compliance* classification, set explicitly by whoever registers the destination. Bridges
  to `cattle_movement_rules.destination_type` without embedding business logic in a trigger.
* `chk_normative_type_fixed_mapping` (migration 049): enforces the three unambiguous pairs
  (`SLAUGHTERHOUSE→RASTRO`, `EXPORT→EXPORTACION`, `THIRD_PARTY_RANCH→UPP`); `BUYER`/`OTHER`
  are deliberately left free to take any `normative_type` value, since a buyer's real
  operation may legally be any of the four.

### `cattle_movement_events` (Movement Event Log) — migration 039, extended 043
* `id` (UUID, PK), `id_company` (INT)
* **Origin** (exactly one, `chk_origin_exclusive`, migration 043): `production_unit_origin_id`
  (nullable since 043) or `psg_facility_origin_id` (added 043).
* **Destination** (exactly one, `chk_destination_exclusive`, migration 039):
  `production_unit_destination_id`, `psg_facility_destination_id`, or
  `external_destination_id`.
* `rule_id` (UUID, FK -> `cattle_movement_rules`, nullable) — stored for future enforcement,
  not yet consulted by any validation logic while `is_confirmed = false` dominates the table.
* `reemo_folio`, `movement_date` (authoritative date for PSG-validity/health-test checks —
  distinct from `captured_at`, which reflects when the WhatsApp/system entry was actually
  made and may lag `movement_date` by days).
* `status` (`COMPLETED`/`PENDING_ACK`/`ACKNOWLEDGED`, default `COMPLETED`) — defaults to
  today's real single-party workflow (photo + REEMO folio, no destination confirmation in
  the system); the other two values are reserved for a possible future two-party
  acknowledgement flow, activatable without another migration.
* Fail-closed tenant isolation via `trg_check_movement_event_tenant`
  (`trg_validate_movement_event_tenant()`), extended in migration 043 to validate whichever
  origin type (`production_unit` or `psg_facility`) is actually set, mirroring the existing
  three-way destination logic.

### `cattle_movement_event_animals` (Movement Detail — Bridge) — migration 039
* `id` (UUID, PK), `event_id` (FK -> `cattle_movement_events`, `ON DELETE CASCADE`),
  `cattle_livestock_id` (FK -> `cattle_livestock`, authoritative reference)
* `fire_number_snapshot` (TEXT) — non-authoritative copy of `numero_fuego` at the time of the
  movement, for field lookups only. Never a join key: fire numbers can repeat by capture
  error (see Regulatory Registry Subsystem, `vw_duplicate_fire_numbers`).
* `UNIQUE (event_id, cattle_livestock_id)` — same mechanism handles a single-animal movement
  or a full batch; batch size is just row count.

### `cattle_movement_event_health_certs` (TB/BR citations — Bridge) — migration 045
* `id` (UUID, PK), `event_id` (FK -> `cattle_movement_events`, `ON DELETE CASCADE`),
  `herd_free_certificate_id` (FK -> `herd_free_certificates`)
* `UNIQUE (event_id, herd_free_certificate_id)`. Many-to-many by design: a single valid
  TB/BR certificate can back several movements during its validity window (confirmed by real
  CZM documents), unlike the one-time-use documents in `compliance_certificates` above.

---

## 🏷️ Identifier History Subsystem (migration 047)

*Añadido en v1.10.0.*

### `cattle_identifier_history`
* `id` (UUID, PK), `cattle_livestock_id` (FK -> `cattle_livestock`)
* `identifier_type` (`FUEGO`/`SINIIGA`/`CHIP`) — generic dimension covering all three
  identifiers on `cattle_livestock` (`numero_fuego`, `rfid_siniiga`, `electronic_rfid`); one
  table instead of three, since the query pattern ("what value did this animal have
  before/after a date") is identical across all three.
* `previous_value`/`new_value` (TEXT, both nullable — `previous_value` is `NULL` only when an
  identifier goes from unset to set for the first time via `UPDATE`, not `INSERT`)
* `reason` (`LOST`/`REPLACED`/`CAPTURE_CORRECTION`/`FOUND_LOOSE_REASSIGNED`, `NOT NULL`,
  defaults to `CAPTURE_CORRECTION` when the triggering `UPDATE` didn't specify a reason
  explicitly)
* `changed_by`, `notes`, `changed_at`

**Populated automatically**, never by application code directly, via
`trg_cattle_livestock_identifier_history` (`AFTER UPDATE ON cattle_livestock`,
`trg_log_identifier_changes()`). Fires on any change to any of the three identifier columns;
logs one row per changed column when a single `UPDATE` touches more than one. Reads two
optional session-local Postgres settings to enrich the log without requiring every caller to
change:

```sql
SET LOCAL app.identifier_change_reason = 'FOUND_LOOSE_REASSIGNED';
SET LOCAL app.identifier_change_user = 'jperez';
UPDATE cattle_livestock SET rfid_siniiga = '...' WHERE id = '...';
```

Neither `SET LOCAL` is required — both fall back to `NULL`/`CAPTURE_CORRECTION` if omitted,
so every existing load script keeps working unmodified. Verified against a real animal
(`ccc04259-e7a9-4b89-8a87-ef994df162af`, tenant 6) in both environments: a `NULL→NULL` no-op
update on `numero_fuego` correctly produced zero history rows; a real `rfid_siniiga` change
correctly produced one row with the `CAPTURE_CORRECTION` default and no `changed_by`.

---

## 📊 Views (BI Layer)

### `vw_cattle_kpi`
* **Source:** `cattle_livestock` `LEFT JOIN` `companys`.
* **Computed columns:**
  * `tenant_name` (from `companys.company_name`)
  * `adg_lifetime_kg` - `current_weight_kg` / age in days since `birth_date`
  * `last_palpation_result` / `current_gestation_days` - latest `PALPACION` entry pulled from `cattle_health_logs.medicines_json`
  * Also passes through `species`, `upp_origen`, `tb_test_date`, `br_test_date`.
* ⚠️ **Column order constraint:** `CREATE OR REPLACE VIEW` requires existing columns to keep their name/position; new columns can only be appended at the end (see migration `004_vw_cattle_kpi_add_salida_fields.sql`).

### `vw_upp_compliance_status` (20 columns)
*Añadido en v1.9.0.* Server-computed `update_status` (OK/WARNING/EXPIRED/UNKNOWN) from `last_update_at`, with
per-tenant thresholds via `companys.metadata` (defaults 300/365 days). Also exposes
`has_surface_inconsistency` and `active_head_in_system` (live count from `cattle_livestock`).

### `vw_psg_compliance_status` (16 columns)
*Añadido en v1.9.0.* `effective_expires_at` / `validity_status` resolved via `fn_psg_validity_status()`.

### `vw_livestock_movement_readiness`
*Añadido en v1.9.0.* Per-animal eligibility: `has_official_tag` + (`tb_herd_free` OR `tb_lot_test_valid`) +
(`br_herd_free` OR `br_lot_test_valid`) → `is_movable`. Does NOT evaluate zone sanitary
status, REEMO/CZM documents, or destination type — those remain unmodelled pending the
movement-rules definition (ver "Movement Subsystem" arriba para el estado actual de esas
reglas).

### `vw_livestock_by_brand`
*Añadido en v1.9.0.* Head count and biomass by `brand_id` × tenant × production unit × category. Animals with
`brand_id IS NULL` are excluded on purpose — an unassigned brand is missing data, not a
fourth owner. **Currently empty**: 0 of 270 animals have a brand assigned.

### `vw_duplicate_fire_numbers`
*Añadido en v1.9.0.* Alert, not a constraint. Surfaces `numero_fuego` values repeated within the same tenant —
the client confirmed this can happen by capture error and must be reviewable, never rejected
outright.

### `vw_birth_events_summary`
*Añadido en v1.9.0.* Read model for the birth log; `calf_tagged` distinguishes calves already linked to a
`cattle_livestock` row from those still identified only by the birth record.

### `vw_cattle_livestock_std` / `vw_cattle_expenses_std` / `vw_historico_movimientos_std`
*Añadido en v1.9.0.* Transitional compatibility shims exposing both `tenant_id` and `id_company` side by side,
pending the eventual column rename once no consumer reads `tenant_id`.

⚠️ **Contract note (all views above, and any future one registered in `crud_models`):**
must expose `created_at` — the n8n gateway's default `getall` ordering depends on it and
its absence fails at runtime, not at deploy time (see CLAUDE.md, Contrato Meta-CRUD).

## ⚙️ Stored Procedures & Triggers (Business Logic Layer)

### `execute_metacrud_write`
* **Purpose:** Centralized Zero-Compute Client mutation gateway.
* **Mechanism:** Validates against `crud_models` whitelist before executing dynamic INSERT/UPDATE.
* ⚠️ Ver `ARCHITECTURE.md`, sección "Hallazgos confirmados sobre `execute_metacrud_write`"
  (v1.9.0) — no es la ruta real de escritura del gateway; incompatible con PK UUID.

### `sp_procesar_salida_ganado(p_electronic_rfid)`

*Reemplazado en v1.9.0 — mecanismo actualizado dos veces desde el registro original.*

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

### `update_current_weight()`
* **Purpose:** Ensures `cattle_livestock.current_weight_kg` is an exact reflection of the latest `cattle_weight_logs` entry without client-side computation.
* **Mechanism:** `AFTER INSERT` trigger on `cattle_weight_logs`.

### `trg_validate_movement_event_tenant()` / `trg_check_movement_event_tenant`
*Añadido en v1.10.0.*
* **Purpose:** Fail-closed multi-tenant isolation for `cattle_movement_events`, since
  `n8n_user` is Postgres superuser and no RLS is in place.
* **Mechanism:** `BEFORE INSERT OR UPDATE` trigger. Resolves `id_company` for whichever
  origin (`production_unit` or `psg_facility`, migration 043) and whichever destination
  (`production_unit`, `psg_facility`, or `external_destination`, migration 039) is actually
  set on the row, and rejects if any of them belongs to a different tenant than
  `NEW.id_company`. Verified: cross-tenant insert rejected with an explicit error naming both
  tenant IDs; same-tenant insert succeeds.

### `trg_validate_movement_animal_tenant()` / `trg_check_movement_animal_tenant`
*Añadido en v1.10.0.*
* **Purpose:** Same fail-closed guarantee, one level down — an animal added to
  `cattle_movement_event_animals` must belong to the same tenant as its parent event.
* **Mechanism:** `BEFORE INSERT OR UPDATE` trigger, resolves the animal's tenant via
  `cattle_livestock -> production_units.id_company` and compares against the event's
  `id_company`.

### `trg_log_identifier_changes()` / `trg_cattle_livestock_identifier_history`
*Añadido en v1.10.0.*
* **Purpose:** Automatic, non-optional audit trail for the three animal identifiers.
* **Mechanism:** `AFTER UPDATE ON cattle_livestock`, `FOR EACH ROW`. Compares `OLD`/`NEW` for
  `numero_fuego`, `rfid_siniiga`, `electronic_rfid` (`IS DISTINCT FROM`, so `NULL→NULL` is
  correctly a no-op); inserts one `cattle_identifier_history` row per changed column. Reads
  `app.identifier_change_reason`/`app.identifier_change_user` (optional session-local
  settings) via `current_setting(..., true)`, defaulting to `CAPTURE_CORRECTION`/`NULL`.