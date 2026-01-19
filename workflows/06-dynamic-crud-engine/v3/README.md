# 🛠️ Dynamic CRUD Engine v3: (PostgreSQL Abstractor)

## 📝 Descripción
La versión 3.0 evoluciona de una simple Capa de Abstracción de Datos (DAL) a un Motor de Gestión de Datos Inteligente. Este workflow no solo centraliza las operaciones de base de datos, sino que ahora es capaz de auto-configurarse mediante IA, validar esquemas de datos en tiempo real y gestionar permisos granulares por roles.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/crud/:model` | Lanzamiento inicial. | `v1-crud.json` |
| **v2** | `Legacy` | `/crud/v2/:model` | IA-Driven: Auto-descubrimiento de tablas, validación de esquemas, RBAC por operación y auditoría de logs. | `v2-crud.json` |
| **v3** | `Stable` | `/crud/v3/:model` | Smart Upsert, SHA-256 Hashing, Hybrid Auth y Filtros Avanzados (_gte, _lte). | `v3-crud.json, v3-Build Query.json, v3-Normalize.json` |

---

## 🚀 Novedades de la v3.0
1. **🛡️ Native Crypto & Hashing:**
    El motor ahora detecta automáticamente campos sensibles. Si el payload contiene un campo llamado password, el sub-workflow Build Query aplica automáticamente un hash SHA-256 antes de guardar en la base de datos, eliminando la necesidad de manejar criptografía en el frontend.
2. **🔄 Smart Upsert (On Conflict Do Update):**
    La operación INSERT ha evolucionado. Ahora implementa lógica ON CONFLICT:
        * Si el registro ya existe (basado en primary_key, id, doc_id o email), el sistema actualiza los campos enviados en lugar de arrojar un error de duplicado.
        * Esto facilita la sincronización de datos sin verificar existencia previa.
3. **🔍 Advanced Filtering (GETALL):**
    El endpoint GETALL ahora soporta operadores lógicos complejos en el cuerpo del JSON para filtrar datos:
        * _gte (Greater than or equal)
        * _lte (Less than or equal)
        * _gt, _lt
        * Ejemplo: {"price": {"_gte": 100}} generará WHERE price >= 100.
4. **🌐 Hybrid Auth (Public/Private Context):**
    El nodo de autenticación Extract Auth Context ahora soporta modelos híbridos.
        * Permite definir modelos públicos (ej. companys) que asignan automáticamente un rol CUSTOMER temporal si no se presenta un token, facilitando procesos de registro o consulta pública sin sacrificar la seguridad RBAC.
5. **🧩 Modularización Extrema:**
    El flujo se ha dividido en 3 componentes para facilitar el mantenimiento:
        * Main CRUD: Orquestación, seguridad y validación IA.
        * Build Query: Construcción de SQL puro, manejo de Joins y Cifrado.
        * Normalize: Estandarización de respuestas JSON ({ data: [], meta: {}, error: bool }).

---

### 🏗️ Arquitectura de la Solución v3
1. **Entrada:** Captura dinámica vía /crud/v3/:model.
2. **Validación & IA:** Verifica existencia del modelo; si falta, GPT-4o genera la configuración.
3. **Auth Híbrida:** Intenta validar Token JWT. Si falla pero el modelo es público (ej. companys), asigna rol invitado.
4. **Generación SQL (Sub-workflow):** Llama a v3/Build Query para construir la sentencia SQL, aplicando hash a passwords y lógica de Upsert.
5. **Ejecución:** Corre la query en PostgreSQL.
6. **Normalización (Sub-workflow):** Llama a v3/Normalize para dar formato consistente a la respuesta.
7. **Auditoría:** Registra la transacción en crud_logs.

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