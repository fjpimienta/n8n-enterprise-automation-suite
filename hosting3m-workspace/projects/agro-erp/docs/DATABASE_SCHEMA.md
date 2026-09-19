# 🗄️ Database Schema & Baseline (v2)

**Historial de versiones documentado en este archivo:**
- Línea base (`v2`) — Cattle Management Subsystem original
- v1.9.0 (2026-07-27 a 2026-07-29) — Regulatory Registry Subsystem; corrección de
  `cattle_livestock` (identificación) y `sp_procesar_salida_ganado`
- v1.10.0 (2026-08-10 a 2026-08-14) — Movement Subsystem; Identifier History Subsystem;
  extensión de `compliance_certificates`
- v1.11.0 (2026-07-23 a 2026-09-11) — Global Parametrization Catalogs; Mortality & Async
  Authorization Subsystem; documentación retroactiva de `weaning_events` y comportamiento
  completo de `sp_register_birth_event` (ya existían en producción, sin documentar); corrección
  de `cattle_livestock.category` (no es un ENUM real de Postgres)
- v1.11.1 (2026-09-16) — *[entrada retroactiva, nunca agregada a este archivo]* Herramienta
  MCP `register_birth_event` validada en producción — ver `ARCHITECTURE.md` para el detalle
  completo de esta versión.
- v1.12.0 (2026-09-18 a 2026-09-19) — Reporte de mortandad/venta para animales sin
  identificador físico (`find_calf_by_dam`, `livestock_id` agregado a
  `sp_solicitar_autorizacion` / `sp_procesar_baja_mortandad` / `sp_procesar_salida_ganado` /
  `sp_resolver_autorizacion`); documentación retroactiva del overload de 4 parámetros de
  `sp_procesar_salida_ganado` (existía en producción desde v1.9.0, nunca documentado);
  corrección de `sp_solicitar_autorizacion` en este archivo (la firma documentada estaba
  desactualizada — ya tenía `livestock_id` en producción antes de esta versión); hallazgo y
  corrección de un caso real de incumplimiento de aislamiento multi-tenant en el Agente IA

> ⚠️ **Nota de higiene de documentación (2026-08-14):** el `schema.sql` versionado en el
> repo **no refleja ninguna tabla ni columna de v1.10.0** (verificado: cero coincidencias
> para `cattle_identifier_history`, `requires_gbg_certificate`,
> `cattle_movement_event_health_certs`, `chk_normative_type_fixed_mapping`,
> `compliance_certificates_type_subject_check`). Regenerar con `pg_dump --schema-only`
> contra producción antes de usarlo como referencia de diagnóstico — mismo patrón de
> desactualización ya señalado en `CLAUDE.md`, regla 7, y van tres veces.

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
  so lineage exists on paper back to 2023 and is not yet loaded into the database. Populated
  automatically going forward by `sp_register_birth_event` when the dam is resolved. Also the
  reference used by `sp_procesar_baja_mortandad` (v1.11.0) to find and flag dependent calves
  when a dam dies. *(añadido en v1.9.0, uso extendido en v1.11.0)*
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
* `category` (VARCHAR + CHECK constraint — **no es un ENUM real de Postgres**, confirmado
  vía `pg_type` el 2026-09-09, corrigiendo la documentación previa que lo listaba como
  ENUM): VACA, TORO, NOVILLO, NOVILLONA, BECERRA, BECERRO, BECERRO_TORETE *(añadido en
  v1.11.0, ver más abajo)*, BUFALA, BUFALO, BUCERRO, BUCERRA, BORREGO, BORREGA, CABALLO,
  YEGUA, POTRO, POTRANCA, CABALLO_CASTRADO. Alterable vía
  `ALTER TABLE ... DROP/ADD CONSTRAINT` (no `ALTER TYPE`, precisamente porque no es un
  ENUM). El CHECK es global a toda la plataforma multi-tenant — incluye categorías equinas
  no usadas por este cliente, compartidas con otro tenant de la suite.
