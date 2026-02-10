# n8n Enterprise Automation Suite 🚀

### CloudFree Architecture: Orquestación de IA & Microservicios (Self-Hosted)

> **Arquitecto:** Francisco Pérez (Senior Systems Engineer | PMP | Full Stack)
> **Core Stack:** n8n v2.4.6, Docker, PostgreSQL (pgvector + JSONB), Node.js, OpenAI (GPT-4o) & Flux (Image Gen), Angular 21.
> **Infraestructura:** CloudFree VPS (Hardened Linux).

---

## 🎯 Objetivo del Proyecto

Suite de automatización empresarial de **grado industrial** diseñada bajo la filosofía **"CloudFree"**: máxima potencia computacional con cero dependencia de licencias SaaS costosas.

Esta arquitectura transforma la automatización convencional en un **Hub de Servicios Inteligente** que garantiza:

1. **Soberanía Total de Datos:** Despliegue 100% Self-Hosted (Sin Vendor Lock-in).
2. **Cost-Efficiency:** Uso de modelos de IA optimizados (Turbo/Flux) y almacenamiento vectorial propio.
3. **Alta Disponibilidad:** Orquestación mediante Docker con redes internas de latencia cero.
4. **Seguridad Corporativa:** Gestión de identidad RBAC y validación de tokens RS256.

---

## 🏗 Arquitectura e Infraestructura (IaC)

El ecosistema opera en un entorno de alta densidad, maximizando los recursos del VPS mediante una arquitectura de microservicios:

| Servicio | Tecnología | Función Crítica |
| --- | --- | --- |
| **Orquestador** | n8n v2.4.6 (Enterprise) | Motor lógico central. Manejo de concurrencia y reintentos (Retry Logic). |
| **Media Gen** | Pollinations AI (Flux/Turbo) | **Nuevo:** Generación de assets visuales ilimitados sin coste de API. |
| **Capa de Datos** | PostgreSQL + pgvector | Almacenamiento híbrido: Relacional (Negocio) + Vectorial (Memoria IA). |
| **Social API** | Facebook Graph v23.0 | **Nuevo:** Integración nativa para publicación estable en Instagram/Facebook. |
| **Seguridad** | Node.js (JWT Service) | Microservicio dedicado para firma y validación de tokens RS256. |
| **Agentes IA** | OpenAI + LangChain | Razonamiento autónomo y RAG (Retrieval-Augmented Generation). |
| **Frontend Hotel** | Angular 21 SPA | Dashboard administrativo con gestión de estado reactivo (Signals). |
| **Frontend Pista** | Angular 21 PWA | WebApp progresiva para operaciones de tiempo real y cobros. |

---

## 📦 Módulos Implementados (Workflows v3)

La suite se compone de módulos interconectados que operan como una malla de servicios:

### 1. 🔐 Secure Token Gateway

Sistema centralizado de **Gestión de Identidad**. Administra la validación de peticiones externas y la auto-generación de tokens para tareas cronometradas bajo un esquema "Zero Trust".

### 2. 🛠️ Contact & CRM Bridge v2

Orquestador de entrada de leads. Realiza validación estricta de tipos (`Strong Typing`) y sanitización de datos antes de la persistencia en el CRM PostgreSQL.

### 3. 📰 Automated News Curator (v3.1)

Motor de inteligencia competitiva actualizado.

* **Extracción:** Scraping de fuentes RSS técnicas.
* **IA Generativa:** Implementación de **Pollinations.ai (Modelo Flux)** para crear portadas de noticias hiper-realistas en formato vertical (4:5) para Instagram.
* **Prompt Engineering:** Inyección dinámica de estilos (Cyberpunk, Isometric, 3D Render).

### 4. 📢 Social Media Orchestrator (Graph API Edition)

Orquestador omnicanal refactorizado para **Meta for Business**.

* **Estabilidad:** Migración de nodos comunitarios a **n8n Native Instagram Node** usando credenciales de Facebook Graph.
* **Upload Protocol:** Implementación de espera activa (`Wait Node`) para garantizar el procesamiento de medios 4K antes de la publicación.
* **Estrategia:** "Link in Bio" automatizada para tráfico orgánico.

### 5. 🤖 Multi-Service WhatsApp Hub

Agente multimodal (Texto/Voz) con **enrutamiento inteligente**. Identifica al cliente en la DB y decide si la atención debe ser orientada a Hosting, Hotel o soporte general, utilizando memoria persistente `pgvector`.

### 6. 🛠️ Dynamic CRUD Engine

Capa de abstracción SQL que actúa como un **Backend as a Service (BaaS)** unificado.

* **Persistencia Híbrida:** SQL para búsquedas indexadas + JSONB para esquemas flexibles (NoSQL dentro de SQL).

### 7. 🏨 MCP Server: Hotel Management

