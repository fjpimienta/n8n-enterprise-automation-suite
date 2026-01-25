# ⛸️ PistaHielo Operations Center

### 🛠️ High-Precision Frontend for Time-Based Operations & Dual-Stage Billing

## 📝 Descripción
**PistaHielo Dashboard** es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada para modernizar la gestión operativa de pistas de patinaje (anteriormente basada en PHP 5.2 legacy).

A diferencia de los sistemas de hospitalidad tradicionales, este dashboard implementa un Event-Driven State Machine para gestionar el "Ice Rack" (monitor de pista en tiempo real). Se especializa en procesos de dos tiempos: asignación inmediata de activos (Tiempo 1: Check-in) y liquidación financiera dinámica basada en tiempo real transcurrido (Tiempo 2: Check-out), todo orquestado por el Dynamic CRUD Engine de la suite Hosting3M.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1** | `Stable` | `Auth & Architecture` | Tabler + Bootstrap | Estructura base, JWT Auth, Ingesta de tablas ph_ legacy. |
| **v0.2** | `In Dev` | `Ice Live Monitor` | Reactive CSS Grid | Visualización de patinadores activos (ACT/ON_ICE). |
| **v0.3** | `Planned`| `Pricing Engine`| n8n Workflows | Lógica de Zamboni, descuentos de Hermanos y liquidación automática. |
| **v0.4** | `Planned` | `VIP & Membership` | Member Skeletons | Gestión de vigencias de alumnos y alertas de renovación. |

---

## 🆕 Características de la Arquitectura PistaHielo
1. 🕒 Dual-Time Operation Pattern
    * Check-in (Fast Path): Registro instantáneo de entrada para minimizar colas en taquilla.
    * Check-out (Billing Path): Cálculo automático de excedentes, tolerancia de 10 minutos y ajustes por mantenimiento de hielo (Zamboni).

2. ⛸️ Ice Live Monitor (The Rack)
    * Interfaz reactiva mediante Angular Signals que muestra el estado de cada par de patines en uso, tiempo transcurrido y alertas de tiempo agotado.

3. 💰 Intelligent Pricing Engine
    *Delegación de la lógica de costos a Workflows de n8n, eliminando el cálculo manual de promociones (2x1, paquetes de 3/6 meses, descuentos por hermanos).

4. 📊 Financial Closures (Corte X/Y)
    * Automatización de cierres de turno y cierres de día con trazabilidad completa de pagos en Efectivo vs. Tarjeta.

---

## 🏗️ Arquitectura Técnica
> 🚀 **Estrategia de Migración:** Esta aplicación consume los esquemas normalizados de PostgreSQL (*ph_clients, ph_transactions, ph_payments*) eliminando la dependencia de archivos PHP procedimentales.
<p align="center">
  <a href="./ARCHITECTURE.md">
    <img src="https://img.shields.io/badge/🏛️_Leer_Guía_de_Arquitectura-206bc4?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Architecture Guide">
  </a>
</p>

La solución utiliza un patrón Smart Services / Dumb Components:

    1. IceTimer Service: Un servicio especializado basado en interval para actualizar cronómetros visuales sin sobrecargar la base de datos.

    2. Transaction Hook: n8n procesa cada cierre de renta, actualiza el inventario de patines y genera el registro en ph_payments de forma atómica.

---

## 🚦 Stack Tecnológico
* **Core:** Angular v21.0.0 (Signals, Standalone Components, Signal Queries).
* **UI Framework:** @tabler/core (Diseño administrativo responsive) + Bootstrap 5 (Dashboard Administrativo).
* **Orquestador:** n8n v2.3.6 (Enterprise Edition).
* **Base de Datos:** PostgreSQL + pgvector (Soberanía de datos y memoria RAG).
* **Seguridad:** JWT (Microservicio Node.js) con roles de Supervisor/Cajero.

---

### 🏗️ Arquitectura de la Solución
La aplicación implementa una arquitectura desacoplada donde el frontend delega la persistencia al orquestador n8n:
1. **Capa de Seguridad:** Implementación de `auth.guard.ts` y `auth.interceptor.ts` para comunicación segura vía JWT con el Módulo 01 (Auth Gateway).
2. **Gestión de Estado:** Uso de Angular Signals para un manejo reactivo y eficiente del estado del usuario y la UI.
3. **Consumo de API:** Comunicación dinámica con el endpoint `/crud/v2/:model` para operaciones atómicas.
4. **Validación:** Middleware de verificación cruzada entre el rol del usuario (`x-jwt-claim-role`) y permisos del backend.
5. **Logging:** `Logger.service.ts` integrado para depuración en modo desarrollo sin ensuciar la consola de producción.

---

## 🚀 Capacidades de PistaHielo Dashboard
- **Monitoreo en Tiempo Real:** Quién está en el hielo, con qué patín y cuánto tiempo le queda.
- **Gestión de Alumnos VIP:** Seguimiento de mensualidades con cálculo de vigencia automático.
- **Ajuste de Zamboni:** Botón global para pausar/ajustar tiempos de todos los patinadores activos durante el mantenimiento.
- **POS Integrado:** Venta de artículos (calcetas, dulces) y servicios (clases particulares) en la misma transacción.

---

## 📊 Roadmap: Gestión de Hotel (17 Habitaciones)

| Módulo | Estado | Descripción | Integración n8n |
| :--- | :--- | :--- | :--- |
| Check-in Form | ⏳ En Progreso | Registro de entrada de clientes y alumnos. | Webhook Entry Processor. |
| Ice Rack UI | ⏳ En Progreso | Grid visual con cronómetros activos. | PostgreSQL Sync. |
| Checkout Engine | 📅 Pendiente | Cálculo de costos y cierre de renta. | Workflow 10 (Pricing Engine). |
| Cortes X / Y | 📅 Pendiente | Reporte de caja por turno y cierre diario. | MetaCRUD Aggregation. |
| WhatsApp Alerts | 🚀 Futuro | Notificaciones de vencimiento a padres de familia. | Módulo 05 (AI Agent). |

---

## 🛠️ Comandos de Desarrollo

1. **Requisitos**
    * Node.js (v20+)
    * Angular CLI v21.0.5

2. **Instalación y Servidor Local**
    ```bash
    # Instalar dependencias
    npm install

    # Iniciar servidor de desarrollo
    ng serve
    ```

3. **Pruebas y Construcción**
    ```bash
    # Ejecutar Unit Tests con Vitest
    ng test

    # Compilación para Producción (Plesk Ready)
    ng build --configuration=production
    ```

---

## 📦 Integración con n8n Enterprise Suite
Este app es el componente `app/pistahielo` dentro del ecosistema n8n Enterprise Suite. Se comunica directamente con los siguientes servicios:

* **JWT Service:** Para validación de tokens RS256.
* **PostgreSQL + pgvector:** Almacenamiento de metadatos de habitaciones y búsqueda semántica.
* **WhatsApp Bridge:** Webhook dedicado para alertas inmediatas de limpieza o fallas técnicas reportadas desde el dashboard.

---

## 📄 Licencia
Este proyecto está bajo la licencia **n8n Sustainable Use License**. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

**Desarrollado por:** Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computacionales y Maestro en Administración de Proyectos.