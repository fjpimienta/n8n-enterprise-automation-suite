# n8n Enterprise Automation Suite 🚀

### Self-Hosted Architecture: Orquestación de IA & Microservicios Soberanos

> **Arquitecto:** Francisco Jesus Pérez Pimienta (Senior Systems Engineer | PMP | Full Stack)
> **Core Stack:** n8n v2.4.6, Docker, PostgreSQL (pgvector + JSONB), Node.js (Upload Service), OpenAI (GPT-4o & DALL-E 3), Angular 21 (Signals).
> **Infraestructura:** CloudFree VPS (Hardened Linux) + Private Media CDN (autenticado, ver módulo 15).

---

## 🎯 Objetivo del Proyecto

Suite de automatización empresarial de **grado industrial** diseñada bajo la filosofía de **"Soberanía de Datos"**. Esta arquitectura transforma la automatización convencional en un **Hub de Servicios Inteligente** que ahora integra la formalización legal, comercial, y la captación directa de clientes.

1. **Soberanía Total:** Despliegue 100% Self-Hosted.
2. **Calidad Enterprise:** Uso de modelos comerciales robustos.
3. **Formalización Digital:** Generación de documentos PDF profesionales (`ui-pdf-export`) directamente desde el cliente.
4. **Seguridad Corporativa:** Gestión de identidad RBAC Multi-Tenant, Context Switcher centralizado y validación RS256.
5. **Captura Pública (Lead Gen):** Integración nativa de interfaces orientadas a la conversión directa con orquestación backend en tiempo real.

---

## 🏗 Arquitectura e Infraestructura (IaC)

El ecosistema opera en un entorno de alta densidad, maximizando los recursos del VPS mediante una arquitectura de microservicios:

| Servicio | Tecnología | Función Crítica |
| --- | --- | --- |
| **Orquestador** | n8n v2.4.6 (Enterprise) | Motor lógico central y procesamiento de Webhooks. |
| **Media Server** | Node.js / Express | CDN Privado para almacenamiento persistente. Autenticado (JWT / secreto interno compartido con Auth Gateway) desde 2026-08. |
| **Capa de Datos** | PostgreSQL + pgvector | Almacenamiento Relacional + Vectorial (RAG). |
| **Auth Gateway** | Node.js / JWT | Gestión de Sesiones Multi-Tenant e Identidad (RBAC). Mismo secreto compartido que protege el Media Server. |
| **Frontends** | Angular 21 (Signals) | SPA Distribuidas en Monorepo (Dashboard / Pista / Cattle / Website). |

---

## 📦 Catálogo de módulos y proyectos (documentación auditada al 2026-10-31)

El changelog raíz registra los cambios de suite por fecha desde 2026-08-14; no existe una
versión SemVer global vigente. Cada módulo conserva su versión independiente. La última
entrada registrada en el changelog raíz es 2026-10-25.

### Proyectos Angular del workspace

El workspace contiene **7 proyectos Angular**: cuatro aplicaciones y tres librerías
compartidas. PistaHielo está registrado históricamente en el workspace, pero está fuera de
producción y no forma parte del ciclo activo.

| Tipo | Proyecto | Estado | Función |
|---|---|---|---|
| SPA principal | `agro-erp` | Activo — v1.20.0 | ERP agropecuario y agrícola; ver [README del producto](hosting3m-workspace/projects/agro-erp/README.md). |
| SPA principal | `dashboard` | Activo — v0.11.0 | Operación administrativa del hotel; ver [README](hosting3m-workspace/projects/dashboard/README.md). |
| SPA pública | `hotel-website` | Activo, reserva online temporalmente deshabilitada | Sitio público del hotel; ver [README](hosting3m-workspace/projects/hotel-website/README.md). |
| SPA histórica | `pista-hielo` | **Legacy / fuera de producción** | Aplicación histórica; ver [README](hosting3m-workspace/projects/pista-hielo/README.md). |
| Librería compartida | `core-auth` | Activa | Autenticación, guards e identidad/contexto de empresa. |
| Librería compartida | `ui-chat` | Activa | Widget conversacional Angular conectado a webhooks configurados por la aplicación host. |
| Librería compartida | `ui-pdf-export` | Activa | Generación client-side de documentos PDF. |

El catálogo de módulos de automatización incluye además workflows y servicios que no son
proyectos Angular; sus números no representan versiones de las aplicaciones.

La suite se compone de módulos interconectados que operan como una malla de servicios:

### 1. 🔐 Secure Token Gateway (Backend)
Sistema centralizado de **Gestión de Identidad**. Administra la validación de peticiones externas, orquesta el acceso Multi-Tenant y auto-genera tokens bajo un esquema "Zero Trust".

### 2. 🛠️ Contact & CRM Bridge v2
Orquestador de entrada de leads. Realiza validación estricta de tipos (`Strong Typing`) y sanitización de datos antes de la persistencia en el CRM PostgreSQL.

### 3. 📰 Automated News Curator (v4.0)
Motor de inteligencia competitiva actualizado a **Sovereign Media** con inyección DALL-E 3.

### 4. 📢 Social Media Orchestrator (v4.0)
Orquestador omnicanal con arquitectura **Self-Hosted** y persistencia binaria avanzada.

### 5. 🤖 Multi-Service WhatsApp Hub
Agente multimodal con **enrutamiento inteligente** y memoria persistente `pgvector`.

### 6. 🛠️ Dynamic CRUD Engine
Capa de abstracción SQL que actúa como un **Backend as a Service (BaaS)** con persistencia híbrida (SQL + JSONB).
* **Cuentas de usuario (2026-10-12, `v6/CRUD`):** `users` es una tabla global compartida por todas las apps. El gateway nunca selecciona ni devuelve `password` (columnas explícitas, además del filtro de `Normalize Data`), no la acepta como filtro, búsqueda ni orden, no sobrescribe una cuenta existente en `insert`, solo actualiza a miembros exclusivos de la empresa del `x-tenant-id` y bloquea `delete`. Las membresías (`user_companies`) se escriben solo vía `sp_access_*` (migración 073 de agro-erp).

### 7. 🏨 MCP Server: Hotel Management
Implementación del **Model Context Protocol** para consultas de inventario mediante IA en lenguaje natural.

### 🏨 08. AdminHotel Dashboard
ERP integral evolucionado a una **Arquitectura Distribuida** con motor financiero, pagos en cascada (Waterfall) y escudos contra *Timezone Offsets*.

### ⛸️ 09. PistaHielo Operations Center — Legacy / Histórico
Aplicación Angular histórica para gestión de centros de entretenimiento. **Fuera de
producción y del ciclo activo de la suite**; su descripción funcional no implica operación
vigente.

### 💬 10. Shared AI Chat Library (`@hosting3m/ui-chat`)
Librería agnóstica de chat IA inyectada transversalmente en el ecosistema (`CHAT_CONFIG_TOKEN`).

### 📄 11. UI PDF Export Library (`@hosting3m/ui-pdf-export`)
Librería para la estandarización de documentos salientes con motor de cálculo fiscal automático (IVA/ISH).

### 🌍 12. Hotel Eco-Website
La interfaz pública de alta conversión del ecosistema (*Customer-Facing*) con diseño Eco-Boutique y captura reactiva.

### 🌾 13. Agro ERP Suite (Ganadería & Agricultura Digital)
*Documentación de producto actualizada para agro-erp v1.20.0 — ver
`hosting3m-workspace/projects/agro-erp/README.md` y su `CHANGELOG.md` para el detalle
técnico y el estado de despliegue.*

ERP agroindustrial multi-dominio para ganadería, agricultura (Palma), cumplimiento
SENASICA-SINIIGA y movilización REEMO.
* **Server-Side BI:** Cálculo de KPIs complejos (ADG, Litros por Hectárea) directamente en Vistas SQL.
* **Trazabilidad Resiliente IoT:** Implementación estricta de chips subcutáneos y bolos ruminales (rechazando aretes físicos por baja durabilidad en campo), con historial automático de cambios de identificador vía trigger de base de datos.
* **Inteligencia Artificial de Campo:** Uso del **WhatsApp Field Agent** (MCP) blindado con directivas *Zero-Hallucination* y validación *Human-in-the-Loop* operando bajo el *Context Switcher* Multi-Empresa.
* **Registro Normativo SENASICA-SINIIGA:** múltiples unidades de producción (UPP) por tenant, propiedad por fierro independiente de la ubicación física del animal, dictámenes de hato libre.
* **Motor de Movimientos SENASICA-REEMO:** reglas de movimiento UPP↔PSG confirmadas contra reglas de negocio reales del cliente, bitácora de traslados con aislamiento multi-tenant fail-closed, y cadena documental de cumplimiento (guía REEMO, Certificado Zoosanitario, constancia de gusano barrenador, permiso de internación estatal).
* **Usuarios y Accesos (migración 073, hotfix de seguridad):** Personal UPP administra solo las membresías de la empresa activa mediante procedimientos almacenados (`sp_access_*`, modelos `company_members`, `access_add_user`, `access_update_member`, `access_set_active`); ya no hay escrituras directas a `users`/`user_companies`. Cerrado el secuestro de cuentas compartidas entre empresas, "eliminar" reemplazado por desactivar/reactivar la membresía, y bitácora de solo inserción `access_audit_log` que nunca guarda contraseñas.

