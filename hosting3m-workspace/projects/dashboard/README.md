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
* **Zero-Ghost States (parcial):** `BookingService` revisa las respuestas `error: true` de Meta-CRUD aunque lleguen con HTTP 200 en el check-in, el check-out y la creación de huéspedes de reservas futuras, y lanza excepción en lugar de presentar la mutación como exitosa. Las demás mutaciones del servicio no lo revisan (ver tabla).
* **Timezone Armor (parcial):** `BookingService` calcula «hoy» con evaluadores de hora local (CST/UTC-6), previniendo desfasajes de calendario en el turno vespertino (post 18:00 hrs). Otros puntos siguen usando `toISOString()` (UTC); ver *Limitaciones y riesgos abiertos*.

**Cobertura del Shield en `BookingService`** ([booking.service.ts](./src/app/features/booking/services/booking.service.ts)):

| Operación | Revisa `error: true` | Comportamiento |
| :--- | :--- | :--- |
| Check-in (`processCheckin`): reserva, huésped, reserva nueva y estado de habitación | Sí | Lanza excepción a la UI |
| Check-out (`processCheckout`): cierre de reserva y de habitación | Sí | Lanza excepción a la UI |
| Reserva futura (`createFutureReservation`): alta de huésped | Indirecto | Sin `id` lanza «No se pudo obtener un ID de huésped válido.» |
| Reserva futura (`createFutureReservation`): alta de reserva | No | Devuelve `true` aunque venga `error: true` |
| `updateReservation`, `registerPayment`, `cancelReservation`, `confirmPendingReservation` | No | Se tratan como exitosas |
| `updateCleaningStatus` | No | Recarga habitaciones sin validar la respuesta |
| `loadRooms` (lectura) | Sí | Trata el error como lista vacía, sin aviso al usuario |

### 2. 💰 Motor Financiero Avanzado
* **Soft-Booking vs Hard-Booking:** Generación de Cotizaciones sin impacto fiscal, con evolución automática a Reservas en firme tras detectar un depósito financiero.
* **Pagos Multi-Cuarto (Waterfall):** Abono masivo que inyecta capital a grupos (Master Folios) distribuyendo automáticamente la liquidación habitación por habitación.
* **Recálculo Dinámico:** Capacidad para extender días de estancias activas (`checked_in`), ajustando la deuda y reabriendo el estatus contable a "Parcial" automáticamente.

### 3. 📄 Generación de Documentos Digitales (PDF)
* **Cotizaciones Proactivas:** Generación instantánea de presupuestos ("PRESUPUESTO" vs "COMPROBANTE" dinámico).
* **Motor Fiscal:** Cálculo automático y desglosado de impuestos locales: Base Imponible, IVA (16%) e ISH (2%). El cálculo lo hace `ui-pdf-export` ([pdf-export.service.ts](../ui-pdf-export/src/lib/services/pdf-export.service.ts), tasas por defecto `0.16` y `0.02`). El dashboard solo pasa las tasas cuando la reserva requiere factura: `taxRate: requiresInvoice ? 0.16 : 0` y `ishRate: requiresInvoice ? 0.02 : 0` ([reservation-manager.component.ts](./src/app/features/booking/components/reservation-manager/reservation-manager.component.ts)).

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
* Son rutas hijas de `MainLayoutComponent`; actualmente se registran con imports directos en [app.routes.ts](./src/app/app.routes.ts), no mediante `loadComponent`/lazy loading.
* Acceso: todas las rutas hijas heredan `authGuard`. `personal`, `inventario` y `finanzas` además exigen `roleGuard(['ADMIN'])`. La pantalla de `personal` no tiene datos hasta migrar `users` a `v6/CRUD` (ver *Limitaciones y riesgos abiertos*).

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
| **Activos (Assets)** | 🟢 Activo | CRUD de inventario físico por habitación o bodega. |
| **Finanzas** | 🟢 Activo | Corte Z, gestión de CAPEX/OPEX y desglose fiscal automático. |
| **AI Concierge** | 🟢 Activo | Asistencia vía `ui-chat`; sin adjuntos habilitados en esta aplicación. |

---

## 📊 Roadmap: Siguientes Pasos (Eco-Hotel Phase II)

### 4. Huéspedes: Inteligencia de Cliente (CRM) ⏳ [EN PROGRESO]

* **Objetivo:** Implementación de `tags` (Senior, Nómada, Familia) y `travel_reason`.
* **Estado en código:** no se encontraron `tags` ni `travel_reason` en el código fuente inspeccionado. Verificado: `tags` y `travel_reason` no aparecen en ninguna rama local ni remota del repositorio (`git grep` sobre `refs/heads` y `refs/remotes`); solo existen en este README.

### 5. PWA Offline Mode ⏳ [PARCIAL]

