# Brief: Módulo de Cumplimiento Normativo (UPP / PSG) — Frontend

> Pegar este documento completo como primer mensaje en Claude Code, desde la raíz del
> monorepo `hosting3m-workspace`. Rama: `feature/v1.6.0/Parametrizacion`.

---

## Contexto

El backend del Registro Normativo SENASICA-SINIIGA ya está desplegado en producción
(migraciones 010–022, 2026-07-27). Existen 4 modelos de solo lectura expuestos vía el gateway
Meta-CRUD de n8n. **No hay que tocar base de datos ni n8n: solo consumir la API existente.**

El dato de negocio que motiva este módulo: el cliente tiene 3 unidades de producción pecuaria
registradas ante SENASICA, y **dos de ellas llevan más de un año sin reactualizarse** (662 y
537 días). Hoy no tiene forma de verlo. Ese es el valor de esta entrega.

## Objetivo

Módulo Angular de **solo lectura** que muestre el estado de cumplimiento del padrón ganadero.
Alta, edición y carga de documentos quedan explícitamente fuera de alcance.

---

## Decisiones ya tomadas (no reabrir)

| Decisión | Valor |
|---|---|
| Ubicación | `projects/agro-erp/src/app/features/compliance/` — módulo propio, NO dentro de `livestock/`. Aplica hoy a ganadería pero el patrón sirve para agricultura. |
| Alcance | Solo lectura. Sin formularios de alta/edición. |
| Tema | Reutilizar `theme-cattle` de Tabler UI. Sin identidad visual propia. |
| Tipos | Ya escritos. Ver sección "Interfaces". |

---

## Stack y reglas del proyecto (obligatorias)

- **Angular 21**, standalone components, **Signals** (`signal`, `computed`). Sin NgModules.
- **Tabler UI** + SCSS. Lazy loading en las rutas.
- **Zero-Compute Client:** el frontend NUNCA calcula métricas persistentes. Todo viene
  computado del servidor. Si falta un cálculo, es un bug del backend, no algo a resolver en
  el cliente.
- **Prohibido `localStorage`/`sessionStorage`** para estado de aplicación (el token de auth es
  la excepción existente, gestionada por `core-auth`).
- **Código, variables, interfaces, comentarios y commits en inglés.** La UI visible al usuario
  va en español.
- Multi-tenant: el `id_company` lo inyecta el gateway desde el JWT. El frontend **no** lo envía
  ni lo filtra manualmente.

---

## Contrato del gateway Meta-CRUD (crítico — leer completo)

Base URL: `environment.apiUrl_crud` (ya configurada), más `/<model_name>`.

### Shape del payload

El modelo va en la URL **y** en el body. Las operaciones van en minúsculas.

```json
{
  "entity": "<model_name>",
  "table_name": "<table_or_view_name>",
  "operation": "getall",
  "filters": {}
}
```

Un payload con otra forma devuelve **HTTP 200 con cuerpo vacío**, sin error. No hay forma de
distinguirlo de un éxito salvo por el body ausente.

### Shape de la respuesta

```json
{
  "error": false,
  "operation": "getall",
  "message": "Ejecución satisfactoria",
  "data": [ ... ],
  "execution_info": { "timestamp": "...", "model": "...", "has_post_hooks": false }
}
```

### Manejo de errores — MUY IMPORTANTE

Los errores de PostgreSQL llegan como **HTTP 200** con `error: true`:

```json
{ "error": true, "operation": "insert",
  "message": "new row for relation \"production_units\" violates check constraint \"...\"",
  "data": null }
```

El servicio DEBE inspeccionar `response.error` en cada respuesta, no solo el status HTTP.
Este es el patrón "MetaCRUD Silent Error Shield" que ya existe en el proyecto — replicarlo,
no inventar uno nuevo. Revisar `AdminService` (`features/admin/services/admin.service.ts`)
como referencia del patrón vigente con `catchError` de RxJS.

