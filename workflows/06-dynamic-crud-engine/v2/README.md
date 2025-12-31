# 🛠️ Dynamic CRUD Engine (PostgreSQL Abstractor)

## 📝 Descripción
La versión 2.0 evoluciona de una simple Capa de Abstracción de Datos (DAL) a un Motor de Gestión de Datos Inteligente. Este workflow no solo centraliza las operaciones de base de datos, sino que ahora es capaz de auto-configurarse mediante IA, validar esquemas de datos en tiempo real y gestionar permisos granulares por roles.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/crud/:model` | Lanzamiento inicial. | `v1-crud.json` |
| **v2** | `Stable` | `/crud/v2/:model` | IA-Driven: Auto-descubrimiento de tablas, validación de esquemas, RBAC por operación y auditoría de logs. | `v2-crud.json` |

---

## 🚀 Novedades de la v2.0
* Auto-Discovery (AI): Si un modelo no existe en la configuración, el motor analiza la tabla física en PostgreSQL y usa GPT-4o para generar automáticamente la configuración técnica (PK, FK, Joins, tipos de datos).
* Validación de Esquema: Nuevo nodo que verifica que los campos obligatorios (required) estén presentes en las peticiones INSERT y UPDATE antes de tocar la base de datos.
* Seguridad Basada en Roles (RBAC): Control de acceso detallado por operación (ej. allowed_roles_delete).
* Sistema de Ganchos (Hooks): Capacidad para ejecutar lógica pre y post operación.
* Auditoría (Logging): Registro automático de cada transacción en la tabla crud_logs para monitoreo y debugging.

---

### 🏗️ Arquitectura de la Solución
1. **Entrada:** Captura dinámica vía /crud/v2/:model.
2. **Validación de Existencia:** Si el modelo existe, carga configuración; si no, inicia el Sub-flujo de IA.
3. **Extracción de Auth:** Procesa el JWT para extraer el rol del usuario desde x-jwt-claim-role.
4. **Validación de Seguridad:** Cruza el rol del usuario con los permisos permitidos para la operación solicitada.
5. **Generación de Query:** Delega a un subworkflow especializado (Build Query v2) la creación del SQL parametrizado.
6. **Normalización y Logs:** Estandariza la salida y guarda el resultado en el historial de logs.

---

## 🚀 Capacidades del Motor
- **Operaciones Soportadas:** `insert`, `update`, `delete`, `getOne`, `getAll`.
- **Seguridad:** Requiere **JWT Auth** (integrado con el Módulo 01).
- **Flexibilidad:** Permite cambiar la lógica de negocio desde la base de datos sin tocar el flujo de n8n.

---

## 📊 Esquema de Base de Datos Necesario
Para soportar las nuevas funciones, la tabla de metadatos se ha expandido:
```sql
-- Tabla de Configuración Maestra
CREATE TABLE crud_models (
    id SERIAL PRIMARY KEY,
    model_name VARCHAR(50) UNIQUE,
    table_name VARCHAR(50),
    primary_key VARCHAR(50),
    allowed_fields JSONB,           -- Lista de columnas permitidas
    schema_json JSONB,              -- Definición de tipos y obligatoriedad
    allowed_ops TEXT[],             -- Ej: {'GETALL', 'INSERT', 'DELETE'}
    allowed_roles_select TEXT,      -- Roles permitidos (separados por coma)
    allowed_roles_insert TEXT,
    allowed_roles_update TEXT,
    allowed_roles_delete TEXT,
    joins JSONB DEFAULT '[]',       -- Relaciones FK detectadas
    hooks JSONB DEFAULT '{"pre": [], "post": []}'
);

-- Tabla de Auditoría
CREATE TABLE crud_logs (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    model_name VARCHAR(50),
    operation VARCHAR(20),
    user_role VARCHAR(50),
    status_code INTEGER,
    payload JSONB,
    response_summary JSONB
);
```

---

## 🛠️ Configuración de los Nodos Principales
1. Validación de IA
    El motor utiliza una consulta a information_schema.columns para alimentar a la IA. El prompt está diseñado para identificar automáticamente:
    * Llaves Primarias (PK).
    * Llaves Foráneas (FK) y sus tablas de destino para generar joins.
    * Mapeo de tipos de datos de Postgres a tipos JSON (string, number, boolean).

2. Seguridad (Security Validation)
    El nodo de código valida el flujo basándose en la jerarquía:
    * ¿La operación está permitida para este modelo?
    * ¿El rol del usuario (del JWT) tiene permiso para esta operación específica?

---

## 🛠️ Configuración de los Nodos Principales
Endpoint: POST /workflow/crud/v2/orders
Headers: Authorization: Bearer <JWT_TOKEN>
Body:
```
{
  "operation": "insert",
  "fields": {
    "customer_id": 101,
    "total_amount": 150.50,
    "status": "pending"
  }
}
```