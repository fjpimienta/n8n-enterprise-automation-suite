# 🛠️ Dynamic CRUD Engine (PostgreSQL Abstractor)

## 📝 Descripción
Este workflow actúa como una **Capa de Abstracción de Datos (DAL)** dinámica. A diferencia de un CRUD tradicional, este flujo no está acoplado a una sola tabla. Utiliza metadatos almacenados en una tabla de configuración para procesar operaciones sobre cualquier modelo de la base de datos de forma segura y centralizada.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/crud/:model` | Lanzamiento inicial. | `v1-crud.json` |

---

### 🏗️ Arquitectura de la Solución
1. **Ruteo Dinámico:** Captura el modelo desde la URL (`/crud/:model`).
2. **Inyección de Configuración:** Consulta la tabla `crud_models` para obtener el nombre real de la tabla física, llaves primarias y filtros por defecto.
3. **Generador de SQL Seguro:** Un nodo de código transforma el body de la petición en sentencias SQL parametrizadas para evitar inyecciones.
4. **Normalización de Respuesta:** Estandariza la salida para que el frontend reciba siempre la misma estructura, independientemente de la operación (Insert/Update/Get).

---

## 🚀 Capacidades del Motor
- **Operaciones Soportadas:** `insert`, `update`, `getOne`, `getAll`.
- **Seguridad:** Requiere **JWT Auth** (integrado con el Módulo 01).
- **Flexibilidad:** Permite cambiar la lógica de negocio desde la base de datos sin tocar el flujo de n8n.

---

## 📊 Esquema de Base de Datos Necesario
Para que este motor funcione, se requiere la tabla de metadatos:

```sql
CREATE TABLE crud_models (
    id SERIAL PRIMARY KEY,
    model_name VARCHAR(50) UNIQUE, -- Ej: 'customers'
    table_name VARCHAR(50),        -- Ej: 'tbl_crm_customers_v2'
    primary_key VARCHAR(50),       -- Ej: 'id'
    default_filter TEXT            -- Ej: 'id=$1'
);