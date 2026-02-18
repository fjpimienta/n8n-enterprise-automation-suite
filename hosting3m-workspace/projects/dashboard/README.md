# 🏨 AdminHotel Dashboard

### 🛠️ Integrated Frontend for Dynamic CRUD Engine

## 📝 Descripción

**AdminHotel** es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M.

Este dashboard actúa como el cliente principal del **Dynamic CRUD Engine**. En su versión actual (**v0.9.0**), ha evolucionado de una estructura monolítica a una **Arquitectura Distribuida**, optimizando la carga inicial y la experiencia de usuario móvil para gestionar operaciones críticas como Mantenimiento, Finanzas e Inventario Global.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1.0** | `Stable` | `Auth & Architecture` | Tabler + Bootstrap | Estructura base, JWT Auth, Signals. |
| **v0.2.0** | `Stable` | `Room Rack v1` | CSS Grid / Cards | Gestión visual de 17 habitaciones. |
| **v0.3.0** | `Stable`| `Ops & Finance`| Modals / Reports | Checkout con inventario, Reporte de Caja y Gestión de Usuarios. |
| **v0.4.0** | `Stable` | `Pro UX & Patterns` | Skeletons / Services | Refactorización a Services, Skeletons de carga, Promesas. |
| **v0.5.0** | `Stable` | `Full Operation` | Interactive UI | Refresh Engine, Reservas dinámicas, Gestión avanzada de Huéspedes. |
 **v0.6.0** | `Stable` | `Accessibility` | Mobile Grid / CSS | Lógica de Descuentos, UX Accesible para Seniors. |
| **v0.6.1** | `Stable` | `Quality Assurance` | **JSONB / Forms** | **Módulo de Rondines, Persistencia Híbrida.** |
| **v0.7.0** | `Stable` | **AI Concierge** | **Shared Lib** | **Integración de `ui-chat`, Inyección de Tokens.** |
| **v0.8.0** | `Stable` | **Eco-Transformation I** | **Tickets / Assets** | **Gestión de Mantenimiento, Activos y Finanzas CAPEX.** |
| **v0.9.0** | `Released` | **Performance & Scale** | **Routing / Signals** | **Arquitectura Distribuida, Carga Asíncrona, Inventario Centralizado.** |

---

## 🚀 Key Features (v0.9.0 Update)

### 1. 🏗️ Arquitectura de Navegación Distribuida

Se migró de un diseño "Todo en Modales" a un sistema de **Rutas Hijas (Child Routes)**, mejorando la separación de responsabilidades y permitiendo enlaces directos (Deep Linking).

* **Rutas:** `/dashboard/mantenimiento`, `/dashboard/finanzas`, `/dashboard/inventario`.
* **Impacto:** Reducción drástica del DOM inicial y mejor gestión de memoria.

### 2. ⚡ Optimización de Rendimiento (Performance First)

Estrategia agresiva para mejorar el *Time to Interactive (TTI)* y la percepción de velocidad.

* **Carga Asíncrona (Deferred Loading):** Priorización del `Room Rack` en el hilo principal. Datos secundarios (Reservas, CRM) se cargan en *background*.
* **Skeletons Inteligentes:** Reducción de nodos DOM (de 8 a 4) y adaptación visual al *Dark Mode* para evitar parpadeos ("flashbang").

### 3. 📦 Sistema de Inventario Centralizado

Unificación de la lógica logística en un módulo robusto.

* **Polimorfismo:** `AssetFormModal` ahora opera en contexto **Global** (Bodega) o **Local** (Habitación).
* **Trazabilidad:** Filtros avanzados por estado (`GOOD`, `DAMAGED`, `MISSING`) y ubicación física.

### 4. 🧠 Lógica de Negocio Reactiva (Smart Services)

Desacoplamiento total de la lógica compleja de la vista.

* **ReportService:** Centraliza cálculos financieros y balances usando `Signals` computadas.
* **AssetService:** Gestiona el ciclo de vida completo de los activos.
* **Beneficio:** Componentes visuales "tontos" (Presentational) que solo renderizan datos, facilitando el testeo y mantenimiento.

---

## 🎨 UX & Theming

* **Dark Mode Nativo:** Implementación de variables CSS (`var(--tblr-body-bg)`) para cambio de tema instantáneo sin recarga.
* **Mobile First:** Sidebar con auto-cierre inteligente y eliminación de headers redundantes para ganar espacio vertical.

---

## 🏗️ Arquitectura Técnica

> 🚀 **Deep Dive:** Consulta el diagrama completo de flujo y decisiones de diseño en:

<p align="center">
<a href="./ARCHITECTURE.md">
<img src="[https://img.shields.io/badge/](https://img.shields.io/badge/)🏛️_Leer_Guía_de_Arquitectura-206bc4?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Architecture Guide">
</a>
</p>

La aplicación implementa una arquitectura **Distributed Data-Access Pattern**:

### 🛠️ Stack Tecnológico

* **Core:** Angular v21.0.0 (Signals, Router, Standalone Components).
* **State Management:** Angular Signals + Computed Properties.
* **Backend Interface:** n8n Webhooks (API v3) + PostgreSQL.
* **UI Library:** Tabler.io (Customized via CSS Variables).

---

## 🚀 Capacidades del Sistema (Capabilities)

| Módulo | Estado | Descripción Técnica |
| :--- | :--- | :--- |
| **Room Rack** | 🟢 Activo | Visualización semafórica de estados (Limpio/Sucio/Mant/Ocupado). |
| **Booking Engine** | 🟢 Activo | Motor de reservas con validación de conflictos de fechas. |
| **Mantenimiento** | 🟢 Activo | Sistema de Tickets con trazabilidad de resolución. |
| **Activos (Assets)**| 🟢 Activo | CRUD de inventario físico por habitación. |
| **Finanzas** | 🟢 Activo | Corte Z y gestión diferenciada de CAPEX/OPEX. |
| **AI Concierge** | 🟢 Activo | Asistencia operativa vía Chat (Librería Compartida). |

---

## 📊 Roadmap: Siguientes Pasos (Eco-Hotel Phase II)

### 4. Huéspedes: Inteligencia de Cliente (CRM) ⏳ [EN PROGRESO]

* **Objetivo:** Validar el concepto "Eco-Boutique" conociendo al cliente.
* **Tarea Técnica:** Implementación de `tags` (Senior, Nómada, Familia) y `travel_reason`.

### 5. PWA Offline Mode ⏳ [PLANEADO]

* **Objetivo:** Operación continua sin internet.
* **Tecnología:** Service Workers para caché de rutas críticas (`/dashboard`, `/inventario`).

---

## 🛠️ Comandos de Desarrollo

1. **Requisitos**
* Node.js (v20+)
* Angular CLI v21.0.5


2. **Instalación y Servidor Local**
```bash
# Instalar dependencias del workspace
npm install

# Iniciar servidor Dashboard
ng serve dashboard

```


3. **Pruebas y Construcción**
```bash
# Compilación para Producción (Optimized)
ng build dashboard --configuration=production

```



---

## 📄 Licencia

Este proyecto está bajo la licencia **n8n Sustainable Use License**. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---

*Built with the assistance of AI-powered development tools.*