* **Tecnología:** Service Workers para caché de rutas críticas como `/inventario`.
* **Estado en código:** existe [sw.js](./public/sw.js), registrado desde `src/index.html`, con caché de respuestas de navegación y de estáticos (js, css, imágenes, fuentes) y [manifest.webmanifest](./public/manifest.webmanifest). No hay caché específica de `/inventario`. Las peticiones a otro origen (el gateway) no se interceptan, así que los datos del CRUD no se guardan sin conexión.

---

## 🏢 Aislamiento por empresa (`id_company`)

* **Origen:** el contexto activo es `TenantService.activeTenantId()` (librería `core-auth`). `BookingService` lo envía como `id_company` en las altas de huéspedes y reservas ([booking.service.ts](./src/app/features/booking/services/booking.service.ts)).
* **Filtros en el cliente:** `AdminService.loadUsers()` y `loadGuests()` filtran por `id_company` ([admin.service.ts](./src/app/features/admin/services/admin.service.ts)). Las lecturas de habitaciones, reservas y tickets, y las actualizaciones por `id`, no incluyen `id_company`.
* **Validación:** el cliente no comprueba el tenant antes de enviar una petición. La validación está en el gateway `v5/CRUD`: toma la empresa del token verificado, responde `403 NO_TENANT` si falta y deniega tablas sin mapeo de tenant. Los datos del hotel pertenecen a la empresa `<COMPANY_ID>` ([README del workflow v5](../../../workflows/06-dynamic-crud-engine/v5/README.md)). Verificado en el export `v5-crud.json`: `Extract Auth Context` toma `id_company` solo del token verificado y responde `403 NO_TENANT` si falta; `Build Query` descarta el tenant que envía el cliente, lo sustituye por el del token y lanza error para tablas sin mapeo; `hotel_reviews` queda sin aislamiento por decisión pendiente (ver `TENANT_COLUMN` / `UNSCOPED_TABLES`).
* **Límite:** es aislamiento en la capa de aplicación (gateway), no en PostgreSQL. `n8n_user` es superusuario y no hay RLS.

## ⚠️ Limitaciones y riesgos abiertos

Verificado contra el código fuente el 2026-11-13.

1. **Shield parcial:** ver la tabla de cobertura en *Key Features (v0.11.0)*. `loadRooms` trata `error: true` como lista vacía sin avisar al usuario (riesgo).
2. **Colecciones vacías:** `loadRooms` no descarta filas sin `id`; un `data: [{}]` produciría una habitación sin datos (riesgo). TODO(verify) con el gateway real.
3. **Pantalla de personal sin datos:** `/dashboard/personal` existe en las rutas, pero `users` está bloqueado en `v5/CRUD` (nota de suite; TODO(verify) en el workflow). Hasta migrar a `v6/CRUD` no carga usuarios.
4. **Vista `user_mgmt` sin comprobación de rol:** `DashboardComponent` conserva `openUserManagement()` ([dashboard.component.ts](./src/app/features/dashboard/components/dashboard/dashboard.component.ts)) sin `roleGuard`. Hoy ningún elemento lo dispara: `RoomFiltersComponent` declara `onManageUsers` pero no lo emite ([room-filters.component.html](./src/app/features/dashboard/components/room-filters/room-filters.component.html)). Riesgo si se vuelve a conectar sin una comprobación de rol.
5. **Fechas en UTC:** después de las 18:00 hora de CDMX, `toISOString()` devuelve el día siguiente. Afecta la fecha de inicio por defecto del cálculo de precio ([checkin-form.component.ts](./src/app/features/booking/components/checkin-form/checkin-form.component.ts)), la fecha del checklist y `inspection_date` ([hotel.service.ts](./src/app/features/dashboard/services/hotel.service.ts)), `expense_date` ([expense-form-modal.component.ts](./src/app/features/finance/components/expense-form-modal/expense-form-modal.component.ts)) y los timestamps `check_in`/`check_out` de `BookingService` (riesgo).
6. **Fechas `YYYY-MM-DD` parseadas como UTC:** `checkAvailability` e `isRoomFree` pasan fechas de solo día a `new Date(...)` y luego usan `setHours(0,0,0,0)` local. En UTC-6 esto puede desplazar un día el límite de traslape (riesgo). TODO(verify) con datos reales.
7. **Entornos:** el `CLAUDE.md` del proyecto indica que `environment.ts` apunta a producción también en desarrollo, así que `ng serve` puede leer y escribir datos de producción. Los archivos de `src/environments/` no están en este checkout; TODO(verify).
8. **Lecturas sin tenant:** ver *Aislamiento por empresa*. Las lecturas dependen del gateway `v5/CRUD`, no del cliente.

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

**Pruebas:** las specs (`*.spec.ts`) están junto a servicios y componentes, por ejemplo [booking.service.spec.ts](./src/app/features/booking/services/booking.service.spec.ts). El script raíz `npm test` (en `hosting3m-workspace/`) ejecuta `ng test`; no verifiqué que lo limite a `dashboard`. TODO(verify).

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