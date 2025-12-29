# n8n Enterprise Automation Suite 🚀
## Arquitectura de Orquestación de IA & Microservicios (Self-Hosted)

![Arquitectura n8n Enterprise](assets/AutomationSuiteHosting3M_by_Gemini.png)

**Arquitecto:** Francisco Pérez (Senior Systems Engineer | PMP | Full Stack)
**Stack:** n8n, Docker, PostgreSQL (pgvector), Node.js, OpenAI, Linux VPS.

## 🎯 Objetivo del Proyecto
Suite de automatización empresarial diseñada para alta disponibilidad y seguridad. A diferencia de implementaciones estándar SaaS, esta arquitectura **Self-Hosted** garantiza soberanía de datos, latencia mínima y personalización profunda mediante microservicios auxiliares.

## 🏗 Arquitectura e Infraestructura (Infrastructure as Code)
Desplegado en VPS Linux optimizado (2 vCore, 4GB RAM, NVMe) usando orquestación de contenedores.

| Servicio 			| Tecnología 				| Función 															|
| :--- 				| :--- 						| :--- 																|
| **Orquestador** 	| n8n v2.1.4 (Enterprise) 	| Motor lógico de flujos. 											|
| **Capa de Datos** | PostgreSQL + pgvector     | Almacenamiento relacional y base de datos vectorial para RAG.     |
| **Seguridad**     | Node.js (JWT Service)     | Microservicio dedicado para firma y validación de tokens RS256.   |
| **Agentes IA**    | OpenAI + LangChain Logic  | Procesamiento de lenguaje natural y razonamiento autónomo.        |
| **Memoria IA** 	| PostgreSQL + pgvector 	| RAG (Retrieval-Augmented Generation) para contexto a largo plazo. |
| **Proxy/Ingress** | Nginx                     | Terminación SSL, balanceo de carga y endurecimiento de cabeceras. |
| **Ingesta** 		| Node.js Scraper 			| Motor de extracción de datos en tiempo real. 						|
| **Mensajería** 	| WhatsApp Gateway 			| Interfaz conversacional asíncrona. 								|

## 📦 Módulos Implementados (Workflows)
1.  **🔐 Secure Token Gateway:** Gestión de autenticación API-Key/JWT centralizada.
2.  **📩 Contact Form Handler:** Procesamiento, sanitización y enrutamiento de leads.
3.  **📰 Automated News Curator:** Scraping, resumen con IA y clasificación semántica.
4.  **📢 Social Media Orchestrator:** Generación de contenido omnicanal (X, FB, LinkedIn).
5.  **🤖 AI WhatsApp Agent (RAG):** Asistente inteligente con memoria persistente en Postgres.
6.  **🛠️ Dynamic CRUD Engine:** Capa de abstracción de datos para gestión dinámica de entidades SQL.

## 🚀 Despliegue
```bash
# Clonar repositorio
git clone [https://github.com/tu-usuario/n8n-enterprise-suite.git](https://github.com/tu-usuario/n8n-enterprise-suite.git)

# Levantar infraestructura
cd infrastructure
docker-compose up -d
```

---

## Documentación de Workflows Individuales

### 📦 Catálogo de Microservicios y Flujos (Workflows)

A continuación se detalla la documentación técnica y el código fuente de cada módulo implementado en n8n:

| ID | Módulo / Servicio | Función Principal | Stack & Integraciones | Documentación |
| :--- | :--- | :--- | :--- | :---: |
| `01` | **Auth JWT Gateway** 		| Middleware de seguridad. Valida tokens y protege webhooks públicos. 		| `Node.js` `Crypto` `JWT` | [📖 Ver Docs](workflows/01-auth-jwt-gateway/README.md) |
| `02` | **CRM Lead Proxy** 		| Sanitización de datos de entrada y enrutamiento seguro de prospectos. 	| `Webhook` `RegEx` `JSON Schema` | [📖 Ver Docs](workflows/02-crm-lead-proxy/README.md) |
| `03` | **RAG News Intelligence** 	| Curaduría de noticias automatizada con análisis de sentimiento vectorial. | `Scraper` `OpenAI` `Pinecone/PgVector` | [📖 Ver Docs](workflows/03-rag-news-intelligence/README.md) |
| `04` | **Omnichannel Social** 	| Orquestador de publicación de contenido en redes sociales. 				| `HTTP Request` `Twitter API` `LinkedIn` | [📖 Ver Docs](workflows/04-omnichannel-social/README.md) |
| `05` | **AI WhatsApp Agent** 		| Asistente conversacional con memoria a largo plazo (RAG). 				| `WhatsApp` `Postgres` `OpenAI` | [📖 Ver Docs](workflows/05-ai-whatsapp-agent/README.md) |
| `06` | **Dynamic CRUD Engine**    | Capa de abstracción para gestión de entidades dinámica.                   | `PostgreSQL` `JS Logic` `JWT` | [📖 Ver Docs](workflows/06-dynamic-crud-engine/README.md) |
---

## GitHub Projects (Gestión Ágil)
**Para este proyecto utilizo GitHub Projects V2 con un enfoque de entrega continua (CI/CD) y gestión de riesgos.**

    * Backlog (R&D): Implementación de MCP (Model Context Protocol) para interoperabilidad entre LLMs y sistemas de archivos locales.
    * En Progreso: Optimización de búsqueda HNSW en pgvector para reducir la latencia en datasets de gran escala (>1M vectores).
    * Completado (Milestones): * Despliegue de infraestructura base con redes Docker aisladas.
        * Implementación del motor CRUD dinámico para reducción de deuda técnica.

**Configuración del Tablero:**

1.  **Nombre:** "n8n Automation Roadmap & Backlog".
2.  **Vistas:**
    * **Board:** Kanban clásico (Status: Todo, In Progress, Review, Done).
    * **Roadmap:** Vista de Cronograma (Gantt) agrupado por "Milestones".

* **Columna "Backlog" (Futuro):**
    * *Ticket:* "Implementar MCP (Model Context Protocol) para conectar Agente IA con sistema de archivos local." (Etiqueta: `R&D`, `AI`).
    * *Ticket:* "Refactorizar `scraper-service` para usar Puppeteer en modo Cluster para escalabilidad." (Etiqueta: `Performance`).
* **Columna "In Progress" (Lo que "estás haciendo"):**
    * *Ticket:* "Optimización de índices HNSW en pgvector para reducir latencia de búsqueda en 100ms." (Muestra conocimiento de DB).
* **Columna "Done" (Tus logros):**
    * *Ticket:* "Despliegue de n8n v2.0.3 con Docker Compose y redes aisladas."
    * *Ticket:* "Creación de Microservicio JWT para seguridad de webhooks."

---

Desarrollado por: Francisco Jesus Pérez Pimienta 
    - Ingeniero en Sistemas Computacionales.
    - Maestro en Administracion de Proyectos.