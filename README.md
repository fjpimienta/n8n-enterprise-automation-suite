# n8n Enterprise Automation Suite 🚀

### Self-Hosted Architecture: Orquestación de IA & Microservicios Soberanos

> **Arquitecto:** Francisco Pérez (Senior Systems Engineer | PMP | Full Stack)
> **Core Stack:** n8n v2.4.6, Docker, PostgreSQL (pgvector + JSONB), Node.js (Upload Service), OpenAI (GPT-4o & DALL-E 3), Angular 21 (Signals).
> **Infraestructura:** CloudFree VPS (Hardened Linux) + Private Media CDN.

---

## 🎯 Objetivo del Proyecto

Suite de automatización empresarial de **grado industrial** diseñada bajo la filosofía de **"Soberanía de Datos"**: máxima potencia computacional con control total sobre los activos.

Esta arquitectura transforma la automatización convencional en un **Hub de Servicios Inteligente** que garantiza:

1. **Soberanía Total:** Despliegue 100% Self-Hosted, incluyendo el almacenamiento de medios (`upload-service`).
2. **Calidad Enterprise:** Uso de modelos comerciales robustos (DALL-E 3) para generación visual sin fallos.
3. **Alta Disponibilidad:** Orquestación mediante Docker con redes internas y persistencia binaria avanzada.
4. **Seguridad Corporativa:** Gestión de identidad RBAC, validación de tokens RS256 y manejo de secretos vía Variables de Entorno (`$env`).

---

## 🏗 Arquitectura e Infraestructura (IaC)

El ecosistema opera en un entorno de alta densidad, maximizando los recursos del VPS mediante una arquitectura de microservicios:

| Servicio | Tecnología | Función Crítica |
| --- | --- | --- |
| **Orquestador** | n8n v2.4.6 (Enterprise) | Motor lógico central. Manejo de concurrencia y reintentos (Retry Logic). |
| **Media Server** | Node.js / Express | **Nuevo:** Microservicio de almacenamiento persistente y entrega de contenidos (CDN Privado). |
| **Capa de Datos** | PostgreSQL + pgvector | Almacenamiento híbrido: Relacional (Negocio) + Vectorial (Memoria IA). |
| **Media Gen** | OpenAI DALL-E 3 | Generación de assets visuales de alta fidelidad y prompt engineering dinámico. |
| **Seguridad** | Node.js (JWT Service) | Microservicio dedicado para firma y validación de tokens RS256. |
| **Frontends** | Angular 21 (Signals) | Aplicaciones Distribuidas optimizadas para SPA (Dashboard) y PWA (Pista). |

---

## 📦 Módulos Implementados (Workflows v4 & v0.9)

La suite se compone de módulos interconectados que operan como una malla de servicios:

### 1. 🔐 Secure Token Gateway

Sistema centralizado de **Gestión de Identidad**. Administra la validación de peticiones externas y la auto-generación de tokens para tareas cronometradas bajo un esquema "Zero Trust".

### 2. 🛠️ Contact & CRM Bridge v2

Orquestador de entrada de leads. Realiza validación estricta de tipos (`Strong Typing`) y sanitización de datos antes de la persistencia en el CRM PostgreSQL.

### 3. 📰 Automated News Curator (v4.0)

Motor de inteligencia competitiva actualizado a **Sovereign Media**.

* **GenAI Premium:** Migración a **DALL-E 3** para generación de imágenes hiper-realistas.
* **Persistencia:** Las imágenes ya no dependen de enlaces temporales externos; se alojan en `upload.hosting3m.com`.

### 4. 📢 Social Media Orchestrator (v4.0)

Orquestador omnicanal con arquitectura **Self-Hosted**.

* **Private CDN:** Integración con el microservicio `upload-service` para alojar medios propios.
* **Reach Back Logic:** Persistencia binaria avanzada en n8n para asegurar que el archivo original llegue intacto a X (Twitter) y LinkedIn.
* **Hardening:** Credenciales inyectadas vía variables de entorno (`$env["FB_TOKEN"]`).

### 5. 🤖 Multi-Service WhatsApp Hub

Agente multimodal (Texto/Voz) con **enrutamiento inteligente**. Identifica al cliente en la DB y decide si la atención debe ser orientada a Hosting, Hotel o soporte general, utilizando memoria persistente `pgvector`.

### 6. 🛠️ Dynamic CRUD Engine

Capa de abstracción SQL que actúa como un **Backend as a Service (BaaS)** unificado.

* **Persistencia Híbrida:** SQL para búsquedas indexadas + JSONB para esquemas flexibles (NoSQL dentro de SQL).

### 7. 🏨 MCP Server: Hotel Management

