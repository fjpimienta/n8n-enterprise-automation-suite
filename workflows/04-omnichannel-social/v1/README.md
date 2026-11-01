# 💡 Social Media Intelligence & Omnichannel Automation Orchestrator

**Concepto:** Microservices Integration / Modular Design

Este flujo epresenta una solución integral de Marketing Automation de grado empresarial. Diseñada para operar de forma autónoma, esta suite orquestada en n8n se encarga de la extracción de noticias tecnológicas, el procesamiento de activos digitales y la distribución programada en múltiples plataformas sociales (X, Facebook, LinkedIn), garantizando una presencia de marca constante y optimizada.

## 📝 Descripción

El workflow automatiza el ciclo de vida completo de un contenido: desde su descubrimiento en la web hasta su publicación definitiva. Su arquitectura está orientada a la eficiencia operativa y al posicionamiento de autoridad en el sector tecnológico.

### Lógica del Sistema:
1.  **Curaduría Basada en Scraping:** Extrae dinámicamente títulos, descripciones e imágenes desde el portal de noticias mediante selectores CSS avanzados, eliminando la dependencia de feeds manuales.
2.  **Lógica Anti-Duplicación::** Implementa un sistema de verificación cruzada con una base de datos CRUD para asegurar que ninguna noticia se publique dos veces el mismo día o se repita el contenido.
3.  **Adaptación de Contenido Omnicanal:** Genera automáticamente copys personalizados con hashtags y estructuras específicas para Twitter, Facebook y LinkedIn (perfiles personales y de empresa) a partir de una única fuente.
4.  **Gestión Robusta de Media:** Descarga, redimensiona y procesa imágenes en tiempo real para cumplir con los requisitos técnicos de cada API social.

---

## 🛠️ Instalación

Para desplegar este workflow en tu infraestructura, sigue estos pasos:

1.  **Requisitos de Infraestructura:**
    * Instancia de **n8n v2.0.3** o superior.
    * Microservicio de autenticación JWT activo.
    * Base de datos o microservicio CRUD accesible vía HTTP para el registro de logs.
    * Acceso a las APIs de desarrollador de X (Twitter), Facebook Graph API y LinkedIn Community Management.

2.  **Importación del Workflow:**
    * Copia el contenido del archivo `.json` de este repositorio.
    * En n8n, selecciona "Import from File" o pega el JSON directamente en el lienzo.
    * Actualice los IDs de página de Facebook y las organizaciones de LinkedIn en los nodos de código y configuración.

3.  **Configuración de Credenciales:**
    * **JWT Auth:** Configura tu secreto de validación en el nodo Webhook.
    * **OAuth2:** Vincular las cuentas de X, Facebook y LinkedIn en el panel de credenciales de n8n.
    * **HTTP Basic/Token:** Configurar el acceso al generador de tokens interno de hosting3m.com.

4.  **Despliegue de Servicios Relacionados:**
    ```bash
    # Start the required JWT authentication service
    docker-compose up -d jwt-service
    ```

---

## 🚀 Uso

El flujo es altamente versátil y puede consumirse de dos formas:

### 🔄 Consumo vía API (Bajo Demanda)
Envíe una petición autenticada para obtener el HTML curado en tiempo real:
```bash
curl -X POST https://n8n.tu-dominio.com/webhook/NewsScraper \
-H "Content-Type: application/json"
-H "Authorization: Bearer <TU_JWT_TOKEN>"
```

### Ejecución Automática

El nodo **Cron** está configurado para ejecutar el proceso diariamente a las 06:00 horas, ideal para alimentar bases de datos vectoriales (RAG) o disparar envíos de correo automáticos.

**Lógica de Salida**
El flujo retorna un objeto JSON con una propiedad `html` que contiene una estructura de `news-cards` responsivas, diseñadas para una experiencia de usuario profesional.

### Monitoreo de Resultados
Cada publicación exitosa genera un registro en la base de datos centralizada, incluyendo la URL del artículo, el título y el timestamp de publicación, permitiendo auditorías de marketing posteriores.

---

### 📦 Tecnologías
Este flujo de trabajo demuestra un dominio avanzado de la integración de sistemas modernos:
    * **n8n Orquestador:** Motor de flujos de trabajo basado en nodos.
    * **JavaScript (Node.js):** Lógica personalizada para manipulación de objetos JSON y limpieza de datos.
    * **HTML Parsing (Scraping):** Uso de selectores DOM para la extracción precisa de metadatos de noticias.
    * **REST API:** Comunicación con servicios externos de CRM y gestión de clientes.
    * **JWT (JSON Web Tokens):** Estándar de seguridad para la autenticación de la petición entrante.
    * **Gestión de Binarios:** Procesamiento de imágenes para carga de media en redes sociales

---

## 🤝 Contribución
### Si deseas mejorar este flujo o añadir validaciones adicionales (como MFA o logging avanzado):
    1. Haz un Fork del repositorio.
    2. Crea una nueva rama (git checkout -b feature/MejoraSeguridad).
    3. Realiza tus cambios y haz un Commit (git commit -m 'Añadida validación de expiración').
    4. Sube los cambios a tu rama (git push origin feature/MejoraSeguridad).
    5. Abre un Pull Request.

---

## 📄 Licencia
### Este proyecto demuestra la capacidad de integración de n8n con stacks modernos de backend:Este proyecto está bajo la licencia n8n Sustainable Use License. Eres libre de usarlo y modificarlo para fines personales o internos de empresa.


Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computaciones y Maestro en Administracion de Proyectos.