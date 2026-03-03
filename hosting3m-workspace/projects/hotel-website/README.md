# 🌍 Hotel Eco-Website

### 🏨 Public-Facing Landing Page & Lead Capture Engine

## 📝 Descripción

**hotel-website** es la interfaz pública del ecosistema Hosting3M. A diferencia del dashboard administrativo, esta aplicación está optimizada para la **conversión de visitantes en huéspedes**, integrando un diseño biófilo ("Eco-Boutique") y capacidades de Inteligencia Artificial en tiempo real.

Desarrollada como una **Angular SPA** (Single Page Application) dentro del monorepo, consume servicios compartidos y se comunica directamente con el orquestador **n8n** para la gestión de prospectos.

---

## 🚀 Key Features (v1.0.0)

### 1. 🎨 Diseño "Eco-Boutique" & UI

* **Tailwind CSS v3 Nativo:** Estilizado mediante un sistema de tokens personalizados (`eco`, `tierra`) con soporte para *Glassmorphism* (efectos de cristal).
* **Responsive & Fluid:** Optimizado para dispositivos móviles bajo el principio de "Fat-Finger Design" en formularios de reserva.
* **Core Web Vitals:** Implementación de *Tree-shaking* y compilación *JIT* para asegurar tiempos de carga menores a 1.2s.

### 2. 🤖 AI Concierge (Shared Library)

* **Integración con `@hosting3m/ui-chat`:** La web reutiliza el widget de chat corporativo, inyectando un `CHAT_CONFIG_TOKEN` específico para atención al cliente público.
* **Atención 24/7:** Filtrado de dudas frecuentes (FAQ) y asistencia en el proceso de reserva mediante lenguaje natural.

### 3. 🔌 Lead Capture & n8n Integration

* **Formulario Reactivo:** Captura de datos de reserva mediante `FormGroup` y validaciones en tiempo real.
* **n8n Webhook Connection:** Envío de leads mediante `HttpClient` (POST) hacia flujos de automatización que notifican a recepción y registran al prospecto en PostgreSQL.

---

## 🏗️ Arquitectura Técnica

El proyecto sigue una estructura desacoplada para facilitar el mantenimiento:

* **Framework:** Angular 21 (Standalone Components).
* **Styling:** Tailwind CSS + CSS Variables (Design Tokens).
* **Communication:** REST API via n8n Webhooks.
* **Shared Dependencies:** * `ui-chat`: Para el asistente virtual.
* `ui-pdf-export`: (Opcional) Para pre-visualización de cotizaciones públicas.

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
* [ ] **Direct Payment Integration:** Conexión con pasarelas de pago (Stripe/PayPal) vía n8n.
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