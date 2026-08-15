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

## 📦 Módulos Implementados (Suite v1.6.0)

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

### 7. 🏨 MCP Server: Hotel Management
Implementación del **Model Context Protocol** para consultas de inventario mediante IA en lenguaje natural.

### 🏨 08. AdminHotel Dashboard
ERP integral evolucionado a una **Arquitectura Distribuida** con motor financiero, pagos en cascada (Waterfall) y escudos contra *Timezone Offsets*.

### ⛸️ 09. PistaHielo Operations Center
PWA Administrativa para gestión de centros de entretenimiento con motor de cobro "Midnight Crossing".

### 💬 10. Shared AI Chat Library (`@hosting3m/ui-chat`)
Librería agnóstica de chat IA inyectada transversalmente en el ecosistema (`CHAT_CONFIG_TOKEN`).

### 📄 11. UI PDF Export Library (`@hosting3m/ui-pdf-export`)
Librería para la estandarización de documentos salientes con motor de cálculo fiscal automático (IVA/ISH).

### 🌍 12. Hotel Eco-Website
La interfaz pública de alta conversión del ecosistema (*Customer-Facing*) con diseño Eco-Boutique y captura reactiva.

### 🌾 13. Agro ERP Suite (Ganadería & Agricultura Digital)
*Actualizado 2026-08-14 — ver `hosting3m-workspace/projects/agro-erp/README.md` y
`CLAUDE.md` para el detalle técnico completo (v1.9.0–v1.10.0).*

ERP agroindustrial evolucionado a una arquitectura Multi-Dominio para la gestión de biomasa, trazabilidad biológica y telemetría de drones agrícolas (Plantaciones), con registro normativo SENASICA-SINIIGA completo y motor de movilización interestatal REEMO.
* **Server-Side BI:** Cálculo de KPIs complejos (ADG, Litros por Hectárea) directamente en Vistas SQL.
* **Trazabilidad Resiliente IoT:** Implementación estricta de chips subcutáneos y bolos ruminales (rechazando aretes físicos por baja durabilidad en campo), con historial automático de cambios de identificador vía trigger de base de datos.
* **Inteligencia Artificial de Campo:** Uso del **WhatsApp Field Agent** (MCP) blindado con directivas *Zero-Hallucination* y validación *Human-in-the-Loop* operando bajo el *Context Switcher* Multi-Empresa.
* **Registro Normativo SENASICA-SINIIGA:** múltiples unidades de producción (UPP) por tenant, propiedad por fierro independiente de la ubicación física del animal, dictámenes de hato libre.
* **Motor de Movimientos SENASICA-REEMO:** reglas de movimiento UPP↔PSG confirmadas contra reglas de negocio reales del cliente, bitácora de traslados con aislamiento multi-tenant fail-closed, y cadena documental de cumplimiento (guía REEMO, Certificado Zoosanitario, constancia de gusano barrenador, permiso de internación estatal).

### 🛡️ 14. Core Auth Library (`@hosting3m/core-auth`)
*Actualizado 2026-08-14 (v0.0.1 → v0.0.2).*

Librería central de seguridad para todo el monorepo. Gestiona el ciclo de vida del JWT, Interceptors, Guards y provee el **Context Switcher Defensivo** para el enrutamiento y la inyección reactiva de temas visuales entre Unidades de Negocio. Extendida con `apiUrl_upload` (campo opcional en `AUTH_ENV_CONFIG`) para que el interceptor funcional proteja también las peticiones hacia el Media Server (módulo 15) — cambio aditivo, no afecta a las apps que no suben archivos.

### 📁 15. Media Server / Upload Service (`upload-file`)
*Endurecido 2026-08-13 — antes sin autenticación desde su lanzamiento en `[0.9.0]`.*

Microservicio propio (Node.js/Express) para alojamiento persistente de archivos, parte de la estrategia "Sovereign Media" de la suite. Ahora exige un JWT válido o el secreto interno compartido (`INTERNAL_SECRET`) en toda subida y lectura, reutilizando la misma infraestructura de confianza del Auth Gateway (módulo 1) en vez de un mecanismo paralelo. Nombres de archivo aleatorios (antes predecibles) y hash SHA-256 calculado en servidor.

*(Módulo 15 previamente marcado como "eliminado por consolidación de la numeración" en versiones anteriores de este README — reactivado aquí para documentar el Media Server explícitamente, dado el trabajo de seguridad de 2026-08. Si esa numeración se reorganiza formalmente, actualizar también la tabla de documentación técnica más abajo.)*

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
| `09`|**PistaHielo Ops**|PWA para centros de entretenimiento.|`Angular 21` `Signals`|[📖 Ver Docs](hosting3m-workspace/projects/pista-hielo/README.md)|
| `10`|**Shared AI Chat Lib**|Componente reutilizable de UI Conversacional.|`Angular 21` `InjectionToken`|[📖 Ver Docs](hosting3m-workspace/projects/ui-chat/README.md)|
| `11`|**UI PDF Export Lib**|Motor de renderizado vectorial PDF.|`jsPDF` `TypeScript`|[📖 Docs](hosting3m-workspace/projects/ui-pdf-export/README.md)|
| `12`|**Hotel Eco-Website**|Landing page optimizada para Core Web Vitals.|`Angular` `Tailwind`|[📖 Docs](hosting3m-workspace/projects/hotel-website/README.md)|
| `13`|**Agro ERP Suite**|ERP multi-dominio (Ganadería, Agricultura, Registro Normativo y Movimientos REEMO).|`Angular 21` `SQL Views` `PL/pgSQL`|[📖 Docs](hosting3m-workspace/projects/agro-erp/README.md)|
| `14`|**MCP Field Agent**|Agente IA agropecuario con Zero-Hallucination.|`n8n` `MCP` `OpenAI`|[📖 Docs](workflows/09-MCP-Agent-Cattle/v6/README.md)|
| `15`|**Core Auth Lib**|Núcleo Auth y Context Switcher Defensivo. Protege también el Media Server (`apiUrl_upload`).|`Angular 21` `RxJS`|[📖 Docs](hosting3m-workspace/projects/core-auth/README.md)|

> ⚠️ Nota: la numeración de esta tabla (`14` MCP Field Agent, `15` Core Auth Lib) no
> coincide con la numeración de la lista de módulos arriba (`14` Core Auth, `15` Media
> Server) — inconsistencia heredada de versiones anteriores de este documento, no
> introducida en esta actualización. Vale la pena unificarla en algún momento; no se tocó
> aquí para no adivinar cuál de las dos numeraciones es la que se quiere conservar.

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

### 🏗️ En Progreso / Backlog (Q3 / Q4 2026)
* [ ] **Huéspedes CRM:** Segmentación eco-boutique y analítica de comportamiento.
* [ ] **Eco-Metrics:** Módulo de sustentabilidad para medición de huella hídrica y eléctrica en instalaciones.
* [ ] **Conversion & Sales:** A/B Testing en la landing page y conexión con pasarelas de pago directo (Stripe/PayPal).
* [ ] **Agro-Finance (OPEX Consolidation):** Abstracción del módulo `cattle_expenses` para consolidar costos transversales por kilo de biomasa o litro de agroquímico en la nueva vertical.
* [ ] **Enforcement activo de reglas de movimiento (Agro ERP):** pendiente de una sola confirmación del cliente para activar el bloqueo automático de movimientos no permitidos.
* [ ] **Confirmación de rotación de `INTERNAL_SECRET`:** verificar en ambos servicios (Auth Gateway, Media Server) y ambos ambientes tras el incidente de exposición de 2026-08-13.

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---
*Built with the assistance of AI-powered development tools.*