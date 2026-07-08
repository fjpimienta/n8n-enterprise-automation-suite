# 🗄️ Database Schema & Baseline (v2)

## 📌 Core Directives
* **RDBMS:** PostgreSQL
* **Security:** Tenant isolation via `tenant_id` (`companys.id_company`).
* **Primary Keys:** UUID v4 default for high-concurrency environments.

## 🏗️ Cattle Management Subsystem

### `cattle_livestock` (Core Entity)
Registry of biomass with embedded compliance rules.
* `id` (UUID, PK)
* `tenant_id` (INT, FK -> `companys`)
* `rfid_siniiga` (VARCHAR, UNIQUE) - Secondary Metadata (physical SINIIGA ear tag; loses reliability due to physical loss)
* `electronic_rfid` (VARCHAR, UNIQUE) - Primary Operational Key (rumen bolus / subcutaneous microchip)
* `numero_fuego` (VARCHAR) - Physical brand/iron mark identifier
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

## 📊 Views (BI Layer)

### `vw_cattle_kpi`
* **Source:** `cattle_livestock` `LEFT JOIN` `companys`.
* **Computed columns:**
  * `tenant_name` (from `companys.company_name`)
  * `adg_lifetime_kg` - `current_weight_kg` / age in days since `birth_date`
  * `last_palpation_result` / `current_gestation_days` - latest `PALPACION` entry pulled from `cattle_health_logs.medicines_json`
  * Also passes through `species`, `upp_origen`, `tb_test_date`, `br_test_date`.
* ⚠️ **Column order constraint:** `CREATE OR REPLACE VIEW` requires existing columns to keep their name/position; new columns can only be appended at the end (see migration `004_vw_cattle_kpi_add_salida_fields.sql`).

## ⚙️ Stored Procedures & Triggers (Business Logic Layer)

### `execute_metacrud_write`
* **Purpose:** Centralized Zero-Compute Client mutation gateway.
* **Mechanism:** Validates against `crud_models` whitelist before executing dynamic INSERT/UPDATE.

### `sp_procesar_salida_ganado(p_electronic_rfid)`
* **Purpose:** Business rule enforcement for livestock checkout (sale).
* **Mechanism:**
  * Uses `FOR UPDATE` row-level locking on `cattle_livestock` to prevent double-processing from concurrent RFID reads.
  * **Hard errors** (`RAISE EXCEPTION`, `ERRCODE` P0002/P0001): RFID not registered, or already `VENDIDO`.
  * **Regulatory rejection** (returns `{"success": false, "motivo": ...}`, no exception): `tb_test_date` or `br_test_date` missing or older than 60 days. This lets the n8n gateway distinguish a "business rejection" (triggers a WhatsApp alert) from a real data error.
  * **On success:** sets `current_status = 'VENDIDO'`, `upp_origen = NULL`, and inserts a `VENTA` row into `historico_movimientos`.

### `update_current_weight()`
* **Purpose:** Ensures `cattle_livestock.current_weight_kg` is an exact reflection of the latest `cattle_weight_logs` entry without client-side computation.
* **Mechanism:** `AFTER INSERT` trigger on `cattle_weight_logs`.