* `current_status` (ENUM: ACTIVO, EN_TRANSITO, VENDIDO, BAJA_MORTANDAD, PREÑADA, VACÍA, DESARROLLO, RIESGO, FINALIZADO, CUARENTENA)
* `birth_date` (DATE)
* `current_weight_kg` (NUMERIC 10,2) - Auto-updated via trigger.
* `metadata` (JSONB) - Flexible attribute bag for vertical-specific data not worth normalizing.
* `species` (VARCHAR, Default: 'BOVINO')
* `upp_origen` (VARCHAR) - Origin ranch / cost center (e.g. "UPP La Bendición"). Automatically set to `NULL` on exit (`VENDIDO`) by `sp_procesar_salida_ganado`. ⚠️ **`sp_procesar_baja_mortandad` (v1.11.0) deliberadamente NO limpia este campo** — a diferencia de venta, se conserva para permitir análisis de mortalidad por lote/UPP.
* `tb_test_date` / `br_test_date` (DATE) - Compliance metrics. Regulatory validity window: 60 days.

### `cattle_weight_logs` (Telemetry)
* `id` (UUID, PK)
* `livestock_id` (UUID, FK -> `cattle_livestock`, `ON DELETE CASCADE`)
* `weight_kg` (NUMERIC 10,2) - Triggers `update_current_weight()` on insert.
* `log_date` (TIMESTAMP)
* `source_device` (VARCHAR) - Identifies the originating scale/RFID reader (IoT ingestion). Values observed in practice include `'AI_Agent'`, `'BIRTH_EVENT'` and `'WEANING_EVENT'` (both *añadido en v1.11.0* documentation, see Birth/Weaning Subsystems below) in addition to physical device identifiers.

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
* `notes` (TEXT) — *(añadido en v1.11.0)* usado por `sp_procesar_baja_mortandad` para
  resumir causa y descripción; el detalle rico vive en `mortality_events` (ver más abajo).
* Write-only side effect of `sp_procesar_salida_ganado` (`VENTA` case) y de
  `sp_procesar_baja_mortandad` (`BAJA_MORTANDAD` case, *añadido en v1.11.0*); not exposed as
  a direct Meta-CRUD model.

### `agriculture_telemetry` (Agriculture Module - Hybrid Table)
* `id` (UUID, PK)
* `tenant_id` (INT, FK -> `companys`)
* `zone_name` (VARCHAR), `activity_type` (VARCHAR)
* `execution_date` (TIMESTAMP)
* `telemetry_data` (JSONB, GIN-indexed) - Drone/sensor payloads without a rigid schema.
* Not yet registered in `crud_models`; reserved for the Agriculture domain rollout.

---

## 🧬 Global Parametrization Catalogs (v1.11.0)

*Añadido 2026-07-23 en adelante.* Catálogos globales (sin `tenant_id`) de estándares
zootécnicos, poblados progresivamente con datos validados directamente con el cliente vía
un documento de validación formal.

**Principio rector, aplica a todo el subsistema:** la edad es un disparador de revisión,
nunca el criterio determinante de una transición de categoría por sí sola — el sistema debe
cruzar edad + peso real antes de promover un animal, nunca promover solo por edad.

### `cattle_breed_catalog`
* `id` (UUID, PK), `especie` (VARCHAR, CHECK: BOVINO/BUFALO/BORREGO)
* `raza_grupo`/`raza_variante` (VARCHAR, `raza_variante` nullable — no todas las razas
  tienen subdivisión). `UNIQUE (especie, raza_grupo, raza_variante)` +
  `UNIQUE (especie, raza_grupo) WHERE raza_variante IS NULL`.
* `peso_adulto_hembra_kg`/`peso_adulto_macho_kg` (NUMERIC, CHECK > 0)
* `pct_peso_primer_servicio` (NUMERIC, default 65.00 — ajustado a 70.00 tras validación
  real del cliente)
* `edad_min_pubertad_meses` (NUMERIC, nullable) — **orientativo, nunca determinante por sí
  solo**.
