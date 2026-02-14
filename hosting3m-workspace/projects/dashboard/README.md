# 🏨 AdminHotel Dashboard

### 🛠️ Integrated Frontend for Dynamic CRUD Engine

![Angular](https://img.shields.io/badge/Angular-21-red) ![Architecture](https://img.shields.io/badge/Architecture-Feature--Based-blue) ![Library](https://img.shields.io/badge/Shared-UI%20Chat-orange) ![Status](https://img.shields.io/badge/Transformation-Eco--Hotel-green)

## 📝 Descripción
**AdminHotel** es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M.

Este dashboard actúa como el cliente principal del **Dynamic CRUD Engine**, permitiendo una gestión de datos en tiempo real. Actualmente, el proyecto atraviesa una **Transformación Estratégica (Eco-Hotel Phase)**, evolucionando de un simple gestor de reservas a un **ERP Hotelero Completo** que gestiona Mantenimiento, Activos Fijos y Finanzas de Inversión (CAPEX).

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
| **v0.6.1** | `Stable` | `Quality Assurance` | **JSONB / Forms** | **Módulo de Rondines, Persistencia Híbrida, Smart Save.** |
| **v0.7.0** | `Released` | **AI Concierge** | **Shared Lib / MCP** | **Integración de `ui-chat`, Arquitectura Standalone, Inyección de Tokens.** |
| **v0.7.1** | `Released` | **AI Concierge** | **Shared Lib / MCP** | **Integración de `ui-chat`, Inyección de Tokens.** |
| **v0.8.0** | `Released` | **Eco-Transformation I** | **Tickets / Assets** | **Gestión de Mantenimiento, Inventario de Activos y Finanzas CAPEX/OPEX.** |
| **v0.9.0** | `Planned` | `Eco-Intelligence` | CRM / IoT | Segmentación de Huéspedes y Métricas de Sustentabilidad (Luz/Agua). |

---

## ♻️ Eco-Hotel Transformation (Strategic Pillars)

El sistema ha implementado 3 de los 5 pilares estratégicos para la certificación y operación "Eco-Boutique".

### 1. 💰 Finanzas: Estrategia de Inversión (CAPEX vs OPEX) ✅
**Objetivo:** Separar el dinero de la operación diaria del dinero de la remodelación/construcción.
* **Tech Stack:** Base de datos actualizada con `expense_type` y `project_phase`.
* **UI:** Modal de Gastos (`ExpenseFormModal`) con selectores de Fases (Fase 0 a 3).
* **Business Value:** Claridad total sobre el costo operativo vs. costo de inversión.

### 2. 🛠️ Mantenimiento: Gestión de Incidencias ✅
**Objetivo:** Convertir quejas en acciones y crear una base de conocimiento técnica.
* **Center Command:** Nuevo **Monitor de Mantenimiento** accesible desde el Header y Room Cards.
* **Ticket Lifecycle:** Automatización de estados (`Reportar` → `Maintenance` | `Resolver` → `Dirty`).
* **Knowledge Base:** Bitácora de soluciones obligatoria al cerrar un ticket en `hotel_maintenance_tickets`.

### 3. 📺 Activos: Inventario Físico (Asset Management) ✅
**Objetivo:** Controlar la ubicación, depreciación y garantía de equipos valiosos.
* **Digital Twin:** Nueva tabla `hotel_assets` vinculada a las habitaciones.
* **Integration:** Pestaña "Inventario" integrada directamente en el `RoomDetailModal`.
* **Sync:** Formulario de Alta (`AssetFormModal`) con validación estricta contra el backend.

---

## 🆕 Novedades Tecnológicas (v0.7.1 & v0.8.0)

1. **Protocolo MCP (Model Context Protocol):**
    * Arquitectura Cliente-Servidor para IA. El **Servidor MCP** expone la base de datos PostgreSQL como herramientas seguras para el Chatbot.

2. **Arquitectura Modular (Shared Libraries):**
    * Migración del módulo `ai-assistant` a la librería corporativa `@hosting3m/ui-chat`.
    * Uso de **Injection Tokens** (`CHAT_CONFIG_TOKEN`) para configuración dinámica por entorno.

3. **Hybrid Persistence (SQL + JSONB):**
    * Uso de columnas JSONB para datos flexibles en los módulos de **Calidad** (Checklists) y **Mantenimiento** (Detalles técnicos), evitando migraciones constantes de esquema.

---

## 🏗️ Arquitectura Técnica
> 🚀 **Deep Dive:** Consulta el diagrama completo de flujo y decisiones de diseño en:
<p align="center">
  <a href="./ARCHITECTURE.md">
    <img src="https://img.shields.io/badge/🏛️_Leer_Guía_de_Arquitectura-206bc4?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Architecture Guide">
  </a>
</p>

La aplicación implementa una arquitectura **Data-Access Service Pattern** y **Standalone Components**:

### 🛠️ Stack Tecnológico
* **Core:** Angular v21.0.0 (Signals, Standalone Components).
* **Shared Libraries:** `@hosting3m/ui-chat` (AI Integration).
* **Backend Interface:** Webhooks n8n (API v3) + PostgreSQL (JSONB Support).
* **State Management:** Angular Signals (Sin NgRx).

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

## 📊 Roadmap: Lo que FALTA (Eco-Hotel Phase II)

Los siguientes puntos son críticos para completar la visión estratégica:

### 4. Huéspedes: Inteligencia de Cliente (CRM) ⏳ [PENDIENTE]
* **Objetivo:** Validar el concepto "Eco-Boutique" conociendo al cliente.
* **Tarea Técnica:** Implementación de `tags` (Senior, Nómada, Familia) y `travel_reason` en el perfil del huésped.
* **UX:** Visualización de "Trato Personalizado" durante el Check-in.

### 5. Sustentabilidad: Métricas "Eco" ⏳ [PENDIENTE]
* **Objetivo:** "Lo que no se mide, no se mejora".
* **Tarea Técnica:** Nueva tabla `utility_readings` para lecturas de CFE (Luz) y Agua.
* **Analytics:** Calculadora de huella de carbono mensual y comparativos de consumo.

---

## 🛠️ Comandos de Desarrollo

1. **Requisitos**
    * Node.js (v20+)
    * Angular CLI v21.0.5

2. **Instalación y Servidor Local**
    ```bash
    # Instalar dependencias del workspace
    npm install

    # Construir la librería de chat (Requisito previo)
    ng build ui-chat

    # Iniciar servidor Dashboard
    ng serve dashboard
    ```

3. **Pruebas y Construcción**
    ```bash
    # Compilación para Producción (Plesk Ready)
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