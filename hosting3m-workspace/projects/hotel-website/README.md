# 🌍 Hotel Eco-Website

### 🏨 Public-Facing Landing Page & Lead Capture Engine

## 📝 Descripción

**hotel-website** es la interfaz pública del Hotel San José dentro del ecosistema Hosting3M. A diferencia del dashboard administrativo, esta aplicación presenta el hotel, capta reseñas y ofrece una experiencia de consulta con diseño "Eco-Boutique".

Desarrollada como una **Angular SPA** dentro del monorepo, integra `ui-chat` y se comunica con webhooks de **n8n** y el gateway Meta-CRUD. La interfaz de disponibilidad y pre-reserva sigue en el código, pero su búsqueda está deshabilitada actualmente por un control preventivo (*kill switch*); el visitante recibe un aviso para contactar al hotel.

---

## 🚀 Funcionalidad documentada

### 1. 🎨 Diseño "Eco-Boutique" y UI

* **Tailwind CSS v3 Nativo:** Estilizado mediante un sistema de tokens personalizados (`eco`, `tierra`) con soporte para *Glassmorphism* (efectos de cristal).
* **Responsive & Fluid:** Optimizado para dispositivos móviles bajo el principio de "Fat-Finger Design" en formularios de reserva.

### 2. 🤖 AI Concierge (Shared Library)

* **Integración con `@hosting3m/ui-chat`:** La web reutiliza el widget de chat corporativo, inyectando un `CHAT_CONFIG_TOKEN` específico para atención al cliente público.
* El componente usa el webhook `apiUrl_ai` configurado por la aplicación. La integración no activa adjuntos ni PDF.

### 3. 📝 Reseñas y flujos HTTP

* La aplicación consulta y envía reseñas a través del endpoint Meta-CRUD `hotel_reviews`.
* La UI conserva el formulario de disponibilidad, selección de tipo de habitación y captura de datos de huésped. Sin embargo, `searchAvailability()` muestra el aviso de mantenimiento y retorna antes de hacer la solicitud al webhook. Por tanto, **la reserva online no está habilitada actualmente desde el sitio**.
* El código de envío del formulario de pre-reserva permanece detrás del paso de disponibilidad; su presencia no significa que el recorrido público completo esté disponible.

---

## 🏗️ Arquitectura Técnica

El proyecto sigue una estructura desacoplada para facilitar el mantenimiento:

* **Framework:** Angular 21 (Standalone Components).
* **Styling:** Tailwind CSS + CSS Variables (Design Tokens).
* **Communication:** `HttpClient` hacia webhooks públicos y Meta-CRUD de n8n.
* **Shared Dependency:** `ui-chat`, configurada con `CHAT_CONFIG_TOKEN` y `apiUrl_ai`.
* **No integrado en esta aplicación:** `ui-pdf-export` y `core-auth`.

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

---

## 🛠️ Configuración y Desarrollo

Para trabajar en este proyecto específico dentro del monorepo, sigue estos pasos:

### 1. Requisitos Previos

Asegúrate de haber compilado las librerías compartidas del monorepo:

```bash
ng build ui-chat

```

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