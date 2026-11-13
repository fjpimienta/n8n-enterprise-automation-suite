# 🌍 Hotel Eco-Website

### 🏨 Public-Facing Landing Page & Lead Capture Engine

## 📝 Descripción

**hotel-website** es la interfaz pública del Hotel San José dentro del ecosistema Hosting3M. A diferencia del dashboard administrativo, esta aplicación presenta el hotel, capta reseñas (flujo deshabilitado por ahora) y ofrece una experiencia de consulta con diseño "Eco-Boutique".

Desarrollada como una **Angular SPA** dentro del monorepo, integra `ui-chat` y se comunica con webhooks de **n8n** y el gateway Meta-CRUD. La interfaz de disponibilidad y pre-reserva sigue en el código, pero su búsqueda está deshabilitada actualmente por un control preventivo (*kill switch*); el visitante recibe un aviso para contactar al hotel.

---

## 🚀 Funcionalidad documentada

### 1. 🎨 Diseño "Eco-Boutique" y UI

* **Tailwind CSS v4:** Estilizado mediante un sistema de tokens personalizados (`eco`, `tierra`) con soporte para *Glassmorphism* (efectos de cristal).
* **Responsive & Fluid:** Optimizado para dispositivos móviles bajo el principio de "Fat-Finger Design" en formularios de reserva.

### 2. 🤖 AI Concierge (Shared Library)

* **Integración con `@hosting3m/ui-chat`:** La web reutiliza el widget de chat corporativo, inyectando un `CHAT_CONFIG_TOKEN` específico para atención al cliente público.
* El componente usa el webhook `apiUrl_ai` configurado por la aplicación. La integración no activa adjuntos ni PDF.

### 3. 📝 Reseñas y flujos HTTP

* El código de reseñas (`App.loadDbReviews()` y `App.submitReview()`) consulta y envía reseñas al endpoint Meta-CRUD `hotel_reviews`, pero está **deshabilitado**: `reviewsEnabled = false` en `app.ts` impide la carga inicial y la plantilla oculta la sección y el modal (`@if (reviewsEnabled)`). Mientras la bandera sea `false`, el sitio no envía peticiones de reseñas.
* La UI conserva el formulario de disponibilidad, selección de tipo de habitación y captura de datos de huésped. Sin embargo, `searchAvailability()` muestra el aviso de mantenimiento y retorna antes de hacer la solicitud al webhook. Por tanto, **la reserva online no está habilitada actualmente desde el sitio**.
* El código de envío del formulario de pre-reserva permanece detrás del paso de disponibilidad; su presencia no significa que el recorrido público completo esté disponible.

---

## 🏗️ Arquitectura Técnica

El proyecto sigue una estructura desacoplada para facilitar el mantenimiento:

* **Framework:** Angular 21 (Standalone Components).
* **Styling:** Tailwind CSS v4 (`tailwindcss` 4.3.5 según `package-lock.json`) con tokens `eco` y `tierra` definidos en `tailwind.config.js`.
* **Communication:** `HttpClient` hacia webhooks públicos y Meta-CRUD de n8n.
* **Shared Dependency:** `ui-chat`, configurada con `CHAT_CONFIG_TOKEN` y `apiUrl_ai`.
* **No integrado en esta aplicación:** `ui-pdf-export` y `core-auth`.
* **Componente raíz y rutas:** `App` (`src/app/app.ts`, plantilla `app.html`). No hay rutas (`app.routes.ts` exporta `[]`); la página es un único documento con anclas (`#esencia`, `#amenidades`, `#habitaciones`, `#contacto`).
* **Servicios:** `HttpClient` inyectado en `App`; `AiService` de `ui-chat` provisto en `app.config.ts`.

### Formularios y endpoints

* **Búsqueda de disponibilidad (paso 1):** `App.searchAvailability()` muestra el aviso de mantenimiento y sale; la petición `POST {apiUrl_public}/availability` está en código inactivo.
* **Pre-reserva (paso 3):** `App.submitForm()` envía `name`, `phone`, `email`, `checkin`, `checkout`, `room_type`, `guests`, `total_price_per_night` y `origen` a `POST {apiUrl_public}/lead`. Una respuesta 2xx se trata como éxito (el cuerpo no se valida); 400 muestra correo inválido, 409 habitación agotada, 422 correo rebotado y cualquier otro error, error de conexión. Este paso no es alcanzable desde la UI.
* **Reseñas:** `App.loadDbReviews()` y `App.submitReview()` usan `POST {apiUrl_crud}/hotel_reviews` con `getall` o `insert` (`is_approved: false`). Las peticiones no llevan token: `app.config.ts` no registra interceptores. Deshabilitadas por `reviewsEnabled`.
* **Chat de atención:** `AiChatComponent` (`lib-ai-chat`) con `AiService` de `ui-chat`, que envía a `apiUrl_ai`. Sin adjuntos: `attachments` no se configura y `ui-chat` lo deja desactivado por defecto.
* **Bases de URL:** `apiUrl_public`, `apiUrl_crud` y `apiUrl_ai` vienen de los archivos de entorno, que no están versionados. TODO(verify): valores por entorno y su origen.
* **Tenant:** el sitio no envía `id_company` ni token en ninguna petición. Cómo n8n determina la empresa en `/lead` y en `hotel_reviews` no se puede comprobar desde este repositorio. TODO(verify): confirmarlo en los workflows.

### Recursos externos

* Tabler CSS (`@tabler/core@latest`, jsdelivr) se importa con `@import` en `src/styles.css`, junto con Font Awesome 6.0.0 (cdnjs) y el webfont de Tabler Icons (`@latest`). Clases como `avatar` dependen de estas hojas.
* En `src/index.html`: Google Fonts (Inter, Merriweather), Lucide (`unpkg.com/lucide@latest`) y Google tag (gtag).
* Las URLs con `@latest` no tienen versión fijada y pueden cambiar sin aviso.

### Current Tailwind build setup

The production build uses Tailwind CSS v4 through `@tailwindcss/postcss`, configured in
`.postcssrc.json`. `src/styles.css` loads Tailwind with `source(none)`, points to the
existing `tailwind.config.js`, and explicitly includes this project and `ui-chat` as
sources. A small compatibility layer preserves Tailwind v3's default border color and
`shadow-sm`; the existing eco/tierra tokens in `tailwind.config.js` are unchanged.

Run the production build from the workspace root:

```bash
npx ng build hotel-website --configuration production
```

The site is served through the Plesk Git deploy action.

The action pulls `main`, builds `ui-pdf-export` and `hotel-website` with the production
configuration, and replaces the published files only if both builds succeed. A failed
build leaves the previous site in place. Back up the currently published files before
triggering a deployment.

Automatic deployment is not active. After a release reaches `main`, trigger the action
manually in Plesk with **Deploy now**.

#### Tailwind v4 deployment troubleshooting

If a build fails, check the deploy log first. A Tailwind/PostCSS error indicates an
incorrect change to `.postcssrc.json` or `src/styles.css`; compare those files with the
Tailwind v4 setup above.

---

## 🛠️ Configuración y Desarrollo

Para trabajar en este proyecto específico dentro del monorepo, sigue estos pasos:

### 1. Requisitos Previos

Asegúrate de haber compilado las librerías compartidas del monorepo:

```bash
ng build ui-chat

```

Los archivos `src/environments/environment.ts` y `src/environments/environment.prod.ts` no están en el repositorio (`.gitignore` los excluye). Deben crearse localmente con las claves `apiUrl_public`, `apiUrl_crud` y `apiUrl_ai`, que usan `app.ts` y `app.config.ts`. Ambos archivos se importan en cualquier configuración porque `angular.json` no define `fileReplacements`, así que los dos son necesarios para compilar. TODO(verify): valores de cada entorno; no documentar valores reales.

Según `tsconfig.json`, `ui-chat` se resuelve a su código fuente, así que el paso anterior puede no ser necesario. TODO(verify).

### 2. Servidor de Desarrollo

Ejecuta el proyecto localmente:

```bash
ng serve hotel-website

```

### 3. Build de Producción

Genera los archivos optimizados para despliegue:

```bash
ng build hotel-website --configuration=production

```

### 4. Pruebas

```bash
ng test hotel-website

```

`src/app/app.spec.ts` todavía espera el texto de la plantilla de ejemplo (`Hello, hotel-website`), que no existe en `app.html`. Además, el spec solo provee `App`, pero el componente inyecta `HttpClient` y `ui-chat` necesita `CHAT_CONFIG_TOKEN`. TODO(verify): no se ejecutó en esta revisión; con el código actual se espera que fallen las pruebas.

### 5. Rendimiento

* **Objetivo:** el `CLAUDE.md` del proyecto fija un presupuesto de carga de menos de 1.2 s (Core Web Vitals). El repositorio no contiene medición de LCP ni prueba de rendimiento. TODO(verify): medir el sitio publicado (p. ej. Lighthouse o CrUX).
* **Presupuesto de build (`angular.json`):** bundle inicial con aviso a 500 kB y error a 1 MB; estilos de componente con aviso a 4 kB y error a 8 kB. Son límites de tamaño, no de tiempo.
* **Tailwind:** solo genera utilidades de los `@source` declarados (`src/` y `ui-chat/src`).
* **Carga bloqueante:** `src/styles.css` importa tres hojas CDN con `@import`, y `src/index.html` carga el script de Lucide en `<head>` sin `defer`, dos veces. TODO(verify): impacto real en LCP.
* **AOT:** `angular.json` no fuerza AOT de forma explícita. TODO(verify): confirmar en el build de producción.

---

## 📋 Roadmap del Proyecto

* [ ] **A/B Testing:** Implementación de diferentes variantes del Hero-Section para medir conversión.
* [ ] **Reactivate Online Booking:** Retirar el kill switch solo después de validar disponibilidad, creación de pre-reservas y manejo de errores de punta a punta.
* [ ] **Direct Payment Integration:** Conexión con pasarelas de pago vía n8n.
* [ ] **Multi-language Support:** Soporte para i18n (Inglés/Español).

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```