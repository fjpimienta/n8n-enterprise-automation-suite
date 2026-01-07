# 🛠️ Enterprise AI News Curator & Persistent Sync (Hosting3m)
## 📝 Concepto
Content Intelligence / AI Automation / Persistent Storage Versión: 2.0 (Enhanced with AI Image Gen & DB Sync)

Este flujo es un motor de curaduría de contenidos de alto rendimiento desarrollado en n8n. El sistema transforma el ruido de la web en inteligencia de negocios procesable, extrayendo, filtrando y persistiendo noticias críticas sobre Inteligencia Artificial, Automatización e Infraestructura.

## 📝 Descripción
La v2.0 evoluciona de un simple lector a un sistema completo de Ingesta, Procesamiento y Persistencia. Ahora no solo filtra noticias, sino que genera arte digital único para cada ejecución y almacena los resultados en una base de datos centralizada mediante microservicios.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/news` | Lanzamiento inicial. | `v1-rag.json` |
| **v2** | `Stable` | `/v2/news` | News 2. Ingesta, Procesamiento y Persistencia de Noticias. | `v2-news.json` |

---

### ⚙️ Lógica de Negocio
1. **Orquestación Dual:** Ejecución programada cada hora (Schedule Trigger) para mantener la base de datos fresca, o activación bajo demanda vía Webhook seguro con soporte CORS para frontends.
2. **Curaduría Basada en Temas:** Algoritmo avanzado en JavaScript que filtra por palabras clave (IA, LLM, n8n, Docker, Linux) y elimina duplicados por título.
3. **IA Generativa de Media:** Integra el modelo Pollinations.ai (Flux) para generar automáticamente imágenes conceptuales futuristas cada vez que el flujo se activa, asegurando una identidad visual única.
4. **Persistencia Automatizada:** Sincroniza las noticias filtradas con un microservicio CRUD externo, realizando inserciones masivas (batching) con reintentos automáticos en caso de fallo.
5. **Gestión de Seguridad JWT:** Sistema híbrido que puede validar tokens entrantes o generar sus propios tokens internos (genera-token) para comunicarse con otros servicios de la infraestructura Hosting3m.

---

## 🛠️ Instalación
- **Requisitos previos:**
    * Instancia de n8n (v2.2.4 o superior).
    * Microservicio de autenticación JWT y servicio CRUD de noticias activos.
    * Credenciales SMTP configuradas para los nodos de envío de correo.
    * Acceso a internet para el nodo de IA (image.pollinations.ai).
- **Importación:**
    * Copia el archivo .json de este workflow.
    * Configura los dominios permitidos en las opciones de CORS del nodo Webhook.
    * En n8n, crea un nuevo flujo y selecciona "Import from File" o pega el código directamente.
- **Configuración de Servidores:**
    * Endpoint de Noticias: Asegúrate de que la URL https://n8n.hosting3m.com/.../news_articles sea accesible.
    * Auth: El flujo solicita automáticamente un token de sistema usando las credenciales de n8n@hosting3m.com.
    * SMTP: Configura las cuentas n8n@hosting3m.com y contacto@hosting3m.com en los nodos de Email.

---

## 🚀 Uso
    El flujo se activa mediante una solicitud HTTP POST al endpoint contactoHosting3m.

``` Bash
    curl -X POST https://n8n.hosting3m.com/webhook/v2/news \
    -H "Authorization: Bearer <TOKEN_VALIDO>" \
    -H "Content-Type: application/json"
```

## 📦 Tecnologías
* n8n Orquestador: Motor de lógica y triggers.
* JavaScript (Node.js): Lógica de filtrado semántico, deduplicación y formateo de fechas ISO.
* RSS/XML Parsing: Extracción de datos de fuentes heterogéneas.
* Pollinations AI: Generación dinámica de imágenes mediante prompts técnicos.
* REST API: Integración con microservicios de persistencia y tokens.
* Security (JWT & CORS): Control estricto de acceso y políticas de origen cruzado para seguridad web.

## 🤝 Contribución
    1. Haz un Fork del repositorio.
    2. Crea una rama para tu mejora: git checkout -b feature/nuevo-filtro.
    3. Realiza un Commit: git commit -m 'Añadida fuente de noticias TechCrunch'.
    4. Abre un Pull Request.

## 📄 Licencia
Este proyecto está bajo la licencia n8n Sustainable Use License. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computacionales y Maestro en Administración de Proyectos.