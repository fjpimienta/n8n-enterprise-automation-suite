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
4. **Seguridad Corporativa:** Gestión de identidad RBAC y validación RS256.
5. **Captura Pública (Lead Gen):** Integración nativa de interfaces orientadas a la conversión directa con orquestación backend en tiempo real.

---

## 🏗 Arquitectura e Infraestructura (IaC)

El ecosistema opera en un entorno de alta densidad, maximizando los recursos del VPS mediante una arquitectura de microservicios:

| Servicio | Tecnología | Función Crítica |
| --- | --- | --- |
| **Orquestador** | n8n v2.4.6 (Enterprise) | Motor lógico central y procesamiento de Webhooks. |
| **Media Server** | Node.js / Express | CDN Privado para almacenamiento persistente. |
| **Capa de Datos** | PostgreSQL + pgvector | Almacenamiento Relacional + Vectorial (RAG). |
| **Doc Engine** | jsPDF / AutoTable | Generación de reportes y cotizaciones vectoriales. |
| **Frontends** | Angular 21 (Signals) | SPA Distribuidas en Monorepo (Dashboard / Pista / Website). |

---

## 📦 Módulos Implementados (Workflows v4 & v1.1.0)

La suite se compone de módulos interconectados que operan como una malla de servicios:

### 1. 🔐 Secure Token Gateway
Sistema centralizado de **Gestión de Identidad**. Administra la validación de peticiones externas y la auto-generación de tokens para tareas cronometradas bajo un esquema "Zero Trust".

### 2. 🛠️ Contact & CRM Bridge v2
Orquestador de entrada de leads. Realiza validación estricta de tipos (`Strong Typing`) y sanitización de datos antes de la persistencia en el CRM PostgreSQL.

### 3. 📰 Automated News Curator (v4.0)
Motor de inteligencia competitiva actualizado a **Sovereign Media**.
* **GenAI Premium:** Migración a **DALL-E 3** para generación de imágenes hiper-realistas alojadas en `upload.hosting3m.com`.

### 4. 📢 Social Media Orchestrator (v4.0)
Orquestador omnicanal con arquitectura **Self-Hosted**.
* **Reach Back Logic:** Persistencia binaria avanzada en n8n para asegurar la integridad de archivos hacia X y LinkedIn.

### 5. 🤖 Multi-Service WhatsApp Hub
Agente multimodal con **enrutamiento inteligente** y memoria persistente `pgvector`.

### 6. 🛠️ Dynamic CRUD Engine
Capa de abstracción SQL que actúa como un **Backend as a Service (BaaS)** con persistencia híbrida (SQL + JSONB).

### 7. 🏨 MCP Server: Hotel Management
Implementación del **Model Context Protocol** para consultas de inventario mediante IA en lenguaje natural.

### 🏨 08. AdminHotel Dashboard (v0.11.0 - Fin Engine & Resilience)
ERP integral evolucionado a una **Arquitectura Distribuida** con motor financiero.
* **Boundary Resilience:** Escudo estricto contra fallos silenciosos del MetaCRUD y protección contra *Timezone Offsets*.
* **Financial Engine:** Soporte nativo para *Soft-Bookings* (Cotizaciones), Pagos en Cascada (Waterfall) para grupos, y recálculo dinámico de deudas en extensiones de estancia.
* **Digital Billing:** Generación de cotizaciones PDF con desglose fiscal (IVA/ISH) mediante `ui-pdf-export`.

### ⛸️ 09. PistaHielo Operations Center (v0.7.1 - Ops AI)

PWA Administrativa para gestión de centros de entretenimiento.

* **Billing Engine:** Motor de cobro con soporte para **"Midnight Crossing"**.
* **Live Monitor:** El "Rack" de patines activos con sincronización en tiempo real.
### 💬 10. Shared AI Chat Library (v1.0.0)
Librería agnóstica de chat IA inyectada transversalmente en el ecosistema (`CHAT_CONFIG_TOKEN`).

### 📄 11. UI PDF Export Library (v1.0.0)

Nueva librería compartida para la estandarización de documentos salientes. 

* 
**Agnostic Design:** Capaz de procesar cualquier entidad comercial bajo una interfaz común. 


* **Tax Engine:** Motor de cálculo automático para regímenes fiscales hoteleros.


### 🌍 12. Hotel Eco-Website (v1.0.0 - Public Frontend)
La interfaz pública de alta conversión del ecosistema Hosting3M (*Customer-Facing*).
* **Diseño Eco-Boutique:** Arquitectura Tailwind CSS v3 nativa con tokens biofílicos y Glassmorphism optimizado para Core Web Vitals (JIT & Tree-shaking).
* **Reactive Lead Capture:** Integración directa de formularios con los webhooks de n8n mediante `HttpClient` para desencadenar notificaciones y embudos en tiempo real.
* **AI Concierge:** Inyección nativa de la librería `@hosting3m/ui-chat` para pre-calificar visitantes 24/7.


### 🐄 13. Ganadería Digital (Cattle Ops Dashboard)
ERP agropecuario para trazabilidad bovina e inteligencia de producción.
* **Server-Side BI:** Cálculo de KPIs complejos (ADG, Tasa de Preñez) directamente en Vistas de PostgreSQL (`vw_cattle_kpi`) para máximo rendimiento del frontend.
* **Metadata Clínica:** Uso de JSONB dinámico para almacenar diagnósticos veterinarios detallados (Palpación, Condición Uterina) integrados al historial del animal.
* **Identificación Resiliente:** Soporte nativo para lectura RFID, SINIIGA oficial y Números a Fuego internos.

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
| `12` | **Hotel Eco-Website** | Landing page de alta conversión y captura de prospectos. | `Angular`, `Tailwind` | [📖 Docs](hosting3m-workspace/projects/hotel-website/README.md) |
| `13` | **Ganadería Digital** | ERP especializado en trazabilidad bovina, biometría y reproducción. | `Angular 21` `SQL Views` `n8n` | [📖 Docs](hosting3m-workspace/projects/cattle-dashboard/README.md) |

---

## 📈 Roadmap & Gestión de Proyectos (SDLC)

### ✅ Completado (Q1 2026)
* [x] **Monorepo Scaling:** Optimización de `tsconfig` para soporte de múltiples librerías.
* [x] **Sovereign Media:** Implementación de `upload-service` propio y DALL-E 3.
* [x] **Public Interface:** Despliegue de `hotel-website` interactivo conectado a webhooks.
* [x] **Digital Formalization:** Liberación de `ui-pdf-export` y flujos de presupuestación corporativa.
* [x] **Core Resilience:** Implementación de MetaCRUD Boundary Shields y motor de pagos en cascada.

### 🏗️ En Progreso / Backlog (Q2 2026)
* [ ] **Huéspedes CRM:** Segmentación eco-boutique y analítica de comportamiento.
* [ ] **Eco-Metrics:** Módulo de sustentabilidad para medición de huella hídrica y eléctrica.
* [ ] **Conversion & Sales:** A/B Testing en la landing page y conexión con pasarelas de pago directo (Stripe/PayPal).

### 🏗️ En Progreso / Backlog ( Q3 2026)
* [ ] **Huéspedes CRM:** Segmentación eco-boutique y analítica de comportamiento.
* [ ] **Eco-Metrics:** Módulo de sustentabilidad para medición de huella hídrica y eléctrica.
* [ ] **Conversion & Sales:** A/B Testing en la landing page y conexión con pasarelas de pago directo (Stripe/PayPal).
* [ ] **WhatsApp Cattle Agent (Agro):** Agente IA con transcripción de audio (Whisper) para registrar eventos sanitarios y partos directamente desde el campo mediante notas de voz.
* [ ] **Agro-Finance & IoT:** Módulo de gastos operativos (`cattle_expenses`) para cálculo de ROI por biomasa e integración de telemetría mediante básculas RFID Bluetooth/Serial.

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```