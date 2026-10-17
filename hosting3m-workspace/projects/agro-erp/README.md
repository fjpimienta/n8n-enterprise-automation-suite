# 🌾 Agro ERP Suite (Ganadería & Agricultura Digital)

### 🚜 Sistema de Trazabilidad Biométrica, Meta-CRUD, Telemetría Agrícola y Movilización REEMO

## 📝 Descripción

**agro-erp** es el sistema de planificación de recursos empresariales de grado industrial dentro de la Hosting3M Automation Suite. Está diseñado para modernizar la gestión agropecuaria mediante la trazabilidad biométrica inmutable, telemetría, gobernanza de datos en tiempo real y cumplimiento normativo SENASICA-SINIIGA para movilización de ganado.

Desarrollada como una **Angular 21 SPA** estructurada por dominios (*Feature-Driven*), interactúa con un motor analítico en PostgreSQL a través de la capa Meta-CRUD de **n8n**. Toda la lógica de mutación de datos está encapsulada en el servidor (PL/pgSQL), eliminando la carga computacional en el cliente y operando bajo estricta "Soberanía de Datos" — incluyendo el almacenamiento de archivos, servido por un microservicio propio (`upload-file`) en vez de depender de terceros.

---

## 🚀 Key Features (v1.17.0) — Órdenes de venta

*Base de datos y workflows en producción desde 2026-10-16; la fecha de liberación se fija al desplegar el frontend.*

### 1. 🧾 Una orden para toda la venta
* El capataz pide por chat o WhatsApp "Vendí los 30 becerros del lote Maceo, guía 7139696" o una lista
  de aretes de varias UPP y empresas: el sistema arma **una sola orden** (`OV-000123`), muestra una vista
  previa agrupada por empresa / UPP / guía y la crea solo con su "Sí". Todo o nada.
* Cada animal queda como solicitud en **su propia empresa**; el ADMIN de cada empresa autoriza solo su parte.
* Puede pedir cualquier miembro ADMIN o EDITOR de la empresa del animal, sin importar la UPP; "Solo lectura" no.

### 2. 📦 Venta por lote sin dictar aretes
* El lote se envía como un solo renglón y la **base de datos** lo expande; si la cantidad no coincide, avisa.
  Mismo principio que la sanitización por voz de v1.13.0: lo que el modelo hace mal (elegir filtros,
  listar decenas de aretes) se movió a código determinista.

### 3. ✅ Aprobación por guía u orden
* Panel agrupado por orden y guía, aprobación en lote con precio por cabeza o por kilo, confirmación del total,
  progreso y resultado por animal. Aviso cuando la orden incluye animales de otras empresas.

### 4. ✉️ Un correo por orden y empresa
* Solo a los ADMIN activos de esa empresa, con resumen por guía y aretes. Revisión cada 5 minutos.

### 5. 🔒 Una solicitud pendiente por animal
* Trigger + índice único: un animal no puede tener a la vez una venta y una mortandad pendientes.

### 🗄️ Migración 074
`074_sale_orders.sql` (dry run por default), `074_tests.sql` (LOCAL, con `ROLLBACK`) y
`074_rollback.sql` (sin DROP ni DELETE: deshabilita las órdenes y conserva los datos).

---

## 🚀 Key Features (v1.16.1) — Hotfix de seguridad: Usuarios y Accesos

*Parche sobre v1.16.0. La fecha de liberación se fija al desplegarse en producción.*

### 1. 🔐 Personal UPP con acceso acotado por membresía
* La pantalla **Personal UPP** (`/admin/personal`) ya no escribe directo en `users` ni en `user_companies`: lee la vista `vw_company_members` (modelo `company_members`) y escribe solo a través de tres procedimientos almacenados, `sp_access_add_user`, `sp_access_update_member` y `sp_access_set_active` (modelos `access_add_user`, `access_update_member`, `access_set_active`).
* Las reglas viven en la base de datos, no en la UI: solo un ADMIN activo de la empresa administra su personal; correo normalizado (trim + minúsculas) y validado; un ADMIN no puede cambiar su propio rol ni desactivarse; ninguna empresa puede quedarse sin ADMIN activo.
* **"Eliminar" ya no existe:** se reemplazó por **Desactivar / Reactivar acceso a esta empresa**. Solo cambia la membresía de esa empresa; la cuenta global y el acceso a otras empresas no se tocan.
* El rol `CUSTOMER` se muestra como **"Solo lectura"** (aplica en el panel web; el Agente IA todavía no valida rol — Fase 3).

### 2. 🛡️ Cierre del secuestro de cuentas entre empresas
* **Hallazgo real:** el alta de usuario del gateway sobrescribía la contraseña y el perfil de una cuenta existente de otra empresa (upsert por correo), y la edición/baja de `users` no tenía alcance por empresa. Existían cuentas reales con acceso a varias empresas, así que era explotable entre cuentas reales.
* **Ahora:** agregar a una persona que ya tiene cuenta solo crea su membresía — nunca modifica su nombre ni su contraseña. El nombre, teléfono y contraseña de alguien que también pertenece a otra empresa solo los cambia esa persona.
* El gateway (`v6/CRUD`, nodo Build Query) aplica la misma regla al modelo `users` crudo, que todavía usa el `dashboard` del hotel: `insert` sin sobrescribir, `update` solo para miembros exclusivos de la empresa, `delete` bloqueado; `password` nunca se selecciona, nunca se devuelve y nunca se acepta como filtro, campo de búsqueda ni columna de orden. `SELECT` de `users` queda solo para ADMIN y `user_companies` es de solo lectura vía gateway.

### 3. 🧾 Bitácora de accesos (`access_audit_log`)
* Tabla de solo inserción con cada alta, cambio de rol, edición de perfil y activación/desactivación: quién, a quién, qué empresa, valor anterior y nuevo.
* Nunca guarda contraseñas ni hashes (solo `password_changed: true/false`).

### 4. 🗄️ Migración 073 y pruebas
* `database/migrations/073_users_access_hotfix.sql` — aditiva e idempotente; re-aplicarla después del rollback restaura su configuración completa.
* `073_users_access_hotfix_rollback.sql` — solo revierte lo que 073 cambió y desactiva (nunca borra) los modelos que creó. ⚠️ Revertir la migración exige volver a desplegar también el frontend anterior.
* `073_tests.sql` (21 pruebas funcionales, todo con `ROLLBACK`) y `073_state_check.sql` (verificación de solo lectura para la secuencia aplicar → rollback → re-aplicar).

### 🗄️ Migraciones desde v1.16.0

| Migración | Contenido |
|---|---|
| `067` | Bitácora de eventos en hora de Ciudad de México (vista; aplicada 2026-10-08, versionada después) |
| `068` | Corrección de datos: fecha de compra de dos registros del tenant de pruebas (2026-10-08) |
| `069` | Autorizaciones: aprobar/rechazar solo ADMIN activo de la empresa; cancelación solo por el solicitante |
| `070` | Corrección de datos (tenant 6): seis ventas directas del 2026-10-03 autorizadas fuera del sistema |
| `071` | Ingresos por venta: el capataz solicita, el ADMIN fija el precio al aprobar; precios de referencia |
| `072` | Vencimiento de autorizaciones al final del día en hora de Ciudad de México |
| `073` | **Hotfix de seguridad: Usuarios y Accesos** (v1.16.1) |
| `074` | **Órdenes de venta** (v1.17.0): `sale_orders`, venta por lote, una solicitud pendiente por animal |

---

## 🚀 Key Features (v1.16.0)

### 1. 🐄 Gestión Avanzada de Hato vía Agente IA — 8 herramientas MCP nuevas
* **Traslado intra-UPP, reproducción, desparasitación, castración, cambio de identificador, autorización y anulación de eventos:** antes solo accesibles por escritura directa en base de datos, ahora disponibles por WhatsApp y Chat Web — `move_livestock`, `list_pending_requests`, `review_pending_request`, `log_breeding_event`, `log_deworming_event`, `update_livestock_tag`, `log_castration_event`, `void_event`.
* **Dos bugs reales de arquitectura de n8n, confirmados en las 8 tools a la vez:** el campo `queryReplacement` necesita el delimitador `{{ }}` o n8n lo trata como texto literal; y el tipo declarado en `$fromAI` debe seguir el casteo intermedio de la query (`::text` antes de `::numeric`/`::date`), no el tipo final de la columna, o n8n rechaza el parámetro antes de llegar a Postgres.
* `void_event` es genérico (whitelist de 3 tablas de evento) pero **no revierte** efectos secundarios en `cattle_livestock` — anular una castración, por ejemplo, no restaura la categoría anterior del animal. Documentado como limitación de diseño, no como bug.

### 2. 🛒 Tres bugs reales corregidos en `register_livestock_purchase`
* La UPP destino ahora se infiere automáticamente de la UPP del lote cuando el usuario solo menciona el lote — antes quedaba sin asignar y el trigger de consistencia rechazaba el alta.
* El Agente IA inventaba un peso cuando el usuario no lo mencionaba (mismo bug de tipos que las 8 tools nuevas) — corregido el tipo y reforzado el `toolDescription` para prohibir explícitamente estimar o inventar el peso.
* Nueva validación de identificador duplicado: rechaza el alta si el arete/fuego/chip ya pertenece a otro animal del mismo tenant — antes se podía duplicar sin aviso.

---

## 🚀 Key Features (v1.15.0)

### 1. 🐂 Módulo de Reproducción en el Dashboard
* **Nueva pestaña "Módulo de Reproducción"** en `main-dashboard`, junto a Cría y Engorda — el modelo de negocio `REPRODUCCION` ya existía en la base de datos pero no tenía vista propia.
* Tablero dedicado con cabezas del hato reproductor, peso promedio, hembras diagnosticadas preñadas y composición del hato por categoría. Accesible también por enlace directo (`?tab=reproduccion`).

### 2. 📋 Cattle Event Log con cobertura completa del Agente IA
* La bitácora de auditoría ahora incluye compras, destetes y solicitudes de baja/venta (con su estado de autorización) — antes, tres herramientas de escritura del Agente IA no dejaban rastro visible en ella.

---

## 🚀 Key Features (v1.14.1)

### 1. 🔓 Diccionario de Herramientas del Agente IA Completado
* Las 4 tools que quedaron invisibles para el LLM en v1.14.0 (`count_livestock`, `register_livestock_purchase`, `log_supplement_event`, `log_palpation_event`) ya están en el diccionario de ambos canales. Verificado por Web Chat y WhatsApp.

### 2. 🐛 Bugs reales de `count_livestock`, corregidos
* Su primera prueba real reveló que el default de `current_status` no funcionaba como documentado, y un primer intento de arreglo (fijarlo a `ACTIVO`) resultó peor — una vaca adulta normalmente no vive en ese estado en este esquema. Corregido con una exclusión explícita de los estados que sí significan "ya no lo tengo" (vendido, finalizado, depurado), en vez de un único valor por default.

### 3. ✅ Consistencia dashboard vs. Agente IA
* El dashboard y el Agente IA reportaban cifras distintas de "cabezas activas" para el mismo tenant. Resuelto alineando el criterio del dashboard con el de `count_livestock` — ambos coinciden, verificado en LOCAL y producción.

---

## 🚀 Key Features (v1.14.0)

### 1. 💉 Vacunación Estructurada en el Agente IA
* **Bug real corregido:** toda vacunación reportada por WhatsApp o Chat Web caía en el
  evento genérico de salud sin datos estructurados, porque la tool dedicada
  (`log_vaccination_event`) ya existía en el servidor MCP pero nunca apareció en el
  diccionario de herramientas del Agente IA.
* **Fix:** ambos canales ahora enrutan vacunación a `log_vaccination_event` — vacuna,
  dosis, unidad y fecha de refuerzo quedan estructurados, no en texto libre. Corregido de
  paso un bug de fecha (medianoche en vez de hora real).

### 2. 🛡️ Endurecimiento Zero-Hallucination
* Tres reglas nuevas en el *System Prompt* de ambos canales, tras observar en pruebas
  reales tres formas distintas en que el Agente IA podía fallar sin decírselo al usuario:
  confirmar un registro sin haber llamado a ninguna herramienta, inventar una razón de
  negocio para disfrazar un error técnico real, e inventarse una política de "ya se hizo
  antes" para negarse a registrar un evento legítimo.

### 3. 🔍 Auditoría de Herramientas MCP (hallazgo, corrección pendiente)
* Al auditar los workflows completos se confirmó que el servidor MCP del módulo ganadero
  expone **15 herramientas, no 11** — 4 de ellas (conteo de hato, alta de animal comprado,
  suplementos y palpaciones) están conectadas pero **invisibles para el LLM**, porque
  ningún *System Prompt* las menciona: el mismo patrón de fondo que causó el bug de
  vacunación de esta misma versión. Documentado como deuda técnica; corrección programada
  para la siguiente versión.

---

## 🚀 Key Features (v1.13.0)