* `dias_gestacion_promedio` (INTEGER)
* `created_at` (TIMESTAMP)
* ⚠️ **Procedencia de datos mixta, sin columna que lo distinga todavía:** las filas
  `CEBU/Brahman Rojo`, `CEBU/Nelore`, `DROUGHTMASTER/Puro`, `DROUGHTMASTER/Cruza` fueron
  primero pobladas con valores de captura preliminar (lista recuperada de una imagen,
  2026-08-11, pesos de captura aleatoria) y **corregidas** el 2026-09 con los valores del
  documento de validación formal firmado por el cliente (rangos de peso → punto medio, %
  primer servicio, edad). La fila `Otras / Sin especificar` es un fallback explícito para
  razas no listadas. No existe columna `fuente_dato`/`confianza` para distinguir
  programáticamente cuáles filas están validadas y cuáles no — deuda técnica abierta, ver
  `CLAUDE.md`.

### `cattle_lifestage_catalog`
* `id` (UUID, PK), `especie` (VARCHAR, CHECK: BOVINO/BUFALO/BORREGO/EQUIDO)
* `categoria_origen`/`categoria_destino` (VARCHAR, CHECK contra la misma lista de valores
  válidos de `cattle_livestock.category` — duplicado intencional del CHECK, no una FK, ya
  que `category` no es un tipo enumerado real referenciable)
* `edad_min_meses` (NUMERIC, CHECK > 0) — mínimo orientativo de revisión, no un disparador
  automático de promoción.
* `requiere_validacion_peso` (BOOLEAN, default `true`) — si `true`, la transición real
  además requiere que el peso del animal alcance `pct_peso_primer_servicio` de
  `cattle_breed_catalog` para su raza. `Becerra→Novillona` y `Becerro→Novillo` son `false`
  (dependen solo de destete); `Novillona→Vaca` y `BecerroTorete→Toro` son `true`.
* `notas` (TEXT, nullable), `created_at` (TIMESTAMP)
* `UNIQUE (especie, categoria_origen, categoria_destino)`,
  `CHECK (categoria_origen <> categoria_destino)`.
* **Rama macho corregida (2026-09):** la transición original `NOVILLO → TORO` era
  biológicamente incorrecta — un Novillo (macho castrado, destinado a engorda) nunca se
  convierte en reproductor. Eliminada y reemplazada por dos filas: `BECERRO →
  BECERRO_TORETE` (designación del ganadero en destete, no depende de peso) y
  `BECERRO_TORETE → TORO` (edad placeholder 16 meses, ⚠️ pendiente confirmación específica
  para machos — ver `CLAUDE.md`, deuda técnica).
* Valores confirmados con el cliente (especie BOVINO; Búfalo/Borrego quedan sin filas
  todavía — este cliente solo maneja Bovino en la práctica): destete 5 meses, etapa
  reproductiva (femenina) 16 meses.

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
* Ver la sección "Birth Subsystem" más abajo (*añadido en v1.11.0*) para el comportamiento
  completo de `sp_register_birth_event`, previamente indocumentado.

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

## ⚰️ Mortality & Async Authorization Subsystem (v1.11.0 – v1.12.0)

*Añadido 2026-09.* Ver `ARCHITECTURE.md`, sección "Async Authorization Subsystem", para las
decisiones de diseño completas (el "por qué"). Esta sección cubre el DDL.

### `mortality_events` (detalle rico, no forzado append-only por trigger — convención)
* `id` (UUID, PK), `id_company` (INT, FK -> `companys`)
* `livestock_id` (UUID, FK -> `cattle_livestock`, `ON DELETE CASCADE`)
* `death_date` (DATE, default `CURRENT_DATE`)
* `causa_mortandad` (VARCHAR, CHECK: ENFERMEDAD/ACCIDENTE/DEPREDACIÓN/DESCONOCIDA/NATURAL)
* `descripcion` (TEXT, nullable)
* `reported_by_email`/`authorized_by_email` (VARCHAR, ambos NOT NULL — deliberadamente
  distintos: quien reporta el evento no es necesariamente quien autoriza la baja)
* `created_at`

### `pending_authorizations` (genérica, reutilizable por tipo de evento)
* `id` (UUID, PK), `id_company` (INT, FK -> `companys`)
* `livestock_id` (UUID, FK -> `cattle_livestock`, `ON DELETE CASCADE`)
* `tipo_evento` (VARCHAR, CHECK: BAJA_MORTANDAD/VENTA)
* `payload` (JSONB, default `{}`) — parámetros exactos que necesita el SP real al aprobar;
  deliberadamente flexible en vez de columnas fijas por tipo de evento, dado que
  mortandad y venta requieren datos distintos.
* `solicitado_por_email` (VARCHAR NOT NULL), `fecha_solicitud` (TIMESTAMP, default now())
* `estado` (VARCHAR, CHECK: PENDIENTE/APROBADO/RECHAZADO/EXPIRADO, default PENDIENTE)
* `resuelto_por_email`/`fecha_resolucion`/`notas_resolucion` (nullable, poblados al resolver)
* `notified_at` (TIMESTAMP, nullable) — evita reenviar el correo de notificación en cada
  ciclo del Cron de sondeo (cada 5 min).
* No hay `UNIQUE` a nivel de constraint sobre `(livestock_id, tipo_evento, estado)`, pero
  `sp_solicitar_autorizacion` reutiliza una solicitud `PENDIENTE` existente del mismo
  animal+tipo en vez de duplicar, a nivel de lógica de aplicación.

### `sp_procesar_baja_mortandad(p_electronic_rfid, p_rfid_siniiga, p_numero_fuego, p_tenant_id, p_causa_mortandad, p_fecha_evento, p_descripcion, p_reportado_por_email, p_autorizado_por_email, p_livestock_id)`
* Mismo patrón de desambiguación multi-identificador que `sp_procesar_salida_ganado`
  (acepta `electronic_rfid`/`rfid_siniiga`/`numero_fuego`, `FOR UPDATE`, rechaza ambigüedad
  con `ERRCODE P0004`, error duro si no hay match con `P0002`).
* **`p_livestock_id uuid DEFAULT NULL`** *(añadido en v1.12.0, 10º parámetro, no rompe
  llamadas existentes)*: cuando viene informado, resuelve el animal directo por UUID
  (validando `tenant_id`) en lugar de por los 3 identificadores físicos — necesario para
  animales recién nacidos sin arete/fuego/chip asignado. Si `p_livestock_id` es `NULL`, el
  comportamiento es idéntico al de antes de v1.12.0. Ver la sección "Reporte de eventos para
  animales sin identificador físico" más abajo.
* Rechaza (error duro) si el animal ya está `VENDIDO` o `BAJA_MORTANDAD`. Sin regla
  especial para `PREÑADA` (confirmado explícitamente por el cliente — no bloquea).
* Al éxito: `current_status = 'BAJA_MORTANDAD'`. **`upp_origen` se conserva** (a diferencia
  de venta, que lo limpia) — decisión de negocio: útil para análisis de mortalidad por
  lote/UPP.
* **Marca automáticamente crías dependientes para revisión:** cualquier cría con
  `mother_id` = el animal, `current_status = 'ACTIVO'`, y sin fila en `weaning_events`, pasa
  a `current_status = 'RIESGO'`. Retorna el array de UUIDs afectados en el resultado JSONB.
* Inserta en `mortality_events` (detalle) y en `historico_movimientos`
  (`tipo_movimiento = 'BAJA_MORTANDAD'`, resumen en `notes`) — `v_audit_identifier` cae a
  `livestock_id::varchar` cuando no hay identificador físico *(v1.12.0)*.

### `sp_solicitar_autorizacion(p_electronic_rfid, p_rfid_siniiga, p_numero_fuego, p_livestock_id, p_tenant_id, p_tipo_evento, p_payload, p_solicitado_por_email)`
* ⚠️ **Corrección de documentación (v1.12.0):** la firma listada aquí en versiones previas
  de este archivo (7 parámetros, sin `p_livestock_id`) estaba desactualizada — el parámetro
  `p_livestock_id uuid DEFAULT NULL` ya existía en producción antes de v1.12.0. Confirmado
  vía `pg_get_function_identity_arguments` (dos overloads coexisten: uno de 7 parámetros
  legacy y uno de 8 con `p_livestock_id`).