Implementación del **Model Context Protocol**. Expone herramientas de base de datos a la IA, permitiendo consultas de inventario y modificaciones en tiempo real mediante lenguaje natural.

### 🏨 08. AdminHotel Dashboard (v0.9.0 - Performance Release)

ERP integral evolucionado a una **Arquitectura Distribuida**.

* **Routing Distribuido:** Módulos separados por rutas hijas (`/dashboard/finanzas`, `/dashboard/inventario`).
* **Performance:** Carga asíncrona de datos secundarios y esqueletos optimizados (0.1s TTI).
* **Inventario Centralizado:** Módulo polimórfico para gestión de activos en bodega y habitaciones.

### ⛸️ 09. PistaHielo Operations Center (v0.7.1 - Ops AI)

PWA Administrativa para gestión de centros de entretenimiento.

* **Billing Engine:** Motor de cobro con soporte para **"Midnight Crossing"**.
* **Live Monitor:** El "Rack" de patines activos con sincronización en tiempo real.

### 💬 10. Shared AI Chat Library (v1.0.0)

Librería transversal de Angular (**Shared Lib**) diseñada bajo el patrón de Componente Agnóstico.

* **DRY Architecture:** Elimina la redundancia de código conectando cualquier frontend con los agentes de n8n mediante **Injection Tokens**.

---

## 📚 Documentación Técnica por Módulo

| ID | Módulo / Servicio | Función Principal | Stack & Integraciones | Documentación |
| :---| :--- | :--- | :--- | :---: |
| `01`|**Auth JWT Gateway**| Middleware de seguridad. Valida tokens y protege webhooks públicos.| `Node.js` `Crypto` `JWT` | [📖 Ver Docs](workflows/01-auth-jwt-gateway/v3/README.md)|
| `02`|**Contact & CRM Bridge**|Sistema de captura de leads de Hosting3m.|`Webhook` `JWT` `CRUD` `Mail` `Postgres`|[📖 Ver Docs](workflows/02-leads-contact/v4/README.md)|
| `03`|**RAG News Intelligence**|Curaduría de noticias automatizada con análisis de sentimiento vectorial.|`Scraper` `OpenAI` `Pinecone/PgVector`|[📖 Ver Docs](workflows/03-rag-news-intelligence/v4/README.md)|
| `04`|**Omnichannel Social**|Orquestador de publicación de contenido en redes sociales.|`HTTP Request` `Twitter API` `LinkedIn`|[📖 Ver Docs](workflows/04-omnichannel-social/v4/README.md)|
| `05`|**AI WhatsApp Agent**|Asistente conversacional con memoria a largo plazo (RAG).|`WhatsApp` `Postgres` `OpenAI`|[📖 Ver Docs](workflows/05-ai-whatsapp-agent/v4/README.md)|
| `06`|**Dynamic CRUD Engine**|Capa de abstracción para gestión de entidades dinámica.|`Postgre` `JS Logic` `JWT`|[📖 Ver Docs](workflows/06-dynamic-crud-engine/v4/README.md)|
| `07`|**MCP Server**| MCP Server: Hotel Management Core|`MCP` `Postgres` `OpenAI`|[📖 Ver Docs](workflows/07-MCP-server-hotel/v3/README.md)|
| `08`|**AdminHotel Dashboard**|Frontend administrativo para gestión de reservas y habitaciones.|`Angular 21` `Tabler` `Vitest`|[📖 Ver Docs](hosting3m-workspace/projects/dashboard/README.md)|
| `09`|**PistaHielo Ops Center**|PWA para gestión de rentas por tiempo y cortes de caja.|`Angular 21` `Signals` `PWA`|[📖 Ver Docs](hosting3m-workspace/projects/pista-hielo/README.md)|
| `10`|**Shared AI Chat Lib**|Librería agnóstica de chat IA reutilizable con configuración dinámica.|`Angular 21` `InjectionToken`|[📖 Ver Docs](hosting3m-workspace/projects/ui-chat/README.md)|

---

## 📈 Roadmap & Gestión de Proyectos

### ✅ Completado (Q1 2026)

* [x] **Sovereign Media:** Implementación de `upload-service` propio y migración a DALL-E 3.
* [x] **Dashboard Performance:** Refactorización a Arquitectura de Rutas Distribuidas y Carga Asíncrona (v0.9.0).
* [x] **Security Hardening:** Gestión de credenciales mediante Variables de Entorno (`$env`).

### 🏗️ En Progreso (Q2 2026)

* [ ] **Huéspedes CRM:** Inteligencia de cliente y etiquetas de segmentación eco-boutique.
* [ ] **Sustentabilidad:** Módulo de métricas de consumo de luz y agua (Eco-Metrics).

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---

*Built with the assistance of AI-powered development tools.*