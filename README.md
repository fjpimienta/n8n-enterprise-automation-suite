# n8n Enterprise Automation Suite 🚀

### Self-Hosted Architecture: Orquestación de IA & Microservicios Soberanos

> **Arquitecto:** Francisco Pérez (Senior Systems Engineer | PMP | Full Stack)
> **Core Stack:** n8n v2.4.6, Docker, PostgreSQL (pgvector + JSONB), Node.js (Upload Service), OpenAI (GPT-4o & DALL-E 3), Angular 21 (Signals).
> **Infraestructura:** CloudFree VPS (Hardened Linux) + Private Media CDN.

---

## 🎯 Objetivo del Proyecto

Suite de automatización empresarial de **grado industrial** diseñada bajo la filosofía de **"Soberanía de Datos"**. Esta arquitectura transforma la automatización convencional en un **Hub de Servicios Inteligente** que ahora integra la formalización legal y comercial mediante documentos digitales.

1. **Soberanía Total:** Despliegue 100% Self-Hosted.
2. **Calidad Enterprise:** Uso de modelos comerciales robustos.
3. **Formalización Digital:** Generación de documentos PDF profesionales (`ui-pdf-export`) directamente desde el cliente.
4. **Seguridad Corporativa:** Gestión de identidad RBAC y validación RS256.

---

## 🏗 Arquitectura e Infraestructura (IaC)
El ecosistema opera en un entorno de alta densidad, maximizando los recursos del VPS mediante una arquitectura de microservicios:

| Servicio | Tecnología | Función Crítica |
| --- | --- | --- |
| **Orquestador** | n8n v2.4.6 (Enterprise) | Motor lógico central. |
| **Media Server** | Node.js / Express | CDN Privado para almacenamiento persistente. |
| **Capa de Datos** | PostgreSQL + pgvector | Almacenamiento Relacional + Vectorial. |
| **Doc Engine** | jsPDF / AutoTable | Generación de reportes y cotizaciones vectoriales. |
| **Frontends** | Angular 21 (Signals) | Aplicaciones Distribuidas (Dashboard / Pista). |

---

## 📦 Módulos Implementados (Workflows v4 & v0.10)

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

* **Digital Billing:** Generación de cotizaciones PDF con desglose automático de impuestos (IVA/ISH).
* **Selección Inteligente:** Interfaz de selección múltiple para facturación agrupada.
* **Inventario Centralizado:** Módulo polimórfico para activos en bodega y habitaciones.

### ⛸️ 09. PistaHielo Operations Center (v0.7.1 - Ops AI)

PWA Administrativa para gestión de centros de entretenimiento.

* **Billing Engine:** Motor de cobro con soporte para **"Midnight Crossing"**.
* **Live Monitor:** El "Rack" de patines activos con sincronización en tiempo real.

### 💬 10. Shared AI Chat Library (v1.0.0)
Librería transversal de Angular (**Shared Lib**) diseñada bajo el patrón de Componente Agnóstico.

### 📄 11. UI PDF Export Library (v1.0.0)

Nueva librería compartida para la estandarización de documentos salientes. 

* 
**Agnostic Design:** Capaz de procesar cualquier entidad comercial bajo una interfaz común. 


* **Tax Engine:** Motor de cálculo automático para regímenes fiscales hoteleros.

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
| `11` | **UI PDF Export Lib** | Librería de exportación de documentos PDF. | `jsPDF` `TypeScript` | [📖 Docs](hosting3m-workspace/projects/ui-pdf-export/README.md) |

---

## 📈 Roadmap & Gestión de Proyectos

### ✅ Completado (Q1 2026)

* [x] **Digital Formalization:** Lanzamiento de `ui-pdf-export` e integración en el flujo de reservas.
* [x] **Sovereign Media:** Implementación de `upload-service` propio y DALL-E 3.
* [x] **Monorepo Scaling:** Optimización de `tsconfig` para soporte de múltiples librerías compartidas. 



### 🏗️ En Progreso (Q2 2026)

* [ ] **Huéspedes CRM:** Segmentación eco-boutique y analítica de comportamiento.
* [ ] **Eco-Metrics:** Módulo de sustentabilidad para medición de huella hídrica y eléctrica.

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---

*Built with the assistance of AI-powered development tools.*
