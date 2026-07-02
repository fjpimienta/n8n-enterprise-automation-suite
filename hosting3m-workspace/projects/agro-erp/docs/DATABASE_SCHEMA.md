# 🗄️ Database Architecture & Meta-CRUD Schema

## 📝 Resumen Ejecutivo
Este documento define la estructura de persistencia para el módulo Agro ERP. El sistema utiliza PostgreSQL 15+ con un modelo de datos híbrido: relaciones estrictas para la integridad Multi-Tenant y campos `JSONB` para absorber la variabilidad de la telemetría agrícola y médica[cite: 1, 2]. Todo el acceso a datos está orquestado por el router dinámico `crud_models` vía n8n[cite: 2, 3].

## 🏗️ Diccionario de Datos (Módulo Cattle)

### 1. Entidades Principales (Core)

*   **`cattle_tenants` (Inquilinos/Empresas)**
    *   **Descripción:** Gestiona el aislamiento Multi-Tenant del sistema.
    *   **Campos Clave:** `id` (UUID), `tax_id`, `name`, `org_type` (GANADERO, UNION, GOBIERNO).
    *   **Meta-CRUD Roles:** SELECT, INSERT, UPDATE, DELETE, GETONE, GETALL (Roles: ADMIN, EDITOR).

*   **`cattle_livestock` (Inventario de Biomasa)**
    *   **Descripción:** Registro maestro de animales. Soporta múltiples especies (BOVINO, BUFALO, BORREGO) y modelos de negocio[cite: 4].
    *   **Campos Clave:** `id` (UUID), `tenant_id` (FK), `rfid_siniiga` (Unique), `electronic_rfid` (Unique), `numero_fuego`, `current_status`.
    *   **Hardware de Trazabilidad:** Optimizado para lectura de Bolo Ruminal (Cápsula Cerámica) como identificador principal en campo por su alta durabilidad.
    *   **Check Constraints:** Valida estatus operativos críticos (ACTIVO, PREÑADA, VACÍA, FINALIZADO)[cite: 4].

### 2. Entidades Transaccionales (Logs & Telemetry)

*   **`cattle_health_logs` (Eventos Sanitarios)**
    *   **Descripción:** Registra intervenciones médicas y diagnósticos.
    *   **Campos Clave:** `event_type`, `event_date`, `medicines_json` (JSONB para flexibilidad de tratamientos)[cite: 1, 4].
    *   **Delete Rule:** `ON DELETE CASCADE` asociado al `livestock_id`.

*   **`cattle_weight_logs` (Control de Biomasa)**
    *   **Descripción:** Registro histórico de pesajes.
    *   **Campos Clave:** `weight_kg`, `log_date`, `source_device`.
    *   **Triggers:** Ejecuta `update_current_weight()` `AFTER INSERT` para recalcular el peso actual de la biomasa automáticamente.

*   **`cattle_expenses` (OPEX / Gasto Operativo)**
    *   **Descripción:** Registra costos directos vinculados a un animal o al tenant general.
    *   **Campos Clave:** `amount`, `category`, `health_event_id` (Opcional, FK a `cattle_health_logs`).

*   **`cattle_task_evidence` (Trazabilidad de Tareas)**
    *   **Descripción:** Almacena evidencia multimedia de tareas ejecutadas en campo.
    *   **Campos Clave:** `task_name`, `evidence_url`, `status` (PENDIENTE, COMPLETADO, RECHAZADO).

## ⚙️ Meta-CRUD Routing Configuration (n8n)
La tabla `crud_models` delega las operaciones al API Gateway, eliminando la necesidad de endpoints rígidos[cite: 1, 2]. 
*   **Aislamiento de Inyección:** Entidades como `cattle_weight_logs` habilitan el rol `IOT` para la ingesta de telemetría sin requerir privilegios `ADMIN`.
*   **Joins Dinámicos:** Configurados a nivel de base de datos. Por ejemplo, `cattle_expenses` ejecuta joins automáticos con `cattle_livestock` (`numero_fuego`, `business_model`) y `cattle_health_logs` para consolidación financiera instantánea.