* Valida animal e identificador con el mismo patrón que los SPs anteriores — ahora también
  acepta `p_livestock_id` como identificador alternativo (el `pending_authorizations.
  livestock_id` resultante se usa después para despachar sin depender de arete/fuego/chip).
  No muta `cattle_livestock` en ningún caso — solo crea o reutiliza la fila en
  `pending_authorizations`.
* Rechaza (error duro) si el animal ya está `VENDIDO` o `BAJA_MORTANDAD`.

### `sp_resolver_autorizacion(p_request_id, p_decision, p_resuelto_por_email, p_notas)`
* Ver `ARCHITECTURE.md` para el diseño del despachador (whitelist fija por `tipo_evento`,
  sin SQL dinámico).
* **Desde v1.12.0, reenvía `v_request.livestock_id` a ambos SPs despachados**
  (`p_livestock_id := v_request.livestock_id` en las llamadas a
  `sp_procesar_baja_mortandad` y `sp_procesar_salida_ganado`). Antes de este fix, la
  solicitud se creaba correctamente con `livestock_id` resuelto pero el despachador nunca lo
  propagaba — un animal sin identificador físico llegaba a aprobación y el SP real fallaba
  con `ERRCODE P0002` ("Ningún animal coincide con el identificador proporcionado"), pese a
  que la solicitud sí tenía el UUID correcto guardado. Bug real detectado y corregido en
  pruebas de producción (2026-09-18/19), no solo teórico.
* Valida vigencia (`fecha_solicitud::date < CURRENT_DATE` → auto-expira la solicitud y
  rechaza con `ERRCODE P0012`) y estado (`estado <> 'PENDIENTE'` → rechaza con
  `ERRCODE P0011`, evita doble resolución) antes de despachar.
* Registrado en `crud_models` con `sp_requires_tenant = false` — no recibe `tenant_id` como
  parámetro; la validación de tenant ya ocurrió al crear la solicitud original en
  `sp_solicitar_autorizacion`.

---

### Reporte de eventos para animales sin identificador físico (v1.12.0)

*Añadido 2026-09-18/19.* Resuelve la limitación #2 señalada en v1.11.1 (Birth Subsystem,
más abajo): una cría recién nacida sin arete/fuego/chip no podía reportarse por mortandad ni
venta, porque `sp_solicitar_autorizacion` (y, hasta este fix, los SPs de despacho) solo
aceptaban los 3 identificadores físicos.

**Herramienta MCP `find_calf_by_dam`** (`v6/MCP Server Cattle`):
* Busca crías **sin ningún identificador físico** (`rfid_siniiga`, `numero_fuego`,
  `electronic_rfid` los 3 `NULL`) nacidas de una madre específica en los últimos 90 días.
  Madre identificada por `electronic_rfid`/`rfid_siniiga`/`numero_fuego` (texto libre, mismo
  patrón que `register_birth_event`).
* No filtra por `current_status` de la madre ni de la cría — una cría ya `BAJA_MORTANDAD`
  sigue apareciendo en los resultados (comportamiento verificado, no un bug: el filtro solo
  mira ausencia de identificador + ventana de fecha).
* Si regresa exactamente un resultado, el Agente usa su `id` como `livestock_id` sin pedir
  confirmación al usuario (el usuario no puede dictar un UUID por voz/texto). Si regresa
  varios, el Agente debe desambiguar listando sexo/fecha/peso — **verificado en producción
  que esto funciona correctamente** tras el fix de tenant_id (ver abajo).

**Flujo completo:** `find_calf_by_dam` (resuelve `livestock_id`) → `log_mortality_event` /
`request_livestock_sale` (pasan `livestock_id` a `sp_solicitar_autorizacion`) →
`pending_authorizations.livestock_id` poblado, con `electronic_rfid`/`rfid_siniiga`/
`numero_fuego` vacíos en el `payload` → aprobación vía `/admin/autorizaciones` →
`sp_resolver_autorizacion` reenvía `livestock_id` → `sp_procesar_baja_mortandad` /
`sp_procesar_salida_ganado` resuelven el animal por UUID directo.

