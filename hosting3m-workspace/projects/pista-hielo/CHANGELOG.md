# Changelog
Todos los cambios notables en el módulo **PistaHielo Operations Center** (Módulo 09 de la Suite Hosting3M) serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), y este proyecto adhiere a [Semantic Versioning](https://spec.org/spec/v2.0.0.html).

## [0.7.1] - 2026-02-14
### ♻️ Refactorización (Architecture)
- **Shared Library Migration:** Integración oficial de la librería corporativa `@hosting3m/ui-chat`. Se eliminó la dependencia de componentes de chat locales para utilizar el estándar del workspace.
- **Dependency Injection Pattern:** Implementación de `CHAT_CONFIG_TOKEN` en `app.config.ts`. Ahora la configuración del asistente (colores, logo de la pista y webhook de n8n) se inyecta dinámicamente, desacoplando la lógica de la UI.
- **Standalone Provisioning:** Refactorización de `app.config.ts` para proveer `AiService` de forma explícita, cumpliendo con las mejores prácticas de Angular 21 para librerías stateless.

### 🐛 Fixed
- **NullInjectorError:** Corrección del error de proveedor faltante para `AiService` tras la migración a la arquitectura de librería compartida.
- **Selector Mismatch:** Actualización de etiquetas en el template de `MainLayout` para coincidir con el nuevo selector de librería `lib-ai-chat`.

## [0.7.0] - 2026-02-09
### 🚀 Added
- **AI Agent Integration (v3):** Despliegue del Asistente Virtual Operativo con personalidad de Pista de Hielo (especializado en rentas y tiempos).
- **MCP Server Pista:** Implementación de herramientas de servidor para que la IA consulte el Rack en vivo, reporte ventas y verifique disponibilidad de patines.
- **JOIN Logic en IA:** Las consultas de "Pista Activa" ahora devuelven nombres de clientes reales en lugar de solo IDs.
- **METACRUD Validation:** El asistente valida campos obligatorios (`full_name`, `phone`, `email`, `doc_id`) antes de registrar nuevos ingresos.

### 🔧 Fixed
- **Time Calculation Precision:** Se migró el cálculo de minutos en el MCP de `start_time` (string) a `created_at` (timestamp) para evitar errores de redondeo.
- **Zamboni AI Rule:** El asistente ahora reconoce comandos de "Zamboni" y ajusta el cálculo de tiempo para el cobro final.

### 🔄 Changed
- **System Instructions:** Refactorización total del prompt del sistema para enfocarse en rentas por hora, clases e instructores.

---

## [0.6.0] - 2026-02-03
### 🔧 Fixed
- **Checkout "Midnight Bug":** Corrección crítica en la lógica de cálculo de tiempo para turnos que cruzan la medianoche.
- **n8n Reporting:** Corrección de variable en el nodo "Build Query" que impedía el filtrado de reportes financieros.
- **Icon Crash:** Migración a una estrategia de `Global Providers` en `app.config.ts` para evitar errores de carga de iconos.
- **Layout Overflow:** Eliminación de scroll horizontal en el sidebar.

### 🔄 Changed
- **Checkout Engine:** Refactorización completa a **Angular Signals**. Recálculo automático de tiempo sin depender de ciclos de vida manuales.
- **UI/UX:** Implementación de **Sidebar Colapsable** (Mini Mode) con animaciones.
- **Dark Mode:** Mejoras de legibilidad en inputs y dropdowns.

---

## [0.5.0] - 2026-01-27
### 🚀 Added
- **MainLayout Shell:** Implementación de arquitectura de "Cascarón" con `MainLayoutComponent`.
- **Mobile Experience:** Header exclusivo para móviles con menú Off-Canvas.
- **Navigation UX:** Lógica "Click-to-Close" en menú móvil.
- **Client Directory (WIP):** Inicio del módulo de gestión de alumnos.

### 🔄 Changed
- **Routing:** Reestructuración de rutas hijas bajo el `MainLayout`.
- **Docs:** Actualización de `README.md` y `ARCHITECTURE.md` al estado Beta Operativo.

### 🔧 Fixed
- **SSR Crash:** Solución al error de destrucción del inyector mediante validación de `isPlatformBrowser`.
- **UI Bugs:** Ajuste de alineación flexbox en botones móviles.

---

## [0.4.0] - 2026-01-26
### 🚀 Added
- **Shift Report (Corte Z):** Nuevo componente financiero para cierre de caja diario.
- **Cash Register Service:** Sumarización en tiempo real (Efectivo vs. Tarjeta).
- **Print Support:** Funcionalidad de impresión para reportes de corte.

### 🔧 Fixed
- **Timezone Bug:** Implementación de envío de fechas en formato ISO local para asegurar consistencia en PostgreSQL.
- **Build Budget:** Incremento de límites de presupuesto en `angular.json` para assets de UI.

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