Implementación del **Model Context Protocol**. Expone herramientas de base de datos a la IA (Claude/Gemini/GPT), permitiendo consultas de inventario y modificaciones en tiempo real mediante lenguaje natural.

### 8. 🏨 AdminHotel Dashboard (v0.7)

Cliente Web SPA para la gestión hotelera integral.

* **Core:** Angular 21 + Tabler UI.
* **QA Module:** Sistema de "Rondines" con formularios dinámicos y "Smart Merge".

### 9. ⛸️ PistaHielo Operations Center (v0.6)

PWA Administrativa para gestión de entretenimiento.

* **Billing Engine:** Motor de cobro de alta precisión con soporte para turnos nocturnos ("Midnight Crossing").
* **Ops:** Reportes financieros de Corte Z en tiempo real.

---

## 🚀 Despliegue Rápido

```bash
# 1. Clonar repositorio
git clone [https://github.com/tu-usuario/n8n-enterprise-suite.git](https://github.com/tu-usuario/n8n-enterprise-suite.git)

# 2. Configurar Entorno (CloudFree Strategy)
cp .env.example .env
# Ajustar POSTGRES_USER, OPENAI_API_KEY, FB_PAGE_ACCESS_TOKEN

# 3. Levantar Infraestructura
cd infrastructure
docker-compose up -d --build

# 4. Verificar Salud de Servicios
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

```

---

## 📚 Documentación Técnica por Módulo

| ID | Módulo / Servicio | Función Principal | Stack & Integraciones | Documentación |
| :---| :--- | :--- | :--- | :---: |
| `01`|**Auth JWT Gateway**| Middleware de seguridad. Valida tokens y protege webhooks públicos.| `Node.js` `Crypto` `JWT` | [📖 Ver Docs](workflows/01-auth-jwt-gateway/v3/README.md)|
| `02`|**Contact & CRM Bridge**|Sistema de captura de leads de Hosting3m.|`Webhook` `JWT` `CRUD` `Mail` `Postgres`|[📖 Ver Docs](workflows/02-leads-contact/v3/README.md)|
| `03`|**RAG News Intelligence**|Curaduría de noticias automatizada con análisis de sentimiento vectorial.|`Scraper` `OpenAI` `Pinecone/PgVector`|[📖 Ver Docs](workflows/03-rag-news-intelligence/v3/README.md)|
| `04`|**Omnichannel Social**|Orquestador de publicación de contenido en redes sociales.|`HTTP Request` `Twitter API` `LinkedIn`|[📖 Ver Docs](workflows/04-omnichannel-social/v3/README.md)|
| `05`|**AI WhatsApp Agent**|Asistente conversacional con memoria a largo plazo (RAG).|`WhatsApp` `Postgres` `OpenAI`|[📖 Ver Docs](workflows/05-ai-whatsapp-agent/v3/README.md)|
| `06`|**Dynamic CRUD Engine**|Capa de abstracción para gestión de entidades dinámica.|`Postgre` `JS Logic` `JWT`|[📖 Ver Docs](workflows/06-dynamic-crud-engine/v3/README.md)|
| `07`|**MCP Server**| MCP Server: Hotel Management Core|`MCP` `Postgres` `OpenAI`|[📖 Ver Docs](workflows/07-MCP-server-hotel/v2/README.md)|
| `08`|**AdminHotel Dashboard**|Frontend administrativo para gestión de reservas y habitaciones.|`Angular 21` `Tabler` `Vitest`|[📖 Ver Docs](hosting3m-workspace/projects/dashboard/README.md)|
| `09`|**PistaHielo Ops Center**|PWA para gestión de rentas por tiempo y cortes de caja.|`Angular 21` `Signals` `PWA`|[📖 Ver Docs](hosting3m-workspace/projects/pista-hielo/README.md)|
| `10`|**Shared AI Chat Lib**|Librería agnóstica de chat IA reutilizable con configuración dinámica.|`Angular 21` `InjectionToken`|[📖 Ver Docs](hosting3m-workspace/projects/ui-chat/README.md)|
---

## 📈 Roadmap & Gestión de Proyectos

### ✅ Completado (Q1 2026)

* [x] **Social Media Fix:** Implementación exitosa de Facebook Graph API para publicación estable en Instagram Business.
* [x] **Visual Upgrade:** Integración de Pollinations.ai para generación de imágenes "Cost-Free".
* [x] **Infraestructura:** Migración a stack **CloudFree** optimizado.

### 🏗️ En Progreso (Q2 2026)

* [ ] **Stories Automation:** Implementación de "Link Stickers" automatizados en Instagram Stories para tráfico directo.
* [ ] **AI Supervisor:** Agente de control de calidad para auditar las respuestas del bot de WhatsApp.

---

Desarrollado por: **Francisco Jesus Pérez Pimienta**

* **Senior Systems Engineer | PMP | Full Stack**
* *Especialista en Automatización de Procesos, Bases de Datos & AI Integration.*