### 🤖 14. MCP Field Agent (Cattle)
Agente IA agropecuario especializado, blindado con directivas Zero-Hallucination y protocolo Anti-Jailbreak (Human-in-the-Loop). Documentado previamente solo en la tabla técnica de abajo; añadido aquí para que la lista de prosa quede alineada con ella. Ver `workflows/09-MCP-Agent-Cattle/v6/README.md`.

### 🛡️ 15. Core Auth Library (`@hosting3m/core-auth`)
*Actualizado 2026-08-14 (v0.0.1 → v0.0.2).*

Librería central de seguridad para todo el monorepo. Gestiona el ciclo de vida del JWT, Interceptors, Guards y provee el **Context Switcher Defensivo** para el enrutamiento y la inyección reactiva de temas visuales entre Unidades de Negocio. Extendida con `apiUrl_upload` (campo opcional en `AUTH_ENV_CONFIG`) para que el interceptor funcional proteja también las peticiones hacia el Media Server — cambio aditivo, no afecta a las apps que no suben archivos.

**Sobre el Media Server (`upload-file`), protegido por esta librería:** endurecido 2026-08-13
(antes sin autenticación desde su lanzamiento en `[0.9.0]`) y reforzado el 2026-08-15 con
rate limiting, sanitización de extensión de archivo y protección contra path traversal
(detectada por análisis estático CodeQL). Exige JWT válido o el secreto interno compartido
(`INTERNAL_SECRET`, rotado el 2026-08-15 tras un incidente de exposición) en toda subida y
lectura — mismo mecanismo de confianza que ya usa el Auth Gateway (módulo 1), sin un
mecanismo paralelo. El Media Server no tiene número de módulo propio en la tabla técnica —
es infraestructura compartida, no un proyecto con README independiente — de ahí que su
documentación viva aquí, junto a la librería que lo protege.

---

## 📚 Documentación Técnica por Módulo

| ID | Módulo / Servicio | Función Principal | Stack & Integraciones | Documentación |
| :---| :--- | :--- | :--- | :---: |
| `01`|**Auth JWT Gateway**| Middleware de seguridad. Valida tokens Multi-Tenant.| `Node.js` `Crypto` `JWT` | [📖 Ver Docs](workflows/01-auth-jwt-gateway/v3/README.md)|
| `02`|**Contact & CRM Bridge**|Sistema de captura de leads de Hosting3m.|`Webhook` `JWT` `Postgres`|[📖 Ver Docs](workflows/02-leads-contact/v4/README.md)|
| `03`|**RAG News Intelligence**|Curaduría de noticias automatizada.|`OpenAI` `Pinecone/PgVector`|[📖 Ver Docs](workflows/03-rag-news-intelligence/v4/README.md)|
| `04`|**Omnichannel Social**|Orquestador de publicación de contenido en redes.|`Twitter API` `LinkedIn`|[📖 Ver Docs](workflows/04-omnichannel-social/v4/README.md)|
| `05`|**AI WhatsApp Agent**|Asistente conversacional con memoria a largo plazo.|`WhatsApp` `OpenAI`|[📖 Ver Docs](workflows/05-ai-whatsapp-agent/v4/README.md)|
| `06`|**Dynamic CRUD Engine**|Capa de abstracción BaaS híbrida (SQL + JSONB).|`Postgre` `JS Logic`|[📖 Ver Docs](workflows/06-dynamic-crud-engine/v4/README.md)|
| `07`|**MCP Server Hotel**| Integración LLM-DB para gestión de cuartos.|`MCP` `Postgres`|[📖 Ver Docs](workflows/07-MCP-server-hotel/v3/README.md)|
| `08`|**AdminHotel**|Frontend administrativo de hospedaje.|`Angular 21` `Tabler`|[📖 Ver Docs](hosting3m-workspace/projects/dashboard/README.md)|
| `09`|**PistaHielo Ops (Legacy)**|Aplicación histórica; fuera de producción y del ciclo activo.|`Angular 21` `Signals`|[📖 Ver Docs](hosting3m-workspace/projects/pista-hielo/README.md)|
| `10`|**Shared AI Chat Lib**|Componente reutilizable de UI Conversacional.|`Angular 21` `InjectionToken`|[📖 Ver Docs](hosting3m-workspace/projects/ui-chat/README.md)|
| `11`|**UI PDF Export Lib**|Motor de renderizado vectorial PDF.|`jsPDF` `TypeScript`|[📖 Docs](hosting3m-workspace/projects/ui-pdf-export/README.md)|
| `12`|**Hotel Eco-Website**|Sitio público; búsqueda de disponibilidad/reserva online deshabilitada temporalmente por kill switch.|`Angular` `Tailwind`|[📖 Docs](hosting3m-workspace/projects/hotel-website/README.md)|
| `13`|**Agro ERP Suite**|ERP multi-dominio (Ganadería, Agricultura, Registro Normativo y Movimientos REEMO).|`Angular 21` `SQL Views` `PL/pgSQL`|[📖 Docs](hosting3m-workspace/projects/agro-erp/README.md)|
| `14`|**MCP Field Agent**|Agente IA agropecuario con Zero-Hallucination.|`n8n` `MCP` `OpenAI`|[📖 Docs](workflows/09-MCP-Agent-Cattle/v6/README.md)|
| `15`|**Core Auth Lib**|Núcleo Auth y Context Switcher Defensivo. Protege también el Media Server (`apiUrl_upload`).|`Angular 21` `RxJS`|[📖 Docs](hosting3m-workspace/projects/core-auth/README.md)|

> ✅ Nota (corregida 2026-08-15): la numeración de esta tabla (`14` MCP Field Agent, `15`
> Core Auth Lib) antes no coincidía con la lista de prosa de módulos arriba (Core Auth
> aparecía como 14 en un lado y 15 en el otro; MCP Field Agent faltaba en la prosa). Ambas
> secciones ya están alineadas — ver la lista de módulos arriba para la versión corregida.

---

## 📈 Roadmap & Gestión de Proyectos (SDLC)

### ✅ Completado (H1 2026)
* [x] **Monorepo Scaling:** Optimización de `tsconfig` e implementación de librerías compartidas (`core-auth`, `ui-chat`, `ui-pdf-export`).
* [x] **Sovereign Media:** Implementación de `upload-service` propio y DALL-E 3.
* [x] **Public Interface:** Despliegue de `hotel-website` interactivo conectado a webhooks.
* [x] **Core Resilience:** Implementación de MetaCRUD Boundary Shields y motor de pagos en cascada (Hotel).
* [x] **WhatsApp Field Agent (Agro):** Agente IA con NLP integrado. Certificado con protocolos Anti-Jailbreak para la fase obligatoria de recolección de datos.
* [x] **Agro ERP Transition:** Refactorización arquitectónica a entorno Multi-Dominio (Feature-Driven), habilitando la gestión paralela de Ganadería y Agricultura de Palma mediante el mismo motor Meta-CRUD.

### ✅ Completado (2026-08, ver módulo 13/14/15 arriba)
* [x] **Registro Normativo SENASICA-SINIIGA:** UPP/PSG multi-tenant, propiedad por fierro, dictámenes de hato libre.
* [x] **Motor de Movimientos SENASICA-REEMO:** reglas de movimiento confirmadas, bitácora de traslados, cadena documental de cumplimiento.
* [x] **Endurecimiento del Media Server:** autenticación JWT/secreto interno en `upload-file`, extensión de `core-auth`.

### ✅ Completado (2026-10, ver módulos 06 y 13 arriba)
* [x] **Hotfix de seguridad de cuentas de usuario:** cerrado el secuestro de cuentas entre empresas en el gateway Meta-CRUD (afectaba a agro-erp y al `dashboard` del hotel); membresías solo vía procedimientos con reglas en la base y bitácora `access_audit_log` (migración 073; introducido en agro-erp v1.16.1 e integrado en la documentación vigente v1.20.0; fecha de liberación al desplegarse).

### 🏗️ En Progreso / Backlog (Q3 / Q4 2026)
* [ ] **Huéspedes CRM:** Segmentación eco-boutique y analítica de comportamiento.
* [ ] **Eco-Metrics:** Módulo de sustentabilidad para medición de huella hídrica y eléctrica en instalaciones.
* [ ] **Conversion & Sales:** A/B Testing en la landing page y conexión con pasarelas de pago directo (Stripe/PayPal).
* [ ] **Agro-Finance (OPEX Consolidation):** Abstracción del módulo `cattle_expenses` para consolidar costos transversales por kilo de biomasa o litro de agroquímico en la nueva vertical.
* [ ] **Enforcement activo de reglas de movimiento (Agro ERP):** pendiente de una sola confirmación del cliente para activar el bloqueo automático de movimientos no permitidos.

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---
*Built with the assistance of AI-powered development tools.*