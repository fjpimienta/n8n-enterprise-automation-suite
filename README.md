# n8n Enterprise Automation Suite 🚀

### Self-Hosted Architecture: Orquestación de IA & Microservicios Soberanos

> **Arquitecto:** Francisco Jesus Pérez Pimienta (Senior Systems Engineer | PMP | Full Stack)
> **Core Stack:** n8n v2.4.6, Docker, PostgreSQL (pgvector + JSONB), Node.js (Upload Service), OpenAI (GPT-4o & DALL-E 3), Angular 21 (Signals).
> **Infraestructura:** CloudFree VPS (Hardened Linux) + Private Media CDN.

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
| **Media Server** | Node.js / Express | CDN Privado para almacenamiento persistente. |
| **Capa de Datos** | PostgreSQL + pgvector | Almacenamiento Relacional + Vectorial (RAG). |
| **Auth Gateway** | Node.js / JWT | Gestión de Sesiones Multi-Tenant e Identidad (RBAC). |
| **Frontends** | Angular 21 (Signals) | SPA Distribuidas en Monorepo (Dashboard / Pista / Cattle / Website). |

---

## 📦 Módulos Implementados (Suite v1.5.0)

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

### 🐄 13. Ganadería Digital (Cattle Ops Dashboard)
ERP agropecuario para trazabilidad bovina e inteligencia de producción.
* **Server-Side BI:** Cálculo de KPIs complejos (ADG, Tasa de Preñez) directamente en Vistas SQL.
* **Inteligencia Artificial de Campo:** Uso del **WhatsApp Cattle Agent** (MCP) blindado con directivas *Zero-Hallucination* y validación *Human-in-the-Loop* para la recolección natural de datos.

### 🛡️ 14. Core Auth Library (`@hosting3m/core-auth`)
Librería central de seguridad para todo el monorepo. Gestiona el ciclo de vida del JWT, Interceptors, Guards y provee el **Context Switcher** (TenantSelector) para enrutamiento Multi-Empresa.

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
| `13`|**Cattle Dashboard**|ERP agropecuario y BI Dashboard.|`Angular 21` `SQL Views`|[📖 Docs](hosting3m-workspace/projects/cattle-dashboard/README.md)|
| `14`|**MCP Agent Cattle**|Agente IA de campo (WhatsApp/Chat) con Zero-Hallucination.|`n8n` `MCP` `OpenAI`|[📖 Docs](workflows/09-MCP-Agent-Cattle/README.md)|
| `15`|**Core Auth Lib**|Núcleo de Autenticación y Context Switcher Multi-Tenant.|`Angular 21` `RxJS`|[📖 Docs](hosting3m-workspace/projects/core-auth/README.md)|

---

## 📈 Roadmap & Gestión de Proyectos (SDLC)

### ✅ Completado (H1 2026)
* [x] **Monorepo Scaling:** Optimización de `tsconfig` e implementación de librerías compartidas (`core-auth`, `ui-chat`, `ui-pdf-export`).
* [x] **Sovereign Media:** Implementación de `upload-service` propio y DALL-E 3.
* [x] **Public Interface:** Despliegue de `hotel-website` interactivo conectado a webhooks.
* [x] **Core Resilience:** Implementación de MetaCRUD Boundary Shields y motor de pagos en cascada (Hotel).
* [x] **WhatsApp Cattle Agent (Agro):** Agente IA con procesamiento de lenguaje natural integrado vía `09-MCP-Agent-Cattle`. Certificado con protocolos Anti-Jailbreak para la fase de recolección de datos obligatoria.

### 🏗️ En Progreso / Backlog (Q3 / Q4 2026)
* [ ] **Huéspedes CRM:** Segmentación eco-boutique y analítica de comportamiento.
* [ ] **Eco-Metrics:** Módulo de sustentabilidad para medición de huella hídrica y eléctrica en instalaciones.
* [ ] **Conversion & Sales:** A/B Testing en la landing page y conexión con pasarelas de pago directo (Stripe/PayPal).
* [ ] **Agro-Finance & IoT:** Integración en UI del módulo de gastos operativos (`cattle_expenses`) para cálculo de ROI por biomasa, e integración de telemetría mediante básculas RFID Bluetooth/Serial.

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```