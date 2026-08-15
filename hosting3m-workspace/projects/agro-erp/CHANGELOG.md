# Changelog

Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.
El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

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