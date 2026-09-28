# 🌾 Agro ERP Suite (Ganadería & Agricultura Digital)

### 🚜 Sistema de Trazabilidad Biométrica, Meta-CRUD, Telemetría Agrícola y Movilización REEMO

## 📝 Descripción

**agro-erp** es el sistema de planificación de recursos empresariales de grado industrial dentro de la Hosting3M Automation Suite. Está diseñado para modernizar la gestión agropecuaria mediante la trazabilidad biométrica inmutable, telemetría, gobernanza de datos en tiempo real y cumplimiento normativo SENASICA-SINIIGA para movilización de ganado.

Desarrollada como una **Angular 21 SPA** estructurada por dominios (*Feature-Driven*), interactúa con un motor analítico en PostgreSQL a través de la capa Meta-CRUD de **n8n**. Toda la lógica de mutación de datos está encapsulada en el servidor (PL/pgSQL), eliminando la carga computacional en el cliente y operando bajo estricta "Soberanía de Datos" — incluyendo el almacenamiento de archivos, servido por un microservicio propio (`upload-file`) en vez de depender de terceros.

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
* [ ] **Garantía arquitectónica de `tenant_id` en tools MCP:** hoy la inyección correcta del tenant en llamadas a herramientas del Agente IA depende solo del refuerzo de prompt, no de un mecanismo verificable a nivel de arquitectura (hallazgo v1.12.0). Diagnóstico completo confirmado el 2026-09-27 sobre las 15 tools reales: todas reciben `tenant_id`/`user_email` vía `$fromAI()`, controlados por el LLM — el único freno real es el `auth_check` SQL (valida que la pareja tenant/email exista y esté activa, pero no que sea la resuelta para esta sesión específica). Solución diseñada y lista para implementar: resolver `tenant_id`/`user_email` server-side por `session_id` (tabla `agent_active_sessions`, TTL 30 min, escrita solo por el backend — nunca por el LLM), sacando esos dos parámetros del control del modelo en las 15 tools. Implementación diferida — se hará en fases (piloto con Web Chat + `count_livestock`, luego el resto de tools de lectura, luego escritura rutinaria, luego las de baja irreversible, luego WhatsApp) en una sesión dedicada, no junto con trabajo de otro tipo.
- [x] **Corrección de sanitización de identificadores dictados por voz:** pérdida de dígitos en folios/aretes transcritos por Whisper, corregida moviendo la limpieza a código determinista antes del Agente IA (v1.13.0).
- [x] **Vista de auditoría de eventos de ganado:** `vw_cattle_event_log` (peso, salud, nacimiento) expuesta en una nueva pestaña de solo lectura en `main-dashboard` (v1.13.0).
- [x] **Vacunación estructurada del Agente IA:** `log_vaccination_event` correctamente enrutada en ambos canales, con Zero-Hallucination reforzado (v1.14.0).
- [x] **Bug de `event_date` en `log_supplement_event`/`log_palpation_event`:** corregido — usan `CURRENT_TIMESTAMP` en vez de `CURRENT_DATE`, mismo fix ya aplicado en `log_vaccination_event` (v1.14.0, 2026-09-27).
- [x] **Visibilidad completa de herramientas MCP para el Agente IA:** `count_livestock`, `register_livestock_purchase`, `log_supplement_event` y `log_palpation_event` agregadas al diccionario de ambos System Prompts, verificado por Web Chat y WhatsApp (v1.14.1, 2026-09-27).
- [x] **Consistencia dashboard vs. Agente IA en conteo de "activos":** resuelto — `herd-status.util.ts` alineado con el criterio de `count_livestock` (excluye solo `VENDIDO`/`FINALIZADO`/`BAJA_DEPURACION_DATOS`, ya no `BAJA_MORTANDAD`). Verificado en LOCAL y producción: dashboard y Agente IA coinciden para el mismo tenant. Confirmado además que ningún tenant en producción tiene animales reales en `FINALIZADO` o `BAJA_DEPURACION_DATOS` — el cambio de criterio no alteró ningún conteo existente (v1.14.1, 2026-09-27).
- [x] **Módulo de Reproducción en el dashboard:** pestaña y tablero dedicados para el modelo de negocio `REPRODUCCION` (v1.15.0, 2026-09-28).
- [x] **Cattle Event Log con cobertura de las 15 tools MCP:** compras, destetes y solicitudes de baja/venta visibles en la bitácora (v1.15.0, 2026-09-28).
- [ ] **Asignar `REPRODUCCION` desde la UI:** el formulario de alta/edición de ganado solo ofrece Cría y Engorda.

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite