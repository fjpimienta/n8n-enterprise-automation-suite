# n8n Enterprise Automation Suite 🚀
## Arquitectura de Orquestación de IA & Microservicios (Self-Hosted)

![Arquitectura n8n Enterprise](assets/AutomationSuiteHosting3M_by_Gemini.png)

**Arquitecto:** Francisco Pérez (Senior Systems Engineer | PMP | Full Stack)
**Stack:** n8n, Docker, PostgreSQL (pgvector), Node.js, OpenAI (GPT-4o), MCP (Model Context Protocol). Linux VPS.

## 🎯 Objetivo del Proyecto
Suite de automatización empresarial de grado industrial diseñada para alta disponibilidad. Esta arquitectura trasciende el uso de simples "bots" para convertirse en un Hub de Servicios Inteligente que garantiza la soberanía de datos mediante un despliegue Self-Hosted, latencia mínima y una gestión de permisos basada en roles (RBAC) vinculada directamente a la base de datos central.

## 🏗 Arquitectura e Infraestructura (Infrastructure as Code)
Desplegado en un entorno endurecido (Hardened VPS) utilizando orquestación de contenedores y redes aisladas.

|Servicio|Tecnología|Función|
|:---|:---|:---|
|**Orquestador**|n8n v2.1.4 (Enterprise)|Motor lógico de flujos.|
|**MCP Server**|Model Context Protocol|Protocolo de interoperabilidad para ejecutar SQL desde la IA.|
|**Capa de Datos**|PostgreSQL + pgvector|Almacenamiento relacional y base de datos vectorial para RAG.|
|**Seguridad**|Node.js (JWT Service)|Microservicio dedicado para firma y validación de tokens RS256.|
|**Agentes IA**|OpenAI + LangChain Logic|Procesamiento de lenguaje natural y razonamiento autónomo.|
|**Voz (STT/TTS)**|Whisper & OpenAI TTS|Conversión bidireccional de audio con normalización de buffers.|
|**Memoria IA**|PostgreSQL + pgvector|RAG (Retrieval-Augmented Generation) para contexto a largo plazo.|
|**Ingesta**|Node.js Scraper|Motor de extracción de datos en tiempo real.|
|**Contactos**|n8n v2.1.4 (Enterprise)|Flujo para recibir informacion de prospectos en Contacto.|

## 📦 Módulos Implementados (Workflows)
1.  **🔐 Secure Token Gateway:** 
    Sistema centralizado que gestiona tanto la validación de peticiones externas como la auto-generación de tokens para tareas cronometradas, permitiendo que los flujos operen de forma autónoma pero segura.
2.  **🛠️ Contact & CRM Bridge v2 (n8n Workflow):**
    La versión de este orquestador de contactos perfecciona la integración entre el frontend (formularios web) y el backend (CRM).
3.  **📰 Automated News Curator:** 
    Motor de curaduría que extrae noticias técnicas, realiza un filtrado semántico y genera una identidad visual única mediante IA generativa antes de persistir los datos en el CRUD central.
4.  **📢 Social Media Orchestrator:**
    Orquestador omnicanal con lógica de idempotencia. Verifica cuotas de publicación diarias y adapta el contenido (truncado de texto, tagging) para maximizar el engagement en X, Facebook y LinkedIn.
5.  **🤖 Multi-Service WhatsApp Hub
    Agente multimodal (Texto/Voz) con enrutamiento inteligente. Identifica al cliente en la DB y decide si la atención debe ser orientada a Hosting, Hotel o soporte general, utilizando memoria persistente pgvector.
6.  **🛠️ Dynamic CRUD Engine:**
    Capa de abstracción que procesa operaciones SQL complejas. Soporta inserciones masivas, joins dinámicos y validación de roles, actuando como el backend unificado para todos los frontends.
7.  **🏨 MCP Server: Hotel Management:** 
    Implementación avanzada del protocolo MCP que expone herramientas de base de datos a la IA. Permite consultas de disponibilidad en tiempo real y registro de reservas directas mediante lenguaje natural.
8.  **🏨 AdminHotel Dashboard:** 
    Cliente Web SPA de alto rendimiento para la gestión visual del inventario hotelero.
    Novedades v0.5:
        * Sistema de refresco inteligente (Refresh Main).
        * Gestión dinámica de reservas.
        * CRUD de huéspedes con validación de identidad y Room Rack con estados reactivos (Sucia, Disponible, Reservada, Ocupada). 
        * Consume Módulos: Secure Token Gateway, Dynamic CRUD Engine, MCP Server.

## 🚀 Despliegue
```bash
# Clonar repositorio
git clone [https://github.com/tu-usuario/n8n-enterprise-suite.git](https://github.com/tu-usuario/n8n-enterprise-suite.git)

# Levantar infraestructura
cd infrastructure
docker-compose up -d

# Levantar Clientes Frontend (Opcional)
cd apps/admin-hotel
npm install && ng serve
```

---

## Documentación de Workflows Individuales

### 📦 Catálogo de Microservicios y Flujos (Workflows)

A continuación se detalla la documentación técnica y el código fuente de cada módulo implementado en n8n:

| ID | Módulo / Servicio | Función Principal | Stack & Integraciones | Documentación |
| :---| :--- | :--- | :--- | :---: |
| `01`|**Auth JWT Gateway**| Middleware de seguridad. Valida tokens y protege webhooks públicos.| `Node.js` `Crypto` `JWT` | [📖 Ver Docs](workflows/01-auth-jwt-gateway/v3/README.md)|
| `02`|**Contact & CRM Bridge**|Sistema de captura de leads de Hosting3m.|`Webhook` `JWT` `CRUD` `Mail` `Postgres`|[📖 Ver Docs](workflows/02-leads-contact/v3/README.md)|
| `03`|**RAG News Intelligence**|Curaduría de noticias automatizada con análisis de sentimiento vectorial.|`Scraper` `OpenAI` `Pinecone/PgVector`|[📖 Ver Docs](workflows/03-rag-news-intelligence/v3/README.md)|
| `04`|**Omnichannel Social**|Orquestador de publicación de contenido en redes sociales.|`HTTP Request` `Twitter API` `LinkedIn`|[📖 Ver Docs](workflows/04-omnichannel-social/v3/README.md)|
| `05`|**AI WhatsApp Agent**|Asistente conversacional con memoria a largo plazo (RAG).|`WhatsApp` `Postgres` `OpenAI`|[📖 Ver Docs](workflows/05-ai-whatsapp-agent/v3/README.md)|
| `06`|**Dynamic CRUD Engine**|Capa de abstracción para gestión de entidades dinámica.|`Postgre` `JS Logic` `JWT`|[📖 Ver Docs](workflows/06-dynamic-crud-engine/v3/README.md)|
| `07`|**MCP Server**| MCP Server: Hotel Management Core|`MCP` `Postgres` `OpenAI`|[📖 Ver Docs](workflows/07-MCP-server-hotel/v2/README.md)|
| `08`|**AdminHotel Dashboard**|Frontend administrativo para gestión de reservas y habitaciones.|`Angular 21` `Tabler` `Vitest`|[📖 Ver Docs](app/dashboard/README.md)|

---

## 📈 Roadmap & Gestión de Proyectos (GitHub Projects V3)
### Completado (Q4 2025 - Q1 2026) ✅
    * Arquitectura Dual-Auth: Implementación de sub-workflows de validación y auto-generación de tokens (Módulos 01 y 07).
    * Generación de Media IA: Integración nativa de Pollinations AI (Flux) en el pipeline de noticias y redes sociales.
    * CRUD Transaccional: Motor dinámico v3 con soporte para operaciones seguras y mapeo de campos.
    * MCP Hotel Core: Capacidad de la IA para interactuar directamente con el inventario de habitaciones.

### En Progreso (Q2 2026) 🏗️
    * Optimización RAG HNSW: Migración de índices vectoriales para búsquedas en milisegundos sobre datasets extensos.
    * Multi-Model Orchestration: Lógica para alternar entre GPT-4o, Claude 3.5 y modelos locales (Ollama) según el coste/complejidad de la tarea.
    * Dashboard AdminHotel v2: Integración total con el CRUD v3 y el sistema de Auth centralizado.

### Backlog & R&D (Futuro) 🚀
    * Agentes Supervisores: Implementación de una capa de "Quality Assurance" donde una IA audita las respuestas de los agentes de WhatsApp antes del envío.
    * Auto-Checkout MCP: Expansión del servidor MCP para procesar pagos y cierres de cuenta automáticos.
    * Resiliencia Geográfica: Clusterización de n8n para alta disponibilidad real.

---

Desarrollado por: Francisco Jesus Pérez Pimienta 
    - Ingeniero en Sistemas Computacionales.
    - Maestro en Administracion de Proyectos.
    - Especialista en Automatización de Procesos y Soberanía de Datos.