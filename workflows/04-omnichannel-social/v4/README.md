# 💡 Social Media Intelligence & Omnichannel Automation Orchestrator v4

**Concepto:** Microservices Architecture / Sovereign Media / Generative AI / Enterprise Social Distribution

**Versión:** 4.0 (CloudFree & Self-Hosted Edition)

Este flujo representa la **cúspide de la ingeniería de automatización** en la infraestructura de Hosting3M. La v4.0 trasciende la simple automatización para convertirse en un **Ecosistema de Microservicios Desacoplados** que garantiza la soberanía de los datos, la persistencia de activos y la seguridad de grado industrial.

---

## 🚦 Evolución del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/NewsScraper` | Lanzamiento inicial. | `v1-omnichanel.json` |
| **v2** | `Legacy` | `/v2/NewsScraper` | CRUD v2, Verificación de cuota diaria, Generación IA (Flux), CRUD v2, Soporte Multi-perfil LinkedIn. | `v2-omnichanel.json` |
| **v3** | `Stable` | `Internal Cron` | Arquitectura v3, Integración con SW Genera Token, Lógica de Error Handling robusta, y optimización de prompts para Flux. | `v3-omnichanel.json` |
| **v4** | **`Production`** | **Self-Hosted** | **Servicio de Carga Propio (Node.js), OpenAI DALL-E 3, Seguridad por Variables de Entorno ($env) y persistencia binaria "Reach Back".** |

---

## 🏗️ Arquitectura e Infraestructura v4 (Self-Hosted)

A diferencia de versiones anteriores, la v4.0 se apoya en un microservicio de almacenamiento propio desplegado en **Docker**, lo que permite que Hosting3M sea el dueño legítimo de cada activo visual generado.

### 1. Servicio de Carga (Upload-Service)

Implementación de un servidor **Node.js/Express** dedicado que actúa como CDN privado:

* **Tecnología:** Node.js, Express, Multer (Manejo de multipart/form-data).
* **Despliegue:** Contenedor Docker aislado con volúmenes persistentes.
* **Endpoint:** `https://upload.hosting3m.com/upload`
* **Función:** Recibe el binario generado por la IA, lo renombra y devuelve una URL pública permanente para las redes sociales.

### 2. Generación de Imagen (DALL-E 3 + Refined Prompting)

Se migró de Pollinations a **OpenAI (DALL-E 3)** para obtener una calidad visual superior:

* **Optimización:** Prompts inyectados dinámicamente con estilos artísticos específicos (Cyberpunk, Isometric, Minimalist).
* **Consistencia:** Se eliminó el riesgo de imágenes de "error" o "filtros de seguridad" mediante el uso de modelos comerciales robustos.

### 3. Persistencia Binaria (Técnica "Reach Back")

Se implementó una lógica avanzada en JavaScript para evitar la pérdida de archivos entre nodos:

* **Re-inyección:** Uso de `$('NodeName').first().binary.media` para recuperar el archivo original sin importar cuántas transformaciones JSON sufra el flujo intermedio. Esto garantiza que X (Twitter) y LinkedIn siempre reciban el archivo binario intacto.

---

## 🔒 Seguridad y Hardening

Siguiendo las mejores prácticas de **Senior Systems Engineering**:

* **Variables de Entorno:** Se eliminaron los passwords "hardcodeados". Ahora el sistema recupera credenciales críticas (como el `N8N_PASS` o el `CLOUDFREE_SECRET_KEY`) directamente del entorno del sistema mediante `{{$env["VARIABLE"]}}`.
* **Seguimiento de Sesión:** Validación estricta de tokens JWT RS256 para todas las operaciones de escritura en la base de datos.

---

## ⚙️ Lógica de Publicación Omnicanal v4

### 1. Control de Tiempos (Engagement Optimization)

* **Trigger:** Ejecución programada a las **08:05 AM**, optimizada para el pico de tráfico de noticias tecnológicas en el ecosistema de habla hispana.

### 2. Idempotencia y Filtrado Semántico

* El flujo consulta el **Dynamic CRUD Engine v3** para verificar si la noticia ya fue procesada, evitando publicaciones duplicadas y optimizando los ciclos de CPU del VPS.

### 3. Orquestación en Paralelo

Una vez que el binario es validado y cargado en el servidor propio, el orquestador dispara las publicaciones en paralelo hacia:

* **𝕏 (Twitter):** Manejo de medios vía API v2.
* **Facebook / Instagram:** Integración nativa vía **Facebook Graph API v23**.
* **LinkedIn:** Publicación dual (Perfil Personal y Organización).

---

## 🛠️ Stack Tecnológico (v4 Edition)

* **Engine:** n8n v2.4.6 (Self-Hosted en Docker).
* **Media Server:** Node.js 18-alpine, Express, Multer.
* **Database:** PostgreSQL (Híbrido Relacional + JSONB).
* **IA Gen:** OpenAI DALL-E 3 (Visuals) + GPT-4o (Semantic Analysis).
* **Reverse Proxy:** Nginx / Plesk para la exposición segura del `upload-service`.

---

## 🚀 Despliegue del Microservicio de Carga

```bash
# Levantar el servicio de almacenamiento persistente
docker-compose up -d upload-file

```

## 📄 Licencia y Autoría

Este ecosistema es propiedad de **Hosting3m**.
Desarrollado por: **Francisco Jesus Pérez Pimienta** - Ingeniero en Sistemas Computacionales | PMP | Full Stack.