---

## Modelos disponibles (los 4, solo lectura)

| model_name | table_name | Uso |
|---|---|---|
| `upp_compliance_status` | `vw_upp_compliance_status` | Feed principal del dashboard |
| `psg_compliance_status` | `vw_psg_compliance_status` | Vigencia de licencias PSG |
| `production_units` | `production_units` | Detalle crudo de la UPP (superficie, matriz JSONB) |
| `livestock_census_snapshots` | `livestock_census_snapshots` | Censo declarado histórico |

Ejemplo de respuesta real de `upp_compliance_status` (producción, verificada):

```json
{
  "production_unit_id": "a2405f34-24a5-4c8a-b0d8-7fbec9aadb15",
  "id_company": 5,
  "company_name": "UPP La Bendición",
  "upp_code": "07-065-8727-001",
  "ranch_name": "LA BENDICION DE DIOS (SAN JOSE Y LA PITA)",
  "state_name": "Chiapas",
  "municipality_name": "Palenque",
  "total_surface_ha": "144.36",
  "is_partial_surface": true,
  "grazing_surface_ha": "0.00",
  "has_surface_inconsistency": false,
  "registration_date": "2022-07-14T05:00:00.000Z",
  "last_update_at": "2024-10-04T18:11:35.000Z",
  "days_since_update": 662,
  "update_status": "EXPIRED",
  "last_declared_head": null,
  "last_census_date": null,
  "active_head_in_system": "216",
  "is_active": true,
  "created_at": "2026-07-28T01:11:44.725Z"
}
```

---

## ⚠️ Trampas de datos reales (leer antes de escribir la UI)

Estas salieron de datos de producción verificados. Ignorarlas produce bugs sutiles.

1. **`grazing_surface_ha: "0.00"` NO significa cero hectáreas de pastoreo.** Significa que la
   constancia no declara superficie de pastoreo utilizable. Las 3 UPP están en 0.00. Mostrar
   "No disponible", nunca "0 ha". **Jamás usarlo como divisor** para carga animal (UA/ha) sin
   verificar `> 0`, o se divide entre cero.

2. **Los numéricos llegan como string.** `total_surface_ha`, `grazing_surface_ha` y
   `active_head_in_system` vienen como `"144.36"`, `"0.00"`, `"216"`. Parsear explícitamente;
   no confiar en coerción implícita ni ordenar como texto (`"216" < "54"` lexicográficamente).

3. **`has_surface_inconsistency: true` NO es un error del sistema.** Significa que el documento
   oficial de SENASICA se contradice a sí mismo (Santa Lucía declara 42.00 ha totales con las
   12 celdas de concepto en 0.00). Presentarlo como advertencia informativa sobre el documento,
   nunca como fallo de la aplicación ni como dato a "corregir".

4. **`days_since_update` y `last_update_at` pueden ser `null`** (San Pedro). En ese caso
   `update_status` es `"UNKNOWN"`. No renderizar "null días".

5. **`update_status = "EXPIRED"` es el estado real de 2 de 3 UPP.** No es un caso borde: es el
   escenario principal que este módulo debe comunicar. Diseñar la UI asumiendo que la mayoría
   estará en rojo.

6. **`active_head_in_system` vs `last_declared_head` divergen mucho** y es correcto: uno es el
   inventario biométrico en el sistema, el otro lo declarado ante SENASICA. Santa Lucía tiene
   302 declaradas y 0 capturadas. **No presentarlo como discrepancia ni sugerir reconciliación
   automática** — el cliente decidió que esa comparación necesita reglas que aún no existen.

7. **Fechas en UTC con desfase.** `last_update_at: "2024-10-04T18:11:35.000Z"` corresponde a
   `2024-10-04 12:11:35` hora local (America/Mexico_City). Formatear con locale `es-MX`.

---

## Interfaces TypeScript

