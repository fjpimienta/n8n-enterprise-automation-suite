# Changelog - Hotel Website

## [1.0.0] - 2026-03-02

### 🚀 Lanzamiento Inicial (Initial Release)

Establecimiento de la presencia web pública del hotel como una **Angular SPA** integrada en el Monorepo, diseñada para la conversión y atención automatizada.

#### 🏗️ Arquitectura & Core

* **Migración a Angular SPA:** Transición completa desde HTML/JS "vanilla" a un proyecto Angular nativo en `projects/hotel-website`, permitiendo la reutilización de lógica de negocio y componentes del monorepo.
* **Tailwind CSS Native Engine:** Implementación de **Tailwind v3** con compilación *Just-in-Time* (JIT). Configuración de `tailwind.config.js` para realizar *tree-shaking* sobre los componentes compartidos, optimizando los Core Web Vitals (LCP/FID).
* **Integración de Librerías Compartidas:** Inyección exitosa de la librería corporativa `@hosting3m/ui-chat`, habilitando el **AI Concierge** en la landing page sin duplicidad de código.

#### 🎨 UI/UX (Eco-Boutique Design)

* **Custom Design System:** Definición de tokens de diseño biófilos con paletas personalizadas (`eco` y `tierra`) y tipografía dual (Inter para legibilidad / Merriweather para elegancia).
* **Glassmorphism Experience:** Implementación de capas visuales con desenfoque de fondo (*backdrop-filter*) en navegación y modales para una estética moderna y fluida.
* **Componentes Reactivos:** Desarrollo de Hero-Sections inmersivos y galerías optimizadas con *lazy loading* nativo.

#### 🔌 Conectividad & Negocio

* **Reactive Lead Capture:** El formulario de reservas ahora utiliza el `HttpClient` de Angular, enviando payloads estructurados directamente a los **Webhooks de n8n** para iniciar el flujo de ventas.
* **State Management:** Implementación de estados de UI (`isSubmitting`, `success`, `error`) para feedback inmediato al usuario durante la solicitud de reserva.
* **CORS & Security:** Configuración de cabeceras de seguridad para la comunicación con el orquestador backend.

#### 📈 Optimización (Performance)

* **Bundle Optimization:** Reducción del peso final del sitio mediante la eliminación del CDN de Tailwind y el uso de compilación AOT (Ahead-of-Time).
* **SEO Ready:** Estructuración de etiquetas meta dinámicas y semántica HTML5 para mejorar el indexado en motores de búsqueda.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```