# Changelog

Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

# Changelog - Cattle Dashboard (Ganadería Digital)

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