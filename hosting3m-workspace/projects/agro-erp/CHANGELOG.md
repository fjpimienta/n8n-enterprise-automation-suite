# Changelog

Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.
El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [Unreleased]

### 🔒 Palma, fase 2b, etapa 1: el chat de ganadería rechaza empresas de palma (migración 082) — en desarrollo, sin desplegar

*Versión por asignar al desplegar. Runbook: `database/migrations/082_RUNBOOK.md` (orden estricto base → n8n).*

**Incidente (producción, 2026-10-21):** con la empresa 10 (palma, de pruebas) activa, el Chat Web llamó a
`register_ranch_expense` con `tenant_id: 10` y guardó en `cattle_expenses` el gasto
`3f294c48-c509-42bd-8d3e-2dcfdf6b7913` ($1,300, "MANTENIMIENTO"). La empresa 7 (cliente real de palma) estaba expuesta a
lo mismo. **Ese gasto se conserva como evidencia** del incidente (decisión del dueño, 2026-10-23); es de la empresa de
pruebas.
* Migración 082: `fn_reject_palm_company(id_company)` (`STABLE`) lanza `P0094` ("Esta empresa es de palma; usa el
  registro de palma…") para empresas de palma (`fn_company_business_domain`, 081) y devuelve `true` en cualquier otro
  caso. Rollback sin DROP: la deja devolviendo `true`.
* `v6/MCP Server Cattle`: 26 de 29 tools la llaman como primera condición del `WHERE` de la sentencia que lee o
  escribe (plan con `One-Time Filter`: se evalúa antes de cualquier fila). `log_cattle_weight` / `log_health_event`
  usan la empresa del animal. Sin tocar: `get_table_metadata` (prohibida por el prompt) y las dos de órdenes de venta
  (no reciben empresa; una empresa de palma no tiene animales).
* Chat Web y WhatsApp: el dominio de la empresa entra al contexto verificado (`Resolver Empresa Chat`;
  `Get User Role` + `Resolver Tenant`). Con una empresa de palma el workflow **no llama al agente**: un IF
  `Es Empresa de Palma` responde un mensaje fijo (Chat Web: `Respond Empresa Palma`, `code: PALM_COMPANY`; WhatsApp:
  `Set - Mensaje Empresa Palma` → `Send Message Tenant`). Se queda además la regla "🌴 EMPRESA DE PALMA" en ambos
  prompts. Provisional hasta el agente de palma de la etapa 2, que reemplaza este IF por el `Switch`.
  Motivo del IF: en LOCAL, con solo la regla del prompt, el modelo la siguió en 1 de 3 mensajes (pidió la categoría
  del gasto y filtros para contar animales).
* Con el IF en medio, las expresiones `$('Nodo').item` del agente y de su memoria dejaron de resolverse cuando el agente
  vuelve después de una tool ("Key parameter is empty" en `Simple Memory`, "No prompt specified" en `AI Agent`). En
  Chat Web y WhatsApp pasan a `.first()` (cada ejecución procesa un solo mensaje).
* `node_fingerprints.py`: cubre tools, `systemMessage`, tipo de endpoint MCP, ruta MCP y credenciales de las tools; la
  salida de los workflows ya cubiertos no cambia.
* Pruebas LOCAL (2026-10-21): `082_tests.sql` 11/11; SQL real de las 26 tools con empresa 10 → 26/26 `P0094`, con
  empresa 3 → ninguna rechaza; lecturas de ganadería con datos reales idénticas a `main` (mismo md5).
* Prueba por Chat Web en LOCAL (2026-10-23, webhook real `v6/ai/chat-cattle`, ADMIN de las empresas 10 y 3):
  empresa 10 → el gasto de la bomba ($1,300), "¿Cuántos animales hay?" y un intento de forzar
  `register_ranch_expense` reciben el mensaje fijo en 0–2 s (`PALM_COMPANY`, sin pasar por el agente); ninguna fila
  nueva en `cattle_expenses` ni en `agri_expenses`. Empresa 3 (con el arreglo de `.first()`) → "¿Cuántos animales hay
  en total?" (30, por la tool `count_livestock`), "¿Y de esos cuántos son becerras?" en la misma conversación (5: la
  memoria funciona después de una tool) y el arete `9999000007` (becerro, UPP Testing, lote La Tuza); ningún error en
  `n8n_error_logs`. Antes se repitió con la imagen local de n8n reconstruida (un archivo corrupto rompía la CLI) y con
  el DNS del contenedor corregido (no resolvía nombres externos tras un apagado brusco del equipo).

### 🌴 Palma, fase 2a: gastos agrícolas (migración 081, `v6/CRUD` y frontend) — v1.19.0

*Incluye la migración 081, `v6/CRUD` (`spConfigByModel` y la corrección de fechas de abajo) y el frontend (pantalla
"Gastos" y tarjeta "Gasto del mes"). Runbook: `database/migrations/081_RUNBOOK.md`. PR #833.*

✅ **Desplegada en producción el 2026-10-20 (CDMX).**
* ⚠️ **El frontend llegó a `main` antes que la base de datos** (segunda vez, tras v1.18.0 el 2026-10-17); la base y
  el `v6` se completaron de inmediato. Desde entonces cada runbook abre con el recuadro "⛔ NO MERGEAR A `main`"
  (regla en el `CLAUDE.md` raíz, sección "Despliegue").
* Base de datos: respaldo `hosting3m_db_pre081_20261020_1057.dump` (956K); `081_state_check before` OK, con las 5
  huellas iguales a las de LOCAL; dry run OK; `081_tests.sql` 72/72; `081 COMMITTED` (empresa 10 → 13
  categorías); `081_state_check applied` OK, con las mismas huellas.
* n8n `v6/CRUD`: antes `versionId` `59010f50…`, Build Query `856b743c…`; después `versionId` `c8bb4fe0…`, Build
  Query `92fd290c…`, `Normalize Data` `b7741e5e…` sin cambio.
* Pruebas de pantalla en producción (empresa 10: tablero, captura, balance, anulación y ganadería): **pendiente de
  registrar el resultado.**

* `agri_expenses`: gasto general, por plantación o por lote; categoría del catálogo de la empresa, fecha (no
  futura en CDMX), monto, cantidad y unidad, proveedor, descripción, factura y folio. Nunca se modifica ni se
  borra: se anula con motivo (`sp_agri_void_expense`, ADMIN/OWNER).
* Captura solo por `sp_agri_record_expense` (ADMIN, OWNER y EDITOR; solo empresas de palma); quien captura sale
  del JWT. Los montos los leen solo ADMIN/OWNER (`vw_agri_expense_list`, `vw_agri_expense_summary`,
  `sp_agri_expense_balance`).
* Catálogo de categorías por empresa (13 iniciales, al crear la primera plantación; la 081 solo siembra las
  empresas que ya tienen plantación) y catálogo global de unidades de solo lectura.
* `fn_company_business_domain`: dominio de la empresa en SQL, con la misma regla del frontend.
* Pruebas LOCAL 2026-10-20: `081_tests.sql` 72/72, `080_tests.sql` 74/74 y dry run. Ciclo completo con
  `apply=true` en LOCAL (before → apply → applied → rollback → rolled_back → re-apply → applied): todos los
  `state_check` OK y las 5 huellas iguales en cada paso (`other_crud_models` `7afa6009…`, `companys_data`
  `7e9456ec…`, `user_companies_data` `d90a7e1c…`, `agri_structure_data` `2535f38d…`, `cattle_expenses_data`
  `e34148ef…`). LOCAL queda con la 081 aplicada.
* Pruebas `curl` contra el `v6` de LOCAL (Build Query `92fd290c…`), 2026-10-20, todas OK:
  * ADMIN (C1–C13): catálogos; captura con monto número/texto y actor del JWT aunque el cliente mande otro; lote
    sin plantación; `""` en uuid y `"10,000"` → `error:true` (el frontend manda `null` y montos sin comas);
    P0080/P0083/P0092/P0093; empresa sin membresía → 403; balance, lista y resumen; anulación;
    `insert`/`update`/`delete` genéricos → 403; categorías por CRUD genérico con clave inmutable.
  * EDITOR `qa-editor-palma@example.test` (C14): captura (respuesta sin monto; `reported_by_email` del JWT) y lee
    categorías y unidades; recibe 403 al listar gastos, leer el resumen o el balance, anular y crear categorías.
  * `v5` (C15): el nodo `Model Allowlist` rechaza los 7 modelos de la 081 (`MODEL_NOT_ALLOWED`).

### 🐛 `v6/CRUD`: filtros de texto con "T" tratados como fecha — v1.19.0

*Cambio solo en el nodo `Build Query` del `v6`; ningún otro nodo cambia.* En el `getall`, un valor de filtro se
consideraba fecha si contenía una `T` mayúscula (`includes('T')`): la columna se convertía a `date` y el valor se
cortaba en la `T`. Cualquier filtro de texto con `T` fallaba con `invalid input syntax for type date`
(`grain: 'MONTH'` llegaba como `'MON'`; también `unit_code: 'TON'` o `current_status: 'ACTIVO'`). El cliente
recibía `error:true`. Encontrado en las pruebas `curl` de la 081 (C10b). Ahora solo es fecha un valor que cumple
exactamente `AAAA-MM-DD` o `AAAA-MM-DDThh:mm[:ss[.fff]][Z|±hh:mm]` (regex anclada), en la rama de operadores
(`_gte`/`_lte`/…) y en la de igualdad.

Huellas del `Build Query`: producción (v1.18.1) `856b743c27c3dabb10d2a3b5fcb00b18` → con la 081
`aa741446695d6438d1e30f8383bbc767` → con esta corrección **`92fd290c2aa41ce57c24e750def90a0b`** (publicada en el
n8n LOCAL, `n8n_db_prod_clone`, y en producción el 2026-10-20, junto con la 081).

Verificado en LOCAL por `curl` (2026-10-20, ADMIN, 7/7): `agri_expense_summary` con `grain: 'MONTH'` y `'WEEK'`;
`agri_expenses` con `unit_code: 'TON'`, con fecha simple, con `_gte`/`_lte` y con fecha ISO con hora y zona
(`…T00:00:00-06:00`, `…T23:59:59.999Z`), que se siguen tratando como fecha; y `vw_cattle_kpi` de la empresa 3
con `current_status: 'ACTIVO'` (21 animales, antes fallaba).

### 🧪 Migración 080: verificaciones independientes de objetos `agri_*` posteriores — v1.19.0

*Sin cambio en ninguna DDL ni en ningún dato que crea la 080: solo cambian sus verificaciones.* Contaban los
triggers con `LIKE 'trg_agri_%'` y los modelos con `LIKE 'agri\_%'`, así que fallarían con la 081 aplicada
(agrega 5 triggers y 7 modelos `agri_*`). Ahora cuentan por nombre los 9 triggers y los 10 modelos de la 080.
Verificado en LOCAL: `080_tests.sql` 74/74 y `080_state_check.sql -v expect=applied` OK, y la 080 se vuelve a
aplicar sin error con la 081 cargada.

| Archivo | md5 en producción / `main` | md5 nuevo |
|---|---|---|
| `080_agri_structure.sql` | `b47cc5971d7db09f7fdcb7c27074faab` | `3f9b1aade997787b5bbce30109e0d5cb` |
| `080_state_check.sql` | `4e45ffb9f21c71b415a146739230feb3` | `25d5aa29f7407a9db397eb6b56277f2b` |
| `080_tests.sql` | `f700ccb6174ad5dcfa1a18f797b5039c` | `e545f93d3a2e39ce6c7d126b2fe4fbda` |

### 🔒 Public Booking Engine (B2C): parámetros como arreglo, filtro por empresa y huésped existente intacto — v1.18.3

*Workflow de n8n únicamente (`v4/Public Booking Engine (B2C)`, `FImcPayB8gqFlxwq`); sin migración ni frontend.
Probado en LOCAL el 2026-10-17. Runbook y huellas en `workflows/08-public-booking-engine/v4/README.md`.*

✅ **Desplegada en producción el 2026-10-17 y verificada el 2026-10-19 (CDMX)**, importada desde el editor: activa,
nodos iguales a `main`, webhooks sin cambio (`public/availability`, `public/lead`); respaldo previo guardado.
* Disponibilidad: responde los 4 tipos de habitación del hotel (consulta nueva, filtrada por empresa).
* Reserva de prueba por `public/lead` con nombre `Prueba, QA`, sin teléfono y el correo del operador:
  `{"status":"success","booking_id":1409}`; en la base, `full_name` completo con la coma, sin teléfono,
  `pending`, `check_in` 2027-02-10 00:00 UTC. Cancelada después desde el `dashboard`.
* Un primer intento sin `name` falló en `Upsert Guest & Book` (`n8n_error_logs` 1779, registrado por el
  handler) y respondió HTTP 200 vacío: falta validar campos obligatorios (deuda en el `CLAUDE.md` raíz).
* 0 errores del booking engine entre el despliegue y la verificación.

**Origen:** los nodos `Check Availability SQL`, `Get Specific Room SQL` y `Upsert Guest & Book` usaban
`queryReplacement` como texto; n8n lo parte por comas y descarta los vacíos. Es un endpoint público que escribe
datos personales.

**Repo sincronizado con producción:** el export del repo tenía otro id de workflow
(`zTVZqQbvOS-WsyXdOQdET`) y otra credencial SMTP. Los nodos, consultas y conexiones eran iguales al export vivo,
que ahora reemplaza al del repo antes del cambio.

**Cambios:**
* `queryReplacement` como arreglo, cada valor con `String(...)` (`null`/`undefined` → `null`) y casts explícitos
  en las tres consultas (`$n::text`, `::date`, `::int`). Teléfono vacío → `NULL`.
* `id_company` sale de un solo nodo (`Site Config`, valor `1`) y las consultas de `hotel_rooms` y
  `hotel_bookings` filtran por él. Antes no filtraban: en LOCAL, una petición con `room_type` recorrido reservó
  una habitación de otra empresa.
* `ON CONFLICT (email)` ya no sobrescribe el teléfono (ni nada) del huésped existente; solo recupera su id.
* `room_type` por igualdad exacta (`type = $3::text`) en vez de `ILIKE $3 || '%'`. `hotel-website` devuelve el
  `type` exacto de la respuesta de disponibilidad.

**Pruebas (n8n LOCAL, arneses con rutas propias, empresa 3, `Send Email` desactivado y sin `errorWorkflow`):**
* Versión anterior: nombre con coma → `invalid input syntax for type integer: "<correo>"`; teléfono vacío o
  ausente → `there is no parameter $7`. **No se escribe nada y el sitio muestra éxito** (la ejecución fallida
  responde HTTP 200 vacío). Un `room_type` con coma reservó otro tipo; un correo existente sobrescribió el
  teléfono.
* v1.18.3, dos corridas completas: nombre con coma, teléfono vacío y ausente (`NULL`), comillas y `$1`/`DROP
  TABLE` como texto, acentos, 28→29 de febrero, salida y entrada el mismo día, traslape con reserva
  `confirmed` (409), habitación inexistente (409), tipo de otra empresa (409), `room_type` con coma (409),
  correo vacío (400), correo existente (teléfono intacto, mismo huésped). Todas las filas con empresa 3 y
  habitación de la empresa 3. Fecha vacía en disponibilidad → error de `date` (antes, `there is no parameter $2`).
* `room_type`: con `ILIKE`, `%`, `QA%`, `QA_Doble`, `qa sencilla` y el prefijo `QA` reservaron; por igualdad
  exacta dan 409 y los tipos exactos reservan. Tercera corrida completa de la batería sin cambios en el resultado.
* Consultas para producción (README) validadas en LOCAL: conteos de campos recorridos (0 en los datos
  históricos) y ejecuciones fallidas con su nodo, sin texto del error.

### 🔒 Global Error Handler: parámetros como texto y alerta primero — v1.18.2

*Workflow de n8n únicamente (sin migración ni frontend). Corrige v1.17.2, que se desplegó y se revirtió en
producción el 2026-10-17. Huella del nodo SQL: `1f72bc10…` (producción hoy) → `1dac24ed…`.*

✅ **Desplegada en producción el 2026-10-17 (CDMX)**, importada desde el editor: handler activo, nodos Alerta y
SQL idénticos a `main`, Alerta arriba del SQL. "Execute workflow" con los datos de ejemplo del Error Trigger
(`execution_id` numérico): alerta recibida solo con Falló / Nodo / Link, y la fila de prueba 1773 en
`n8n_error_logs` (`Example Workflow`, `'231'`).

**Origen:** al probar v1.17.2 en producción con "Execute step", el nodo `Execute a SQL query` falló con
`invalid input syntax for type integer: ""`. Con un `queryReplacement` de tipo arreglo, n8n pasa cada valor con
su tipo de JS y pg-promise arma la consulta del lado del cliente: un número entra sin comillas, así que el
`execution.id: 231` de los datos de ejemplo del Error Trigger dejó `NULLIF(231, '')`. Además, con
`executionOrder: v1` la rama SQL (más arriba en el lienzo) corría antes que la alerta, y un `INSERT` fallido
detenía la ejecución **sin enviar la alerta**. La validación de v1.17.2 había sido un `SELECT` preparado, nunca
una ejecución real del nodo.

**Cambios:**
* La consulta usa `$1::text … $4::text` y el `queryReplacement` convierte cada valor con `String(...)` (objetos
  a JSON, `null`/`undefined` a `null`).
* La alerta queda arriba del nodo SQL en el lienzo: sale primero, y con `continueRegularOutput` nunca bloquea el
  registro.
* El resto de v1.17.2 se conserva: URL desde `$env.NTFY_ALERT_URL`, alerta sin el texto del error, `INSERT`
  parametrizado y recortado al tamaño de cada columna.

**Pruebas (n8n LOCAL, ejecutando los nodos):**
* Con los nodos de `main` (v1.17.2), el caso numérico reproduce el error y la alerta no sale.
* Con v1.18.2, un arnés con los mismos nodos del handler (Manual Trigger + payload del Error Trigger) cubrió
  5 casos: `execution.id` numérico (los datos de ejemplo exactos), vacíos, nulos, campos ausentes, y comillas
  con `$1` y `DROP TABLE` como texto y longitudes de más de 255. Cada caso escribió su fila (vacíos y nulos
  → `(desconocido)`/`(sin id)`/`(sin mensaje)`; recorte a 255/100/255) y envió su alerta a un tema de prueba.