Ya están escritas en el archivo `agro-registry.model.ts` que acompaña este brief. Copiarlo a
`features/compliance/models/` y usarlo tal cual. Contiene: `UppComplianceStatus`,
`PsgComplianceStatus`, `ProductionUnit`, `LivestockCensusSnapshot`, `SurfaceMatrix`, y los
union types `UpdateStatus`, `PsgValidityStatus`, `TenureType`, etc.

Nota: los tipos declaran `number` para los campos numéricos porque ese es el contrato lógico.
La API los envía como string — el mapeo va en el servicio, no cambiando las interfaces.

---

## Entregables

### 1. `ComplianceService`
`features/compliance/services/compliance.service.ts`

- Signals: `uppList`, `psgList`, `loadingUpp`, `loadingPsg`, `error`
- Métodos: `loadUppStatus()`, `loadPsgStatus()`, `getUppDetail(id)`
- Computed: `expiredUppCount`, `warningUppCount`, `expiredPsgCount`
- Parseo de los numéricos-como-string en el mapeo de respuesta
- Manejo de `response.error === true` siguiendo el patrón de `AdminService`

### 2. `ComplianceAlertCardComponent`
Tarjeta compacta para el dashboard principal. Muestra el conteo de UPP y PSG que requieren
atención, con enlace al listado. Si no hay ninguna vencida, estado positivo discreto (no
ocultar el componente).

### 3. `UppComplianceListComponent`
Listado con semáforo por `update_status`:
- `OK` verde · `WARNING` ámbar · `EXPIRED` rojo · `UNKNOWN` gris
- Columnas: rancho, clave UPP, ubicación, días sin actualizar, estado, cabezas en sistema
- Badge de advertencia cuando `has_surface_inconsistency`
- Orden por defecto: más críticas primero

### 4. `UppDetailComponent`
Detalle de una unidad: datos de identificación, superficie (con el manejo correcto de
"no disponible"), último censo declarado, y ubicación. Sin edición.

### 5. Rutas
Lazy loading en `app.routes.ts` bajo `/cumplimiento`, protegidas por `authGuard`.
Agregar la entrada correspondiente en el `SidebarComponent`, visible solo cuando el tenant
activo sea del dominio ganadero (revisar cómo lo resuelve hoy el Context Switcher).

---

## Criterios de aceptación

- [ ] `ng build agro-erp --configuration=production` compila sin errores ni warnings nuevos
- [ ] El listado muestra 3 UPP; las dos de Chiapas en rojo (`EXPIRED`), San Pedro en gris (`UNKNOWN`)
- [ ] Santa Lucía muestra el badge de inconsistencia de superficie
- [ ] Ninguna UPP muestra "0 ha" de pastoreo; muestran "No disponible"
- [ ] El orden por `active_head_in_system` es numérico, no lexicográfico
- [ ] Con la API caída, la UI degrada con mensaje claro y no lanza `TypeError`
- [ ] Una respuesta con `error: true` se presenta al usuario, no se traga en silencio
- [ ] Sin uso de `localStorage`/`sessionStorage` para estado del módulo
- [ ] Sin cálculos derivados que debieran venir del servidor

---

## Qué NO hacer

- No crear migraciones ni tocar `crud_models`
- No implementar alta/edición de UPP, PSG ni carga de documentos
- No implementar reconciliación censo vs inventario (bloqueada por decisión del cliente)
- No recalcular en cliente nada que la vista ya devuelva computado
- No inventar endpoints: solo los 4 modelos listados existen
- No modificar `agro-registry.model.ts` para que "cuadre" con los strings de la API — el mapeo
  va en el servicio

---

## Verificación manual de la API

Para inspeccionar respuestas reales durante el desarrollo (requiere JWT válido):

```bash
curl -s -X POST "$API_CRUD/upp_compliance_status" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $JWT" \
  -d '{"entity":"upp_compliance_status","table_name":"vw_upp_compliance_status","operation":"getall","filters":{}}'
```
