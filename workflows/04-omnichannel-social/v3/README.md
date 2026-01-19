# 💡 Social Media Intelligence & Omnichannel Automation Orchestrator v3

**Concepto:** Microservices Integration / Generative AI / Enterprise Social Distribution Versión: 3.0 (v3/OmniChannel)

Este flujo representa la cúspide de la automatización de Marketing en la infraestructura de Hosting3m. Es un orquestador autónomo que no solo distribuye contenido, sino que toma decisiones basadas en el estado de la base de datos, genera activos visuales únicos mediante IA y asegura la presencia de marca en X (Twitter), Facebook y LinkedIn de forma coordinada.

## 📝 Descripción

La v3.0 evoluciona hacia una arquitectura de microservicios, desacoplando la lógica de autenticación y persistencia. El workflow ahora utiliza sub-workflows de seguridad centralizados para la gestión de tokens JWT y se comunica con la API CRUD v3 para garantizar la integridad de los datos y evitar la redundancia de publicaciones.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/NewsScraper` | Lanzamiento inicial. | `v1-omnichanel.json` |
| **v2** | `Legacy` | `/v2/NewsScraper` | CRUD v2, Verificación de cuota diaria, Generación IA (Flux), CRUD v2, Soporte Multi-perfil LinkedIn. | `v2-omnichanel.json` |
| **v3** | `Stable` | `Internal Cron` | Arquitectura v3, Integración con SW Genera Token, Lógica de Error Handling robusta, y optimización de prompts para Flux. | `v3-omnichanel.json` |

---

## ⚙️ Arquitectura y Lógica v3

El flujo se ha optimizado para ser 100% resiliente y seguro:

### 1. Disparadores (Triggers) Híbridos
* **Automática (Cron):** Ejecución programada diariamente a las 06:00 AM y 02:00 PM.

### 2. Autenticación y Control de Publicación
Antes de procesar contenido, el sistema realiza verificaciones de seguridad y negocio:
* **Generación de Token:** Obtiene un token JWT interno (`Get Token`) para interactuar con la API de backend.
* **Verificación de Cuota Diaria:** Consulta la base de datos (`Check Publish`) para verificar si ya se ha publicado contenido en el rango de tiempo actual (`$now.startOf('day')` a `$now.endOf('day')`). Si ya existe una publicación, el flujo se detiene para evitar spam.

### 3. Curaduría y Scraping
* **Extracción:** Se conecta a la fuente de noticias (`Get News`) y utiliza selectores CSS específicos (`.news-title`, `.news-body`, etc.) para extraer metadatos relevantes.
* **Selección:** Limita el procesamiento al primer artículo disponible (`Limit`) y asigna una fuente estática de marca.

### 4. Idempotencia (Prevención de Duplicados)
* Consulta a la API interna (`Check Article Exists`) verificando la URL del artículo.
* **Lógica Condicional:** Si el artículo ya existe en la base de datos, el flujo termina y notifica la existencia. Si no existe, procede a la generación de contenido.

### 5. Enriquecimiento con IA Generativa (GenAI)
En lugar de usar la imagen original (que puede tener derechos de autor o baja calidad), el sistema crea su propio activo visual:
* **Prompt Engineering:** Construye un prompt dinámico basado en el título de la noticia (e.g., *"Futuristic technology concept... high detail, 8k"*).
* **Generación:** Utiliza la API de **Pollinations.ai (Modelo Flux)** para generar una imagen única de 1000x800px.
* **Fallback:** Incluye lógica de recuperación (`HandleImageError`) en caso de que la generación o descarga de la imagen falle.

### 6. Distribución Omnicanal
El contenido se adapta y se publica simultáneamente en:
* **𝕏 (Twitter):**
    * Sube la imagen generada (`UploadImageX`).
    * Ejecuta código JavaScript (`Code in JavaScript`) para truncar el texto si supera los 280 caracteres, añadiendo un enlace "Ver más".
* **Facebook:**
    * Detecta dinámicamente el ID de la página objetivo y extrae el Token de acceso (`ExtractPageToken`).
    * Publica el post con imagen y enlace en la Fan Page.
* **LinkedIn:**
    * Publica en el **Perfil de Empresa** (Organization).
    * Publica en el **Perfil Personal** (Person) para maximizar el alcance.

### 7. Persistencia de Datos
Una vez que las redes confirman la recepción, el flujo actualiza la base de datos marcando el artículo como "publicado", registrando la URL final de la imagen generada y el timestamp exacto.

---

## 🛠️ Stack Tecnológico & Integraciones

* **Core:** n8n (Workflow Automation) version 2.3.6.
* **Backend:** API REST propia con Autenticación JWT.
* **IA:** Pollinations.ai (Flux Model) para generación de imágenes.
* **Social APIs:**
    * Twitter API v2 (OAuth2 & OAuth1.0a para media upload).
    * Facebook Graph API (v19.0/v20.0).
    * LinkedIn API (Community Management).
* **Lenguajes:** JavaScript (para lógica de negocio dentro de los nodos `Function/Code`).

## 📋 Requisitos de Configuración (Credenciales)

Para desplegar este flujo, se requieren las siguientes credenciales configuradas en n8n:
1.  **JWT Auth account:** Para la API interna.
2.  **Twitter OAuth2 & API Key:** Para postear y subir medios.
3.  **Facebook Graph Posts:** Permisos de `pages_manage_posts` y `pages_read_engagement`.
4.  **LinkedIn Credential:** Permisos de `w_member_social` y `w_organization_social`.

## 🤝 Contribución
    1. Haz un Fork del repositorio.
    2. Crea una rama para tu mejora: git checkout -b feature/nuevo-filtro.
    3. Realiza un Commit: git commit -m 'Añadida fuente de noticias TechCrunch'.
    4. Abre un Pull Request.

## 📄 Licencia
Este proyecto está bajo la licencia n8n Sustainable Use License. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computacionales y Maestro en Administración de Proyectos.