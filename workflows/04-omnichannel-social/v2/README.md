# 💡 Social Media Intelligence & Omnichannel Automation Orchestrator v2

**Concepto:** Microservices Integration / Modular Design

Este flujo representa una solución integral de Marketing Automation de grado empresarial. Diseñada para operar de forma autónoma, esta suite orquestada en n8n se encarga de la extracción de noticias tecnológicas, el procesamiento de activos digitales mediante IA generativa y la distribución programada en múltiples plataformas sociales (X, Facebook, LinkedIn), garantizando una presencia de marca constante y optimizada.

## 📝 Descripción

El workflow automatiza el ciclo de vida completo del contenido: desde su descubrimiento en la base de datos hasta su publicación definitiva. La arquitectura v2 introduce capas de seguridad robustas y una lógica de prevención de spam que asegura que la marca mantenga una comunicación profesional y no redundante.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/NewsScraper` | Lanzamiento inicial. | `v1-omnichanel.json` |
| **v2** | `Stable` | `/v2/NewsScraper` | CRUD v2, Verificación de cuota diaria, Generación IA (Flux), CRUD v2, Soporte Multi-perfil LinkedIn. | `v2-omnichanel.json` |

---

## ⚙️ Arquitectura y Lógica del Sistema

El flujo opera bajo un esquema secuencial con validación condicional. A continuación se detalla cada etapa:

### 1. Disparadores (Triggers) Híbridos
El sistema puede iniciarse de dos formas:
* **Automática (Cron):** Ejecución programada diariamente a las 06:00 AM.
* **Manual (Webhook):** Endpoint `/v2/NewsScraper` protegido con autenticación JWT para ejecuciones bajo demanda.

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
Finalmente, tras una publicación exitosa, se registra el artículo en la base de datos interna (`insert` operation) con la fecha de publicación, URL, título e imagen generada, cerrando el ciclo de validación para futuras ejecuciones.

---

## 🛠️ Stack Tecnológico & Integraciones

* **Core:** n8n (Workflow Automation) version 2.2.4.
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