# 🗄️ Database Architecture & Meta-CRUD Schema

## 📝 Resumen Ejecutivo
Este documento define la estructura de persistencia centralizada para el módulo Agro ERP dentro de la Hosting3M Automation Suite. El sistema utiliza PostgreSQL 15+ con un modelo de datos híbrido: relaciones estrictas para la integridad y control de acceso (RBAC), y columnas `JSONB` (`metadata`, `medicines_json`) para absorber la variabilidad de la telemetría agrícola, datos de padrones oficiales y registros médicos. Todo el acceso a datos está orquestado por el router dinámico `crud_models` vía n8n (Meta-CRUD v3).

## 🏗️ Diccionario de Datos (Módulo Agro/Cattle)

### 1. Entidades Principales (Core & Multi-Tenant)

* **`companys` (Inquilinos / UPPs / Ranchos Maestros)**
    * **Descripción:** Tabla maestra que gestiona el aislamiento Multi-Tenant y Multi-Dominio de todo el ecosistema (Hotelería, Ganadería, etc.).
    * **Mapeo Agropecuario:** El `company_name` funge como el Nombre del Rancho, y el campo `industry` se clasifica como `"GANADERIA"`.
    * **Soporte Híbrido (JSONB):** Incorpora la columna `metadata` para inyectar datos específicos de la vertical sin sobre-normalizar la base de datos relacional. Aquí reside la parametrización de SINIIGA: `clave_upp`, `folio_holograma`, `curp`, `rfc`, `superficie_ha`, y `fecha_alta`.
    * **Meta-CRUD Roles:** SELECT, INSERT, UPDATE, DELETE, GETONE, GETALL. (Operaciones restringidas a ADMIN y EDITOR).

* **`cattle_livestock` (Inventario de Biomasa)**
    * **Descripción:** Registro maestro de animales. Soporta múltiples especies biológicas y modelos de negocio transaccionales (CRIA, ENGORDA).
    * **Campos Clave:** `id` (UUID), `tenant_id` (FK a `companys`), `rfid_siniiga` (Unique), `electronic_rfid` (Unique), `numero_fuego`, `current_status`.
    * **Hardware de Trazabilidad:** Optimizado para lectura de Bolo Ruminal (Cápsula Cerámica) como identificador primario en campo para mitigar la pérdida física de aretes plásticos.
    * **Check Constraints:** Valida de forma nativa estatus operativos críticos a nivel de motor (ACTIVO, PREÑADA, VACÍA, FINALIZADO).

### 2. Entidades Transaccionales (Logs & Telemetry)

* **`cattle_health_logs` (Eventos Sanitarios)**
    * **Descripción:** Registra intervenciones médicas, palpaciones y diagnósticos reproductivos.
    * **Campos Clave:** `event_type`, `event_date`, `medicines_json` (JSONB para flexibilidad de dosificación de tratamientos).
    * **Delete Rule:** `ON DELETE CASCADE` asociado al `livestock_id`.

* **`cattle_weight_logs` (Control de Biomasa)**
    * **Descripción:** Registro histórico inmutable de pesajes para el cálculo de la Ganancia Diaria de Peso (ADG).
    * **Campos Clave:** `weight_kg`, `log_date`, `source_device`.

* **`cattle_expenses` (OPEX / Gasto Operativo)**
    * **Descripción:** Registra costos directos vinculados a un animal específico o al Rancho en general para el cálculo de rentabilidad por kilo.
    * **Campos Clave:** `amount`, `category`, `health_event_id` (Opcional, FK a `cattle_health_logs`).

* **`cattle_task_evidence` (Trazabilidad de Auditoría)**
    * **Descripción:** Almacena evidencia multimedia de tareas ejecutadas en campo (fotografías/videos).
    * **Campos Clave:** `task_name`, `evidence_url`, `status` (PENDIENTE, COMPLETADO, RECHAZADO).

## ⚙️ Meta-CRUD Routing Configuration (n8n v3)
La tabla `crud_models` delega todas las validaciones de entrada, RBAC y operaciones al API Gateway, garantizando una arquitectura de *Zero-Hallucination* al no exponer endpoints rígidos.

* **Validación Estricta de Payload (`schema_json`):** Bloquea inyecciones de parámetros no deseados. Campos dinámicos como `metadata` en la tabla `companys` están explícitamente habilitados (whitelisted) en la propiedad `allowed_fields` para permitir el tráfico de objetos anidados desde el cliente Angular.
* **Aislamiento de Inyección IOT:** Entidades como `cattle_weight_logs` habilitan el rol secundario `IOT` para la ingesta automatizada de telemetría (básculas/lectores) sin requerir privilegios de `ADMIN`.
* **Joins Declarativos Multidireccionales:** Configurados a nivel del motor en n8n. Entidades como `cattle_expenses` ejecutan *joins* automáticos con `cattle_livestock` y `cattle_health_logs` para retornar objetos consolidados al cliente sin carga computacional en el frontend.