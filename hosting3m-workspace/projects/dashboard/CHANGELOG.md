# Changelog

Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [0.10.0] - 2026-02-19

### 📄 Documentación Digital & Exportación

Integración del módulo de generación de documentos PDF para la formalización de reservas y cotizaciones, impulsado por la nueva librería corporativa `ui-pdf-export`.

#### 📚 Nueva Librería: UI PDF Export

* **Motor de Renderizado:** Creación de `projects/ui-pdf-export`, una librería agnóstica basada en `jspdf-autotable` para generar documentos vectoriales directamente en el navegador (Client-Side generation).
* **Motor Financiero:** Lógica interna encapsulada para el desglose automático de impuestos mexicanos:
    * **Base Imponible**
    * **IVA (16%)**
    * **ISH (2%)**
* **Diseño Corporativo:** Plantillas estandarizadas con encabezados dinámicos, datos fiscales y alineación contable precisa (columnas numéricas a la derecha).

#### 🏨 Gestión de Reservas (Booking)

* **Impresión de Cotizaciones:** Nueva funcionalidad en `ReservationManager` para generar PDFs de "Presupuesto de Hospedaje" personalizados para clientes corporativos (ej. PCP Construcciones).
* **Selección Múltiple:** Implementación de casillas de verificación (checkboxes) y "Select All" en la tabla de reservas para agrupar múltiples estancias en un solo documento.
* **Agrupación Inteligente:** Algoritmo que detecta habitaciones del mismo tipo, precio y duración para resumirlas en una sola línea del reporte (ej. "3x Habitación Doble - 7 Noches").

#### 🔧 Arquitectura (Monorepo)

* **Path Mapping Refactor:** Reingeniería de los archivos `tsconfig` (Root y Dashboard) para soportar correctamente la compilación AOT y los imports de librerías locales (`ui-chat`, `ui-pdf-export`) en entorno de desarrollo y producción.
* **Strict Typing:** Adopción de interfaces `PdfExportConfig` para garantizar la integridad de los datos financieros antes de la exportación.

## [0.9.0] - 2026-02-18

### 🚀 Eco-Hotel Optimization (Phase II)

Transición de una arquitectura monolítica (basada en modales) a una arquitectura distribuida (basada en páginas), junto con optimizaciones críticas de rendimiento y experiencia de usuario.

#### 🏗️ Arquitectura de Navegación (Routing)

* **Rutas Hijas (Child Routes):** Implementación de una arquitectura de enrutamiento anidado para desacoplar módulos del `DashboardComponent`.
    * `/dashboard/mantenimiento`: Monitor de tickets a pantalla completa.
    * `/dashboard/finanzas`: Reportes financieros y caja.
    * `/dashboard/huespedes` y `/dashboard/personal`: Gestión administrativa dedicada.
    * `/dashboard/inventario`: Nuevo módulo centralizado.
* **Impacto:** Mejor separación de responsabilidades (*Separation of Concerns*), URLs compartibles y reducción significativa del tamaño del DOM inicial.

#### ⚡ Optimización de Rendimiento (Performance)

* **Estrategia de Carga Asíncrona:** Priorización de la carga de `loadRooms` en el hilo principal del `DashboardComponent`. La carga de datos secundarios (Reservas, Usuarios) se difirió (*deferred loading*), mejorando el *Time to Interactive (TTI)*.
* **Skeletons Optimizados:**
    * Reducción de nodos DOM de 8 a 4 elementos.
    * Aceleración de animación CSS (`fadeIn`) de 0.3s a 0.1s.
    * Adaptación visual al *Dark Mode* para evitar el "flashbang".

#### 🧠 Gestión de Estado (Business Logic)

* **Servicios Reactivos (Signals):** Extracción de lógica compleja hacia servicios inyectables.
    * **ReportService:** Centraliza cálculos financieros (balances, filtrado por fechas, sumatorias), dejando a `DailyReportModal` como componente puramente presentacional.
    * **AssetService:** Maneja operaciones CRUD universales para inventario global y local.
* **Computed Signals:** Recálculo automático de KPIs (Totales, Alertas, Saldos) ante cambios en los datos crudos.

#### 📦 Sistema de Inventario Centralizado

* **Componente Polimórfico:** Refactorización de `AssetFormModal` para operar en dos contextos:
    * **Global:** Gestión de activos en bodega.
    * **Local:** Asignación directa desde el detalle de habitación.
* **Trazabilidad:** Filtrado avanzado por estado (`GOOD`, `DAMAGED`, `MISSING`) y ubicación.

#### 🎨 UX & Theming

* **Dark Mode Nativo:** Reemplazo de estilos *hardcoded* por Variables CSS (`var(--tblr-body-bg)`), permitiendo cambio de tema instantáneo.
* **Layout Limpio:** Eliminación de *headers* redundantes para ganar espacio vertical en móviles.
* **Smart Sidebar:** Auto-cierre del menú lateral en dispositivos móviles al navegar.

## [0.8.0] - 2026-02-14

### 🚀 Eco-Hotel Transformation (Phase I)

Implementación de los módulos estratégicos para la gestión de activos y mantenimiento, elevando el sistema a un **ERP Hotelero**.

#### 💰 Finanzas & CAPEX

* **Estrategia de Inversión:** Separación lógica de gastos operativos (`OPEX`) vs inversión en remodelación (`CAPEX`).
* **Fases de Proyecto:** Nueva columna `project_phase` en base de datos y selector en `ExpenseFormModal` (Fase 0 a 3) para auditar el costo de la transformación.

#### 🛠️ Mantenimiento (Tickets)

* **Sistema de Incidencias:** Nueva tabla `hotel_maintenance_tickets` para convertir quejas en tickets de soporte.
* **Monitor de Mantenimiento:** Dashboard centralizado para visualizar tickets abiertos, en progreso y resueltos.
* **Automatización de Estados:** Lógica de negocio que cambia el estado de la habitación automáticamente (`Reportar` → `Maintenance` | `Resolver` → `Dirty`).
* **Bitácora de Soluciones:** Campo obligatorio para registrar la solución técnica aplicada antes de cerrar un ticket.

#### 📺 Gestión de Activos (Assets)

* **Inventario Digital:** Nueva tabla `hotel_assets` para el control de equipos valiosos (TVs, Aires Acondicionados) por habitación.
* **Integración UI:** Pestaña "Inventario" agregada al `RoomDetailModal` para auditoría rápida durante el check-out.
* **Validación de Garantías:** Registro de fecha de compra y proveedor para alertas de garantía.

## [0.7.1] - 2026-02-14

### ♻️ Refactorización (Architecture)

* **Shared Library Migration:** Desacoplamiento total del módulo de chat. El Dashboard ahora consume la librería corporativa `@hosting3m/ui-chat` en lugar de mantener una copia local.
    * **Impacto:** Centralización de la lógica de UI/UX del asistente para compartir mejoras automáticamente con *Pista Hielo*.
    * **Deuda Técnica:** Eliminación del directorio `features/ai-assistant`.
* **Dependency Injection Pattern:** Adopción de `CHAT_CONFIG_TOKEN` en `app.config.ts`. La URL del Webhook de Hotel ahora se inyecta dinámicamente.

### 🔧 Configuración

* **Standalone Providers:** Actualización del registro en `app.config.ts` para instanciar `AiService` explícitamente.

## [0.7.0] - 2026-02-09

### 🚀 Añadido (New Features)

* **AI Concierge Module (v1):** Implementación de un Asistente Virtual Inteligente capaz de gestionar operaciones hoteleras mediante lenguaje natural.
* **Architecture MCP (Model Context Protocol):** Desacoplamiento total entre el LLM y la base de datos.
    * **MCP Server:** Microservicio en n8n que expone herramientas seguras (`Query Available`, `Query Reservation`) conectadas a PostgreSQL.
* **Strict Business Logic:** El "System Prompt" del agente impone reglas de integridad referencial.
* **Context Awareness:** Memoria a corto plazo (`Memory Buffer Window`).

### 🔄 Cambiado (Improvements)

* **Security Hardening:** El Agente de IA genera y utiliza sus propios tokens de autorización (`Genera Token` sub-workflow).
* **Error Handling:** Protocolo "Zero-Hallucination" implementado en el prompt.

### 🔧 Tech Stack Update

* **LLM Engine:** Integración de `gpt-4o-mini`.

## [0.6.1] - 2026-02-03

### 🚀 Añadido (New Features)

* **Quality Assurance Module (Rondines):** Sistema integral para la inspección diaria de habitaciones.
    * **Checklist Dinámico:** Formulario persistido como JSONB.
    * **Smart Save Logic:** Detección automática de `INSERT` vs `UPDATE`.
* **Hybrid Persistence:** Implementación de tablas mixtas (SQL + JSONB) en PostgreSQL.

### 🔄 Cambiado (Improvements)

* **n8n Integration Protocol:** Estandarización del payload de Angular (propiedad `fields`).
* **DevOps:** Configuración de Proxy Reverso para CORS.

## [0.6.0] - 2026-01-27

### 🚀 Añadido (New Features)

* **Finance Module (Hotel):** Lógica financiera avanzada integrada en el flujo de Check-in.
    * **Descuentos Dinámicos** y **Auditoría Financiera**.
* **Mobile Accessibility (Senior-First):** Rediseño total de la interfaz Dashboard para facilitar el uso táctil.
    * **Grid Navigation** y **Fat-Finger Design**.

### 🔄 Cambiado (Improvements)

* **Room Rack UI:** Diseño de "Semáforo Visual" (Verde/Rojo/Naranja).

## [0.5.0] - 2026-01-13

### 🚀 Añadido (New Features)

* **Hotel Management Core:** Implementación completa del ecosistema hotelero.
    * **MCP Server** y **Dashboard SPA**.
* **Auth Gateway v2:** Microservicio centralizado para JWT.
* **News Intelligence v2:** Generación de imágenes con IA.

## [0.4.0] - 2026-01-03

### 🚀 Añadido

* **Arquitectura Modular:** Sub-workflows reutilizables.
* **Sistema de Versionado:** Semantic Versioning.

## [0.3.0] - 2025-12-20

### 🎉 Lanzamiento Inicial

* Despliegue de infraestructura base, PostgreSQL + pgvector y Core Workflows iniciales.

---

*Este changelog es mantenido automáticamente por el equipo de arquitectura.*