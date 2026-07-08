# Changelog

Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.
El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

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