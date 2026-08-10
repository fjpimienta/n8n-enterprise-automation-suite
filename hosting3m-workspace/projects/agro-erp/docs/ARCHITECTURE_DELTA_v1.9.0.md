# ARCHITECTURE.md — Delta v1.9.0

Aplicar así:
1. **Añadir** la sección "Contrato del motor Meta-CRUD" — es la más importante de este
   delta, documenta tres restricciones descubiertas en producción que costaron horas de
   depuración y no estaban escritas en ningún lado.
2. **Corregir** la nota sobre `execute_metacrud_write` en la sección 2 (ya insinuada, ahora
   con hallazgo completo).
3. **Añadir** la tabla de los 11 modelos nuevos del registro normativo.
4. **Corregir** la fecha/alcance de "Registrado: 2026-07-02" en `salida_ganado` — sigue
   siendo la misma rutina pero con dos reescrituras posteriores documentadas en
   DATABASE_SCHEMA.md.

---

## 1. Corrección — sección 2, tras el punto "Anatomía de Campos del Motor Dinámico"

Añadir:

```markdown
### ⚠️ Hallazgos confirmados sobre `execute_metacrud_write` (2026-07-27)

Esta función existe en la base pero **no es la ruta real de escritura del gateway**.
Confirmado mediante prueba directa:

```sql
SELECT execute_metacrud_write('UPDATE','cattle_livestock','{"tb_test_date":"2026-07-20"}'::jsonb, 1);
-- {"status": "error", "message": "invalid input syntax for type uuid: \"1\""}
```

Tres defectos verificados:
1. **`p_record_id` es `integer`**, incompatible con cualquier tabla de PK UUID —
   es decir, todas las tablas `cattle_*` y todas las del registro normativo.
2. **`WHERE id = %L` está hardcodeado**, ignorando `crud_models.primary_key`. Nunca pudo
   actualizar `companys` (PK real: `id_company`).
3. `RETURNING to_jsonb(*)` es sintaxis inválida sin alias de tabla — cualquier INSERT/UPDATE
   que la alcance cae en el `EXCEPTION WHEN OTHERS` y responde `status:error` con HTTP 200.

**Confirmado por contraste:** el gateway sí escribe correctamente contra tablas de PK UUID
(prueba real: `UPDATE cattle_livestock` con `id` UUID via el endpoint `crud/v5`, exitoso).
Esto significa que el nodo **Build Query** del workflow `06-dynamic-crud-engine` construye
su propio SQL dinámicamente y no invoca esta función — `execute_metacrud_write` es un
vestigio parcial, probablemente usado solo por flujos anteriores al módulo agropecuario
(hotel/pista de hielo). No asumir que es la ruta de escritura sin verificarlo primero contra
el workflow real.
```

## 2. Nueva sección — pegar después del diagrama de flujo del runtime Meta-CRUD

```markdown
### ⚠️ Contrato del motor Meta-CRUD (restricciones implícitas, no declaradas en `crud_models`)

Tres restricciones que el gateway impone en runtime y que no aparecen en ningún esquema ni
documentación previa. Cada una costó una ronda de depuración en producción antes de
identificarse.

**1. Toda tabla o vista registrada debe exponer `created_at`.**
El gateway lo usa para el `ORDER BY` por defecto de `getall`. Omitirlo produce, en tiempo de
ejecución (no en el despliegue):
```
{"error":true,"message":"column vw_upp_compliance_status.created_at does not exist"}
```
Corregido para las vistas de cumplimiento en la migración 021, tras detectarse ya en
producción con el módulo desplegado.

**2. Shape exacto del payload.** El modelo va en la URL **y** en el body:
```json
{ "entity": "<model>", "table_name": "<table>", "operation": "getall|getone|insert|update",
  "filters": { }, "fields": { }, "id": "<pk>" }
```
Las operaciones van en minúsculas. Un payload con otra forma (por ejemplo, con
`"operacion"` en español o sin `"entity"`) devuelve **HTTP 200 con cuerpo vacío**, sin
ningún indicio de error. Esto llevó a diagnosticar erróneamente un "bug crítico de
`allowed_fields`" que resultó ser, simplemente, un payload de prueba mal formado.

**3. Las colecciones vacías devuelven `data:[{}]`, no `[]`.** Verificado contra
`cattle_breed_catalog` con 0 filas reales: la UI mostraba "1/1 razas" con una tarjeta en
blanco. Cualquier consumidor debe filtrar por la clave primaria esperada antes de contar o
renderizar — un `Object.keys().length === 0` no basta, porque el objeto fantasma puede traer
claves con valor `null`.

**4. Los errores de PostgreSQL llegan como HTTP 200 con `error:true` y el mensaje real**
(ej. violación de CHECK). El "MetaCRUD Silent Error Shield" del frontend es la mitigación
correcta a este comportamiento del gateway, no un patrón defensivo redundante.
```

## 3. Nueva tabla — pegar en "3. Modelos Operativos Registrados", después de los "Modelos Secundarios"

```markdown
### 🏛️ Modelos del Registro Normativo (migraciones 018, 021 — 11 modelos)

| Modelo | Tabla / Vista | Ops | RBAC escritura |
|---|---|---|---|
| `livestock_producers` | tabla (sin PII) | SELECT, INSERT, UPDATE, GETONE, GETALL | ADMIN, OWNER |
| `livestock_producers_pii` | `vw_livestock_producers` | SELECT, GETONE | — (solo lectura, PII descifrada) |
| `production_units` | tabla | SELECT, INSERT, UPDATE, GETONE, GETALL | ADMIN, OWNER |
| `psg_licenses` | tabla | SELECT, INSERT, UPDATE, GETONE, GETALL | ADMIN, OWNER |
| `compliance_certificates` | tabla | SELECT, INSERT, GETONE, GETALL | ADMIN, EDITOR (append-only) |
| `compliance_documents` | tabla | SELECT, INSERT, GETONE, GETALL | ADMIN, EDITOR (append-only) |
| `livestock_census_snapshots` | tabla | SELECT, INSERT, GETONE, GETALL | ADMIN, EDITOR (append-only) |
| `upp_compliance_status` | `vw_upp_compliance_status` | SELECT, GETONE, GETALL | — |
| `psg_compliance_status` | `vw_psg_compliance_status` | SELECT, GETONE, GETALL | — |
| `producer_pii` | `sp_upsert_producer_pii` | INSERT | ADMIN, OWNER |
| `cattle_tenants` | tabla (DEPRECADO) | SELECT, GETONE, GETALL | NONE (bajado en migración 010) |

**Nota sobre `cattle_livestock` (ID 37):** su `allowed_fields` se amplió en la migración 018
para incluir `production_unit_id` (16 → 17 campos). No hubo bug previo de exclusión de
`species`/`upp_origen`/`tb_test_date`/`br_test_date` — esos ya estaban correctamente listados
en producción; el diagnóstico inicial que lo sugería se basó en un `crud_models_seed.sql`
desactualizado en el repo, no en el estado real. Corregido en el registro de la sesión de
despliegue del 2026-07-27.

**`brand_registrations`, `production_unit_paddocks`, `birth_events`, `herd_free_certificates`
y `cattle_movement_rules`** (migraciones 028, 030, 020) existen en base de datos pero **aún
no están registrados en `crud_models`** — se diseñaron y probaron a nivel de esquema; su
exposición vía Meta-CRUD es trabajo pendiente, no completado en esta ronda.
```

## 4. Corrección — entrada de `salida_ganado` (ID 46)

Añadir al final de esa entrada:

```markdown
* **Reglas actualizadas dos veces desde el registro original (2026-07-02):**
  - Migración 024 (2026-07-29): agrega validación de arete oficial SINIIGA
    (`fn_has_official_ear_tag`) y exención por dictamen de hato libre
    (`fn_is_herd_free`) a la ventana de 60 días TB/BR. Ver `DATABASE_SCHEMA.md` para el
    detalle completo de la rutina corregida.
  - La firma e invocación del modelo Meta-CRUD (`INSERT` sobre `electronic_rfid`) no
    cambiaron; solo el cuerpo de la función PL/pgSQL.
```