**⚠️ Hallazgo real durante las pruebas — el `tenant_id` de una llamada MCP no es un límite
de confianza garantizado.** El Agente IA, al invocar `find_calf_by_dam`, en una ejecución
envió `tenant_id: 5` (una empresa real, "UPP La Bendición") en vez de `tenant_id: 3`
(tenant de pruebas), **pese a que la resolución de tenant en el workflow de WhatsApp ya
había determinado correctamente `tenant_id = 3`** para esa conversación — el LLM ignoró el
valor correcto al construir los parámetros de esa herramienta específica. Sin match en la
BD, la llamada no tuvo efecto (no se filtró ni escribió nada en tenant 5), pero el patrón es
real: cualquier parámetro `tenant_id` que dependa de `$fromAI()` en una tool MCP puede, en
principio, ser sustituido por el LLM.
* **Mitigación aplicada:** se agregó una línea con el valor **literal** del tenant
  (`{{ $('Resolver Tenant').item.json.tenant_id }}` / `{{ $('Validar Token').item.json.data.
  id_company }}`) justo antes del diccionario de herramientas en ambos system prompts
  (WhatsApp y Chat Web) — la proximidad al punto de decisión del LLM resultó ser más
  efectiva que reforzar la regla general de tenant (Regla 4), que ya existía y no fue
  suficiente por sí sola.
* **No es una garantía arquitectónica**, solo un refuerzo de prompt — `v6/MCP Server Cattle`
  corre como workflow MCP separado, sin acceso directo al contexto de sesión del workflow
  que lo invoca, así que no hay forma simple de inyectar `tenant_id` por expresión de n8n en
  vez de depender del LLM. Queda como deuda técnica de arquitectura, ver `CLAUDE.md`.

**Probado end-to-end en producción (2026-09-18/19), tenant 3 ("Pista de Hielo"):**
mortandad ✅ (madre `9999999999`, cría `aab8e413-f94b-40ef-afdb-5577b091703f` →
`BAJA_MORTANDAD`, `mortality_events` insertado correctamente) y venta ✅ (cría
`4d8dbcb3-f73c-4cff-b5e3-72eac8cca738` → `APROBADO`, `sp_procesar_salida_ganado`
ejecutado sin error).

---

## 🐄 Weaning Subsystem — previamente indocumentado, tabla/función ya existentes en producción

*Corrección de gap de documentación, detectado 2026-09.* `weaning_events` y
`sp_register_weaning_event` ya existían en producción y no estaban en ninguna versión
anterior de este archivo — no son nuevos de v1.11.0, solo su documentación lo es.

### `weaning_events`
* `id` (UUID, PK), `id_company` (INT), `livestock_id` (UUID, FK, `ON DELETE CASCADE`)
* `weaning_date` (DATE), `weaning_method` (VARCHAR, CHECK: NATURAL/INDUCED/EARLY, default
  NATURAL)
* `weight_log_id` (UUID, FK -> `cattle_weight_logs`, nullable) — si se captura peso al
  momento del destete, queda enlazado.
* `reported_by_email` (VARCHAR NOT NULL), `notes`, `created_at`
* `UNIQUE (livestock_id)` — un animal se desteta una sola vez.
* Consultada por `sp_procesar_baja_mortandad` (v1.11.0) para decidir si una cría cuenta como
  "activa sin destetar" y debe marcarse en `RIESGO` al morir su madre.

### `sp_register_weaning_event(p_id_company, p_livestock_id, p_weaning_date, p_weaning_method, p_reported_by_email, p_weight_kg, p_notes)`
* Rechaza si `category` no está en (BECERRO, BECERRA, BUCERRO, BUCERRA, POTRO, POTRANCA,
  BORREGO, BORREGA) o si `current_status <> 'ACTIVO'`, o si ya existe un destete previo
  para el animal.
* Inserta opcionalmente en `cattle_weight_logs` (`source_device = 'WEANING_EVENT'`) si se
  proporciona peso.
* Retorna `(weaning_event_id, weight_log_id)`.

## 🐄 Birth Subsystem — `sp_register_birth_event`, comportamiento previamente indocumentado

* Ya documentada la tabla `birth_events` (v1.9.0); el comportamiento del SP no estaba
  descrito hasta ahora.
* Asigna categoría automáticamente por especie+sexo (`BOVINO_MACHO → BECERRO`,
  `BOVINO_HEMBRA → BECERRA`, equivalentes para BUFALO/BORREGO/EQUIDO).
* **Si la madre estaba `PREÑADA`, la pasa automáticamente a `VACÍA`** al registrar el parto
  — parte del ciclo reproductivo ya automatizado, más allá de lo que se documentó en
  v1.9.0/v1.10.0.
* Inserta opcionalmente en `cattle_weight_logs` (`source_device = 'BIRTH_EVENT'`) si se
  proporciona peso al nacer.
* Inserta en `birth_events` con `source = 'MOBILE_APP'` para altas capturadas por este
  camino (distinto de `'FIELD_NOTEBOOK'`/`'SPREADSHEET_IMPORT'` usados en backfill histórico).

### ⚠️ Dos versiones sobrecargadas en producción, confirmado vía `pg_get_functiondef` (2026-09-16)

`sp_register_birth_event` existe en **dos firmas simultáneas**:

* **Versión de 12 parámetros** (sin `p_lot_id`): resuelve ubicación solo con
  `COALESCE(v_dam_production_unit, p_production_unit_id)` — lote heredado de la madre o
  nada.
* **Versión de 13 parámetros** (con `p_lot_id uuid DEFAULT NULL`, la vigente para la tool
  MCP `register_birth_event`, ver más abajo): agrega la tabla **`production_unit_lots`**
  (`id`, `id_company`, `production_unit_id`, previamente indocumentada — no confundir con
  `production_unit_paddocks`, que es un concepto distinto: potrero físico vs. lote
  administrativo). Si `p_lot_id` viene poblado, se valida que exista y pertenezca al
  tenant (`RAISE EXCEPTION ... P0002` si no), y **de ahí se deriva `production_unit_id`
  automáticamente** — no hace falta mandar ambos.
* **Prioridad de ubicación real (versión de 13 parámetros):**
  `v_final_lot_id := COALESCE(p_lot_id, v_dam_lot_id)`
  `v_final_production_unit := COALESCE(v_explicit_lot_unit, v_dam_production_unit, p_production_unit_id)`
  — es decir: lote explícito del payload (si se manda) determina la UPP por encima de
  cualquier otra fuente; si no hay lote explícito, se hereda lo que tenga la madre; si la
  madre tampoco tiene nada, se usa `p_production_unit_id` tal cual.
* `production_unit_lots` está vacía en producción al 2026-09-16 (0 filas para todos los
  tenants existentes) — en la práctica, hoy `p_lot_id` siempre debe omitirse/ir `NULL`.

### Herramienta MCP `register_birth_event` (Agente IA, v1.11.0+)

* Expone la versión de 13 parámetros al Agente conversacional (WhatsApp/Chat Web). Acepta
  a la madre por `dam_id` (UUID, si ya se resolvió vía `get_livestock_info`) o por
  `dam_ear_tag`/`dam_fire_number` (texto libre) — no exige resolución previa a UUID, a
  diferencia de la mayoría de las demás tools.
* **Evento rutinario, sin protocolo de confirmación previa** (a diferencia de mortandad y
  venta) — coherente con la clasificación de eventos confirmada por el cliente: solo
  "Baja por muerte" y "Baja por venta" requieren autorización/confirmación.
* Probada de punta a punta en producción (Chat Web y WhatsApp, 2026-09-16), incluyendo el
  caso de madre sin ubicación asignada (el Agente pregunta explícitamente por la UPP, no
  la asume) y el caso de madre con estatus distinto a `PREÑADA` (el SP informa que no
  modificó su estatus, sin tratarlo como error).