### 1. 🎙️ Corrección de Sanitización de Identificadores Dictados por Voz
* **Bug real en producción:** Whisper transcribe folios/aretes dictados por voz dígito por dígito con espacios (ej. `"9 9 9 9 8 8 8 8 7 7"`). El Agente IA (WhatsApp) delegaba en el propio LLM la reconstrucción del identificador antes de consultar la base — una tarea de conteo/reensamblaje en la que el modelo falló en producción, perdiendo un dígito y devolviendo "animal no encontrado" pese a existir.
* **Fix:** la sanitización se movió a código determinista (expresión regular) en el nodo `Set Prompt Final` del workflow `v6/WhatsApp Agent Cattle`, antes de que el texto llegue al Agente IA — ya no depende de que el LLM cuente y reensamble dígitos correctamente.
* Verificado en producción con el mismo folio de prueba tras el fix, tenant de pruebas dedicado ("Pista de Hielo").

### 2. 📋 Vista de Auditoría de Eventos de Ganado
* **Nueva vista de solo lectura `vw_cattle_event_log`** (migración 060): combina peso, salud/vacunación y nacimiento en una sola bitácora por animal, filtrable por tenant.
* **Nueva pestaña "Cattle Event Log"** en `main-dashboard`, de solo lectura, para que cualquier admin pueda auditar manualmente los eventos capturados por el Agente IA de WhatsApp sin entrar a la base de datos.
* Nace directamente del hallazgo de pérdida de dígitos de esta misma versión, como mecanismo de QA continuo — no solo para ese incidente puntual.

---

## 🚀 Key Features (v1.12.0)

### 1. 🐄 Reporte de Mortandad/Venta para Animales sin Identificador Físico
* **Nueva herramienta MCP `find_calf_by_dam`:** localiza crías sin arete/fuego/chip nacidas de una madre dada en los últimos 90 días — resuelve el caso real de una cría recién nacida que muere o se vende antes de ser aretada, algo imposible de reportar hasta esta versión.
* **`livestock_id` (UUID interno) propagado de punta a punta** por toda la cadena de autorización asíncrona (`sp_solicitar_autorizacion` → `pending_authorizations` → `sp_resolver_autorizacion` → `sp_procesar_baja_mortandad`/`sp_procesar_salida_ganado`) como alternativa a los tres identificadores físicos.
* Probado end-to-end en producción (tenant de pruebas dedicado), ambos flujos — mortandad y venta — con crías reales sin identificador.

### 2. 🔍 Hallazgo y Mitigación de Aislamiento Multi-Tenant en el Agente IA
* Confirmado en pruebas reales: el `tenant_id` inyectado en una llamada a una tool MCP puede ser ignorado por el LLM al construir los parámetros, pese a estar correctamente resuelto en el contexto de la conversación — sin efecto real en la prueba que lo detectó, pero confirma que no es una garantía arquitectónica, solo *prompt-enforced*.
* **Mitigado** reforzando ambos system prompts (WhatsApp y Chat Web) con el valor literal del tenant justo antes del diccionario de herramientas. Sigue como deuda técnica de arquitectura — ver Roadmap.

---

## 🚀 Key Features (v1.11.0)

### 1. 🔒 Autorización Asíncrona para Bajas Irreversibles
* **Mortandad y venta (vía Agente IA) requieren aprobación humana diferida:** el reporte se captura de inmediato (WhatsApp/Chat), pero el cambio de estado del animal espera la aprobación explícita de un ADMIN/dueño desde el panel Web — vigencia hasta medianoche del día de la solicitud, sin importar la hora exacta en que se solicitó.
* **Notificación automática por correo** a los ADMIN del tenant correspondiente, con enlace directo al panel de aprobación.
* **Panel Web dedicado** (`/admin/autorizaciones`) con pestañas de Pendientes e Historial, trazabilidad completa de quién reportó y quién autorizó.
* **Marcado automático de crías en riesgo:** si el animal fallecido tiene crías dependientes sin destetar, quedan señaladas para revisión humana, sin decisiones automáticas sobre su destete o descarte.

### 2. 🧬 Catálogos Globales de Parametrización Zootécnica
* **Catálogo de Razas** (pesos objetivo, % de peso para primer servicio, gestación promedio) y **Catálogo de Etapas de Vida** (transiciones de categoría con validación dual edad+peso), poblados con datos validados directamente con el cliente.
* **Principio rector:** la edad es un disparador de revisión, nunca el criterio determinante por sí solo — toda transición reproductiva real cruza edad y peso antes de promover una categoría.
* Rama de reproductor macho (`Becerro Torete`) separada de la rama de engorda (`Novillo`), corrigiendo una transición previa biológicamente incorrecta que permitía a un macho castrado convertirse en toro reproductor.

---

## 🚀 Key Features (v1.10.0)

### 1. 🚚 Motor de Movimientos SENASICA-REEMO
* **Reglas de movimiento confirmadas:** el catálogo de reglas UPP↔PSG, creado como borrador meses atrás, ya está poblado con reglas de negocio reales del cliente (audio grabado + documentos REEMO/CZM/permiso reales). `PSG → UPP` queda permanentemente prohibido; los requisitos varían según el movimiento sea local o interestatal.
* **Bitácora real de movimientos:** cada traslado queda registrado con origen, destino, folio REEMO, y aislamiento multi-tenant fail-closed — un movimiento entre tenants distintos se rechaza automáticamente.
* **Cadena documental de cumplimiento:** guía de tránsito, Certificado Zoosanitario, constancia de gusano barrenador (GBG), permiso de internación estatal y carta de cesión de derechos, todos enlazados al movimiento que respaldan.
* **Historial automático de identificadores:** cualquier cambio de arete, número a fuego o chip queda registrado solo, sin depender de que un script se acuerde de hacerlo.

### 2. 🔐 Almacenamiento de Archivos Endurecido ("Sovereign Media Service")
* El microservicio propio de archivos (`upload-file`) pasó de ser completamente público a exigir autenticación JWT o secreto interno, reutilizando la infraestructura de `core-auth`/`jwt-service` ya existente — sin inventar un mecanismo de seguridad paralelo.
* Nombres de archivo aleatorios (antes predecibles), hash SHA-256 calculado en servidor, y credenciales fuera del control de versiones.

---

## 🚀 Key Features (v1.9.0)

### 1. 🏛️ Registro Normativo SENASICA-SINIIGA
* **Multi-UPP por tenant:** un rancho (`companys`) puede sostener múltiples unidades de producción registradas ante SENASICA — la equivalencia "una empresa = un predio" ya no aplica.
* **Propiedad independiente de ubicación:** el fierro de marca (`brand_registrations`) es un catálogo global, independiente de en qué UPP esté parado el animal — modela la realidad real del padrón (ganado de un titular pastando en tierra del otro).
* **Dictámenes de hato libre:** exención de la ventana de 60 días de pruebas TB/BR para hatos con certificado vigente de hasta 24 meses.
* **Linaje materno y herencia de fierro:** la cría hereda automáticamente el fierro de la madre al registrar un parto.
* ⚠️ **Esta versión también corrigió dos afirmaciones de las secciones "v1.8.0" de abajo**, verificadas contra producción el 2026-07-29 y el 2026-07-27 respectivamente — ver las notas de corrección insertadas ahí. `CHANGELOG.md` no tiene todavía una entrada `[1.9.0]` propia; pendiente agregarla.

---

## 🚀 Key Features (v1.8.0)

### 1. 🐾 Trazabilidad Multi-Especie y Biométrica (RFID / Bolo Ruminal)
* **Identidad Resiliente:** El sistema está diseñado en torno al uso de **Bolos Ruminales y Microchips Subcutáneos** (`electronic_rfid`) como estándar de retención física. Los aretes plásticos tradicionales (SINIIGA) se mantienen únicamente como metadato normativo secundario debido a su alta tasa de pérdida en campo.
  > ⚠️ **Corregido en v1.9.0 (verificado en producción 2026-07-29):** en la práctica es al revés — 262 de 270 animales (97%) no tienen bolo ruminal ni chip. El arete SINIIGA (`rfid_siniiga`) es hoy la identificación que realmente cubre al hato; `electronic_rfid` solo cubre 8 animales. Ver `CLAUDE.md`, Regla 2, y `DATABASE_SCHEMA.md`.
* **Soporte Universal:** Aislamiento de biomasa y KPIs de capitalización para hatos mixtos (Bovinos, Búfalos, Borregos) mediante la columna física `species`.

### 2. 🧠 Server-Side Business Intelligence (BI) y Meta-CRUD transaccional
* **Dynamic Gateway:** La función `execute_metacrud_write` orquesta todas las inyecciones de datos (INSERT/UPDATE) desde n8n de forma dinámica, validando permisos contra la tabla `crud_models`.
  > ⚠️ **Corregido en v1.9.0 (verificado en producción 2026-07-27):** `execute_metacrud_write` existe en la base pero **no es la ruta real de escritura** del gateway — su `p_record_id` es `integer` (incompatible con PKs UUID) y su `WHERE id = %L` está hardcodeado, ignorando `crud_models.primary_key`. El gateway real construye su propio SQL en el nodo Build Query del workflow `v6/crud`. Ver `ARCHITECTURE.md`, sección "Hallazgos confirmados sobre `execute_metacrud_write`", y `CLAUDE.md`, Regla 1.
* **Reglas Sanitarias Estrictas:** El procedimiento `sp_procesar_salida_ganado` bloquea ventas si el animal no cuenta con pruebas de Tuberculosis o Brucelosis vigentes (menos de 60 días de antigüedad).
* **Auditoría de Movimientos:** Cada venta, baja o traslado queda registrado de forma inmutable en `historico_movimientos`, preservando el `upp_origen` (rancho/centro de costos) del animal al momento del evento.
* **Sincronización de Biomasa:** Triggers en base de datos (`update_current_weight`) automatizan la actualización de la biomasa actual del animal cada vez que se registra un pesaje.

### 3. 🏢 Escalabilidad Multi-Dominio (Context Switcher)
* **Aislamiento de Negocios:** Capacidad nativa para gestionar simultáneamente Ranchos Ganaderos y Plantaciones desde una misma sesión mediante un selector reactivo, aislando el DOM y el estado en memoria.

### 4. 🤖 Inteligencia Artificial Contextual & Anti-Jailbreak
* **Desambiguación Contextual:** Inyección silenciosa del `tenant_id`. Protocolo estricto *Human-in-the-Loop* que requiere confirmación explícita para el Agente IA durante la fase de recolección de datos operativos de 12 meses.

---

## 🚀 Key Features (v1.7.0)

### 1. 🏢 Escalabilidad Multi-Dominio (Context Switcher)
* **Aislamiento de Negocios:** Capacidad nativa para gestionar simultáneamente Ranchos Ganaderos y Plantaciones (ej. Palma Africana) desde una misma sesión mediante un selector reactivo, aislando el DOM y el estado en memoria.
* **Lazy Loading:** Enrutamiento inteligente que solo descarga los módulos necesarios para la vertical operativa seleccionada.

### 2. 🚁 Arquitectura Híbrida para Telemetría (IoT & Drones)
* **Ingesta Flexible (JSONB):** Capacidad para absorber reportes de vuelo de aspersión agrícola, variables de clima y uso de agroquímicos sin romper esquemas relacionales.
* **Server-Side BI:** Delegación de cálculos pesados de rendimiento (litros por hectárea, OPEX) a Vistas Materializadas en PostgreSQL.

### 3. 🐾 Trazabilidad Multi-Especie y Biométrica
* **Identidad Resiliente:** Soporte nativo para lectura de Chip RFID (subcutáneo/ruminal) y Número a Fuego.
* **Filtrado Reactivo (Signals):** Interfaz ultra-rápida basada en `computed` signals que recalcula el valor del hato y ganancias de peso al instante.

### 4. 🤖 Inteligencia Artificial Contextual & Anti-Jailbreak
* **WhatsApp & Web Field Agents:** Desambiguación contextual dinámica inyectando silenciosamente el `tenant_id`. Protocolo estricto *Human-in-the-Loop* que requiere confirmación explícita para registrar información en la base de datos de producción.

---

## 🏗️ Arquitectura Técnica

El proyecto está optimizado para entornos rurales de baja conectividad garantizando un rendimiento extremo:
* **Framework:** Angular 21 (Standalone Components, Signals).
* **Styling:** Tabler UI + SCSS dinámico (`theme-cattle` / `theme-palm`).
* **Communication:** REST API via n8n Meta-CRUD (workflow `v6/crud`) & Webhooks.
* **Data Processing:** PostgreSQL 15+ (Views & JSONB GIN Indexes).
* **File Storage:** Microservicio propio (`upload-file`, Node/Express) autenticado vía JWT compartido con `core-auth`/`jwt-service` — sin dependencia de almacenamiento externo.

---

## 🛠️ Configuración y Desarrollo

Para levantar el módulo ganadero en entorno local:

### 1. Servidor de Desarrollo
Ejecuta el proyecto aisladamente desde la raíz del monorepo:
```bash
ng serve agro-erp

```

### 2. Build de Producción

Genera el compilado AOT para despliegue en el VPS:

```bash
ng build agro-erp --configuration=production

```
---

## 📋 Roadmap del Proyecto (Hito Q3 2026)

* [x] **Refactoring Estructural (Fase 1):** Migración a `agro-erp` y aislamiento Multi-Negocio.
* [x] **Adaptación del Backend (Fase 2):** Tablas JSONB y despliegue del modelo `PalmTelemetry` en Meta-CRUD.
* [x] **Frontend Multi-Dominio (Fase 3):** Implementación de menús reactivos y Context Switcher.
* [x] **Registro Normativo SENASICA-SINIIGA:** UPP/PSG multi-tenant, propiedad por fierro, dictámenes de hato libre (v1.9.0).
* [x] **Motor de Movimientos SENASICA-REEMO:** reglas de movimiento confirmadas, bitácora de traslados, cadena documental de cumplimiento (v1.10.0).
* [x] **Endurecimiento de Almacenamiento de Archivos:** autenticación JWT/secreto interno en `upload-file` (v1.10.0).
* [x] **Catálogos Globales de Parametrización:** razas y etapas de vida, validados con el cliente (v1.11.0).
* [x] **Subsistema de Autorización Asíncrona:** mortandad y venta vía Agente IA requieren aprobación humana diferida, con notificación por correo y expiración diaria automática (v1.11.0).
* [ ] **Motor Financiero (Fase 4):** Integración transversal del OPEX para calcular costo por kilo de biomasa vs. costo por litro de agroquímico.
* [ ] **Dashboards Consolidados (Fase 5):** Estabilización final y pruebas E2E.
* [ ] **Enforcement activo de reglas de movimiento:** pendiente de una sola confirmación del cliente (`requires_destination_ack`) para activar el bloqueo automático de movimientos no permitidos.
* [ ] **Digitalización de expediente documental:** `compliance_documents` sigue en 0 archivos cargados — estructura y seguridad listas, sin datos reales aún.
* [x] **Confirmación de edad de madurez reproductiva para `BECERRO_TORETE`:** confirmada con el cliente (16 meses) el 2026-09-15.
* [x] **Herramienta de alta de nacimiento por Agente IA (`register_birth_event`):** validada en producción por Chat Web y WhatsApp, evento rutinario sin confirmación previa (v1.11.0).
* [ ] **Resolución de nombre de UPP en texto libre:** el Agente IA no distingue una UPP específica por nombre cuando un tenant tiene varias unidades de producción reales — solo reconoce el tenant completo.
* [x] **Reporte de mortandad/venta para animales sin identificador físico:** resuelto en v1.12.0 vía la herramienta MCP `find_calf_by_dam` y la propagación de `livestock_id` en toda la cadena de autorización asíncrona.
* [ ] **Garantía arquitectónica de `tenant_id` en tools MCP:** hoy la inyección correcta del tenant en llamadas a herramientas del Agente IA depende solo del refuerzo de prompt, no de un mecanismo verificable a nivel de arquitectura (hallazgo v1.12.0). Diagnóstico completo confirmado el 2026-09-27 sobre las 15 tools reales de entonces: todas reciben `tenant_id`/`user_email` vía `$fromAI()`, controlados por el LLM — el único freno real es el `auth_check` SQL (valida que la pareja tenant/email exista y esté activa, pero no que sea la resuelta para esta sesión específica). Solución diseñada y lista para implementar: resolver `tenant_id`/`user_email` server-side por `session_id` (tabla `agent_active_sessions`, TTL 30 min, escrita solo por el backend — nunca por el LLM), sacando esos dos parámetros del control del modelo en todas las tools, hoy 23 (las 15 originales + las 8 de v1.16.0). Implementación diferida — se hará en fases (piloto con Web Chat + `count_livestock`, luego el resto de tools de lectura, luego escritura rutinaria, luego las de baja irreversible, luego WhatsApp) en una sesión dedicada, no junto con trabajo de otro tipo.
- [x] **Corrección de sanitización de identificadores dictados por voz:** pérdida de dígitos en folios/aretes transcritos por Whisper, corregida moviendo la limpieza a código determinista antes del Agente IA (v1.13.0).
- [x] **Vista de auditoría de eventos de ganado:** `vw_cattle_event_log` (peso, salud, nacimiento) expuesta en una nueva pestaña de solo lectura en `main-dashboard` (v1.13.0).
- [x] **Vacunación estructurada del Agente IA:** `log_vaccination_event` correctamente enrutada en ambos canales, con Zero-Hallucination reforzado (v1.14.0).
- [x] **Bug de `event_date` en `log_supplement_event`/`log_palpation_event`:** corregido — usan `CURRENT_TIMESTAMP` en vez de `CURRENT_DATE`, mismo fix ya aplicado en `log_vaccination_event` (v1.14.0, 2026-09-27).
- [x] **Visibilidad completa de herramientas MCP para el Agente IA:** `count_livestock`, `register_livestock_purchase`, `log_supplement_event` y `log_palpation_event` agregadas al diccionario de ambos System Prompts, verificado por Web Chat y WhatsApp (v1.14.1, 2026-09-27).
- [x] **Consistencia dashboard vs. Agente IA en conteo de "activos":** resuelto — `herd-status.util.ts` alineado con el criterio de `count_livestock` (excluye solo `VENDIDO`/`FINALIZADO`/`BAJA_DEPURACION_DATOS`, ya no `BAJA_MORTANDAD`). Verificado en LOCAL y producción: dashboard y Agente IA coinciden para el mismo tenant. Confirmado además que ningún tenant en producción tiene animales reales en `FINALIZADO` o `BAJA_DEPURACION_DATOS` — el cambio de criterio no alteró ningún conteo existente (v1.14.1, 2026-09-27).
- [x] **Módulo de Reproducción en el dashboard:** pestaña y tablero dedicados para el modelo de negocio `REPRODUCCION` (v1.15.0, 2026-09-28).
- [x] **Cattle Event Log con cobertura de las 15 tools MCP:** compras, destetes y solicitudes de baja/venta visibles en la bitácora (v1.15.0, 2026-09-28).
- [ ] **Asignar `REPRODUCCION` desde la UI:** el formulario de alta/edición de ganado solo ofrece Cría y Engorda.
- [x] **Gestión avanzada de hato vía Agente IA (8 tools nuevas):** traslado intra-UPP, reproducción, desparasitación, castración, cambio de identificador, listado/resolución de solicitudes pendientes y anulación de eventos — probadas de punta a punta en producción por chat real (v1.16.0, 2026-10-03/04).
- [x] **Tres bugs reales corregidos en `register_livestock_purchase`:** inferencia de UPP desde el lote, bug de tipos `number`/`null` en `current_weight_kg` (y el peso inventado por el Agente IA que ese bug disfrazaba), y validación de identificador duplicado (v1.16.0, 2026-10-04).
- [ ] **Anulación de eventos sin reversión de estado:** `void_event` no revierte efectos secundarios sobre `cattle_livestock` (ej. categoría tras anular una castración) — decisión de producto pendiente sobre si corregirlo.
- [ ] **Consulta de historial de eventos por animal:** no existe una tool MCP de lectura para reproducción/desparasitación/castración — las 8 tools nuevas de v1.16.0 son solo de escritura.
- [x] **Hotfix de seguridad de Usuarios y Accesos (migración 073):** secuestro de cuentas entre empresas cerrado, Personal UPP vía procedimientos con alcance por membresía, desactivar en vez de eliminar, bitácora `access_audit_log` (v1.16.1; fecha de liberación al desplegarse).
- [ ] **Usuarios y Accesos, fases 1–2 (migración 075+):** administrador de plataforma (`platform_admins`), alcance por UPP/lote (`user_scope`) y `fn_user_can_access`; además "Mi perfil" para que cualquier miembro cambie su propia contraseña.
- [ ] **Usuarios y Accesos, fase 3:** aplicar rol y alcance en el Agente IA (WhatsApp/Chat Web), las tools MCP y los procedimientos existentes — hoy "Solo lectura" solo aplica en el panel web.
- [x] **Órdenes de venta (migración 074):** una orden por venta, por lote o por aretes, a través de varias UPP y empresas; aprobación por guía/orden y un correo por orden y empresa (v1.17.0, 2026-10-16).
- [ ] **Correo del solicitante en tools MCP desde la sesión, no desde el modelo:** parte de la garantía arquitectónica de `tenant_id`/`user_email` (ver punto de arriba).

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite