# Changelog

Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [0.11.0] - 2026-03-25

### 🛡️ Seguridad & Arquitectura (Boundary Resilience)

* **MetaCRUD Silent Error Shield:** Implementación de un escudo de validación estricta en `BookingService`. El sistema ahora intercepta respuestas `HTTP 200 OK` de n8n que contienen la bandera interna `error: true`. Las violaciones de base de datos (ej. `idx_prevent_double_checkin_global`) se capturan y lanzan como excepciones reales hacia la UI, evitando que la interfaz y la base de datos se desincronicen.
* **Payload Sanitization:** Limpieza profunda de los paquetes de datos (`INSERT` y `UPDATE`) enviados a PostgreSQL para evitar colisiones de esquemas y errores 500 (CORS bloqueados). El ID de actualización fue movido a la raíz de la petición REST.
* **Signal Binding Fix:** Resolución de errores de inyección de Signals en el DOM (`activeBooking()`), garantizando la transmisión de datos primitivos a los modales hijos.

### 💰 Motor Financiero & Flujos (Business Logic)

* **Soft-Booking vs Hard-Booking:** Arquitectura dual de reservas. El sistema ahora permite registrar "Cotizaciones" (`pending`) que bloquean el inventario sin exigir pago, y evolucionan automáticamente a "Reservas Confirmadas" (`confirmed`) al detectar un abono.
* **Pagos en Cascada (Bulk Waterfall Payments):** Nuevo botón de "Abono Grupal" en el Gestor de Reservas. Permite seleccionar múltiples habitaciones de un cliente (ej. empresas) y distribuir un pago único matemáticamente entre todas las estancias seleccionadas.
* **Extensiones de Estancia Activas:** Los huéspedes con estatus `checked_in` ahora son editables. Al extender los días, el motor financiero recalcula el nuevo `total_amount` vs `amount_paid` y degrada dinámicamente la cuenta de `paid` a `partial` para activar el cobro.
* **Impuestos Dinámicos:** Los PDFs de exportación ahora evalúan el estado de la reserva y la bandera `is_invoiced` para titular el documento de forma inteligente ("PRESUPUESTO DE HOSPEDAJE" vs "COMPROBANTE DE RESERVA").

### 🕒 UX & Timezone Integrity

* **Timezone Offset Shield:** Reemplazo de funciones `toISOString()` por evaluadores de tiempo local (`getFullYear`, `getMonth`). Se erradicó el bug que causaba que el sistema "saltara" al día siguiente después de las 18:00 hrs (UTC-6 CDMX/Mérida).
* **Walk-in Decoupling:** Modificación en `room-detail-modal` para independizar el flujo de *Walk-ins* de las reservas futuras. Si una habitación tiene una reserva para dentro de 3 días, el sistema ahora permite ingresar a un huésped de "Descanso" hoy mismo sin sobrescribir el ID de la reserva futura.
* **Dark Mode UI Fix:** Limpieza de clases estáticas (`bg-light`) en formularios financieros que rompían la jerarquía visual del modo oscuro.

## [0.10.0] - 2026-02-19

### 📄 Documentación Digital & Exportación

* **Motor de Renderizado:** Creación de `projects/ui-pdf-export`, librería agnóstica basada en `jspdf-autotable`.
* **Motor Financiero:** Desglose automático de Base Imponible, IVA (16%) e ISH (2%).
* **Agrupación Inteligente:** Algoritmo que detecta habitaciones del mismo tipo para resumirlas en una partida.

## [0.9.0] - 2026-02-18

### 🚀 Eco-Hotel Optimization (Phase II)

* **Rutas Hijas (Child Routes):** Implementación de arquitectura distribuida para `/mantenimiento`, `/finanzas`, `/inventario`.
* **Estrategia de Carga Asíncrona:** Priorización del Hilo Principal (`Room Rack`) sobre datos secundarios difiriendo la carga.

## [0.8.0] - 2026-02-14

### 🚀 Eco-Hotel Transformation (Phase I)

* **Finanzas & CAPEX:** Separación de OPEX y CAPEX mediante `project_phase`.
* **Mantenimiento (Tickets):** Sistema de incidencias con automatización de estados físicos de cuarto.
* **Gestión de Activos:** Auditoría de equipos físicos en recámaras (TVs, AC).

## [0.7.0] - 2026-02-09
* **AI Concierge Module:** Integración de Asistente Virtual y protocolo MCP con PostgreSQL.

## [0.6.0] - 2026-01-27
* **Finance Module:** Lógica de Check-in con descuentos, y rediseño Mobile-First (Fat-Finger).

## [0.5.0] - 2026-01-13
* **Hotel Core:** MCP Server, Auth Gateway v2.

## [0.3.0] - 2025-12-20
* Lanzamiento Inicial.

## 📦 Authors
**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite