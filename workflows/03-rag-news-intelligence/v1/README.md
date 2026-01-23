# 💡 Enterprise Contact Lead & CRM Sync (Hosting3m)

**Concepto:** Microservices Integration / Modular Design

Este flujo contiene un motor de curaduría de contenidos de alto rendimiento desarrollado en n8n. El sistema transforma el ruido de la web en inteligencia de negocios procesable, extrayendo, filtrando y formateando noticias críticas sobre Inteligencia Artificial, Automatización e Infraestructura.

## 📝 Descripción

El proyecto es una solución "Enterprise-Grade" para el monitoreo de tendencias tecnológicas. A diferencia de un lector de RSS convencional, este flujo implementa lógica de programación avanzada en JavaScript para garantizar la relevancia del contenido.

### Capacidades Estratégicas:
1.  **Orquestación Híbrida:** Activación mediante un endpoint seguro (JWT) para consumo bajo demanda o ejecución programada (Cron) para reportes matutinos..
2.  **Algoritmo de Curaduría Inteligente:** Filtra contenidos por relevancia semántica (IA, Agentes, LLMs, Docker) y aplica criterios de frescura (últimas 48 horas).
3.  **Motor de Extracción de Media:** Heurísticas personalizadas para recuperar miniaturas de Google News y otros proveedores que no incluyen imágenes en sus feeds estándar.
4.  **Generación de UI Dinámica:** Transforma los datos crudos en una galería de componentes HTML listos para ser insertados en newsletters, dashboards corporativos o aplicaciones web.

---

## 🛠️ Instalación

Para desplegar este workflow en tu infraestructura n8n (v2.0.3 o superior), sigue estos pasos:

1.  **Requisitos de Infraestructura:**
    * Instancia de **n8n v2.0.3** o superior.
    * Microservicio de autenticación JWT activo.

2.  **Importación del Workflow:**
    * Copia el contenido del archivo `.json` de este repositorio.
    * En n8n, selecciona "Import from File" o pega el JSON directamente en el lienzo.

3.  **Configuración de Credenciales:**
    * **JWT Auth:** Configura tu secreto de validación en el nodo Webhook.
    * **FEEDS:** Asegúrese de que su instancia tiene permisos de salida hacia las URLs de los feeds (Reddit, TechCrunch, Wired, etc.).

4.  **Ajuste de Parámetros:** En el nodo `FiltrarTemas`, puede modificar la constante `topics` para adaptar el radar de noticias a los intereses específicos de su organización.

5.  **Levantamiento de Infraestructura:** En el nodo `FiltrarTemas`, puede modificar la constante `topics` para adaptar el radar de noticias a los intereses específicos de su organización.
```bash
# Si utiliza Docker, asegúrese de que su contenedor n8n tenga acceso a internet
docker-compose up -d n8n-compose
```

---

## 🚀 Uso

El flujo es altamente versátil y puede consumirse de dos formas:

### 🔄 Consumo vía API (Bajo Demanda)
Envíe una petición autenticada para obtener el HTML curado en tiempo real:
```bash
curl -X POST https://n8n.tu-dominio.com/webhook/news \
-H "Content-Type: application/json"
-H "Authorization: Bearer <TU_JWT_TOKEN>"
```

### Ejecución Automática

El nodo **Cron** está configurado para ejecutar el proceso diariamente a las 00:00 horas, ideal para alimentar bases de datos vectoriales (RAG) o disparar envíos de correo automáticos.

**Lógica de Salida**
El flujo retorna un objeto JSON con una propiedad `html` que contiene una estructura de `news-cards` responsivas, diseñadas para una experiencia de usuario profesional.

---

### 📦 Tecnologías
Este flujo de trabajo demuestra un dominio avanzado de la integración de sistemas modernos:
    * **n8n Orquestador:** Orquestación de flujos de trabajo asíncronos.
    * **JavaScript (Node.js):** Utilizado para el filtrado complejo, algoritmos de aleatoriedad (Fisher-Yates) y construcción de templates de UI.
    * **Arquitectura REST & Webhooks:** Para la interoperabilidad con otros microservicios.
    * **JWT (JSON Web Tokens):** Capa de protección para el acceso a la información curada.
    * **CORS Management:** Cabeceras configuradas para permitir la integración directa con frontends externos.
    * **RSS/XML Parsing:** Ingesta de datos de múltiples fuentes heterogéneas.

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