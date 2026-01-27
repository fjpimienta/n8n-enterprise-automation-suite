# Changelog
Todos los cambios notables en el módulo **PistaHielo Operations Center** (Módulo 09 de la Suite Hosting3M) serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.5.0] - 2026-01-27
### Added
- **MainLayout Shell:** Implementación de una arquitectura de "Cascarón" (`MainLayoutComponent`) que contiene el menú lateral y el header.
- **Mobile Experience:** Nuevo Header exclusivo para móviles con botón "Hamburguesa" y lógica de menú Off-Canvas.
- **Navigation UX:** Implementación de "Click-to-Close" en el menú móvil para mejorar la fluidez al navegar entre módulos.
- **Client Directory (WIP):** Creación inicial de `ClientListComponent` y `ClientService` para la gestión futura de alumnos.

### Changed
- **Routing:** Reestructuración total de `app.routes.ts`. Ahora `Operations` y `Admin` son rutas hijas del `MainLayout`.
- **Docs:** Actualización mayor de `README.md` y `ARCHITECTURE.md` reflejando el estado Beta Operativo.

### Fixed
- **SSR Crash:** Solución crítica al error `Injector has already been destroyed` mediante la inyección de `PLATFORM_ID` y `isPlatformBrowser` en los intervalos de polling (`setInterval`).
- **UI Bugs:** Corrección de estilos en el botón de cierre del menú móvil (alineación Flexbox).

---

## [v0.4.0] - 2026-01-26
### Added
- **Shift Report (Corte Z):** Nuevo componente `ShiftReportComponent` para visualizar el balance financiero del día.
- **Cash Register Service:** Lógica para sumarizar totales en tiempo real (Efectivo vs. Tarjeta).
- **Print Support:** Botón nativo para imprimir el reporte de corte.

### Fixed
- **Timezone Bug:** Corrección del error donde el reporte mostraba $0.00. Se implementó el envío de fechas en formato ISO local (`sv-SE`) para forzar la comparación correcta (`::date`) en PostgreSQL/n8n.
- **Build Budget:** Ajuste en `angular.json` aumentando los límites de advertencia (2MB) y error (4MB) para soportar librerías UI.

### Changed
- **Model:** Actualización de la interfaz `PhTransaction` incluyendo campos opcionales `amount`, `end_time` y `payment_method`.

---

## [v0.3.0] - 2026-01-25
### Added
- **Checkout Engine:** Implementación del `CheckoutModalComponent`.
- **Pricing Logic:** Cálculo automático de tiempo transcurrido (Minutos).
- **Zamboni Rule:** Checkbox lógico que resta 15 minutos al tiempo total por mantenimiento de pista.
- **Payment Method:** Selector para registrar si el pago fue en Efectivo o Tarjeta.

### Security
- **DB Permissions:** Actualización de la tabla `crud_models` en PostgreSQL para permitir operaciones `UPDATE` en la tabla `ph_transactions`.

---

## [v0.2.0] - 2026-01-24
### Added
- **Live Monitor (The Rack):** Componente `IceMonitorComponent` visualizando tarjetas de patines activos.
- **Real-time Polling:** Implementación de actualización automática cada 30 segundos.
- **Visual Feedback:** Indicadores de estado (Color Verde para activos) y Skeleton Loaders durante la carga de datos.
- **IceTimerService:** Servicio dedicado al manejo de contadores de tiempo en el frontend.

### Changed
- **Data Source:** Migración de "Mock Data" a consumo real del endpoint `/crud/v3/transactions` vía n8n.

---

## [v0.1.0] - 2026-01-22
### Added
- **Project Scaffold:** Inicialización del proyecto Angular 21 con Standalone Components.
- **Auth Core:** Implementación de `AuthGuard` y `JwtInterceptor` conectados al Gateway de Seguridad (Módulo 01).
- **Entry Form:** Componente `EntryFormComponent` con interfaz "Touch-First" para el registro rápido de patines.
- **UI Framework:** Integración de Tabler.io y Bootstrap para estilos base.

### Security
- **Initial Setup:** Configuración de CORS y validación de tokens RS256.