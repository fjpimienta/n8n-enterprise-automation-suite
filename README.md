# n8n Enterprise Automation Suite 🚀
## Arquitectura de Orquestación de IA & Microservicios (Self-Hosted)

![Arquitectura n8n Enterprise](assets/AutomationSuiteHosting3M_by_Gemini.png)

**Arquitecto:** Francisco Pérez (Senior Systems Engineer | PMP | Full Stack)
**Stack:** n8n v2.4.6, Docker, PostgreSQL (pgvector + JSONB), Node.js, OpenAI (GPT-4o), Angular 21 (Signals). Linux VPS.

## 🎯 Objetivo del Proyecto
Suite de automatización empresarial de grado industrial diseñada para alta disponibilidad. Esta arquitectura trasciende el uso de simples "bots" para convertirse en un **Hub de Servicios Inteligente** que garantiza:

1.  **Soberanía de Datos:** Despliegue 100% Self-Hosted.
2.  **Latencia Mínima:** Optimización de redes internas Docker.
3.  **Seguridad Corporativa:** Gestión de permisos basada en roles (RBAC) y validación de tokens RS256.

---

## 🏗 Arquitectura e Infraestructura (Infrastructure as Code)
Desplegado en un entorno endurecido (**Hardened VPS**) utilizando orquestación de contenedores y redes aisladas.

| Servicio | Tecnología | Función Crítica |
| :--- | :--- | :--- |
| **Orquestador** | n8n v2.4.6 (Enterprise) | Motor lógico central de flujos. |
| **IA Bridge** | MCP Protocol | Interoperabilidad para ejecutar SQL seguro desde la IA. |
| **Capa de Datos** | PostgreSQL + pgvector | Almacenamiento híbrido (Relacional + JSONB) y base de datos vectorial. |
| **Seguridad** | Node.js (JWT Service) | Microservicio dedicado para firma y validación de tokens RS256. |
| **Agentes IA** | OpenAI + LangChain | Procesamiento de lenguaje natural y razonamiento autónomo. |
| **Frontend Hotel** | Angular 21 SPA | Dashboard administrativo con gestión de estado reactivo (Signals). |
| **Frontend Pista**| Angular 21 PWA | WebApp progresiva para operaciones de tiempo real y cobros. |
| **Ingesta** | Node.js Scraper | Motor de extracción de datos en tiempo real. |
| **Contactos** | n8n v2.4.6 (Enterprise) | Orquestador de entrada de leads y CRM. |

---

## 📦 Módulos Implementados (Workflows)

La suite se compone de 9 módulos principales que operan como microservicios interconectados:

### 1. 🔐 Secure Token Gateway
Sistema centralizado que gestiona tanto la validación de peticiones externas como la auto-generación de tokens para tareas cronometradas (Zero Trust).

### 2. 🛠️ Contact & CRM Bridge v2
Orquestador de entrada de leads con validación estricta de tipos y sanitización antes de la persistencia en CRM.

### 3. 📰 Automated News Curator
Motor de curaduría que extrae noticias técnicas, realiza un **filtrado semántico** y genera una identidad visual única mediante IA generativa.

### 4. 📢 Social Media Orchestrator
Orquestador omnicanal con lógica de **idempotencia**. Verifica cuotas de publicación diarias y adapta el contenido para X, Facebook y LinkedIn.

### 5. 🤖 Multi-Service WhatsApp Hub
Agente multimodal (Texto/Voz) con enrutamiento inteligente basado en memoria persistente `pgvector`.

### 6. 🛠️ Dynamic CRUD Engine
Capa de abstracción SQL que actúa como backend unificado. **Novedad v3:** Soporte para persistencia híbrida (SQL para búsquedas + JSONB para esquemas flexibles).

### 7. 🏨 MCP Server: Hotel Management
Implementación avanzada del **Model Context Protocol**. Expone herramientas de base de datos a la IA para consultas de inventario en tiempo real.

### 8. 🏨 AdminHotel Dashboard (v0.7)
Cliente Web SPA para la gestión hotelera integral.
* **Core:** Angular 21 + Tabler UI.
* **Módulo QA:** Nuevo sistema de **Rondines** con formularios dinámicos y "Smart Merge" de datos.
* **Room Rack:** Semáforo visual de estados (Sucia, Disponible, Ocupada).
* **Finance:** Auditoría de fugas y descuentos dinámicos.

### 9. ⛸️ PistaHielo Operations Center (v0.6)
PWA Administrativa para gestión de centros de entretenimiento.
* **Core:** Angular 21 + Reactive Signals.
* **Dual-Stage Billing:** Motor de cobro de alta precisión con soporte para **"Midnight Crossing"** (turnos que cruzan la medianoche).
* **Ops:** Monitoreo en tiempo real y reportes de Corte Z (Efectivo vs Tarjeta).

---

## 🚀 Despliegue
```bash
# Clonar repositorio
git clone [https://github.com/tu-usuario/n8n-enterprise-suite.git](https://github.com/tu-usuario/n8n-enterprise-suite.git)

# Levantar infraestructura Backend
cd infrastructure
docker-compose up -d

# Levantar Clientes Frontend (Ejemplo)
cd apps/admin-hotel
npm install && ng serve

```

---

## Documentación de Workflows Individuales

### 📚 Documentación Técnica por Módulo

| ID | Módulo / Servicio | Función Principal | Stack & Integraciones | Documentación |
| --- | --- | --- | --- | --- |
| `01` | **Auth JWT Gateway** | Middleware de seguridad. | `Node.js` `JWT` | [📖 Ver Docs](https://www.google.com/search?q=workflows/01-auth-jwt-gateway/README.md) |
| `02` | **Contact & CRM Bridge** | Captura de leads Hosting3m. | `Webhook` `Postgres` | [📖 Ver Docs](https://www.google.com/search?q=workflows/02-leads-contact/README.md) |
| `03` | **RAG News Intelligence** | Curaduría vectorial. | `OpenAI` `PgVector` | [📖 Ver Docs](https://www.google.com/search?q=workflows/03-rag-news-intelligence/README.md) |
| `04` | **Omnichannel Social** | Orquestador de redes. | `Twitter API` `LinkedIn` | [📖 Ver Docs](https://www.google.com/search?q=workflows/04-omnichannel-social/README.md) |
| `05` | **AI WhatsApp Agent** | Asistente con memoria RAG. | `WhatsApp` `Postgres` | [📖 Ver Docs](https://www.google.com/search?q=workflows/05-ai-whatsapp-agent/README.md) |
| `06` | **Dynamic CRUD Engine** | Backend dinámico SQL/JSONB. | `JS Logic` `JWT` | [📖 Ver Docs](https://www.google.com/search?q=workflows/06-dynamic-crud-engine/README.md) |
| `07` | **MCP Server** | IA Context Protocol Hotel. | `MCP` `Postgres` `OpenAI` | [📖 Ver Docs](https://www.google.com/search?q=workflows/07-MCP-server-hotel/README.md) |
| `08` | **AdminHotel Dashboard** | Frontend Hotelero (v0.7). | `Angular 21` `Tabler` | [📖 Ver Docs](https://www.google.com/search?q=app/dashboard/README.md) |
| `09` | **PistaHielo Ops Center** | Frontend Pista Hielo (v0.6). | `Angular 21` `Signals` | [📖 Ver Docs](https://www.google.com/search?q=app/pista-hielo/README.md) |

---

## 📈 Roadmap & Gestión de Proyectos (GitHub Projects V3)

### Completado (Q4 2025 - Q1 2026) ✅

* **Infraestructura:** Despliegue de redes Docker aisladas y Auth Gateway RS256.
* **Hotel Core:** Dashboard v0.7 con Módulo de Calidad (Rondines) y persistencia híbrida.
* **Pista Hielo:** PWA v0.6 con corrección de cálculo de tiempos (Midnight Bug) y reportes financieros.
* **Backend:** Dynamic CRUD Engine v3 con soporte JSONB.

### En Progreso (Q2 2026) 🏗️

* **PistaHielo Membership:** Integración de directorio de alumnos VIP y control de mensualidades.
* **Optimización RAG:** Migración a índices HNSW en pgvector para búsquedas masivas.

### Backlog (Futuro) 🚀

* **Agentes Supervisores:** IA de control de calidad para auditar respuestas de bots.
* **Auto-Checkout MCP:** Pagos automatizados mediante IA.

---

Desarrollado por: **Francisco Jesus Pérez Pimienta**

* Ingeniero en Sistemas Computacionales | PMP | Full Stack.
* Especialista en Automatización de Procesos y Soberanía de Datos.