* ⚠️ Ver `CLAUDE.md`, Regla 11, para una limitación confirmada en pruebas reales que sigue
  abierta: el Agente no resuelve un nombre de UPP mencionado en texto libre contra
  `production_units.ranch_name` cuando el tenant tiene varias UPPs — solo reconoce nombres
  de tenant.
* ✅ **Resuelto en v1.12.0** (antes listada aquí como limitación #2): un animal recién
  nacido sin identificador físico asignado ahora **sí** puede reportarse por mortandad/venta,
  vía la herramienta MCP `find_calf_by_dam` + el parámetro `livestock_id` agregado a toda la
  cadena de autorización asíncrona. Ver "Reporte de eventos para animales sin identificador
  físico" arriba.

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

### `sp_procesar_salida_ganado(p_electronic_rfid)` — overload legacy de 1 parámetro

*Reemplazado en v1.9.0 — mecanismo actualizado dos veces desde el registro original.*

* **Purpose:** Business rule enforcement for livestock checkout (sale).
* **Signature and invocation unchanged since v1.0.0:** `SELECT sp_procesar_salida_ganado(rfid)`.

### `sp_procesar_salida_ganado(p_electronic_rfid, p_tenant_id, p_rfid_siniiga, p_numero_fuego, p_livestock_id)` — overload de 4/5 parámetros

⚠️ **Gap de documentación retroactivo, cerrado en v1.12.0:** este overload existe en
producción desde v1.9.0 (es el que realmente invoca el gateway Meta-CRUD vía
`spConfigByModel` en el nodo Build Query) y nunca se documentó por separado del overload
legacy de arriba — ambos coexisten como funciones distintas en Postgres (sobrecarga por
firma), no una sola función con parámetros opcionales agregados con el tiempo.

* Mismo patrón de desambiguación multi-identificador y mismas reglas normativas
  (arete oficial, TB/BR con exención por hato libre, exención completa para `species =
  'EQUIDO'`) que el resto de esta sección describe para el mecanismo general.
* **`p_livestock_id uuid DEFAULT NULL`** *(añadido en v1.12.0, 5º parámetro)*: mismo
  patrón que en `sp_procesar_baja_mortandad` — si viene informado, resuelve el animal
  directo por UUID en vez de por los 3 identificadores físicos. Necesario para venta de
  animales sin arete todavía asignado, aunque en la práctica la validación de arete oficial
  SINIIGA sigue aplicando después de resolver el animal (un animal sin arete físico
  legítimamente no puede venderse per la NOM-001-SAG/GAN-2015, salvo `EQUIDO`) — este
  parámetro resuelve el *lookup*, no exime del requisito legal.
* Ver "Reporte de eventos para animales sin identificador físico" arriba para el flujo
  completo de venta de animales sin arete.
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
    * ⚠️ **`species = 'EQUIDO'` exemption, added same session, previously undocumented
      here:** both checks above (official ear tag and TB/BR) are skipped entirely when
      `v_species = 'EQUIDO'` — horses legitimately carry no SINIIGA tag under Mexican
      regulation. Fixed live in production during a real client transaction (a mare sale),
      not caught until then because this SP's rules were written cattle-first.
  * **On success:** sets `current_status = 'VENDIDO'`, clears both `upp_origen` AND
    `production_unit_id`, and inserts a `VENTA` row into `historico_movimientos`. Returns
    `tb_herd_free`/`br_herd_free` flags alongside the result for transparency.
* **Compensating reversal:** if a row is mistakenly marked `VENDIDO` (e.g. a test run
  against production), restore the animal by hand and insert a `REVERSION` row in
  `historico_movimientos` (added to the CHECK in migration 025) — never delete the
  original `VENTA` row. The audit table is append-only.
* ⚠️ **Segundo camino de invocación desde v1.11.0:** una venta iniciada por el Agente IA ya
  no llama a este SP directamente — pasa primero por `sp_solicitar_autorizacion`
  (`tipo_evento = 'VENTA'`), y este SP solo se ejecuta al aprobarse, vía el despachador
  `sp_resolver_autorizacion`. Firma e invocación sin cambios; el segundo camino es aditivo.

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