* El handler real, activo, como `errorWorkflow` de un webhook que falla: la fila llegó con `execution_id`
  en texto y la alerta llegó.

**Hallazgo pendiente, sin cambiar:** ntfy recibe el cuerpo JSON completo como texto del mensaje y no aplica
la prioridad `high` (el JSON se publica en la URL del tema, no en la raíz).

### 🔒 Upsert del `insert` acotado por empresa (`v6/CRUD`) y "Nueva Empresa" oculta — v1.18.1

*Workflow `v6/CRUD` y frontend; sin migración. Probado en LOCAL el 2026-10-17. Huellas: Build Query
`0aedcb74…` → `856b743c…`, Normalize Data `05153e7f…` → `b7741e5e…`; los demás nodos no cambian.*

**Origen:** el `insert` de `v6` es un upsert (`ON CONFLICT (pk) DO UPDATE SET …`) y su `SET` incluía la
columna de tenant. Un `insert` con el `id` de un registro de otra empresa (cualquier modelo con la PK en
`allowed_fields`, columna de tenant e `INSERT`: 36 modelos, p. ej. `cattle_livestock`, `production_units`,
`cattle_expenses`) lo sobrescribía **y lo pasaba a la empresa de quien llamaba**. Aparte, en `companys` el
`id_company` es PK y columna de tenant a la vez: el Build Query le inyectaba el header y "Nueva Empresa"
sobrescribía la empresa **activa** en vez de crear una.

**Cambios:**
* **Build Query (`insert`):** las columnas de tenant ya no entran al `DO UPDATE SET`; en modelos con columna
  de tenant el `DO UPDATE` lleva `WHERE <tabla>.<tenant> = EXCLUDED.<tenant>` (siempre la empresa del header)
  y exige el header. Un `id` de otra empresa ya no toca nada.
* **Normalize Data:** ese `insert` acotado que no devuelve filas responde `error:true` ("No se guardó el
  registro: el identificador no es válido para la empresa activa."). Los caminos `DO NOTHING` (`users`, de la
  073, e inserts solo con PK) conservan su contrato (`error:false`, 0 filas).
* **`companys`:** en `insert` el `id_company` nunca se inyecta ni se acepta, y la sentencia es un
  `INSERT … RETURNING *` simple (el id sale de la secuencia).
* **Frontend:** "Nueva Empresa" queda oculto en `/admin/tenants` (`canCreateCompany = false`, también en
  `openModal()`) hasta que exista el administrador de la plataforma (Usuarios y Accesos fases 1–2, migraciones
  075–079). Mientras tanto, las empresas nuevas se crean con un script tipo seed (dry run por default, como
  `080_qa_palm_tenant_seed.sql`).

**Pruebas (LOCAL):** harness fuera de línea con las configuraciones reales de `crud_models` (SQL antes/después);
`EXPLAIN` sin `ANALYZE` en transacción de solo lectura para cada forma nueva; `curl` contra el `v6` LOCAL: `insert`
con el `id` de un registro temporal de la empresa 6 desde la 3 → `error:true` y la fila sin cambios (md5);
`insert`, upsert y `update` de la misma empresa funcionan; "Nueva Empresa" con `id_company: 3` en el body crea
una empresa nueva y deja la 3 sin cambios (md5); regresiones de `agri_lots`, `production_unit_lots` y `users`
(`DO NOTHING`) en verde. Los registros de prueba quedaron desactivados, no borrados. Build de producción sin
errores; Vitest 176/176.

### 🌴 Palma, fase 1: plantaciones, lotes y filas (migración 080) — v1.18.0

*Base de datos y `v6/CRUD` (Build Query: solo `spConfigByModel`). Aplicada y probada solo en LOCAL
(2026-10-17). El frontend va en la misma rama (ver abajo). El hotfix del upsert de `v6` pasa a v1.18.1.*

⚠️ **Despliegue fuera de orden (2026-10-17):** el frontend se publicó en producción antes que la base de datos y
el `v6`; mientras tanto las pantallas de palma mostraban "El servidor no confirmó la operación" (los modelos
`agri_*` no existían) y ganadería siguió funcionando. El orden correcto es **base de datos → n8n → frontend**
(misma lección que v1.17.0, Regla 16).

**Frontend (`agro-erp`):**
* Detección de dominio centralizada en `@shared/utils/business-domain.util` (layout, sidebar, selector de
  empresa y login); el login, la raíz y las URLs desconocidas llevan al dashboard del dominio. Se quitó el
  link roto `/agricultura/telemetria`.
* `PlantationContextService` y selector de plantación junto a la empresa (última elección por empresa →
  predeterminada → otra activa; fail-closed; `localStorage` por empresa con try/catch; el cierre de sesión
  limpia el contexto).
* Pantallas: Plantaciones (ADMIN/OWNER), Lotes de la plantación activa, Filas (alta individual y masiva por
  SP, conteo con motivo para ADMIN/OWNER/EDITOR, cambio de puntos solo ADMIN/OWNER, historial) y Tablero de
  Palma de solo lectura. Guards locales por el rol de la empresa activa (`roleGuard` de `core-auth` intacto).
* Specs de Vitest standalone para las utilidades puras; `ng build agro-erp --configuration=production` sin
  errores. Probado a mano en LOCAL con la empresa 10 como ADMIN y como EDITOR (2026-10-17).


**Jerarquía:** Empresa → Plantación (≈ UPP del dominio palma) → Lote → Fila, con conteo de plantas por
fila. Varias plantaciones por empresa; plantas individuales, pagos, inventario, cosecha y alcance por
usuario son fases posteriores.

**Base de datos (migración 080, aditiva e idempotente, dry run por default, rollback sin DROP/DELETE):**
* Tablas `agri_variety_catalog` (global, con semilla), `agri_plantations`, `agri_lots` (tenencia propia
  opcional; si no, hereda la de la plantación), `agri_rows` y `agri_row_census_history` (solo inserción).
* Aislamiento fail-closed por `id_company`: triggers con mensajes que no revelan la otra empresa y
  llaves foráneas compuestas `(padre, id_company)`; padre e `id_company` inmutables; nada se crea ni se
  reactiva bajo un padre inactivo; nada se borra físicamente.
* Una plantación predeterminada activa por empresa (la primera es automática; después solo con
  `sp_agri_set_default_plantation`).
* `sp_agri_bulk_create_rows` (también para una sola fila) y `sp_agri_record_row_census`, único camino
  para `alive_plants` (ADMIN, OWNER, EDITOR) y `planting_positions` (ADMIN, OWNER), con historia
  automática de motivo y actor; un `CENSO` que confirma los mismos números también queda registrado.
* Vistas `vw_agri_lot_summary` (edad, etapa productiva **orientativa, pendiente de confirmar con el
  cliente**, tenencia efectiva, densidades, faltantes) y `vw_agri_plantation_summary` (área sembrada y
  bandera de inconsistencia).
* 10 modelos `agri_*` en `crud_models`, ninguno con `id` en `allowed_fields` (el upsert del `insert`
  nunca alcanza un registro existente) ni con `DELETE`. `PalmTelemetry` pierde `DELETE` y deja `UPDATE`
  solo para ADMIN.
* Códigos de error `P0080`–`P0089`.

**Gateway (`v6/CRUD`):** los 3 procedimientos registrados en `spConfigByModel` (tenant primero, actor
siempre desde el JWT).

**Empresa de pruebas de palma:** `080_qa_palm_tenant_seed.sql` crea "Plantación de Pruebas" (LOCAL:
`id_company = 10`) con ADMIN para el dueño del proyecto. Todo lo que cuelga de ella es dato de prueba;
la empresa 7 es cliente real.

**Pruebas (LOCAL):**
* `080_tests.sql`: 73 de 73 OK, todo revertido. `apply` → `applied` → rollback → `rolled_back` →
  re-apply → `applied`, con huellas idénticas en cada paso.
* `curl` contra `v6` LOCAL con la empresa 10: plantaciones (la primera queda predeterminada; el `id`
  del cliente se ignora), cambio de predeterminada por SP, lotes, filas por SP, conteos por SP (el actor
  sale del JWT aunque el cliente mande otro), `getone`/`update` por `id`, vistas.
* Aislamiento en ambos sentidos entre las empresas 3 y 10: lecturas vacías, escrituras con `error:true`
  y sin cambios en la base; sin membresía o sin header → 403. `v5` no atiende ningún `agri_*`.

### 🔒 Global Error Handler: URL de ntfy fuera del repo e `INSERT` de errores parametrizado — v1.17.2

⚠️ **Desplegada y revertida en producción el 2026-10-17:** el `INSERT` fallaba con un `execution.id` numérico
y la alerta no salía. Se corrigió en v1.18.2 (arriba).

*Workflow de n8n + una variable en `.env`; sin migración ni frontend. Se despliega **después** de la
contención de `v5/CRUD` (v1.17.1).*

**Origen:** el Global Error Handler (`9SrVXdATmlrZemJT`, `errorWorkflow` de `v5`/`v6` y otros, activo en
producción) publicaba los errores en un tema público de ntfy.sh, con el texto crudo del error (un error
de Postgres puede traer valores de filas). El 2026-10-17 el dueño lo **mitigó a mano en producción**:
tema nuevo aleatorio y alerta sin `error_message`. Este cambio versiona esa versión de producción y la
termina de corregir.

**Cambios:**
* La URL del tema ya no vive en el JSON: el nodo de alerta usa `={{ $env.NTFY_ALERT_URL }}`, definida
  en `infrastructure/.env` (no versionado) de `n8n.hosting3m.com/n8n-compose`.
* La alerta conserva el mensaje de producción (workflow, nodo y link; nunca el texto del error) y ya
  no bloquea el registro: `onError: continueRegularOutput`, así que si falta la variable o ntfy no
  responde, la fila en `n8n_error_logs` se escribe igual.
* `INSERT INTO n8n_error_logs` con parámetros (`queryReplacement`) en vez de interpolar escapando solo
  comillas; seguro ante nulos/vacíos (`workflow_name`, `execution_id` y `error_message` son `NOT NULL`;
  antes un `failed_node` o `error_message` ausente hacía tronar el `.replace()`) y recortado al tamaño
  de cada columna. `created_at` toma el `now()` de la base.
* El JSON del repo (de enero, con un nodo `Insert rows in a table` que ya no existía) se reemplaza por
  el export real de producción con estos cambios.
* `workflows/00-global-error-handler/README.md`: configuración de `NTFY_ALERT_URL` y propuesta (no
  implementada) de tema protegido con token de acceso en una credencial Bearer de n8n.

**Validación (LOCAL, solo lectura):** las expresiones del `INSERT` probadas con un `SELECT` preparado:
nulos, vacíos, comillas/`DROP TABLE` como texto literal y recorte a 255/255/100.

**Deuda documentada:** `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` deja a cualquier workflow leer todas las
variables de entorno de n8n (incluido `INTERNAL_SECRET`); no se cambia porque `GenerateToken` depende de
ello.

### 🔒 Contención de seguridad del gateway `v5/CRUD` y `companys` pública — v1.17.1

*Workflows de n8n únicamente (sin migración ni frontend). Probado en LOCAL el 2026-10-17; la fecha de
liberación se fija al importar en producción. La regla WAF de Cloudflare para `crud/v5/` ya está activa.*

**Origen:** al revisar el hotfix del upsert de `v6` se confirmó que el `dashboard` del hotel y
`hotel-website` no usan `v6/CRUD` sino `v5/CRUD`, todavía activo en producción y sin ninguno de los
endurecimientos de `v6` (sin membresía, rol del JWT, header de tenant opcional). Sobre el export de
producción (`versionId 32719959-…`) se confirmó en el código:
* **Inyección SQL como superusuario:** `Get Model Config` y `Get` interpolaban el nombre del modelo;
  `Build Query` pegaba `sort_by` en el `ORDER BY` y el primer campo del `getone` en el `WHERE`. La
  ruta pública de `companys` llegaba a `sort_by` **sin token**.
* **El body podía reemplazar el modelo de la URL** (`Get Model Name` hacía el spread después de
  `model_name`), lo que también saltaba cualquier filtro por URL.
* **Registro automático de tablas:** un modelo inexistente se registraba en `crud_models` con todas
  las operaciones (rama falsa de `ModelExist` → OpenAI → `INSERT`). Sin evidencia de que haya pasado
  en producción (revisado por el dueño).
* **Cualquier modelo de `crud_models` era alcanzable por `v5`**, incluidos ganado, `users`,
  `livestock_producers_pii` (CURP/RFC descifrados) y `employee_credentials`.
* **`companys getall` público devolvía `companys.*`** (`metadata`, notas, ingresos) en `v5` y `v6`.

**Cambios (`v5/CRUD`):**
* Nodos nuevos `Model Allowlist` + `Is Allowed Model`, justo después de `Get Model Name` y antes de
  `If`/`Verify Token`/`Get Model Config`: solo pasan los 9 modelos del hotel (`hotel_guests`,
  `hotel_bookings`, `hotel_reviews`, `hotel_expenses`, `hotel_rooms`, `hotel_room_inspections`,
  `hotel_maintenance_tickets`, `hotel_assets`, `hotel_capital`; la misma lista que la regla WAF).
  Todo lo demás → HTTP 404 `MODEL_NOT_ALLOWED`, sin tocar la base.
* `Get Model Name`: la URL siempre gana sobre el body; la lista blanca además exige que coincidan.
* `Get Model Config`: parámetro enlazado (`model_name = $1`) en vez de interpolación.
* La rama falsa de `ModelExist` responde 404 `MODEL_NOT_FOUND`; el registro automático queda
  desconectado (no borrado). `Get` (`information_schema`) quedó inalcanzable y no se modificó.
* `sort_by` y el campo de búsqueda de `getone` solo aceptan identificadores simples (misma regla que
  `v6`).

**Cambios (`v5/CRUD` y `v6/CRUD`):** `companys getall` devuelve solo `id_company` y `company_name`,
ignora cualquier filtro salvo `id_company` y ordena siempre por `company_name`.

**Sin cambios a propósito:** el aislamiento por empresa, el upsert, el `update` y el `delete` de `v5`
(van con la migración del hotel a `v6`); `Insert Logs` (no alcanzable: ningún modelo tiene
`hooks.post`); el `call_sp` de `v5` (no alcanzable: ningún modelo tiene `CALL_SP`).

**Efecto conocido:** la **pantalla de usuarios del `dashboard` del hotel queda sin servicio** (`users`
bloqueado en `v5`) hasta migrar el hotel a `v6`. `pista-hielo` queda marcado como **legacy, fuera
de uso**; sus modelos (`ph_*`, `transactions`) ya no pasan por `v5`.

**Pruebas en LOCAL (2026-10-17, `localhost`, token de un ADMIN del tenant 3):**
* `v5`: `cattle_livestock`, `companys`, `users`, `livestock_producers_pii`, `employee_credentials`,
  `crud_models`, `ph_clients`, `transactions` y un modelo inexistente → 404 `MODEL_NOT_ALLOWED`;
  en ninguna de esas ejecuciones corrió un nodo de Postgres.
* `v5` `hotel_rooms`: `getall` normal y con `sort_by` válido → 200 con datos; `sort_by` con comilla o
  subconsulta y `getone` con campo inválido → rechazados en `Build Query`, sin ejecutar SQL (responden
  HTTP 200 con cuerpo vacío, comportamiento previo de `v5` ante un error); `"model_name": "users"` en
  el body → devuelve habitaciones, no usuarios.
* `v6`: `companys getall` sin token → 9 filas con solo `id_company`/`company_name`, aun con filtros
  sobre `metadata`; `livestock_producers_pii` con header del tenant 3 → 0 productores de otras
  empresas (también con filtro `id_company=5` y con `getone` del id de un productor de la empresa 5).

**Deuda nueva** (detalle en el `CLAUDE.md` raíz): migrar el hotel a `v6` (`hotel_guests` → `users` →
resto); errores de producción publicados en un tema público de ntfy.sh; `dashboard`/`hotel-website`
apuntan a producción en dev; modelos y datos de `pista-hielo` en la base; modelos con PII sin
consumidor; `sp_upsert_producer_pii` sin tenant.

### 🧾 Órdenes de venta: una sola orden para muchos animales, varias UPP y varias empresas (migración 074) — v1.17.0

*La base de datos (074 + alta de 38 animales) y los workflows de n8n se aplicaron en producción el
2026-10-16 (22:00 CDMX), con respaldo previo; la fecha de liberación se fija al desplegar el frontend.*

**Origen (petición del propietario, 2026-10-16):** la venta real se hace por **orden**, no por animal:
el capataz o cualquier trabajador con acceso pide la venta de "los 30 becerros del lote Maceo" o de
"8 hembras" de dos UPP distintas, y solo los ADMIN autorizan. Reglas confirmadas:
* Puede solicitar cualquier miembro con rol de escritura (ADMIN o EDITOR) de la empresa del animal,
  **sin importar la UPP o el lote**; "Solo lectura" (`CUSTOMER`) no puede.
* Solo un ADMIN de la empresa del animal autoriza (sin cambios desde 069/071).
* Una guía de tránsito por grupo de UPP de origen.
* Un correo por orden **y por empresa** (antes era uno por animal).

**Base de datos (migración 074, aditiva e idempotente, con rollback sin DROP/DELETE y 17 pruebas):**
* `sale_orders`: encabezado de la orden (`order_code` `OV-000001`, solicitante, fecha de venta, canal).
  Abarca empresas; **nunca se expone por el gateway**. Los números pueden tener huecos (la secuencia
  no se reutiliza tras un `ROLLBACK`); no es folio fiscal — el folio va en `folio_factura` al aprobar.
* `pending_authorizations.sale_order_id` (FK opcional, indexada). Las solicitudes de un solo animal
  siguen igual.
* `sp_solicitar_venta_orden(items, email, fecha, preview, canal)`:
  * dos tipos de renglón: un animal `{"identificador","guia_transito"}` o un **lote completo**
    `{"lote","categoria"?,"cantidad"?,"guia_transito"}` que la base expande a sus animales disponibles;
    si `cantidad` no coincide, el renglón falla ("El lote Maceo tiene 30 animal(es) BECERRO disponibles, no 29");
  * busca cada animal solo en las empresas donde el solicitante es ADMIN/EDITOR y crea cada solicitud
    **en la empresa del animal**, ligadas por la orden;
  * `preview = true` no escribe y agrupa por empresa / UPP / guía; `preview = false` es **todo o nada**;
  * bloquea los animales (`FOR UPDATE`) y re-valida antes de insertar;
  * cada solicitud lleva `orden_venta`, `orden_total_animales` y `orden_total_empresas` (solo conteos,
    nunca identidades de otra empresa).
* **Una sola solicitud PENDIENTE por animal, de cualquier tipo:** trigger
  `trg_pending_auth_one_pending_guard` (mensaje legible, código P0036, cubre también
  `sp_solicitar_autorizacion` sin modificarlo) + índice único parcial
  `uq_pending_auth_one_pending_per_animal`. Una venta pendiente se cancela antes de reportar una mortandad.
* `pending_authorizations.notified_at` queda versionada; `crud_models.pending_authorizations` += `sale_order_id`.
* Códigos: P0031 sin membresía, P0032 orden vacía/>300, P0033 fecha futura, P0034 orden rechazada,
  P0035 solo lectura, P0036 animal con solicitud pendiente, P0037 órdenes deshabilitadas (rollback).

**Agente IA (`v6/MCP Server Cattle`, Chat Web y WhatsApp):**
* Tools nuevas `preview_livestock_sale_order` (siempre primero, solo lectura) y
  `request_livestock_sale_order` (solo tras el "Sí"). No reciben `tenant_id` ni precios.
* `find_livestock_by_criteria`: filtros de lote y UPP (sin acentos; el nombre de la empresa enviado
  como UPP se ignora) y devuelve `upp`/`lote` de cada animal.
* `request_livestock_sale` queda solo para crías sin arete (`find_calf_by_dam`).
* Prompts: toda venta es una orden; para un lote, la primera y única llamada antes del resumen es la
  vista previa con el objeto de lote. WhatsApp pasa de `gpt-4o-mini` a `gpt-4.1-mini`.

**Notificaciones (`V6/Notificación de Autorizaciones Pendientes`, versionado por primera vez):**
un correo por orden y empresa, solo a los ADMIN activos **de esa empresa** (`user_companies.role`, antes
se usaba el rol global), con resumen por guía y lista de aretes; texto de vencimiento 23:59 CDMX.
Corre **cada 5 minutos**.

**Panel de Autorizaciones:** vista "Por orden y guía", aprobar/rechazar una guía u orden completa
(llamadas en secuencia, filas fallidas quedan PENDIENTES), confirmación del total del lote, aviso
"Esta orden incluye N animal(es) de otras empresas; su ADMIN los autoriza por separado."

**Alta por regularización de padrón (`alta_38_bendicion_20261015.sql`, LOCAL y PRODUCCIÓN):** 38 animales
que existían físicamente pero nunca se capturaron, tomados de las guías 7139696/7139697/7139698
(`metadata.source = 'REGULARIZACION_PADRON'`, fecha de nacimiento aproximada por edad de la guía):
30 BECERRO en el nuevo lote **Maceo** (UPP La Bendición – San José y La Pita, empresa 5), 5 NOVILLONA en
Santa Lucía (empresa 8) y 1 BECERRA + 2 NOVILLONA en San José (empresa 5). "VAQUILLA" de la guía se
registró como `NOVILLONA` (no existe en el catálogo).

**QA:** LOCAL — órdenes OV-000010 (30, un lote) y OV-000011 (8, dos empresas), 3 correos, 38/38 APROBADO →
VENDIDO. PRODUCCIÓN — orden de prueba en la empresa 3 (2 animales, aprobada).

⚠️ **Hallazgos durante el despliegue (2026-10-16):**
* El chat **LOCAL** apuntaba su cliente MCP a `https://n8n.hosting3m.com/...` (producción): las pruebas
  "locales" consultaban la base de producción. Solo hubo lecturas (verificado: 0 solicitudes creadas).
* Los workflows se importaron en producción **antes** de aplicar 074: la notificación falló cada
  5 minutos (~21:45–22:00) porque `sale_orders` no existía; se corrigió aplicando 074 de inmediato.
* El n8n LOCAL envía correos reales a los ADMIN reales.

⚠️ **Pendientes:**
* El correo del solicitante en las tools MCP lo llena el modelo (`$fromAI`) — deuda de sesión del agente.
* El webhook del chat en producción sigue aceptando `http://localhost:4200` en CORS.
* "Usuarios y Accesos, fases 1–2" pasa a la migración **075+**.

### 🔒 Hotfix de seguridad: cuentas de usuario compartidas entre empresas (migración 073) — v1.16.1

*Parche sobre v1.16.0; la fecha de liberación se fija al desplegarse en producción.*

Hallazgos F1–F3 del reporte "Usuarios y Accesos" (Step 0, 2026-10-12). En producción existen
cuentas con acceso a varias empresas (2 a 5 cada una), así que los tres eran explotables entre
cuentas reales:

* **F1 — secuestro de cuenta:** el `insert` de `users` del gateway era
  `ON CONFLICT (email) DO UPDATE SET names, password, role, tenant_id…`. El ADMIN de la empresa A
  que "daba de alta" un correo que ya pertenecía a la empresa B **sobrescribía su contraseña** y
  podía entrar como esa persona a la empresa B.
* **F2 — edición/baja global:** `update`/`delete` de `users` no tenían alcance por empresa. Cualquier
  ADMIN podía cambiar nombre, teléfono, rol global o contraseña de cualquier cuenta, y el botón
  "Eliminar" de Personal UPP era un soft-delete **global** (`users.is_active = false`): cortaba
  WhatsApp y Chat Web en todas las empresas de esa persona (el login web seguía funcionando porque
  `jwt-service` no revisa `users.is_active`).
* **F3 — lectura de `users`:** `SELECT` permitido a ADMIN, EDITOR y CUSTOMER sobre `users.*`.
  `Normalize Data` ya quita `password` de la respuesta desde 2026-10-08, pero el hash seguía llegando
  a n8n y un EDITOR podía listar los datos personales de todo el personal.

**Base de datos (migración 073, aditiva e idempotente, con rollback, 21 pruebas funcionales y `073_state_check.sql` de solo lectura para la secuencia aplicar → rollback → re-aplicar):**
* `vw_company_members` (modelo `company_members`, solo ADMIN): miembros de **una** empresa, sin
  `password`. `profile_managed_here = false` indica que la persona también pertenece a otra empresa
  (sin revelar cuál).
* `sp_access_add_user` / `sp_access_update_member` / `sp_access_set_active`: única vía de escritura
  de membresías. Validan en la base: ADMIN activo de la empresa, correo normalizado (trim +
  minúsculas) y bien formado, una cuenta existente **nunca** se modifica al agregarla a otra empresa,
  nombre/teléfono/contraseña de una persona compartida solo los cambia ella misma, un ADMIN no puede
  cambiar su propio rol ni desactivarse, y no se puede dejar a una empresa sin ADMIN activo. Las
  membresías se desactivan/reactivan, nunca se borran; `users.is_active` no se toca.
* `access_audit_log` (solo inserción): cada alta, cambio de rol, edición de perfil y
  (des)activación. Nunca guarda contraseñas ni hashes.
* `crud_models`: `users` → `SELECT` solo ADMIN y sin `DELETE`; `user_companies` sin
  `INSERT`/`UPDATE`/`DELETE`.
  Los 4 modelos nuevos se registran con upsert (`ON CONFLICT (model_name) DO UPDATE`): re-aplicar
  073 después del rollback restaura su configuración completa. El rollback solo restaura las dos
  columnas que 073 cambia en `users`/`user_companies` y desactiva (nunca borra) los modelos que creó.

**Gateway (`v6/CRUD`, nodo Build Query):** `users` con columnas explícitas (nunca `password`) en
`getall`/`getone`/`RETURNING`; `insert` con `DO NOTHING` (nunca sobrescribe); `update` solo si la
persona pertenece únicamente a la empresa del `x-tenant-id`; `getone` solo miembros de esa empresa;
`delete` bloqueado; `password` nunca se acepta como filtro, campo de búsqueda ni columna de orden en
`users`; listar `users`/`company_members` exige `x-tenant-id` (defensa en profundidad: `Get Membresia`
ya lo niega). Registro de los 3 procedimientos en `spConfigByModel` (actor tomado del JWT).

⚠️ **Rollback = migración + frontend:** el rollback de 073 desactiva `company_members` y los
`sp_access_*` que usa la nueva pantalla de Personal UPP; si se revierte la migración hay que volver
a desplegar también el frontend anterior. Los guardias de `users` del Build Query pueden quedarse.

⚠️ **Datos de ejecución de n8n:** el alta/edición vía `sp_access_*` deja la contraseña en texto plano
en los datos de ejecución de `v6/CRUD` (el webhook y `Get Model Name` ya la tenían antes de 073).
Recomendado: no guardar ejecuciones exitosas de `v6/CRUD` y activar el pruning por antigüedad.
~~También protege la pantalla de usuarios del `dashboard` del hotel, que usa el mismo modelo.~~
⚠️ **Corrección (v1.17.1, 2026-10-17):** no era así. El `dashboard` del hotel usa `v5/CRUD`, que no
tiene ninguno de estos guardias. Desde v1.17.1 `users` está bloqueado en `v5`.

**Frontend (Personal UPP):** lista desde `company_members`; alta y edición vía los procedimientos;
"Eliminar" reemplazado por **Desactivar/Reactivar acceso a esta empresa** con confirmación; campos
de perfil bloqueados (con explicación) para personas compartidas; rol bloqueado al editarse a sí
mismo; CUSTOMER se muestra como **"Solo lectura"**; estados explícitos de envío/éxito/error con el
mensaje del SP (Silent Error Shield). Se quitó el switch "Cuenta Activa" (era el flag global).
**Fail-closed:** solo cuenta como éxito una respuesta con `error === false` **y** `data.success === true`
(`interpretAccessResponse`); cualquier otra (cuerpo vacío, falla de n8n, `error: true`) muestra el
estado rojo. "La persona ya tenía cuenta" solo aparece si el SP devuelve explícitamente
`created_account: false` — en pruebas locales, con un Build Query sin la configuración del SP, la
pantalla mostraba ese mensaje en verde sin haber escrito nada.

⚠️ **Pendientes, fuera de este hotfix:**
* Los usuarios que el botón "Eliminar" anterior desactivó globalmente siguen con
  `users.is_active = false` (la lista los marca como "Cuenta desactivada"); su reactivación es una
  decisión manual.
* Crear una empresa nunca le dio membresía a su creador (`currentUser()?.email` no existe en el JWT);
  se resuelve con el administrador de plataforma (migración 074).
* "Solo lectura" aplica en el panel web; el Agente IA (WhatsApp/Chat) y las tools MCP todavía no
  validan rol — Fase 3.
* `jwt-service` compara el correo del login de forma exacta (sensible a mayúsculas).

### 🔒 "Ver detalle" (metadata) ocultaba todo menos lo financiero — ahora también oculta lo financiero para no-ADMIN

Follow-up al ciclo de visibilidad financiera: `cattle_livestock.metadata` (JSONB sin shape
fijo) contiene, para algunos animales, `purchase_price`, `seller_name`, `purchase_date`,
`nota_venta` y `venta_registrada_solo_en_libreta` — confirmado contra el contenido real de
LOCAL (29 claves distintas en total) y contra la única herramienta MCP que escribe aquí
(`register_livestock_purchase`; las dos últimas vienen de los scripts de carga histórica, no
del Agente IA). El modal "Ver detalle" en `main-dashboard` y `cattle-list` pasaba
`animal.metadata` tal cual a `<app-metadata-detail-modal>`, sin ningún filtro por rol — un
EDITOR podía ver el precio de compra y el vendedor de cualquier animal.

**Fix:** nueva lista compartida `FINANCIAL_METADATA_KEYS` (`shared/utils/financial-metadata.util.ts`)
y `withoutFinancialMetadata()`, que devuelve una copia de la metadata sin esas 5 claves.
`main-dashboard.component.ts`/`cattle-list.component.ts` agregan `getDisplayMetadata(animal)`
(ADMIN recibe `animal.metadata` íntegro; no-ADMIN recibe la copia filtrada) y lo usan tanto en
el binding `[metadata]` del modal como en `animalHasMetadata()` — si tras filtrar no queda nada
mostrable, el ícono de "Detalle" se oculta igual que ya pasaba con las claves puramente
técnicas. Deliberadamente NO se incluyen `notes`/`source` en la lista: son genéricos, se usan
también para contenido no financiero, y ocultarlos perdería información legítima.

