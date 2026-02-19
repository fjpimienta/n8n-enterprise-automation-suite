# 🏨 AdminHotel Dashboard

### 🛠️ Integrated Frontend for Dynamic CRUD Engine

## 📝 Descripción

**AdminHotel** es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M.

En su versión actual (**v0.10.0**), el sistema integra capacidades avanzadas de **Exportación de Documentos Digitales**, consolidando una arquitectura distribuida que gestiona de forma eficiente Mantenimiento, Finanzas, Inventario y ahora la formalización de Reservas mediante PDF.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1.0** | `Stable` | `Auth & Architecture` | Tabler + Bootstrap | Estructura base, JWT Auth, Signals. |
| **v0.2.0** | `Stable` | `Room Rack v1` | CSS Grid / Cards | Gestión visual de 17 habitaciones. |
| **v0.3.0** | `Stable`| `Ops & Finance`| Modals / Reports | Checkout con inventario, Reporte de Caja y Gestión de Usuarios. |
| **v0.4.0** | `Stable` | `Pro UX & Patterns` | Skeletons / Services | Refactorización a Services, Skeletons de carga, Promesas. |
| **v0.5.0** | `Stable` | `Full Operation` | Interactive UI | Refresh Engine, Reservas dinámicas, Gestión avanzada de Huéspedes. |
| **v0.6.0** | `Stable` | `Accessibility` | Mobile Grid / CSS | Lógica de Descuentos, UX Accesible para Seniors. |
| **v0.6.1** | `Stable` | `Quality Assurance` | **JSONB / Forms** | **Módulo de Rondines, Persistencia Híbrida.** |
| **v0.7.0** | `Stable` | **AI Concierge** | **Shared Lib** | **Integración de `ui-chat`, Inyección de Tokens.** |
| **v0.8.0** | `Stable` | **Eco-Transformation I** | **Tickets / Assets** | **Gestión de Mantenimiento, Activos y Finanzas CAPEX.** |
| **v0.9.0** | `Stable` | **Performance & Scale** | **Routing / Signals** | **Arquitectura Distribuida, Carga Asíncrona, Inventario Centralizado.** |
| **v0.10.0** | `Released` | **Digital Doc Export** | **ui-pdf-export** | **Exportación de cotizaciones PDF, motor financiero de impuestos y selección múltiple.** |

---

## 🚀 Key Features (v0.10.0 Update)

### 1. 📄 Generación de Documentos Digitales (PDF)

Integración de la librería corporativa `@hosting3m/ui-pdf-export` para la formalización de procesos comerciales.

* **Cotizaciones Proactivas:** Generación instantánea de presupuestos de hospedaje para clientes corporativos (ej. PCP Construcciones).
* **Motor Financiero:** Cálculo automático y desglosado de impuestos locales: Base Imponible, IVA (16%) e ISH (2%).
* **Selección Múltiple e Inteligente:** Nueva interfaz con checkboxes que permite agrupar múltiples estancias en un solo documento consolidado.
* **Agrupación Automática:** Lógica de negocio que colapsa habitaciones idénticas en una sola partida del reporte para mayor claridad visual.

### 2. 🏗️ Arquitectura de Navegación Distribuida (v0.9.0)

Migración a un sistema de **Rutas Hijas (Child Routes)**, permitiendo enlaces directos (Deep Linking) a módulos específicos.

* **Rutas:** `/dashboard/mantenimiento`, `/dashboard/finanzas`, `/dashboard/inventario`.
* **Impacto:** Reducción drástica del DOM inicial y mejor gestión de memoria.

### 3. ⚡ Optimización de Rendimiento

Estrategia para mejorar el *Time to Interactive (TTI)* y la percepción de velocidad.

* **Carga Asíncrona (Deferred Loading):** Priorización del `Room Rack`. Los datos de reservas y CRM se cargan en segundo plano.
* **Skeletons Inteligentes:** Reducción de nodos DOM y adaptación visual al *Dark Mode*.

### 4. 🧠 Lógica de Negocio Reactiva (Smart Services)

* **PdfExportService:** Motor agnóstico para la creación de reportes profesionales.
* **ReportService:** Centraliza cálculos financieros y balances usando `Signals` computadas.
* **AssetService:** Gestiona el ciclo de vida completo de los activos físicos del hotel.

---

## 🎨 UX & Theming

* **Dark Mode Nativo:** Variables CSS para cambio de tema instantáneo.
* **Mobile First:** Sidebar con auto-cierre y selección de filas optimizada para uso táctil.

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
* **Librerías Internas:** `ui-chat` (IA) y `ui-pdf-export` (Documentos).
* **State Management:** Angular Signals + Computed Properties.
* **PDF Engine:** jsPDF + AutoTable.

---

## 🚀 Capacidades del Sistema (Capabilities)

| Módulo | Estado | Descripción Técnica |
| --- | --- | --- |
| **Room Rack** | 🟢 Activo | Visualización semafórica de estados (Limpio/Sucio/Mant/Ocupado). |
| **Booking Engine** | 🟢 Activo | Motor de reservas con validación de conflictos y **Exportación PDF**. |
| **Mantenimiento** | 🟢 Activo | Sistema de Tickets con trazabilidad de resolución. |
| **Activos (Assets)** | 🟢 Activo | CRUD de inventario físico por habitación. |
| **Finanzas** | 🟢 Activo | Corte Z, gestión de CAPEX/OPEX y desglose fiscal automático. |
| **AI Concierge** | 🟢 Activo | Asistencia operativa vía Chat (Librería Compartida). |

---

## 📊 Roadmap: Siguientes Pasos (Eco-Hotel Phase II)

### 4. Huéspedes: Inteligencia de Cliente (CRM) ⏳ [EN PROGRESO]

* **Objetivo:** Implementación de `tags` (Senior, Nómada, Familia) y `travel_reason`.

### 5. PWA Offline Mode ⏳ [PLANEADO]

* **Tecnología:** Service Workers para caché de rutas críticas como `/inventario`.

---

## 🛠️ Comandos de Desarrollo

1. **Instalación**

```bash
npm install

```

2. **Compilación de Librerías (Requerido para el Build)**

```bash
ng build ui-pdf-export
ng build ui-chat

```

3. **Servidor Local y Producción**

```bash
# Iniciar servidor Dashboard
ng serve dashboard

# Compilación para Producción
ng build dashboard --configuration=production

```

---

## 📄 Licencia

Este proyecto está bajo la licencia **n8n Sustainable Use License**.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---

*Built with the assistance of AI-powered development tools.*
