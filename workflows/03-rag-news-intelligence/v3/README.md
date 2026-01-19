# 🛠️ Enterprise AI News Curator & Persistent Sync v3 (Hosting3m)
## 📝 Concepto
Content Intelligence / AI Automation / Persistent Storage / Dual-Auth System

Este flujo es un motor de curaduría de contenidos de alto rendimiento. Transforma el ruido de la web en inteligencia de negocios procesable, extrayendo, filtrando y persistiendo noticias críticas sobre Inteligencia Artificial, Automatización e Infraestructura, enriqueciéndolas con arte generativo.

## 📝 Descripción
La v3.0 perfecciona el sistema de ingesta con una arquitectura de seguridad híbrida. Ahora es capaz de operar en dos modos simultáneos:
    * Modo Autónomo (Cron): Se auto-genera un token JWT válido (usando credenciales de sistema) para poder escribir en la base de datos protegida sin intervención humana.
    * Modo API (Webhook): Actúa como un endpoint seguro (/v3/news) que valida tokens de terceros antes de servir el contenido almacenado.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Endpoint Path | Cambios Principales | Archivo JSON |
| :--- | :--- | :--- | :--- | :--- |
| **v1** | `Legacy` | `/news` | Lanzamiento inicial. | `v1-rag.json` |
| **v2** | `Legacy` | `/v2/news` | News 2. Ingesta, Procesamiento y Persistencia de Noticias. | `v2-news.json` |
| **v3** | `Stable` | `/v3/news` | Dual-Auth (Auto-Login & Verify), Integración con CRUD v3 y Generación de Imagen mejorada (Flux). | `v3-news.json` |

---

### ⚙️ Lógica de Negocio
1. **Orquestación Dual (Híbrida):** 
    * Trigger Cron (6AM & 2PM): Inicia la recolección automática. Para escribir en el CRUD protegido, el flujo primero se autentica a sí mismo invocando el sub-workflow Genera Token con el usuario n8n@hosting3m.com.
    * Trigger Webhook: Permite consultar las noticias desde el frontend. Valida la petición entrante usando el sub-workflow Verify Token.
2. **Curaduría Inteligente:** 
    * Fuentes: Google News, Reddit, Menéame y medios tech especializados.
    * Filtrado Semántico: Algoritmo JS que prioriza temas clave (IA, LLM, n8n, Docker) y elimina duplicados y noticias irrelevantes.
3. **Arte Generativo (Flux Model):** 
    * Cada ciclo de ejecución invoca a Pollinations.ai con un prompt técnico futurista ("isometric 8k, unreal engine 5").
    * Esta imagen se asigna como portada para todas las noticias del lote, manteniendo una coherencia visual diaria.
4. **Persistencia Segura:** 
    * Utiliza el endpoint crud/v2/news_articles para escritura masiva (Insert).
    * Utiliza el endpoint crud/v3/news_articles para lectura (GetAll).
5. **Gestión de Seguridad JWT:** Sistema híbrido que puede validar tokens entrantes o generar sus propios tokens internos (genera-token) para comunicarse con otros servicios de la infraestructura Hosting3m.

---

## 🛠️ Instalación
- **Dependencias:**
    * Requiere los sub-workflows: v3/SW Genera Token (ID: fnzdIRyMWYUHggME) y v3/SW ValidaToken (ID: RSz6L3aXj3NfumwG).
    * Microservicio CRUD v2 y v3 operativos.
- **Configuración de Credenciales:**
    * Autónoma: Configura el nodo "Set User" con las credenciales de sistema (n8n@hosting3m.com / password) para permitir que el cron job genere sus propios tokens.
    * SMTP: Asegúrate de que las credenciales de correo estén activas si se habilitan notificaciones de error.
-   **Importación:**
    * Importa v3-news.json.
    * Verifica que los IDs de los sub-workflows en los nodos "Execute Workflow" coincidan con los de tu instancia.

---

## 🚀 Uso
    A. Ejecución Automática (Ingesta)
        No requiere acción. El sistema se despierta a las 06:00 y 14:00, genera su token, descarga noticias, crea imágenes y guarda todo en la DB.

    B. Consumo desde Frontend (Lectura)
        Para obtener las noticias guardadas desde una web o app:

        ``` Bash
            curl -X POST https://n8n.hosting3m.com/webhook/v3/news \
            -H "Authorization: Bearer <TOKEN_VALIDO>" \
            -H "Content-Type: application/json"
        ```
        Respuesta:
        ```
            [
            {
                "id": 150,
                "title": "Lanzamiento de GPT-5: Todo lo que sabemos",
                "url": "https://...",
                "image": "https://image.pollinations.ai/...",
                "source": "TechCrunch",
                "created_at": "2026-01-19T10:00:00Z"
            },
            ...
            ]
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