⚠️ **Riesgo residual, NO cerrado por este fix:** el dato financiero sigue viajando completo en
la respuesta HTTP de `vw_cattle_kpi` — el gateway no filtra columnas ni claves de `metadata`
(`Build Query`'s `buildSelectFields()` siempre hace `SELECT *`, confirmado). Este fix solo evita
que la UI lo renderice; cualquiera con las herramientas de desarrollador del navegador abiertas
sigue viendo la respuesta cruda completa. El cierre real es una vista en PostgreSQL que excluya
estas claves de `metadata` antes de que el gateway las devuelva — **Fase 1, no implementada
aquí.**

### 📌 Deuda técnica — el gateway corta GETALL en 1500 filas (tope 2000), listas client-side truncan en silencio

Hallazgo del diseño de estandarización de paginación (fase 0-1, `PagedTable`/`exportRowsToCsv`
en `shared/utils/`, aún sin cablear a ningún componente). `Build Query` (`v6/CRUD`,
`sanitizePaginationParams`) aplica `limit = 1500` por default cuando el frontend no manda
`body.limit`, con un tope duro de 2000 aunque se pida más. Todas las tablas de agro-erp hoy
(`cattle-list`, `cattle-event-log`, main-dashboard, etc.) hacen "traer todo, paginar/filtrar/
ordenar en memoria" sin mandar `limit` nunca — **si el hato o la bitácora de un tenant superan
1500 filas, el resto se descarta silenciosamente antes de llegar al cliente**: ni un error, ni
un aviso, ni un "mostrando parcial" — el paginador simplemente calcula `totalPages` sobre un
dataset ya incompleto, y lo que no entró en esas 1500 filas no existe para el usuario. Hoy no
hay evidencia de que ningún tenant real supere ese umbral (el ejemplo más grande documentado es
581 animales, un tenant), pero no hay ninguna alarma que avise cuando se cruce.

Propuesta (no implementada, solo nota, según se pidió): un chequeo explícito en el pipeline de
carga de cada tabla grande — si el array recibido tiene exactamente `1500` o `2000` elementos
(las dos cotas conocidas de `sanitizePaginationParams`), mostrar una advertencia visible ("estos
datos pueden estar incompletos, contactar a soporte") en vez de asumir que esa cifra redonda es
coincidencia. Cierre real requiere tocar el gateway (subir el tope, o mejor, implementar
paginación servidor-side real con `limit`/`offset` — ver la entrada de diseño de paginación para
el detalle de qué le falta a `Build Query` para eso, p.ej. total-count y sort ASC) — fuera de
alcance de esta nota.

### 📌 Deuda técnica — `ng test agro-erp` no compila; specs nuevos verificados solo por Vitest standalone

`ng test agro-erp` falla al compilar el proyecto completo, no solo las pruebas nuevas de este
ciclo: `admin.service.ts`/`production-unit-lot.service.ts` tienen errores reales de TypeScript
en modo estricto (`Object is of type 'unknown'`, `Cannot find module 'core-auth'`), y varios
specs preexistentes (`reproductive-dashboard.component.spec.ts` ×2, `expense-modal.component.spec.ts`,
`tenant-selector.component.spec.ts`) importan rutas/clases que ya no existen — boilerplate de
`ng generate` nunca actualizado. Ninguno de estos errores lo introdujo este ciclo de trabajo.

Por eso `paged-table.util.spec.ts` (13 casos: slicing, reset por `linkedSignal`, clamp al
encoger el dataset, `showPager` con y sin umbral, búsqueda normalizada) y, en la rama
`Parametrizacion`, `tenant.service.spec.ts`, se verificaron corriendo Vitest de forma standalone
(`npx vitest run --config <config temporal>`, fuera del builder de Angular) en vez de vía
`ng test` — válido porque ambos archivos son clases puras sin decoradores de Angular, pero
significa que **ningún test de este ciclo corrió nunca por el comando real del proyecto**.
Cerrar esto requiere arreglar los specs rotos y los errores de `admin.service.ts` primero —
fuera de alcance de este ciclo (es deuda preexistente, no introducida por `PagedTable`).

### 🐛 Tasa de Preñez Global inflaba el denominador con animales sin diagnóstico

`reproductive-dashboard.component.ts` (módulo CRIA) mostraba cosas como "0 de 147 vientres" con el
donut en 100% Vacías, aunque casi ningún vientre tuviera palpación registrada. Causa: `stats()`/
`getChartOptions()` usaban `data().length` (**todas** las CRIA: machos, becerros, hembras nunca
palpadas) como denominador de la tasa y como "Vacías" del chart — un animal sin ningún diagnóstico
se contaba silenciosamente como si estuviera diagnosticado "VACIA". El computed `diagnosisSummary`
ya distinguía correctamente `sinDiagnostico`/`prenadas`/`vacias`, pero solo se usaba en los badges
de la tabla colapsable, no en la tarjeta principal ni en el chart.

**Fix:** `stats()`/`getChartOptions()` ahora derivan de `diagnosisSummary()` — el denominador es
`prenadas + vacias` (solo vientres **con** diagnóstico), nunca el total de animales del módulo.
`tasa: null` quando no hay ningún vientre diagnosticado (vs. una tasa real de 0%) — la plantilla
muestra "Sin diagnóstico" en vez de "0.0%" y oculta el donut (con un placeholder) en ese caso,
mismo criterio que el "Sin Diagnósticos Reproductivos" que ya existía para `data().length === 0`.
Verificado que `reproduccion-dashboard.component.ts` (módulo REPRODUCCION) no tiene este bug — su
"X vientres preñados" es un conteo simple, sin denominador ni gráfico de "Vacías".

### 👷 Panel Operativo (no-ADMIN) enriquecido — sin endpoints nuevos, sin Cattle Event Log

Extiende el Panel Operativo del fix anterior. Cambios en `main-dashboard.component.ts/.html`:
* **Título de página** condicional: "Capitalización y Rendimiento" (ADMIN) vs. "Panel Operativo"
  (no-ADMIN), vía `isAdminForActiveTenant()`.
* **Widgets enviados**, todos de solo lectura, sin ninguna cifra financiera, 100% client-side
  desde `filteredCattleList()` (cero fetches nuevos): Peso Promedio por Lote y Categoría, e
  Identificación Incompleta (falta arete SINIIGA y/o RFID electrónico).

🔴 **Hallazgo de seguridad encontrado al construir esta entrega, y por qué faltan 3 widgets que
se intentaron primero:** se habían agregado también "Pesajes Recientes", "Eventos Sanitarios
Recientes" y "Animales Sin Pesaje Reciente" (dos métodos nuevos en `CattleApiService`,
`getRecentWeightLogs`/`getRecentHealthLogs`, mismo endpoint genérico Meta-CRUD de siempre) — pero
se confirmó que `cattle_weight_logs` y `cattle_health_logs` **NO TIENEN columna `tenant_id`**
(vía `\d` directo contra ambas tablas) y por lo tanto tampoco aparece en su `allowed_fields` de
`crud_models`. El "SECURITY PATCH: Aislamiento Multi-Tenant" de `Build Query` solo inyecta el
filtro de tenant cuando `tenant_id`/`id_company` SÍ está en `allowed_fields` del modelo — para
estas dos tablas esa condición nunca se cumple: **un `GETALL` sin filtro de `livestock_id`
devuelve las filas de *todos* los tenants del sistema, sin excepción**, para cualquier rol con
SELECT (incluido EDITOR y CUSTOMER). Los métodos previos (`getExpensesByAnimal`,
`getHealthLogsByAnimal`) nunca lo exponían porque siempre filtran por un `livestock_id` puntual
que el frontend ya sabía que pertenecía al tenant activo — nadie había hecho antes un GETALL
"todo el tenant" sobre estas dos tablas.

Se había mitigado client-side (filtro de segunda capa contra `filteredCattleList()`, mismo patrón
que `cattle-event-log.component.ts#entries`), pero en revisión **se decidió retirar los tres
widgets y los tres métodos/computeds que dependían de datos tenant-wide de estas tablas** —
un filtro en el navegador nunca es aislamiento real: la respuesta cruda con filas de otros
tenants sigue llegando al cliente antes de filtrarse, visible en cualquier inspector de red.
Removido de `CattleApiService`: `getRecentWeightLogs`, `getRecentHealthLogs`. Removido de
`main-dashboard.component.ts`: `rawWeightLogs`, `rawHealthLogs`, el branch de fetch no-ADMIN en
`loadDashboardData()`, `animalById`, `recentWeightLogs`, `recentHealthLogs`,
`lastWeighDateByAnimal`, `recentWeighWindowDays`, `animalsWithoutRecentWeighIn`. Confirmado que
`vw_cattle_kpi` (`pg_get_viewdef`) no tiene ninguna columna de fecha de pesaje — "Animales Sin
Pesaje Reciente" no se puede reconstruir sin tocar `cattle_weight_logs`, así que queda pendiente
por completo, no solo pausado por estilo.

**Pendiente de raíz, bloqueante para reintroducir estos 3 widgets:** agregar `tenant_id` real a
`cattle_weight_logs`/`cattle_health_logs` (o una vista tenant-scoped con `default_filter`/join de
cross-check, registrada aparte en `crud_models` con su propio `tenant_id` en `allowed_fields`)
para que el gateway mismo filtre — ver la auditoría completa de los 62 modelos en la entrada de
abajo. Cualquier otro consumidor futuro de estos dos modelos que haga un GETALL amplio sin pasar
por un componente con su propia segunda capa queda expuesto al mismo problema hoy.

### 📌 Deuda técnica — ciclo de visibilidad financiera/rol (Cattle Event Log + gastos, 2026-10-05)

Cuatro ítems de deuda, confirmados con evidencia directa durante este ciclo de fixes (migración
064 + gates de frontend), ninguno corregido aquí a propósito — alcance mayor al de "ocultar un tab":

1. **`PRECIO_KILO = 65.00` hardcodeado en el cliente** (`main-dashboard.component.ts`). "Valor
   Estimado del Hato"/capitalización no vienen de ningún modelo de precios del servidor — es
   `current_weight_kg × 65.00`, constante fija en el componente. Sin tabla de precios, sin
   historial, sin ajuste por especie/categoría. Cualquier cambio de precio real requiere un
   despliegue de frontend. No es parte del alcance de este fix (que es de *visibilidad* por rol,
   no de *exactitud* del dato), pero es la raíz de por qué no hubo nada que restringir en el
   servidor para esa cifra específica.
2. **Rol de JWT congelado al login vs. rol por-empresa** (ver detalle completo en la entrada
   "Cattle Event Log debía ser ADMIN-only" más abajo). Afecta a *todo* el enforcement de rol de la
   suite, backend y frontend — `roleGuard`/`authService.hasRole()` y el nodo `Security Validation`
   de `v6/CRUD` leen el `role` del JWT (fijo a la empresa del login); solo
   `tenantService.activeTenant()?.role` se actualiza en vivo al cambiar de rancho. Confirmado con
   test real (`tenant.service.spec.ts`, 5 casos, todos verdes) que el mecanismo del frontend sí
   funciona correctamente — el gap es que el *backend* no tiene un mecanismo equivalente.
3. ❌ **"Actividad reciente" sigue sin implementar — intento revertido en revisión.** Se había
   construido "Pesajes Recientes"/"Eventos Sanitarios Recientes" directo de
   `cattle_weight_logs`/`cattle_health_logs` (EDITOR ya tiene SELECT en ambas), pero se descubrió
   que ninguna de las dos tablas tiene `tenant_id` — un GETALL tenant-wide devuelve filas de
   *todos* los tenants al navegador antes de cualquier filtro client-side, que nunca es
   aislamiento real. Removido por completo (código y widgets), no solo oculto. Ver la entrada
   "Panel Operativo (no-ADMIN) enriquecido" más arriba para el detalle completo y la auditoría de
   los 62 modelos más abajo. Bloqueado hasta que exista una fuente tenant-scoped real (columna
   `tenant_id` nativa o vista con `default_filter`/join registrada aparte en `crud_models`).
4. 🔴 **`cattle_livestock` permite UPDATE a EDITOR, y el gateway no acota ese UPDATE por tenant —
   confirmado contra el workflow `v6/CRUD` EN VIVO (no el JSON del repo), 2026-10-05.** El nodo
   `Build Query`, caso `'update'`, arma el `WHERE` **solo** con las columnas de la primary key
   (`pkList`, para `cattle_livestock` es únicamente `id`) — nunca con `tenant_id`/`id_company`.
   Peor aún: como `cattle_livestock.allowed_fields` SÍ incluye `"tenant_id"`, el parche de
   aislamiento (`fields['tenant_id'] = tenantIdHeader`, aplicado a TODAS las operaciones antes del
   `switch`) hace que **cualquier UPDATE exitoso reasigne silenciosamente `tenant_id` al valor del
   header `x-tenant-id` del solicitante** — no es solo una fuga de lectura/escritura cruzada, es
   un vector activo de secuestro de registro: un usuario de la Empresa B que conozca (o adivine)
   el `id` (UUID) de un animal de la Empresa A puede, con su propio rol EDITOR legítimo, hacer
   `UPDATE` sobre ese registro y de paso reclamarlo para su propio tenant. Mismo patrón ya
   documentado de forma genérica en "🔴 Hallazgo de seguridad (gateway, no corregido aquí)" más
   abajo (deuda técnica a nivel suite) — esta entrada lo confirma con evidencia fresca y lo ata
   específicamente a `cattle_livestock`, el modelo donde EDITOR tiene UPDATE hoy. **No corregido
   en este ciclo** (alcance de infraestructura del gateway, no de un modelo puntual) — reportado
   como hallazgo, no arreglado, tal como se pidió.

### 🔒 Datos financieros (gastos, capitalización) ocultos para no-ADMIN — Panel Operativo nuevo

Follow-up directo del fix de Cattle Event Log: un EDITOR (capataz) tampoco debía ver valor
estimado del hato, balance neto, capitalización, historial de gastos ni costo por animal, ni
tener el botón "Registrar Gasto" en `main-dashboard`.

**Servidor — inventario completo de `crud_models`, leído en solo-lectura (62 filas).** Solo
`cattle_expenses` alimenta los widgets financieros de "Capitalización y Rendimiento"
(`CattleApiService.getExpenses()` → Historial de Gastos, Costo por Animal, Balance por UPP) y
tenía `allowed_roles_select = 'ADMIN,EDITOR,CUSTOMER'` — el default de la columna, igual que el
hallazgo de `cattle_event_log`. "Valor Estimado del Hato"/Biomasa **no tienen modelo propio**: se
calculan 100% client-side en `main-dashboard.component.ts` desde `cattleList()` (peso) × una
constante hardcodeada `PRECIO_KILO = 65.00` — no hay nada que restringir en el servidor para esa
parte, solo ocultarla en el frontend. `cattle_livestock`/`vw_cattle_kpi` quedan sin tocar a
propósito: EDITOR los necesita para pesajes, eventos de salud e inventario, que siguen siendo
operación legítima suya.

**Migración 064 preparada, NO aplicada** (`database/migrations/064_restrict_cattle_expenses_select_to_admin.sql`):
backup de la fila (`crud_models_backup_20261005`) + `UPDATE allowed_roles_select = 'ADMIN'` +
SELECT de verificación, con rollback documentado. **Deliberadamente deja intacto**
`allowed_roles_insert` (`'ADMIN,EDITOR'`) — revocar INSERT habría roto la tool MCP
`register_ranch_expense` del Agente IA, decisión de negocio ya confirmada (ver Regla 10/Deuda
técnica, "EDITOR debe poder usar las 5 tools rutinarias... sin restricción de rol"). Efecto neto:
EDITOR puede seguir *reportando* un gasto por WhatsApp/Chat, pero no puede *leerlos* de vuelta vía
el gateway. Producción pendiente de que el dueño del proyecto corra la migración.

**Frontend aplicado** (mismo patrón que Cattle Event Log, fuente de rol
`tenantService.activeTenant()?.role` vía `isAdminForActiveTenant`, nunca `roleGuard`/JWT — ver
hallazgo de abajo): tarjeta "Valor Estimado del Hato", botón "Registrar Gasto", y los tabs
"Historial de Gastos"/"Costo por Animal" ocultos para no-ADMIN, con el mismo triple gate
(nav oculto + `setSubTab()` rechaza el tab + bloque `@if` del contenido) extendido a
`ADMIN_ONLY_SUBTABS = {EVENT_LOG, GASTOS, POR_ANIMAL}`. `loadDashboardData()` ya ni siquiera llama
`getExpenses()` para un rol no-ADMIN (evita un 403 inútil).

**Panel Operativo nuevo** (reemplaza la tarjeta "Balance por UPP" en el tab Resumen para
no-ADMIN, cero cifras financieras, sin ningún fetch nuevo — reutiliza `filteredCattleList()`):
hato por especie, por categoría y por lote (conteos), y una tabla de animales en
RIESGO/CUARENTENA/EN_TRANSITO ("requieren atención").

⚠️ **"Actividad reciente" del panel operativo, pedida en el requerimiento, NO implementada.** El
`Livestock` del frontend no trae ningún timestamp de evento (ni `last_weighed_at` ni similar), y
la única fuente con fecha real por evento es `vw_cattle_event_log` — que este mismo ciclo de fixes
dejó ADMIN-only a propósito. Construir una actividad reciente para EDITOR requeriría una fuente
de datos nueva (ej. una vista reducida, sin gasto/health_event_type, con su propio
`allowed_roles_select` separado) — no se improvisó sin esa decisión de diseño. Pendiente de
confirmar si se quiere como follow-up.

**Rol de escritura hoy para pesaje y salud (sin cambios en este fix):**
`cattle_weight_logs.allowed_roles_insert = 'ADMIN,EDITOR,IOT'`,
`cattle_health_logs.allowed_roles_insert = 'ADMIN,EDITOR'` — EDITOR puede registrar ambos eventos
hoy, vía panel Web o Agente IA.

### 🔒 Cattle Event Log debía ser ADMIN-only — gateado en 3 capas, hallazgo arquitectónico de rol obsoleto

Reproducido con una cuenta EDITOR: el tab "Cattle Event Log" era visible y usable por cualquier rol.

**Hallazgo clave — fuente de rol correcta para un gate por-empresa:** `authService.hasRole()` /
`roleGuard` (core-auth) leen `authService.currentUser()?.role`, decodificado del JWT — y el JWT
fija el rol de la empresa activa **al momento del login**, nunca se refresca. `TenantSelectorComponent.onSelect()`
(Context Switcher) solo llama `tenantService.setActiveTenant()` con la entrada ya cacheada de
`availableTenants()` — no vuelve a loguear, no emite un token nuevo. Resultado: si un usuario con
roles distintos entre empresas (el esquema lo permite vía `user_companies.role` por fila, aunque
ningún usuario real de hoy lo tiene) cambia de rancho, `authService.hasRole()`/`roleGuard` siguen
reportando el rol de la empresa del login original, no el de la empresa activa. Solo
`tenantService.activeTenant()?.role` es correcto y se actualiza en vivo en cada cambio de contexto
— es la fuente usada para este gate, no `roleGuard`.

**"Guardar la ruta" no aplica literalmente — `EVENT_LOG` no es una ruta.** `ganaderia/dashboard`
(`livestock.routes.ts`) carga `MainDashboardComponent` sin ningún `canActivate` (ni siquiera
`authGuard`); "Cattle Event Log" es `activeSubTab() === 'EVENT_LOG'`, un signal interno, nunca
reflejado en la URL/queryParams. No hay nada donde enganchar `canActivate: [roleGuard(['ADMIN'])]`
tal cual se pidió. Protección equivalente implementada a nivel de componente (`main-dashboard.component.ts`):
* `isAdminForActiveTenant` (computed, fuente `tenantService.activeTenant()?.role`).
* `setSubTab()` rechaza activar `'EVENT_LOG'` si el rol de la empresa activa no es ADMIN (defensa
  ante consola/binding forzado).
* Nuevo `effect()` reactivo: si el usuario ya está en el tab y cambia de rancho hacia una empresa
  donde no es ADMIN, lo saca al instante a `'RESUMEN'`.
* Plantilla: el `<li>` del tab y el `@if` que monta `<app-cattle-event-log>` quedan ambos detrás
  de `isAdminForActiveTenant()` — ni visible ni montado (no dispara su propio fetch) para no-ADMIN.

**No era solo ocultamiento de frontend — había enforcement real, mal configurado.** El gateway
Meta-CRUD (`v6/CRUD`, workflow vivo en n8n, confirmado leyendo el JSON real — `06-dynamic-crud-engine/v6/v6-crud.json`
del repo puede estar desactualizado, ver deuda técnica de re-exportación pendiente) tiene un nodo
`Security Validation` que sí valida `crud_models.allowed_roles_<operación>` contra el rol del
usuario antes de ejecutar cualquier query. El problema: `cattle_event_log` tenía
`allowed_roles_select = 'ADMIN,EDITOR,CUSTOMER'` (el default de la columna, nunca se endureció al
crear el modelo en v1.13.0) — EDITOR y CUSTOMER sí estaban autorizados a nivel de base de datos,
no solo "visibles por error de UI". **Corregido en LOCAL:**
`UPDATE crud_models SET allowed_roles_select = 'ADMIN' WHERE model_name = 'cattle_event_log'`.
**Pendiente aplicar en PRODUCCIÓN** (mismo protocolo de Regla 7).

⚠️ **Hallazgo arquitectónico más profundo, NO corregido aquí (alcance mayor al de este bug) — el rol
usado por `Security Validation` también viene del JWT.** El nodo `Extract Auth Context` obtiene el
rol vía `/verify-token` de `jwt-service` → `decoded.role`, el mismo valor congelado al login,
nunca re-derivado para la empresa activa real de la petición. Mientras tanto, el aislamiento de
datos por tenant (`tenantInterceptor` → header `x-tenant-id` ← `tenantService.activeTenantId()`,
vivo) sí viaja actualizado en cada petición. Es decir: **el tenant de una petición es siempre
fresco, pero el rol que la autoriza puede corresponder a una empresa distinta a la que esa misma
petición está consultando.** Sin impacto confirmado hoy (ningún usuario real tiene roles distintos
entre empresas), pero es un gap real, afecta a *todo* el enforcement de rol de la suite (no solo
Cattle Event Log), y cerrarlo requiere re-emitir el JWT en cada cambio de Context Switcher, o que
`Extract Auth Context`/`Security Validation` re-deriven el rol por `(email, x-tenant-id)` contra
`user_companies` en cada petición en vez de confiar en el claim plano del JWT. Queda como deuda
técnica de arquitectura, fuera del alcance de este fix puntual.

### 🐛 Context Switcher mostraba empresas a las que el usuario no tenía acceso

Un usuario con una sola empresa activa en `user_companies` (ej. `id_company=6`) veía en el
selector de rancho empresas de una sesión anterior en el mismo navegador (ej. Hosting3m, UPP La
Bendición, Rancho El Palomar), pese a que el backend (`jwt-service`, filtrado correctamente por
`user_companies`) nunca las autorizó para esa cuenta.

**Causa raíz confirmada** (verificada con cuentas QA sintéticas en LOCAL, sin tocar datos
reales — ver detalle completo en el hilo de la sesión que originó este fix):
* `TenantService` (`core-auth`) persiste `user_tenants`/`active_tenant_context` en
  `localStorage` y solo los limpia vía `clearContext()` — nunca invocado automáticamente.
* `AuthService.logout()` solo limpiaba `authToken`/`role`, dejando esas dos llaves obsoletas
  en el navegador tras cerrar sesión.
* `jwt-service` (`/generate-token`) devolvía `data.company` (singular) en el login exitoso de
  una cuenta con **una sola empresa**, pero **omitía `data.companies`** por completo — el
  `login.component.ts` de `agro-erp` ya sabía sincronizar `TenantService.setAvailableTenants()`
  con ese arreglo, pero nunca se ejecutaba porque el arreglo nunca llegaba.
* Resultado: una cuenta de una sola empresa heredaba silenciosamente el `user_tenants` de la
  sesión anterior en ese navegador.

**Fix aplicado (2 archivos, sin cambios en `login.component.ts` — ya sincronizaba correctamente
una vez que el backend empezó a mandar `companies`):**
* `microservices/jwt-service/index.js`: el login exitoso ahora siempre incluye
  `data.companies` (la lista completa, aunque sea de 1), no solo `data.company`.
* `core-auth/src/lib/services/auth.service.ts`: `logout()` ahora también llama a
  `tenantService.clearContext()` — defensa en profundidad, fail-closed, independiente del fix
  del punto anterior.
* Verificado en LOCAL con dos cuentas QA sintéticas (1 empresa / 3 empresas, creadas y
  eliminadas en la misma sesión, sin tocar cuentas reales): el flujo de una sola empresa ahora
  devuelve `companies` con 1 entrada y sobrescribe el caché viejo; el flujo multi-empresa
  (`select_company` → selección → `success`) sigue devolviendo la lista completa sin cambios.
* **Pendiente antes de cerrar:** aplicar ambos archivos a PRODUCCIÓN (mismo protocolo de
  backup/checksum/rebuild) y verificar con las dos cuentas reales que originaron el reporte —
  `12095038@gmail.com` (debe ver únicamente `id_company=6`) y `aguilar.resendez@hotmail.com`
  (debe seguir viendo exactamente `5,6,7,8,9`, caso multi-empresa legítimo que no debe romperse).

**Deuda técnica no bloqueante, detectada durante la revisión (no forma parte de este fix):**
* `activeCompany.business_type` en `login.component.ts` siempre cae al default `'ADMIN'`
  porque el `SELECT` de `/generate-token` en `jwt-service` nunca incluye la columna
  `business_type` — cualquier lógica de UI de `agro-erp` que ramifique sobre `business_type`
  está recibiendo silenciosamente `'ADMIN'` sin importar el valor real.
* `login.component.ts` línea ~70 tiene una llamada muerta a `this.tenantService.debugState()`
  (el método ya es un no-op, solo código de debug sin usar) — remover antes de mergear a `main`.

### 💰 Ingresos por venta: el ADMIN fija el precio al aprobar (frontend de la migración 071)

El capataz solo **solicita** la venta (animal, fecha, guía de tránsito); el precio lo fija el ADMIN
al aprobar. Nunca se usan los importes de guías o facturas (suelen ser simbólicos).

* **Aprobar una venta abre un formulario de venta** (en vez del confirm simple): encabezado de solo
  lectura (identificador, categoría/especie, fecha de venta, guía), modo de venta (por pieza / por
  kilo / por genética), importe del animal, peso con vista previa de $/kg (solo y obligatorio en
  POR_KG), comprador, forma de pago (Efectivo / Transferencia), facturado y folio opcional. Se envía
  como `datos_venta` a `resolver_autorizacion`; nunca se manda email (lo toma el gateway del JWT).
  BAJA_MORTANDAD no cambia.
* **Precarga desde precio de referencia:** misma empresa, categoría del animal, modo elegido, activo
  y vigente en la fecha de venta (`valid_from <= fecha <= valid_to`). Si hay varios, gana el de
  `valid_from` más reciente. En POR_KG con precio por kilo, el importe es $/kg × peso. El ADMIN
  siempre puede editarlo; un importe editado a mano ya no se sobrescribe al cambiar modo o peso.
* **Excepción sanitaria:** se conserva el flujo de 069, reenviando los **mismos** `datos_venta` con
  `APROBADO_CON_EXCEPCION` y la justificación obligatoria.
* **Aprobación por lote:** casillas en las ventas pendientes, "Seleccionar todos de la guía X" y
  "Aprobar ventas seleccionadas". Campos compartidos (modo, comprador, forma de pago, facturado,
  folio, importe por defecto) y tabla por animal (importe editable precargado, peso y $/kg en
  POR_KG) con total del lote. Opción de aprobar con excepción sanitaria las que la requieran
  (justificación obligatoria). Se ejecuta **una llamada por animal, en secuencia**, sin detenerse
  ante una fila fallida; al final se muestra el resultado por fila (aprobada / aprobada con
  excepción / pendiente: motivo / error: mensaje) y se recarga la lista.
* **Historial:** columna "Venta" con importe y modo leídos de `payload.venta`.
* **Nueva pantalla "Precios de referencia"** (`/admin/precios-referencia`, Configuración, solo
  ADMIN): alta, edición, desactivación y reactivación por empresa activa. Categorías tomadas de la
  lista del `CHECK` de `cattle_livestock.category` (nuevo `shared/utils/livestock-category.util.ts`).
* **Nueva pestaña "Ingresos por Venta"** en el dashboard, junto a "Historial de Gastos" y con el
  mismo gate ADMIN (nav oculto + `setSubTab()` + `@if`). Filtro por rango de fechas y totales:
  importe, cabezas, facturado vs. no facturado, bancarizado vs. no bancarizado. Mismo alcance por
  módulo que Cattle Event Log; una venta cuyo animal no aparece en el hato se muestra igual (nunca
  se omite de los totales). `sale_date` es fecha calendario: se muestra tal cual, sin convertir de
  zona horaria (convertirla la recorría al día anterior).
* Helpers puros en `shared/utils/sale-income.util.ts` (`pickReferencePrice`, `computePricePerKg`,
  `validateSaleData` espejo de `fn_normalize_sale_data`, `batchTotal`, entre otros) con Vitest
  standalone (47 casos en total con los specs existentes, verdes en UTC, Asia/Tokyo y CDMX).

⚠️ **Bloqueante para que funcione de punta a punta — gateway, no incluido en este cambio:** el
`call_sp` de `sp_resolver_autorizacion` en `v6/CRUD` (repo y LOCAL vivo, verificado 2026-10-10) solo
envía `['request_id', 'decision', 'resuelto_por_email', 'notas']`. `datos_venta` se descarta y toda
aprobación de VENTA desde el panel falla con P0021 hasta agregarlo al `paramOrder`.

⚠️ **Agente IA:** `sp_review_pending_request` sigue llamando al resolver con 4 argumentos, así que
aprobar una venta por chat/WhatsApp ahora siempre falla con P0021 (coherente con "el precio solo lo
fija el ADMIN en el panel", pero el agente debería explicarlo en vez de reportar un error genérico).

### 🔒 Autorizaciones: frontend alineado con la migración 069 (aprobación solo ADMIN, cancelación por el solicitante)

Adapta `/admin/autorizaciones` a las reglas nuevas de `sp_resolver_autorizacion` /
`sp_cancelar_autorizacion` (migración 069):

* **Sin email del actor en el payload:** `resolveAuthorization()` ya no envía
  `resuelto_por_email` y la nueva `cancelAuthorization()` (modelo `cancelar_autorizacion`,
  `call_sp`, `{ request_id, motivo }`) tampoco manda `cancelado_por_email` — el gateway lo toma
  del JWT verificado y sobrescribe cualquier valor del body.
* **Motivo obligatorio:** `confirm-action-modal` tiene un input nuevo `notesRequired` (default
  `false`, sin cambios en usos existentes) que deshabilita "Confirmar" mientras las notas estén
  vacías. Se usa en Rechazar, Cancelar solicitud y Aprobar con excepción sanitaria.
* **Excepción sanitaria (solo VENTA):** si un APROBADO regresa `success:false` con
  `resultado_sp.excepcion_disponible === true`, se muestra el `motivo` del backend y el botón
  "Aprobar con excepción sanitaria" (decisión `APROBADO_CON_EXCEPCION`, justificación
  obligatoria). Nunca se ofrece para `BAJA_MORTANDAD`. Antes un `success:false` se trataba como
  éxito y la fila desaparecía de Pendientes sin haberse resuelto.
* **Cancelar solicitud:** botón visible solo en filas PENDIENTE cuyo `solicitado_por_email`
  coincide (sin distinguir mayúsculas) con el usuario actual. Es solo conveniencia de UI; la
  regla real la aplica el SP.
* **Errores:** un `error:true` muestra el `message` del backend tal cual y deja la fila sin
  cambios. Tras cualquier acción exitosa se recarga la lista.
* **Estado nuevo `CANCELADO`:** badge neutro (`bg-dark-lt`) en Historial y en Cattle Event Log
  (`SOLICITUD_BAJA`/`SOLICITUD_VENTA`), distinto del rojo de RECHAZADO.
* Helpers puros nuevos en `shared/utils/authorization-actions.util.ts` (`canCancelRequest`,
  `isSanitaryExceptionAvailable`, `resolveCurrentUserEmail`) con 10 casos de Vitest, verificados
  standalone (`ng test agro-erp` sigue sin compilar, deuda preexistente).

⚠️ **Limitación conocida:** la ruta `/admin/autorizaciones` sigue con `roleGuard(['ADMIN'])`, así
que un EDITOR que creó una solicitud (p. ej. el capataz) no llega a esta pantalla y no puede
cancelarla desde la Web, aunque `cancelar_autorizacion` sí permite `ADMIN,EDITOR`. Abrir la vista
a EDITOR (solo con su propia cancelación, sin aprobar/rechazar) queda como decisión pendiente.

### ✨ Refresco manual y automático (cada 5 min) del dashboard, sin recargar la página

Hasta ahora la única forma de ver datos nuevos (ej. eventos registrados por el Agente IA) en
"Capitalización y Rendimiento" era F5 — lo que reiniciaba `<lib-ai-chat>` y todo el estado de la
UI. Nuevo botón **Actualizar** (ícono Tabler `ti-refresh`, spinner mientras carga) junto al
título, con "Actualizado hh:mm" (hora local del navegador) y auto-refresco cada
`AUTO_REFRESH_MS = 5 * 60 * 1000` (un solo lugar, `main-dashboard.component.ts`).

* **Pausa en pestaña oculta, recupera al volver:** el chequeo corre cada 30s pero solo actúa si
  `document.visibilityState === 'visible'` y ya venció el intervalo desde el último refresco
  (`isAutoRefreshDue()`, nuevo `shared/utils/auto-refresh.util.ts`, puro y cubierto por
  5 casos de Vitest standalone). Un `visibilitychange` listener revisa lo mismo al volver a la
  pestaña, sin esperar al siguiente tick.
* **Hijos con fetch propio, todos cubiertos:** `cattle-event-log` recibe un nuevo input
  `refreshToken` (bumpeado en cada refresco explícito) que su propio `effect()` ya observa junto
  al tenant activo; `compliance-alert-card` se refresca vía
  `ComplianceService.loadUppStatus(true)/loadPsgStatus(true)`. Los demás paneles
  (reproductive/engorda/reproduccion-dashboard) son 100% `[cattleData]` input, sin fetch propio
  — nada que cablear ahí.
* **Concurrencia "latest-wins" con número de secuencia** (no un simple booleano "ocupado"), en
  `MainDashboardComponent.loadDashboardData()`, `CattleDataService.loadCattleData()` y
  `CattleEventLogComponent.loadEventLog()`: un cambio de tenant SIEMPRE dispara una carga nueva,
  nunca se "salta" por un guard de concurrencia; si la respuesta de una carga vieja llega después
  de una más reciente, se descarta sin tocar ningún signal. El tick automático y el botón
  "Actualizar" sí se omiten si ya hay un refresco en curso (nunca peticiones simultáneas
  apiladas). Verificado con una simulación standalone (Node, fuera de Angular) que reproduce el
  algoritmo exacto de ambos componentes bajo resolución fuera de orden — no solo razonamiento.
* **`isLoading` (carga inicial/cambio de tenant) y `isRefreshing` (refresco manual/automático)
  son signals separados a propósito:** los datos visibles nunca se ocultan ni se vacían durante
  un refresco — el spinner vive únicamente en el botón "Actualizar". Un refresco fallido muestra
  un aviso no intrusivo (`refreshError`, banner descartable) y conserva la última información
  disponible; solo la carga inicial fallida bloquea la pantalla con un estado de error explícito
  y un botón "Reintentar" (`initialLoadFailed`, basado en el nuevo `CattleDataService.hasLoadedOnce()`
  — distingue "el hato está genuinamente vacío" de "nunca llegamos a cargar datos reales").
* **Estado de UI 100% preservado:** el refresco no toca `activeSubTab`/especie/lote/búsqueda/
  agrupación/paginación — ninguno de esos signals se escribe durante una carga, así que el tab,
  los filtros y la página actual sobreviven intactos. El chat (`<lib-ai-chat>`) ni siquiera está
  en el árbol de este componente, así que un refresco por signals nunca lo toca.

### 🔧 `fix(agro-erp): stop swallowing MetaCRUD errors in CattleApiService` (commit previo, prerrequisito de lo anterior)

`getAllLivestock()` y `getExpenses()` atrapaban tanto los errores HTTP como el `error:true` que
el gateway devuelve con status 200 (MetaCRUD Silent Error Shield) y devolvían `[]` en ambos
casos — indistinguible de "el tenant genuinamente no tiene animales/gastos". Para el refresco de
arriba esto era inaceptable: un error transitorio de red habría vaciado el inventario completo en
vez de conservar el último dato bueno. Ambos métodos ahora validan `res.error` y relanzan en vez
de devolver `[]`. Verificado que el único otro llamador de `getAllLivestock()`
(`production-unit-lot.service.ts#getLots()`, sin try/catch propio) ya propaga el rechazo hasta
`lot-list.component.ts`, que sí lo captura y muestra `loadError` — un fallo ahora se ve como error
real, no como "0 lotes/0 animales por lote" engañoso. `getExpenses()` no tiene otros llamadores.

### 🐄 Ocho herramientas MCP nuevas: traslado, reproducción, desparasitación, castración, cambio de arete, autorización y anulación de eventos

El Agente IA no podía trasladar animales entre lotes de la misma UPP, registrar reproducción,
desparasitación ni castración, cambiar un identificador perdido/dañado, ni anular un evento mal
capturado — todo eso se hacía solo por acceso directo a base de datos. Ocho tools MCP nuevas en
`v6/MCP Server Cattle`, probadas de punta a punta en PRODUCCIÓN (tenant 3) por el canal real de
chat: `move_livestock`, `list_pending_requests`, `review_pending_request`, `log_breeding_event`,
`log_deworming_event`, `update_livestock_tag`, `log_castration_event`, `void_event`.

#### 🏗️ Dos bugs de arquitectura de n8n, confirmados en las 8 tools a la vez

* **`queryReplacement` sin el delimitador `{{ }}`:** el campo `options.queryReplacement` de un
  nodo `postgresTool` debe envolverse en `{{ ... }}` (ej. `={{ (() => {...})() }}`), no basta con
  `=[$fromAI(...)]`. Sin el wrapper, n8n trata el campo como texto literal y lo separa ingenuamente
  por comas — confirmado con una prueba aislada (`[3]` hardcodeado seguía fallando como el string
  `"[3]"`). Corregido en las 8 tools copiando el patrón ya usado en `find_livestock_by_criteria`.
* **Tipo declarado en `$fromAI` debe coincidir con el casteo de la query, no con el tipo final de
  la columna:** `$fromAI('current_weight_kg', ..., 'number', null)` rompe la validación de schema
  de n8n en cuanto el LLM manda `null` (`Expected number, received null`) — la llamada nunca llega
  a Postgres. Si la query castea `$N::text` antes de `::numeric`/`::date` (patrón estándar de esta
  sesión), el `$fromAI` correspondiente debe declararse `'string'`, aunque el valor final sea
  numérico.
* **Patrón adoptado para parámetros opcionales en las 8 tools:**
  `NULLIF(NULLIF($N::text, 'null'), 'undefined')` en la CTE `params` (cubre el string literal
  `"null"`/`"undefined"` que a veces manda el LLM, además de `''`/`undefined` real), combinado con
  `empty($fromAI(..., 'string', null))` en el `queryReplacement`.

#### 🐂 `move_livestock`

* Limitado a propósito a traslados **dentro de la misma UPP** (cambio de lote) — confirmado con el
  cliente. El motor de movilización oficial UPP↔UPP/PSG (`cattle_movement_rules`) sigue sin SP
  propio, es un sistema distinto.
* Nombre de lote resuelto con `ILIKE '%...%'` (match parcial), no exacto — el Agente IA
  frecuentemente descarta artículos al extraer el nombre ("el 110" → `"110"`, lote real "El 110").
  El chequeo de ambigüedad (rechaza si hay >1 match en la misma UPP) hace seguro el match parcial.
* Bug real corregido antes de la primera prueba: usaba `tipo_movimiento = 'TRASLADO_LOTE'`, valor
  no permitido por `historico_movimientos_tipo_check` — corregido a `'TRASLADO'`.

#### 🏷️ `update_livestock_tag`

* Requirió ampliar `historico_movimientos_tipo_check` (`ALTER TABLE`, LOCAL y PRODUCCIÓN mismo
  turno) para incluir `'CAMBIO_ARETE'`, antes inexistente en la lista permitida.
* Valida unicidad del nuevo identificador contra el tenant antes de actualizar.

#### ✅ `review_pending_request`

* Wrapper nuevo sobre `sp_resolver_autorizacion` que agrega una validación de propiedad por
  tenant — hallazgo de seguridad real: el SP original no valida por sí solo que la solicitud
  pertenezca al tenant que la resuelve.

#### 🗑️ `void_event`

* Genérico por diseño (whitelist de 3 tablas de evento + SQL dinámico). ⚠️ **Solo registra la
  anulación en `event_voids` — no revierte efectos secundarios sobre `cattle_livestock`.**
  Confirmado: anular una castración deja `category = CABALLO_CASTRADO` sin cambio, aunque el
  evento ya no aparezca en la Bitácora.

#### 🛒 `register_livestock_purchase` (tool preexistente, 3 bugs reales corregidos)

1. `production_unit_id` ahora se infiere automáticamente de la UPP del lote resuelto cuando el
   usuario solo da el nombre del lote — antes quedaba `NULL` y el trigger de consistencia
   UPP/lote rechazaba el insert.
2. `current_weight_kg`: mismo bug de tipos descrito arriba (`'number'` → `'string'`); además, el
   Agente IA **inventaba** un peso cuando el usuario no lo mencionaba (120kg, luego 100kg) — se
   reforzó el `toolDescription` (parámetro y descripción principal) prohibiéndolo explícitamente.
3. Nueva validación de duplicado: rechaza el insert si el `rfid_siniiga` dado ya identifica a otro
   animal del mismo tenant en cualquiera de las 3 columnas de identificador — antes insertaba un
   segundo animal duplicado sin aviso.

### 📌 Pendientes que quedan abiertos

* No existe tool MCP de **consulta** de historial de eventos por animal (reproducción/
  desparasitación/castración) — las 8 tools nuevas son de escritura.
* Decisión de producto pendiente: si `void_event` debe revertir estado del animal por tipo de
  evento (rompería su diseño genérico).

### ✨ Cattle Event Log: filtro y agrupación por Lote

La Bitácora no permitía filtrar ni agrupar por lote. Nuevo selector **Lote** (Todos / Sin lote /
lotes del módulo activo) y nueva opción **Agrupar por → Lote** (`Lote: <nombre>` / `Lote: Sin lote`).
La exportación CSV respeta el filtro, igual que el de tipo de evento.

* **Lote ACTUAL del animal**, no el lote en el que estaba al momento de cada evento: un animal
  trasladado muestra todo su historial bajo su lote de hoy. Mismo criterio que las demás columnas de
  estado del animal (categoría, módulo).
* **Sin cambios de base de datos (sin migración 064):** el lote actual ya llega al componente vía
  `vw_cattle_kpi.lot_name` (`cattle_livestock.lot_id → production_unit_lots`), cruzado por
  `livestock_id`. Misma fuente que "Filtrar Lote" de Inventario (`@shared/utils/lot.util`).
* Las opciones del selector se derivan de los animales del módulo activo; los animales sin lote
  aparecen bajo "Sin lote" y quedan fuera al elegir un lote específico.
* ⚠️ Filtro por **nombre** de lote, igual que Inventario: el nombre es único por UPP, no por tenant.
  Hoy ningún tenant repite nombre de lote entre UPPs (verificado 2026-10-04); si ocurre, ambos lotes
  se mezclarían en la Bitácora.

### ✨ Cattle Event Log: Reproducción, Desparasitación, Castración, Traslado y Cambio de Arete

La Bitácora (`vw_cattle_event_log`) no incluía los eventos de las tablas nuevas
`cattle_breeding_events`, `cattle_deworming_events` y `cattle_castration_events`, ni los movimientos
`TRASLADO`/`CAMBIO_ARETE` de `historico_movimientos`.

**Migración 063** (`CREATE OR REPLACE VIEW`, aplicada y verificada en LOCAL y PRODUCCIÓN el
2026-10-04): cuatro ramas `UNION ALL` al final de la vista, sin cambiar columnas ni las 8 ramas
existentes (0 filas previas modificadas en ambos ambientes).

| `event_type` | Fuente | Fecha | Detalle (`description`) |
|---|---|---|---|
| `REPRODUCCION` | `cattle_breeding_events` | `breeding_date` | método — semental — parto estimado — notas |
| `DESPARASITACION` | `cattle_deworming_events` | `application_date` | producto — dosis — refuerzo — notas |
| `CASTRACION` | `cattle_castration_events` | `castration_date` | categoría anterior → nueva — método — notas |
| `TRASLADO` / `CAMBIO_ARETE` | `historico_movimientos` | `fecha_registro` | origen (`lot_origen_anterior`/`upp_origen_anterior`) — notas |

* **Anulaciones:** los eventos de las tres tablas nuevas anulados en `event_voids` (mismo tenant) no
  aparecen. Verificado: la castración anulada del tenant de pruebas no se muestra.
* **Fuera de alcance a propósito:** `VENTA`/`BAJA_MORTANDAD`/`REVERSION` de `historico_movimientos`
  (posible duplicidad con las filas `Solicitud de Baja/Venta`, decisión de producto pendiente).
* **Frontend:** los 5 tipos nuevos en `CattleEventType`, etiquetas, filtro por tipo, colores de badge
  y detalle en tabla y CSV.
* ⚠️ `CAMBIO_ARETE` cubre cualquier identificador (SINIIGA, fuego o chip); el tipo viene en el
  detalle. La fila aparece bajo el arete SINIIGA actual del animal.

### ✨ Edición de UPP oficial (`production_units`)

No existía pantalla para corregir los datos de identificación de una UPP oficial (solo lectura en
Cumplimiento Normativo). Nuevo botón **Editar** en cada tarjeta de `admin/tenants/:tenantId/production-units`.

* **Editables:** nombre del rancho, clave UPP, estado, municipio y localidad.
* **No editables a propósito:** `state_code`/`municipality_code` (columnas `GENERATED ALWAYS` a partir
  de `upp_code`) y superficie (`surface_matrix`, se transcribe verbatim del documento SENASICA — Regla 4).
* Clave UPP validada con el mismo regex que `production_units_upp_code_format_check`.
* `uq_production_units_active_code` es **global entre tenants**: no se puede prevalidar en cliente, así
  que la violación se muestra con un mensaje que no revela a qué empresa pertenece la clave.
* Mismas protecciones que lotes: solo empresa activa, re-lectura con `getone` acotado por tenant antes
  del `update` (el gateway filtra `update` solo por PK) y validación de `error:true`.
* Escritura limitada a rol de tenant `ADMIN`/`OWNER` (`crud_models` de `production_units`).

### 🐛 Empresas: el modal "no guardaba" y cada guardado podía borrar la metadata

El `update` de `companys` sí llegaba a la base (`error:false`), pero:
* **Lectura rota:** `getone` del gateway devuelve `data` como **objeto** (`rows[0]` en `Normalize
  Data`), y `openModal` leía `res.data?.[0]` → siempre `undefined` → caía al `TenantContext` de
  localStorage (sin `metadata`). Al reabrir, el modal se veía vacío aunque el dato estuviera guardado.
* **Pérdida de datos latente:** como el modal arrancaba con `metadata: {}`, cada guardado reemplazaba
  el JSONB completo con solo lo capturado en esa sesión (clave UPP, productor, RFC… se perdían).
* `saveUpp` ignoraba `error:true` (HTTP 200) y enviaba llaves que no son columnas (`role`).
* La tarjeta y el selector no reflejaban el nombre nuevo (leen el contexto cacheado del login).

**Fix:** se desempaqueta `data` como objeto o arreglo; si no hay registro, se muestra error en vez de
abrir con datos parciales (fail-closed); se envían solo `company_name`/`metadata` (+ `industry` en
alta); se valida `error:true`; y tras actualizar se sincroniza el nombre en `availableTenants` y en el
tenant activo.

⚠️ **Hallazgo, sin cambiar aquí:** el modal guarda `curp` y `rfc` en texto plano dentro de
`companys.metadata`, mientras que la Regla 4 de `CLAUDE.md` establece que la PII del productor se cifra
vía `sp_upsert_producer_pii()` (`livestock_producers`). Pendiente decidir si estos campos deben salir
del modal o redirigirse a ese SP.

### 🧭 "Empresa" vs. "UPP oficial": un término = un concepto

La pantalla `admin/tenants` y el menú llamaban "UPP" a la **empresa** (`companys`), y la nueva
pantalla de lotes llama "UPP" al **registro oficial SENASICA** (`production_units`). Al entrar a la
empresa "UPP 54" aparecía otra "UPP" ("EL PUYACATENGO", clave `27-009-4146-002`), lo que se
percibía como un cambio de nombre inesperado.

* `admin/tenants`, su modal de alta/edición y la entrada del menú ahora dicen **Empresas** /
  **Nueva Empresa**. "UPP" queda reservado para las UPP oficiales (`production_units`).
* Breadcrumb en las pantallas nuevas: `Empresas › <empresa> › UPP <clave> · <rancho> › Lotes`.
* Botón con texto **"UPP oficiales y Lotes"** en el pie de la tarjeta de la empresa activa (antes
  un ícono sin etiqueta, poco descubrible en modo oscuro).

Fuera de alcance, pendientes de validar con el cliente: "Personal UPP" en el menú, el campo
"Clave UPP" del modal de empresa (metadata SINIIGA), y el nombre de la empresa "UPP 54" (dato capturado
por el cliente). El Agente IA sigue tratando "UPP" como sinónimo de empresa (Regla 11 de `CLAUDE.md`).

### ✨ Módulo de administración de Lotes por UPP (`production_unit_lots`)

Hasta ahora los lotes solo se podían crear/consultar directo en base de datos. Nuevo flujo en
`admin/tenants` → **UPP y Lotes** (solo para la empresa activa):

* `admin/tenants/:tenantId/production-units` — UPPs (`production_units`) del tenant activo.
* `admin/tenants/:tenantId/production-units/:uppId/lots` — tabla de lotes (nombre, tenencia,
  arrendador, animales asignados, estado) con alta, edición, desactivación y reactivación.

**Reglas aplicadas (solo frontend, sin cambios de esquema, vista ni gateway):**
* **Fail-closed multi-tenant:** `activeTenantRouteGuard` rechaza cualquier `:tenantId` distinto
  del tenant activo (nunca cambia de tenant implícitamente); la UPP de la URL se revalida con un
  `getone` acotado por tenant; toda fila devuelta se descarta si su `id_company` no coincide; y
  **antes de cada `update` se re-lee el lote con `getone` acotado por tenant** (ver hallazgo abajo).
* **Sin DELETE físico:** "eliminar" es `is_active = false`; el modelo Meta-CRUD tampoco expone DELETE.
* `lessor_name` solo se captura con tenencia `RENTADA` y se envía `null` en cualquier otro caso
  (incluido al cambiar de `RENTADA` a otra tenencia) — respeta `production_unit_lots_lessor_only_if_rented_check`.
* Unicidad de `lot_name` validada en cliente (case-insensitive, solo entre lotes activos, igual
  que `uq_lot_name_per_unit`); la violación del índice que llegue del gateway (`error:true`) se
  muestra como mensaje claro, incluido al reactivar un lote cuyo nombre ya usa otro lote activo.
* Escritura limitada a rol de tenant `ADMIN`/`OWNER` (mismo criterio que `crud_models.allowed_roles_insert/update`).

⚠️ **Limitaciones conocidas (aceptadas, requieren cambio de BD fuera de este alcance):**
* `cattle_livestock.lot_id` no está expuesto por ningún modelo Meta-CRUD ni por `vw_cattle_kpi`.
  El conteo de animales por lote se deriva de `vw_cattle_kpi` por (`production_unit_id`,
  `upper(lot_name)`) excluyendo estados terminales — exacto mientras el nombre sea único en la
  UPP; si dos lotes comparten nombre (uno inactivo) se muestra "—" en vez de un número dudoso.
* Desactivar un lote **no** limpia `lot_id` de sus animales: siguen vinculados al lote inactivo
  (no quedan "sin lote"). El diálogo de confirmación lo advierte así, con el conteo real.

🔴 **Hallazgo de seguridad (gateway, no corregido aquí):** en el `Build Query` de `v6/CRUD`
(verificado en la instancia LOCAL de n8n, 2026-10-03; pendiente confirmar en PRODUCCIÓN), `update`
filtra **solo por llave primaria** y agrega el tenant del header al `SET`, no al `WHERE`. Un tenant
que conozca el id de un registro ajeno puede modificarlo **y reasignarlo a su propio tenant**.
Aplica a todo modelo con `UPDATE` y columna `tenant_id`/`id_company`. Ver `CLAUDE.md` → Deuda técnica.

### 🐛 "Cattle Event Log" ignoraba el módulo seleccionado (Cría / Engorda / Reproducción)

La pestaña "Cattle Event Log" de `main-dashboard` mostraba exactamente las mismas filas sin
importar el módulo activo, mientras Inventario y los KPIs sí cambiaban (ej. tenant 3: 16 → 0 → 2
cabezas). No era un bug de backend: `vw_cattle_event_log` ya trae `livestock_id` por fila, y el
componente recibía a propósito el hato completo del tenant (`cattleList()`) desde `624b918`, que
lo desacopló de `filteredCattleList()` para que animales vendidos/muertos no perdieran su historial.

**Fix (solo frontend, sin cambios de vista ni de gateway):**
* Nuevo computed `eventLogCattleList` en `main-dashboard`: filtra `cattleList()` **solo por
  módulo** (`business_model === activeTab`). Deliberadamente **sin** especie/lote y **sin**
  `herdStatusFilter` — un animal vendido o muerto conserva su historial dentro de su módulo (no se
  reabre lo corregido en `624b918`).
* Nuevo input `moduleCattleData` en `CattleEventLogComponent`; las filas se filtran por
  `livestock_id` contra ese subconjunto. `cattleData` (hato completo) se mantiene como la compuerta
  de aislamiento multi-tenant — el filtro de módulo es de alcance, no de seguridad.
* Animales sin `business_model`: mismo criterio que `scopedCattleList` en el resto de la página
  (excluidos). Verificado 2026-10-01: 0 animales sin `business_model` en los tenants 3, 5 y 6.

⚠️ **Limitación conocida (aceptada):** el módulo usado es el `business_model` **actual** del animal,
no el que tenía al momento del evento — no existe historial de módulo. Una cría nacida en CRIA y
movida después a ENGORDA muestra su nacimiento (y todo su historial) bajo ENGORDA.

## [1.15.1] - 2026-09-30

### 🐛 Bug real: el Agente IA sumaba mal el resultado de `count_livestock`

`count_livestock` devuelve una fila por combinación categoría+estatus (ej. 7 filas
para 12 animales reales). Al preguntar "¿cuántos animales en total?", el LLM debía
sumar el campo `total` de todas las filas — y en la práctica se "perdía" algunas:
en una prueba real devolvió **9** en vez de **12**, omitiendo silenciosamente las
3 filas de categoría `VACA` de la suma (aunque sí las describió correctamente en el
desglose). No es un bug de SQL ni de datos — la query ya traía el desglose correcto,
verificado fila por fila contra el dashboard. Es un error de aritmética del modelo
sobre datos tabulares, no corregible con más instrucciones de prompt.

**Fix:** se quita al LLM la necesidad de sumar. La query ahora calcula el total real
con una función de ventana (`SUM(COUNT(*)) OVER ()`) y lo entrega como columna
`grand_total`, idéntica en cada fila. El `toolDescription` se actualizó para
instruir explícitamente: usar `grand_total` tal cual, nunca sumar `total` a mano
ni omitir filas. De paso se corrigió una línea de documentación desactualizada del
mismo `toolDescription` que aún prometía "default ACTIVO" (superada por el fix de
v1.14.1, exclusión de `VENDIDO`/`FINALIZADO`/`BAJA_DEPURACION_DATOS`).

Verificado en LOCAL y producción: "¿cuántos animales tengo en total?" → 12,
desglose completo y correcto por categoría/estatus, coincide con el dashboard.

⚠️ Patrón a vigilar: cualquier otra tool MCP que agrupe filas y espere que el LLM
sume manualmente un total está expuesta al mismo tipo de error. Ninguna otra tool
del servidor hace esto hoy (todas las demás son de una sola fila por operación),
pero aplica el mismo criterio (calcular el total en SQL, nunca en el prompt) si se
agrega una en el futuro.

## [1.15.0] - 2026-09-28

### 🐂 Módulo de Reproducción en el Dashboard

* La base de datos ya manejaba el modelo de negocio `REPRODUCCION`, pero `main-dashboard` solo
  ofrecía las vistas de Cría y Engorda — los animales de reproducción no tenían un tablero propio.
* **Nuevo tipo `BusinessModel`** (`'CRIA' | 'ENGORDA' | 'REPRODUCCION'`) en `livestock.model.ts`,
  usado por `Livestock.business_model`, `activeTab` y `setTab()` — fuente única del tipo.
* **Nueva pestaña "Módulo de Reproducción"** en `main-dashboard`, con deep link `?tab=reproduccion`
  (cualquier otro valor sigue cayendo en `CRIA` por default).
* **Nuevo componente `ReproduccionDashboardComponent`** (standalone, OnPush, misma estructura que
  Engorda): filtra estrictamente `business_model === 'REPRODUCCION'`, muestra cabezas del hato
  reproductor, peso promedio y hembras con diagnóstico `PREÑADA`, más una gráfica de composición del
  hato por categoría.
* ⚠️ **Nombres parecidos:** `ReproductiveDashboardComponent` (existente) es el tablero de **Cría**, no
  el de Reproducción — renombrarlo a `CriaDashboardComponent` queda como refactor pendiente.

### 📋 Cattle Event Log: cobertura de las 15 herramientas MCP

* `vw_cattle_event_log` solo cubría `PESO`, `SALUD`, `PARTO` y `NACIMIENTO` — tres tools de escritura
  del Agente IA no dejaban rastro en la bitácora: `register_livestock_purchase`, `log_weaning_event`
  y `log_mortality_event`/`request_livestock_sale`.
* Tres ramas `UNION ALL` nuevas en la vista para `COMPRA`, `DESTETE`, `SOLICITUD_BAJA` y
  `SOLICITUD_VENTA`, reutilizando `health_event_type` para el estado de la solicitud
  (`PENDIENTE`/`APROBADO`/`RECHAZADO`/`EXPIRADO`) y `medicines_json` para el payload crudo — mismo
  patrón de reutilización de columnas de la rama `SALUD`, sin cambiar la forma de la vista.
* Frontend: `CattleEventType`, etiquetas, filtros, badges y detalle extendidos a los 4 tipos nuevos.
  Los gastos (`register_ranch_expense`) quedan fuera a propósito — viven en "Historial de Gastos".
* ⚠️ **El cambio a la vista se aplicó directo en Postgres, sin migración versionada en el repo.**

### 📌 Pendientes que quedan abiertos

* El formulario de alta/edición (`cattle-detail-modal`) todavía no ofrece `REPRODUCCION` en el
  selector de modelo de negocio — no se puede asignar un animal a ese modelo desde la UI.
* Versionar como migración el cambio de `vw_cattle_event_log` de esta versión.

## [1.14.1] - 2026-09-27

### 🔓 Cierre del hallazgo v1.14.0: diccionario de herramientas completado

* Las 4 tools que quedaron pendientes en v1.14.0 (`count_livestock`, `register_livestock_purchase`,
  `log_supplement_event`, `log_palpation_event`) ya están en el diccionario de herramientas de ambos
  `systemMessage` (`v6_ai_chat_cattle`, `v6_WhatsApp_Agent_Cattle`).
* ✅ Verificado en LOCAL y producción por **ambos canales, Web Chat y WhatsApp** (WhatsApp
  confirmado el 2026-09-27, después del corte inicial de esta versión).

### 🐛 Bugs reales en `count_livestock`, encontrados en su primera prueba real

* **Bug 1:** `current_status`, al omitirse, no aplicaba ningún filtro pese a que la `toolDescription`
  prometía un default de `ACTIVO` — "¿cuántas vacas tengo?" devolvía vacas en cualquier estado,
  incluida una en `BAJA_MORTANDAD`.
* **Intento de fix incorrecto (revertido en el mismo turno):** forzar el default a `'ACTIVO'` literal
  dejó la misma pregunta en 0 resultados — en este esquema una VACA adulta normalmente vive en
  `PREÑADA`/`VACÍA`, no `ACTIVO` puro (confirmado contra el CHECK constraint real: 11 valores
  posibles; uso real: 317 `ACTIVO`, 145 `VACÍA`, 110 `PREÑADA`, 4 `BAJA_MORTANDAD`, 4 `VENDIDO`,
  1 `RIESGO`).
* **Fix correcto:** exclusión explícita de los 3 estados terminales (`VENDIDO`, `FINALIZADO`,
  `BAJA_DEPURACION_DATOS`) en vez de un default positivo — decisión de negocio confirmada: todo lo
  demás, incluido `BAJA_MORTANDAD` mientras la baja no se apruebe, cuenta como "lo tengo".
* Verificado en LOCAL y PRODUCCIÓN.

### ✅ Hallazgo resuelto: inconsistencia dashboard vs. Agente IA

* Para el mismo tenant de pruebas, el dashboard (filtro "Estado: Activos") reportaba 9 cabezas activas
  y `count_livestock` reportaba 11 — la diferencia eran 2 animales en `BAJA_MORTANDAD`. Decisión del
  cliente: ambos deben ser consistentes. Corregido alineando `herd-status.util.ts` al mismo criterio
  de exclusión de `count_livestock` (`VENDIDO`, `FINALIZADO`, `BAJA_DEPURACION_DATOS`). Verificado en
  LOCAL y producción — dashboard y Agente IA coinciden. Confirmado sin efectos secundarios: 0 animales
  reales en `FINALIZADO`/`BAJA_DEPURACION_DATOS` en cualquier tenant de producción.

### 📌 Pendientes

* Ninguno — v1.14.1 queda cerrada.

## [1.14.0] - 2026-09-26

### 💉 Vacunación Estructurada en el Agente IA

* **Bug real confirmado en producción:** toda vacunación reportada por WhatsApp o Chat Web
  caía en `log_health_event` con `event_type = 'VACUNACION'` y `medicines_json = {}` — la
  tool dedicada `log_vaccination_event` ya existía en el MCP Server (su propia
  `toolDescription` incluso advertía "NO uses `log_health_event` para vacunación"), pero
  nunca apareció en el diccionario de herramientas de ningún `systemMessage`, así que el
  LLM no sabía que existía y jamás la invocaba.
* **Corregido:** ambos `systemMessage` (`v6_ai_chat_cattle`, `v6_WhatsApp_Agent_Cattle`)
  ahora enrutan vacunación explícitamente a `log_vaccination_event` — vacuna, dosis, unidad
  y fecha de refuerzo quedan en `medicines_json` estructurado.
* **Bug de `event_date` corregido en la misma tool:** usaba `COALESCE(application_date,
  CURRENT_DATE)` — sin fecha explícita, el evento quedaba a medianoche, descuadrando el
  orden cronológico de `vw_cattle_event_log` frente a otros eventos del mismo día. Cambiado
  a `COALESCE(application_date::timestamp, CURRENT_TIMESTAMP)`.

### 🛡️ Endurecimiento Zero-Hallucination (Reglas 4bis/5/6)

* **Tres patrones de alucinación distintos, confirmados en pruebas reales** contra el
  tenant ficticio (`id_company = 3`, "Pista de Hielo", arete `71569901`):
  1. Falso éxito sin invocar ninguna herramienta ("ya registré la vacunación", solo memoria
     conversacional).
  2. Excusa de negocio inventada sobre un error técnico real (`livestock_id` vacío →
     `invalid input syntax for type uuid`; el agente respondió que "el animal está VACÍA" —
     regla inexistente en el prompt).
  3. Rechazo de negocio inventado sin ningún error de por medio ("no se puede hacer otra
     llamada para el mismo evento inmediato").
* **Mitigado** con tres reglas nuevas en ambos `systemMessage`: Regla 4bis (propagación
  obligatoria del `id` de `get_livestock_info` a `livestock_id`, prohibido enviarlo vacío),
  Regla 5 (prohibición de excusas de negocio inventadas ante un error técnico real) y Regla
  6 (prohibición de rechazos inventados en herramientas rutinarias — cada evento reportado
  es un registro nuevo, sin límite de repeticiones).
* ⚠️ Mitigación de prompt sobre un modelo estocástico (`gpt-4o-mini`) — no garantiza que no
  aparezca un cuarto patrón de alucinación distinto.

### 🔍 Auditoría de Herramientas MCP — 4 tools reales, invisibles para el LLM (hallazgo, NO corregido en esta versión)

* Al releer los 3 workflows completos (no solo fragmentos de nodo) para documentar el fix
  de vacunación, se confirmó que el servidor MCP expone **15 herramientas, no 11** como se
  creía: además de `log_vaccination_event`, existen `log_supplement_event`,
  `log_palpation_event`, `count_livestock` y `register_livestock_purchase` — las últimas 4
  sin documentar hasta ahora.
* **Mismo bug de fondo que el de vacunación, sin corregir todavía:** las 4 tools están
  correctamente conectadas al servidor MCP pero **ninguna aparece en el diccionario de
  herramientas de ningún `systemMessage`**. Un usuario que reporte un suplemento o una
  palpación hoy probablemente cae en `log_health_event` genérico (sin `medicines_json`, sin
  actualizar `current_status` en el caso de palpación); una pregunta de conteo de hato
  probablemente no se responde con datos reales.
* **`log_supplement_event` y `log_palpation_event` tienen el mismo bug de `event_date`**
  que tenía `log_vaccination_event` antes de esta corrección — sin corregir.
* Decisión explícita de esta sesión: documentar el hallazgo sin tocar los workflows
  todavía — ver `workflows/09-MCP-Agent-Cattle/v6/README.md`, punto 8bis, para el detalle
  completo.

### ✅ Validado

* Confirmado leyendo los 3 JSON completos de los workflows el 2026-09-26: el fix de
  vacunación y las reglas 4bis/5/6 ya están desplegados en ambos canales.

### 📌 Pendientes que quedan abiertos

* Agregar `count_livestock`, `register_livestock_purchase`, `log_supplement_event` y
  `log_palpation_event` al diccionario de herramientas de ambos `systemMessage`.
* Corregir `event_date` en `log_supplement_event` y `log_palpation_event`.
* Inconsistencia sin resolver en el animal de pruebas (`71569901`): `current_status =
  'VACÍA'` con última palpación registrada `'PREÑADA'` — no pudo originarse en
  `log_palpation_event` (sincroniza ambos campos en la misma transacción).
  
## [1.13.0] - 2026-09-22

### 🎙️ Corrección de Sanitización de Identificadores Dictados por Voz

* **Bug real confirmado en producción (execution #699966):** Whisper transcribe folios y
  aretes dictados por voz dígito por dígito con espacios (`"9 9 9 9 8 8 8 8 7 7"`). El
  `systemMessage` del Agente IA (WhatsApp) delegaba en el propio LLM (`gpt-4o-mini`) la
  reconstrucción manual del identificador antes de invocar `get_livestock_info` — el modelo
  perdió un dígito al reensamblar (`"999988877"` en vez de `"9999888877"`), devolviendo
  "animal no encontrado" pese a que el animal existía. Texto escrito nunca tuvo el bug,
  porque llega ya contiguo (sin espacios que reconstruir).
* **Corregido:** sanitización movida a código determinista (expresión regular
  `\d(?:\s+\d){2,}`) en el nodo `Set Prompt Final` del workflow `v6/WhatsApp Agent Cattle`
  — colapsa 3+ dígitos sueltos consecutivos en un bloque contiguo antes de que el texto
  llegue al Agente IA. El `systemMessage` (Regla 2, "SANITIZACIÓN DE ARETES") se simplificó
  para asumir que el identificador ya llega limpio, en vez de pedirle al LLM que lo re-limpie.

### 📋 Vista de Auditoría de Eventos de Ganado

#### 🗄️ Base de datos
* **`vw_cattle_event_log` (nueva, migración 060, idempotente):** combina
  `cattle_weight_logs`, `cattle_health_logs` y `birth_events` por `livestock_id`, con
  `event_type` (`PESO`/`SALUD`/`NACIMIENTO`) y `tenant_id` explícito para filtrado.
* Registrada en `crud_models` (`model_name = 'cattle_event_log'`,
  `allowed_ops = {SELECT,GETALL,GETONE}`, sin escritura).

#### 🖥️ Frontend
* **Nueva pestaña "Cattle Event Log"** dentro de `main-dashboard` (app `agro-erp`), de solo
  lectura, para auditoría manual de los 3 tipos de evento capturados por el Agente IA de
  WhatsApp — nace directamente del hallazgo de pérdida de dígitos de esta misma versión,
  como mecanismo de QA continuo.

### ✅ Validado en producción

* Tenant 3 ("Pista de Hielo"), 2026-09-22: folio de prueba dictado por voz resuelto
  correctamente tras el fix de sanitización; los 3 tipos de evento (peso, vacuna,
  nacimiento) registrados y verificados vía `vw_cattle_event_log`.
* Migración 060 aplicada en LOCAL y PRODUCCIÓN con backup previo (`pg_dump -Fc`) y
  verificación de checksum (`md5sum`) tras la transferencia del archivo al servidor.
  
## [1.12.0] - 2026-09-19

### 🐄 Reporte de eventos para animales sin identificador físico

* Nueva herramienta MCP `find_calf_by_dam`: busca crías sin arete/fuego/chip nacidas de
  una madre dada en los últimos 90 días, para poder reportar mortandad o venta de animales
  recién nacidos aún sin identificador — resuelve la limitación #2 señalada en v1.11.1.
* **`livestock_id` propagado de punta a punta** en la cadena de autorización asíncrona:
  agregado a `sp_solicitar_autorizacion` (8vo parámetro) y a `sp_procesar_baja_mortandad`
  (10mo parámetro, `p_livestock_id DEFAULT NULL`) como alternativa a los 3 identificadores
  físicos.
* **Corregido bug real:** `sp_resolver_autorizacion` creaba la solicitud con `livestock_id`
  resuelto correctamente, pero no lo reenviaba a `sp_procesar_baja_mortandad` /
  `sp_procesar_salida_ganado` al aprobar — el SP real fallaba con `ERRCODE P0002` pese a
  tener el UUID correcto guardado. Corregido reenviando `v_request.livestock_id` en ambas
  invocaciones del despachador.
* Documentación retroactiva del overload de 4 parámetros de `sp_procesar_salida_ganado`
  (existía en producción desde v1.9.0, nunca documentado) y corrección de la firma
  documentada de `sp_solicitar_autorizacion` (le faltaba `p_livestock_id`, ya presente en
  producción antes de esta versión).

### 🔍 Hallazgo de seguridad — aislamiento multi-tenant en el Agente IA

* Durante las pruebas de `find_calf_by_dam`, el Agente IA envió `tenant_id: 5` (empresa
  real) en vez de `tenant_id: 3` (tenant de pruebas) al invocar la herramienta, pese a que
  el workflow de WhatsApp ya había resuelto correctamente el tenant en contexto — el LLM
  lo ignoró al construir esa llamada específica. Sin efecto real (sin match en BD para ese
  tenant), pero confirma que `tenant_id` vía `$fromAI()` en una tool MCP no es un límite de
  confianza garantizado, solo prompt-enforced.
* **Mitigado** colocando el valor literal del tenant justo antes del diccionario de
  herramientas en ambos system prompts (WhatsApp y Chat Web) — más efectivo que la regla
  general de tenant ya existente.
* Mismo riesgo confirmado también en el panel "Chat" interno del editor de n8n (no solo en
  el panel "Test" de un nodo individual): cualquier prueba del Agente IA debe hacerse por el
  canal real (WhatsApp o Chat Web app).
* ⚠️ No es una garantía arquitectónica — `v6/MCP Server Cattle` corre aislado, sin acceso al
  contexto de sesión del workflow que lo invoca. Deuda técnica abierta, ver `CLAUDE.md`.

### ✅ Validado en producción

* Tenant 3 ("Pista de Hielo"), 2026-09-18/19: mortandad ✅ (cría sin identificador →
  `BAJA_MORTANDAD`) y venta ✅ (cría sin identificador → `APROBADO`,
  `sp_procesar_salida_ganado` ejecutado sin error).

## [1.11.1] - 2026-09-16

### 🐄 Herramienta MCP de Alta de Nacimiento — validada en producción

* **`register_birth_event` (Agente IA)** conectada y probada de punta a punta por Chat Web
  y WhatsApp, con datos reales. Evento rutinario, sin protocolo de confirmación previa —
  consistente con la clasificación confirmada por el cliente (solo "Baja por muerte" y
  "Baja por venta" requieren autorización).
* Documentado por primera vez: `sp_register_birth_event` existe en **dos versiones
  sobrecargadas** en producción; la vigente (13 parámetros) introduce `p_lot_id`, que
  referencia la tabla `production_unit_lots` — previamente indocumentada, actualmente sin
  datos cargados.

### 🐛 Fixes

* **`register_birth_event` (nodo n8n):** los campos `query` y `options.queryReplacement`
  del nodo quedaron invertidos durante la construcción inicial — corregido.
* **`register_birth_event` (nodo n8n):** parámetros UUID opcionales (`dam_id`, `lot_id`,
  `production_unit_id`, `paddock_id`) fallaban con `invalid input syntax for type uuid`
  cuando el panel de prueba (o el propio modelo) mandaba string vacío en vez de omitir el
  campo. Corregido con una función `empty()` que normaliza `""`/`undefined` a `null` antes
  de castear.
* **Panel Web `/admin/autorizaciones`:** el payload de Aprobar/Rechazar no incluía
  `resuelto_por_email`, requerido por `sp_resolver_autorizacion` — el botón fallaba con
  "Se requiere email de quien reporta y de quien autoriza la baja". Corregido para leerlo
  del usuario autenticado.

### 🔍 Hallazgos confirmados en pruebas reales (no bloqueantes, documentados como deuda)

* El Agente IA no resuelve un nombre de UPP mencionado en texto libre contra
  `production_units.ranch_name` — su vocabulario trata "UPP" como sinónimo del tenant
  completo. Sin impacto en clientes actuales (ninguno tiene aún más de una UPP real
  cargada), pero es una limitación de diseño, no solo de datos.
* Un animal sin ningún identificador físico (arete/fuego/chip) — por ejemplo, una cría
  recién nacida antes de ser aretada — no puede reportarse por mortandad ni venta hoy, ya
  que `sp_solicitar_autorizacion` no acepta el `livestock_id` interno como identificador.
* Confirmado (y corregido operativamente, no en código): el panel de prueba de un nodo
  `postgresTool` en n8n ejecuta contra la base real configurada en su credencial, sin
  distinguir si la instancia de n8n abierta es local o de producción. Adoptada una
  estrategia de tenant ficticio dedicado a pruebas conversacionales del Agente IA (ver
  `CLAUDE.md`, Regla 11) para no repetir el incidente.

### ✅ Confirmaciones del cliente

* Edad de madurez reproductiva `BECERRO_TORETE → TORO`: **16 meses**, confirmado por
  Alejandro el 2026-09-15. El valor placeholder insertado originalmente resultó correcto.

## [1.11.0] - 2026-09-11

### 🔒 Subsistema de Autorización Asíncrona

Introduce un mecanismo de aprobación humana diferida para dos eventos irreversibles —
baja por mortandad y baja por venta iniciada desde el Agente IA — separando la captura del
reporte (WhatsApp/Chat) de la ejecución real del cambio de estado, que ahora requiere
aprobación explícita de un ADMIN/dueño del tenant desde el panel Web.

#### 🗄️ Base de datos
* **`pending_authorizations` (genérica) + `mortality_events` (detalle rico):** el animal
  no cambia de `current_status` al solicitar, solo al aprobarse. `payload` JSONB flexible
  por tipo de evento en vez de columnas fijas.
* **`sp_solicitar_autorizacion` / `sp_resolver_autorizacion`:** despachador con whitelist
  explícita por `tipo_evento` (sin SQL dinámico) que invoca `sp_procesar_baja_mortandad` o
  `sp_procesar_salida_ganado` según corresponda, solo al aprobar.
* **`sp_procesar_baja_mortandad` (nuevo):** mismo patrón de desambiguación
  multi-identificador que `sp_procesar_salida_ganado`. A diferencia de venta, **conserva**
  `upp_origen` (útil para análisis de mortalidad por lote). Marca automáticamente crías
  activas y sin destetar como `RIESGO` cuando muere la madre.
* **Vigencia hasta medianoche del día de solicitud**, no una ventana móvil de 24h —
  confirmado con el cliente. Revalidada tanto por un Cron diario (00:05,
  `America/Mexico_City`) como por el propio `sp_resolver_autorizacion` al momento de
  aprobar.
* **Corregido bug real de gateway:** el nodo Build Query del workflow `v6/crud` inyectaba
  `tenant_id` en el `WHERE` de cualquier `GETALL`, sin verificar si la tabla lo tenía —
  rompía el listado de los nuevos catálogos globales (`column ... tenant_id does not
  exist`). Corregido condicionando la inyección a `allowed_fields`. Agregada columna
  `sp_requires_tenant` a `crud_models` para procedimientos `call_sp` que no reciben
  `tenant_id` como parámetro.

#### 🧬 Catálogos Globales de Parametrización
* **`cattle_breed_catalog` / `cattle_lifestage_catalog` (nuevas, sin `tenant_id`):**
  pesos objetivo por raza, % de peso para primer servicio, y transiciones de categoría con
  validación dual edad+peso — la edad nunca es el único criterio de promoción.
* Datos de razas poblados en dos rondas: captura preliminar (lista de imagen, pesos
  aleatorios) corregida posteriormente con el documento de validación formal firmado por
  el cliente.
* **Corregida transición biológicamente inválida:** `NOVILLO → TORO` implicaba que un
  macho castrado pudiera convertirse en reproductor. Reemplazada por
  `BECERRO → BECERRO_TORETE → TORO` (rama separada para machos destinados a semental).

#### 🤖 Agente IA (WhatsApp / Chat Web)
* Nuevas herramientas MCP `log_mortality_event` y `request_livestock_sale`: ya no
  ejecutan el cambio de estado directamente, crean una solicitud de autorización. El
  Agente informa al usuario que la solicitud quedó pendiente de aprobación, nunca que el
  animal ya fue dado de baja.
* Candado Anti-Jailbreak (confirmación explícita antes de invocar herramientas de
  escritura) extendido a ambas herramientas nuevas en los dos *system prompts* (Chat Web y
  WhatsApp) — el de WhatsApp no lo tenía replicado explícitamente y quedó alineado con
  Chat Web en esta versión.

#### 🖥️ Frontend
* **Nueva pantalla `/admin/autorizaciones`:** pestañas Pendientes (con cuenta regresiva a
  medianoche y botones Aprobar/Rechazar con modal de confirmación) e Historial (solo
  lectura, badges por estado).
* **Nuevas pantallas de catálogos** (`/admin/catalogos/razas`, etapas de vida) siguiendo
  el mismo patrón que `tenant-list`.

#### 📚 Documentación
* **Corregido:** `cattle_livestock.category` estaba documentado como ENUM real de
  Postgres — es `VARCHAR` + `CHECK constraint`, confirmado vía `pg_type`. Afecta cómo se
  agregan valores nuevos (`ALTER TABLE ... DROP/ADD CONSTRAINT`, no `ALTER TYPE`).
* **Documentados por primera vez** (existían en producción sin documentación previa):
  `weaning_events`, `sp_register_weaning_event`, y el comportamiento completo de
  `sp_register_birth_event` (incluyendo el cambio automático de estatus de la madre de
  `PREÑADA` a `VACÍA` al registrar el parto).
* Confirmado: el workflow del gateway Meta-CRUD documentado previamente como
  `06-dynamic-crud-engine` es el mismo workflow actualmente nombrado `v6/crud` — solo
  renombrado, no una migración de infraestructura.

### 📌 Pendientes que quedan abiertos
* Edad de madurez reproductiva de `BECERRO_TORETE → TORO` — actualmente 16 meses como
  placeholder, sin confirmación específica del cliente para machos.
* `cattle_breed_catalog` sin columna que distinga programáticamente filas validadas de
  filas de captura preliminar.
* Confirmación de `requires_destination_ack` (cliente) — sin cambios desde v1.10.0.
* Rotación confirmada de `INTERNAL_SECRET`/`JWT_SECRET` en ambos ambientes — sin cambios
  desde v1.10.0.

## [1.10.0] - 2026-08-14

### 🚀 Motor de Movimientos SENASICA-REEMO y Cumplimiento Documental

Convierte el catálogo de reglas de movimiento (`cattle_movement_rules`, creado en migración
020, nunca ejecutado) en un subsistema completo y confirmado contra reglas de negocio reales
del cliente (audio grabado, 2026-08-11, más cuatro ejemplos de documentos REEMO/CZM/permiso
reales), junto con el registro de eventos de movimiento, la cadena documental de cumplimiento
que los respalda, y el historial automático de identificadores del animal.

#### 🐄 Registro de eventos de movimiento
* **`cattle_movement_events` / `cattle_movement_event_animals`:** bitácora real de
  movilizaciones, con origen y destino cada uno estrictamente uno de UPP interna, PSG interna
  o destino externo (`CHECK` de exclusividad de tres vías). Un mismo evento cubre tanto un
  animal individual como un lote completo — mismo mecanismo, solo cambia el número de filas
  en la tabla de detalle.
* **`psg_facilities`:** un PSG pasa a modelarse como una ubicación física real (a donde se
  transporta ganado), no solo como una licencia — confirmado con documentos reales del
  cliente.
* **Aislamiento multi-tenant fail-closed** vía triggers `BEFORE INSERT/UPDATE`, verificado en
  local y producción: un movimiento entre tenants distintos se rechaza explícitamente; uno
  dentro del mismo tenant se acepta.

#### 📜 Matriz de reglas confirmada (16 filas, antes 8 en borrador)
* **`PSG → UPP` queda permanentemente prohibido** — un animal que entra a un PSG nunca puede
  volver a una UPP, solo a otro PSG o salir a rastro/exportación. Confirmado y aplicado de
  inmediato (`is_confirmed = true`).
* Los requisitos ahora dependen de si el movimiento es interestatal (`is_interstate`), no
  solo del par origen/destino — un mismo par UPP→UPP tiene requisitos completamente distintos
  según cruce o no una frontera estatal.
* 14 de las 16 filas quedan con los valores reales ya capturados pero `is_confirmed = false`,
  a la espera de una única confirmación pendiente del cliente (`requires_destination_ack`) —
  el enforcement real sigue inactivo hasta que llegue esa respuesta.

#### 📄 Cadena documental real (`compliance_certificates` extendido)
* 5 tipos de documento nuevos: guía de tránsito REEMO, Certificado Zoosanitario de
  Movilización, constancia de tratamiento GBG (gusano barrenador — requisito DINESA vigente
  desde diciembre 2025, verificado independientemente contra fuentes oficiales), permiso de
  internación estatal, y carta de cesión de derechos.
* **Corrección de un bug real detectado en revisión posterior:** el constraint original de
  "sujeto único" hacía imposible insertar cualquier documento de movimiento sin forzar
  también una UPP/PSG no relacionada — no era solo una regla sin aplicar, bloqueaba la
  inserción por completo. Corregido con dos constraints (sujeto ampliado a tres opciones +
  emparejamiento tipo-de-documento↔sujeto correcto).
* **TB/BR enlazado vía tabla puente**, no FK directo: el mismo folio de hato libre puede
  respaldar varios movimientos mientras siga vigente, confirmado por los documentos CZM
  reales que citan folios TB/BR como referencia, no como documento de un solo uso.

#### 🏷️ Historial automático de identificadores
* **`cattle_identifier_history`:** registra automáticamente cualquier cambio a los tres
  identificadores del animal (fuego, arete SINIIGA, chip RFID) vía trigger — nada se pierde
  sin importar qué script haga el cambio. El motivo por default es corrección de captura;
  scripts que conozcan el motivo real (pérdida, reposición, arete suelto reasignado) pueden
  enriquecerlo sin que el resto del sistema tenga que cambiar.
* `herd_free_certificates` **registrada en `crud_models`** por primera vez desde su creación
  (migración 024) — el frontend no podía leerla ni escribirla hasta ahora.

#### 🔐 Seguridad — `upload-file`
* El microservicio de almacenamiento de archivos que respalda `compliance_documents`
  (`upload-file`, no documentado previamente) era completamente público y sin autenticación.
  Dado que va a almacenar credenciales de identificación reales, se endureció reutilizando la
  infraestructura JWT/`INTERNAL_SECRET` ya existente en `n8n-jwt-service` — mismo modelo de
  confianza de dos niveles, sin inventar un mecanismo paralelo.
* Nombres de archivo ahora criptográficamente aleatorios (antes basados en timestamp);
  SHA-256 calculado en servidor; secretos movidos fuera del `docker-compose.yml` versionado.
* **`core-auth` 0.0.1 → 0.0.2:** `apiUrl_upload` agregado a `AuthEnvironmentConfig` para que
  el interceptor funcional adjunte el JWT también hacia `upload-file` — campo opcional,
  aditivo, sin romper apps consumidoras que no suben archivos.
* ⚠️ **Pendiente operativo:** el valor real de `INTERNAL_SECRET` se expuso en texto plano
  durante el trabajo de endurecimiento y debe tratarse como comprometido. Rotación
  instruida, **no confirmada como completada**.

### 🗄️ Migraciones incluidas
`020` (aplicada por primera vez), `039`–`049`. Todas aplicadas y verificadas contra el clon
local y el VPS de producción, con respaldo previo a cada aplicación en producción.

### 📌 Pendientes que quedan abiertos
* Confirmación de `requires_destination_ack` (cliente).
* Alta de tenant/UPP/PSG para Juan Carlos (nuevo titular, primo de Alejandro y Pedro).
* Confirmación de dos grupos de registros de Pedro (8 correcciones NOVILLO→NOVILLONA, 2
  conflictos de arete reales).
* Lista final corregida del archivo `TRATAMIENTO_LOTE_ROJO_VACIO_AGO_2026.xlsx`.
* Rotación confirmada de `INTERNAL_SECRET`/`JWT_SECRET` en ambos ambientes.
* Inconsistencia en `jwt-service`: `/verify-token` no valida `internal_secret` pese a
  recibirlo.


## [1.8.1] - 2026-07-08

### 📚 Sincronización de Documentación y Validación de Esquema

Alineación de `DATABASE_SCHEMA.md` y `ARCHITECTURE.md` contra el estado real de producción (VPS), con verificación campo por campo sin discrepancias contra un clon local restaurado el mismo día.

#### 🗄️ Documentación de Base de Datos
* **Campos y tablas antes indocumentados:** `cattle_livestock.upp_origen`, la tabla de auditoría `historico_movimientos`, la vista `vw_cattle_kpi`, y las tablas `cattle_tenants`, `cattle_task_evidence` y `agriculture_telemetry`.
* **Modelo Meta-CRUD `salida_ganado` (ID 46):** Documentado en `ARCHITECTURE.md` como el único modelo que invoca una función PL/pgSQL (`sp_procesar_salida_ganado`) en lugar de una tabla física.
* **Corrección de RBAC:** `cattle_livestock` (el borrado es `ADMIN` exclusivo, no `ADMIN,EDITOR`) y `cattle_tenants` (la lectura está abierta a `EDITOR`, no solo a `ADMIN`).

#### 🔁 Infraestructura de Validación
* **Pipeline de respaldo extendido:** `backup_postgres_vps_to_local.sh` ahora replica tanto `n8n_db` como `hosting3m_db` diariamente (antes solo `n8n_db`), permitiendo validar la documentación contra un clon local sin necesitar acceso directo al VPS de producción.

## [1.8.0] - 2026-07-07

### 🚀 Consolidación del Core Business Logic y Server-Side BI

Esta versión formaliza la delegación computacional de la lógica de negocio al motor de PostgreSQL mediante Procedimientos Almacenados y Triggers, eliminando la duplicidad de reglas en la capa de integración.

#### 🏗️ Arquitectura y Procedimientos Almacenados (PL/pgSQL)
* **Meta-CRUD Gateway:** Documentación e integración formal de la función `execute_metacrud_write` para orquestar la inserción y actualización dinámica (JSONB) desde n8n de manera segura.
* **Control Sanitario Estricto:** Implementación del SP `sp_procesar_salida_ganado`. Se añadieron reglas de validación en el servidor que bloquean operaciones de venta si las pruebas de Tuberculosis y Brucelosis superan los 60 días de antigüedad o son inexistentes.
* **Automatización de Biomasa:** Alta del trigger `update_current_weight` que sincroniza el `current_weight_kg` de la tabla maestra `cattle_livestock` al detectar nuevos registros en `cattle_weight_logs`.

#### 🐾 Gobernanza de Datos y Biometría
* **Transición de Estándar Físico:** Depreciación del enfoque en aretes SINIIGA para el control de inventario en vivo debido a las bajas tasas de retención física. Adopción oficial del esquema basado en **Bolos Ruminales y Microchips Subcutáneos** (`electronic_rfid`) como Primary Key operativa.

## [1.7.0] - 2026-06-18

### 🚀 Evolución a Agro-ERP y Arquitectura Multi-Dominio

Transformación estructural del proyecto para soportar múltiples verticales de negocio (Ganadería y Agricultura) bajo un mismo ecosistema de código y persistencia, garantizando la escalabilidad transversal.

#### 🏗️ Refactorización Estructural (Feature-Driven Architecture)
* **Domain Isolation:** Renombramiento del workspace a `agro-erp`. Separación estricta de módulos en `features/livestock` y `features/agriculture`.
* **Lazy Loading Estricto:** Reescritura del `app.routes.ts` para delegar la carga de componentes mediante *Lazy Loading*, asegurando que el código agrícola no sature clientes ganaderos y viceversa.
* **Context Switcher Reactivo:** Actualización del `MainLayoutComponent` y `SidebarComponent` para reaccionar dinámicamente al `business_type` y la columna `industry` de la base de datos, alternando rutas y temas visuales (`theme-cattle` vs `theme-palm`) sin recargar la SPA.

#### 🚁 Arquitectura Híbrida y Telemetría Agrícola
* **JSONB Persistence Layer:** Creación de la tabla `agriculture_telemetry` en PostgreSQL utilizando tipos de datos JSONB para ingestar formatos variables provenientes de vuelos de drones (litros, hectáreas, agroquímicos).
* **Meta-CRUD Integration (v3):** Registro del modelo `PalmTelemetry` en el motor de n8n, permitiendo operaciones CRUD completas para la plantación de palma con seguridad Multi-Tenant inherente sin requerir nuevos endpoints.

#### 🛡️ Programación Defensiva y Paridad IA
* **Resilient Routing:** Implementación de Signals computadas (`isLivestock`, `isAgriculture`) para mitigar desincronizaciones en el Payload JWT, previniendo pantallas vacías.
* **UI Chat Restoration:** Corrección del selector de Standalone Components (`<lib-ai-chat>`) para garantizar la persistencia del Agente IA en ambos dominios operativos.

---

## [1.6.0] - 2026-06-09

### 🚀 Multi-Species Architecture & Stateful AI Context

Esta actualización mayor transforma el dashboard en una plataforma integral multiespecie y eleva el motor de Inteligencia Artificial a un nivel transaccional seguro, introduciendo desambiguación de contextos para múltiples ranchos.

#### 🐾 Arquitectura Multi-Especie y UI Reactiva
* **Database Evolution:** Creación de la columna física `species` en la tabla `cattle_livestock` y actualización de los Constraints de Postgres para soportar taxones extendidos (BÚFALO, BORREGO, etc.).
* **Meta-CRUD Synchronization:** Actualización dinámica en la tabla `crud_models` (ID 37) para mapear el campo `species` de manera nativa sin requerir endpoints adicionales.
* **Reactive Signals (Frontend):** Refactorización de `MainDashboardComponent` para extraer opciones taxonómicas y filtrar el DOM instántaneamente sin peticiones asíncronas innecesarias.

#### 🤖 Inteligencia Artificial & Stateful Context Injection
* **Context-Aware Disambiguation:** Refactorización de la herramienta MCP `get_livestock_info` para eliminar consultas ciegas (`LIMIT 1`). Ahora inyecta el `tenant_id` y permite al LLM desambiguar colisiones naturales (Ej. múltiples animales con el mismo número de fuego).
* **Web Chat Context Bridge:** Actualización de `AiService` en Angular para inyectar silenciosamente el `tenant_id` extraído desde `core-auth` hacia el webhook del Agente IA en n8n.
* **Master Prompt Consolidation:** Unificación del prompt del sistema para el Chat Web y WhatsApp con reglas de Sanitización de Aretes y protocolos Anti-Jailbreak.

#### 🛠️ Correcciones y Refactorización (Bug Fixes)
* **Fix (Angular Compiler):** Resolución de excepción `NG5002` en `EngordaDashboardComponent` reestructurando el árbol lógico de `@if / @else if` para prevenir colapsos en la renderización condicional.
* **Component Isolation:** Aplicación de filtros rígidos (`validEngordaData`) dentro de sub-componentes para prevenir contaminación cruzada de KPIs de peso entre módulos de Cría y Engorda.

---

## [1.5.0] - 2026-06-02

### 🚀 Multi-Tenant Auth & AI Data Integrity Hardening

Este release mayor consolida la arquitectura del Monorepo mediante la abstracción de la seguridad y despliega las defensas de grado empresarial para el Agente de Inteligencia Artificial, asegurando la fase estratégica de 12 meses de recolección de datos.

#### 🛡️ Inteligencia Artificial & MCP (Model Context Protocol)
* **Zero-Hallucination Firewall:** Inyección de directivas estrictas en el *System Prompt* del Agente IA (`v6_ai_chat_cattle.json`) para prohibir la inferencia de parámetros de base de datos.
* **Anti-Jailbreak Protocol (Human-in-the-Loop):** Candado de ejecución que bloquea herramientas de escritura (`log_health_event`, `register_ranch_expense`) si no existe una confirmación afirmativa explícita en el turno inmediato anterior.
* **Strongly Typed Schema Definition:** Implementación de `$fromAI` en el `v6_MCP_Server_Cattle.json` para garantizar un casting determinista de tipos (string, number) desde el LLM hacia PostgreSQL. Fix de desfase de columnas inyectando `CURRENT_TIMESTAMP`.
* **WhatsApp Field Agent:** Despliegue de `v6_WhatsApp_Agent_Cattle.json` en el nuevo directorio `workflows/09-MCP-Agent-Cattle` para captura automatizada desde campo mediante lenguaje natural.

#### 🏗️ Arquitectura Multi-Tenant (Frontend & Backend)
* **Librería `core-auth`:** Extracción exitosa de la lógica de autenticación, Guards e Interceptors desde las aplicaciones individuales hacia una librería Angular independiente (`@hosting3m/core-auth`).
* **Context Switcher:** Implementación de una interfaz reactiva basada en Angular Signals (`TenantService`) que permite a los usuarios con múltiples unidades de negocio (ej. Rancho y Hotel) seleccionar su entorno de trabajo dinámicamente.
* **Data Pipeline Resilience:** Refactorización de servicios (`CattleApiService`) implementando programación defensiva (operadores `catchError` y `map` en RxJS) para evitar colapsos de UI (`TypeError`) al desenvolver respuestas anidadas de n8n.

---

## [1.0.0] - 2026-05-21

### 🚀 Lanzamiento Inicial (Core Architecture)

Establecimiento del sistema transaccional y analítico para la gestión de ranchos ganaderos, enfocado en los ciclos de Cría (Cow-Calf) y Engorda (Feedlot).

#### 🏗️ Arquitectura & Base de Datos
* **Multi-Tenancy:** Aislamiento de datos a nivel de base de datos (`tenant_id`), permitiendo gestionar múltiples ranchos desde una sola instancia. Migración de llaves foráneas a `Integer` para compatibilidad con sistemas legados.
* **Meta-CRUD Integration:** Conexión fluida con el API Gateway de n8n, implementando reglas estrictas de integridad (`Check Constraints`) para modelos de negocio y estatus del animal (ACTIVO, PREÑADA, VACÍA, FINALIZADO).

#### 📊 Business Intelligence & Server-Side Computing
* **Vista `vw_cattle_kpi`:** Creación del motor de cálculo en PostgreSQL para resolver la Ganancia Diaria de Peso (ADG) y extraer el último diagnóstico reproductivo directamente desde campos JSONB (`medicines_json`).
* **Supresión de Mock Data:** Transición exitosa del `CattleDataService` simulado a conexiones en tiempo real usando Angular Signals y el `HttpClient`.

#### 🎨 UI/UX y Flujos Operativos
* **Tabler UI Integration:** Implementación de modales reactivos con `FormGroup` para Altas, Control de Biomasa (Pesajes) y Eventos Sanitarios.
* **Captura Flexible:** Rediseño del formulario de alta para admitir SINIIGA, Número de Fuego y Chip RFID, soportando la realidad operativa donde los animales pierden sus identificadores físicos.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite