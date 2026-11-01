# 🏨 AdminHotel Dashboard

### 🛠️ Integrated Frontend for Dynamic CRUD Engine

## 📝 Descripción

**AdminHotel** es una aplicación web Angular 21 para la operación del Hotel San José, integrada en el monorepo Hosting3M Automation Suite. El hotel opera un inventario de **18 habitaciones**; el dashboard carga las habitaciones desde el backend y no fija ese total como límite en el cliente.

La versión documentada más reciente es **v0.11.0** ([CHANGELOG](./CHANGELOG.md)). La aplicación cubre reservas y operación diaria, mantenimiento, inventario de activos y reportes financieros; comparte las librerías `core-auth`, `ui-chat` y `ui-pdf-export` con otros proyectos del monorepo.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1.0** | `Stable` | `Auth & Architecture` | Tabler + Bootstrap | Estructura base, JWT Auth, Signals. |
| **v0.2.0** | `Stable` | `Room Rack v1` | CSS Grid / Cards | Primera gestión visual del inventario de habitaciones. |
| **v0.3.0** | `Stable`| `Ops & Finance`| Modals / Reports | Checkout con inventario, Reporte de Caja y Gestión de Usuarios. |
| **v0.4.0** | `Stable` | `Pro UX & Patterns` | Skeletons / Services | Refactorización a Services, Skeletons de carga, Promesas. |
| **v0.5.0** | `Stable` | `Full Operation` | Interactive UI | Refresh Engine, Reservas dinámicas, Gestión avanzada de Huéspedes. |
| **v0.6.0** | `Stable` | `Accessibility` | Mobile Grid / CSS | Lógica de Descuentos, UX Accesible para Seniors. |
| **v0.6.1** | `Stable` | `Quality Assurance` | **JSONB / Forms** | **Módulo de Rondines, Persistencia Híbrida.** |
| **v0.7.0** | `Stable` | **AI Concierge** | **Shared Lib** | **Integración de `ui-chat`, Inyección de Tokens.** |
| **v0.8.0** | `Stable` | **Eco-Transformation I** | **Tickets / Assets** | **Gestión de Mantenimiento, Activos y Finanzas CAPEX.** |
| **v0.9.0** | `Stable` | **Performance & Scale** | **Routing / Signals** | **Arquitectura Distribuida, Carga Asíncrona, Inventario Centralizado.** |
| **v0.10.0** | `Stable` | **Digital Doc Export** | **ui-pdf-export** | **Exportación de cotizaciones PDF, motor financiero de impuestos y selección múltiple.** |
| **v0.11.0**| `Released` | **Resilience & Fin Engine**| **Signals/Services** | **Soft/Hard Bookings, Pagos Cascada, Timezone Armor, Error Boundary Shield.** |

---

## 🚀 Key Features (v0.11.0 Update)

### 1. 🛡️ Resiliencia y Manejo de Errores (MetaCRUD Shield)
* **Zero-Ghost States:** `BookingService` interpreta las respuestas `error: true` de Meta-CRUD aunque lleguen con HTTP 200 y evita presentarlas como una mutación exitosa.
* **Timezone Armor:** Funciones blindadas que calculan fechas relativas en hora local (CST/UTC-6), previniendo desfasajes de calendario o bloqueos automáticos en el turno vespertino (post 18:00 hrs).

### 2. 💰 Motor Financiero Avanzado
* **Soft-Booking vs Hard-Booking:** Generación de Cotizaciones sin impacto fiscal, con evolución automática a Reservas en firme tras detectar un depósito financiero.
* **Pagos Multi-Cuarto (Waterfall):** Abono masivo que inyecta capital a grupos (Master Folios) distribuyendo automáticamente la liquidación habitación por habitación.
* **Recálculo Dinámico:** Capacidad para extender días de estancias activas (`checked_in`), ajustando la deuda y reabriendo el estatus contable a "Parcial" automáticamente.

### 3. 📄 Generación de Documentos Digitales (PDF)
* **Cotizaciones Proactivas:** Generación instantánea de presupuestos ("PRESUPUESTO" vs "COMPROBANTE" dinámico).
* **Motor Fiscal:** Cálculo automático y desglosado de impuestos locales: Base Imponible, IVA (16%) e ISH (2%).

### 4. 🛏️ Inventario y operación hotelera
* El Room Rack consulta `hotel_rooms` y presenta las habitaciones agrupadas por tipo: **Sencilla, Kingsize, Doble y Triple**. La suite identifica también los tipos `INDIVIDUAL` y otros valores recibidos del backend.
* El inventario operativo del Hotel San José es de **18 habitaciones**. El frontend no codifica una capacidad máxima: trabaja con las filas que devuelve el gateway, de modo que el número efectivo depende del inventario configurado en el backend.
* La operación distingue habitación disponible, ocupada, en mantenimiento o sucia; además consulta reservas, entradas/salidas del día, limpieza e incidencias pendientes.

### 5. 🧰 Activos e infraestructura
* El módulo de inventario registra activos físicos por categoría, estado y ubicación (habitación o bodega); permite guardar costo y fecha de compra.
* No se encontró en el código una función de captura de lecturas, telemetría o integración con sub-medidores eléctricos. El catálogo de activos no equivale a monitoreo energético.

### 6. 🔌 Servicios compartidos y límites de integración
* **`core-auth`:** autenticación, selección/contexto de empresa, guards por rol e interceptor HTTP.
* **`ui-chat`:** asistente conversacional global conectado al webhook de n8n. Esta aplicación no habilita `attachments`, por lo que la integración aquí es de chat sin adjuntos.
* **`ui-pdf-export`:** generación client-side de documentos desde el módulo financiero.
* Reservas y gastos guardan métodos/estados de pago para operación y reportes; no se identificó una integración del dashboard con un procesador o pasarela de pago externa.

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

* **Rutas:** `/dashboard/mantenimiento`, `/dashboard/reservas`, `/dashboard/huespedes`, `/dashboard/personal`, `/dashboard/inventario` y `/dashboard/finanzas`.
* Son rutas hijas de `MainLayoutComponent`; actualmente se registran con imports directos en `app.routes.ts`, no mediante `loadComponent`/lazy loading.

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
<a href="./ARCHITECTURE.md">🏛️ Leer guía de arquitectura</a>
</p>

La aplicación implementa una arquitectura **Distributed Data-Access Pattern**:

### 🛠️ Stack Tecnológico

* **Core:** Angular v21.0.0 (Signals, Router, Standalone Components).
* **Librerías Internas:** `core-auth` (IAM), `ui-chat` (IA) y `ui-pdf-export` (Documentos).
* **State Management:** Angular Signals + Computed Properties.
* **PDF Engine:** jsPDF + AutoTable.

---

## 🚀 Capacidades del Sistema (Capabilities)

| Módulo | Estado | Descripción Técnica |
| --- | --- | --- |
| **Room Rack** | 🟢 Activo | Inventario dinámico del hotel (18 habitaciones operativas) y estados de cuarto/limpieza. |
| **Booking Engine** | 🟢 Activo | Motor de reservas con validación de conflictos y **Exportación PDF**. |
| **Mantenimiento** | 🟢 Activo | Sistema de Tickets con trazabilidad de resolución. |
| **Activos (Assets)** | 🟢 Activo | CRUD de inventario físico por habitación. |
| **Finanzas** | 🟢 Activo | Corte Z, gestión de CAPEX/OPEX y desglose fiscal automático. |
| **AI Concierge** | 🟢 Activo | Asistencia vía `ui-chat`; sin adjuntos habilitados en esta aplicación. |

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

```
---
*Built with the assistance of AI-powered development tools.*

```