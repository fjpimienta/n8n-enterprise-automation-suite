# 🏨 AdminHotel Dashboard

### 🛠️ Integrated Frontend for Dynamic CRUD Engine

## 📝 Descripción
**AdminHotel** es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M.

Este dashboard actúa como el cliente principal del **Dynamic CRUD Engine**, permitiendo una gestión de datos en tiempo real (Reservas, Habitaciones, Check-ins, Calidad) mediante una capa de abstracción basada en n8n y PostgreSQL. Se especializa en la gestión operativa de flujos de hospitalidad mediante el uso intensivo de Angular Signals y una arquitectura de servicios desacoplados.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1.0** | `Stable` | `Auth & Architecture` | Tabler + Bootstrap | Estructura base, JWT Auth, Signals. |
| **v0.2.0** | `Stable` | `Room Rack v1` | CSS Grid / Cards | Gestión visual de 17 habitaciones. |
| **v0.3.0** | `Stable`| `Ops & Finance`| Modals / Reports | Checkout con inventario, Reporte de Caja (D/S/M/Y) y Gestión de Usuarios. |
| **v0.4.0** | `Stable` | `Pro UX & Patterns` | Skeletons / Services | Refactorización a Services, Skeletons de carga, Promesas (Async/Await).|
| **v0.5.0** | `Stable` | `Full Operation` | Interactive UI | Refresh Engine, Reservas dinámicas, Gestión avanzada de Huéspedes. |
| **v0.6.0** | `Stable` | `Accessibility` | Mobile Grid / CSS | Lógica de Descuentos, UX Accesible para Seniors (Fat-Finger Design). |
| **v0.6.1** | `Stable` | `Quality Assurance` | **JSONB / Forms** | **Módulo de Rondines, Persistencia Híbrida, Smart Save.** |
| **v0.7.0** | `Released` | **AI Concierge** | **MCP / Chat UI** | **Arquitectura Cliente-Servidor MCP, Agente gpt-4o-mini, Reglas de Negocio en Prompt.** |
| **v0.8.0** | `Planned` | `Analytics` | Dashboard KPIs | Gráficos de ocupación y proyecciones financieras. |

---

## 🆕 Novedades de la v0.7.0 (AI Revolution)

1. **Protocolo MCP (Model Context Protocol):**
    * Implementación pionera de una arquitectura Cliente-Servidor para IA dentro de n8n.
    * El **Servidor MCP** expone la base de datos PostgreSQL como herramientas seguras.
    * El **Cliente IA** razona sobre cuándo usar esas herramientas.

2. **Asistente Virtual "San José":**
    * Capacidad para consultar disponibilidad en tiempo real ("¿Qué habitaciones matrimoniales tienes libres y limpias?").
    * Gestión de reservas con validación estricta de datos (No permite reservar sin teléfono o email).
    * Acceso a la memoria histórica de mantenimiento ("¿Qué reparaciones se hicieron en la habitación 5 la semana pasada?").

3. **Seguridad Cognitiva:**
    * El agente posee credenciales de ADMIN inyectadas dinámicamente para realizar operaciones de escritura, pero está restringido por un "System Prompt" que prohíbe alucinaciones sobre transacciones fallidas.

---

## 🏗️ Arquitectura Técnica
> 🚀 **Deep Dive:** Consulta el diagrama completo de flujo y decisiones de diseño en:
<p align="center">
  <a href="./ARCHITECTURE.md">
    <img src="https://img.shields.io/badge/🏛️_Leer_Guía_de_Arquitectura-206bc4?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Architecture Guide">
  </a>
</p>

La aplicación implementa una arquitectura **Data-Access Service Pattern**, donde la lógica de negocio se centraliza en servicios inyectables...

---

## 🚦 Stack Tecnológico
* **Core:** Angular v21.0.0 (Signals, Standalone Components).
* **UI Framework:** @tabler/core + Bootstrap 5.
* **Backend Interface:** Webhooks n8n (API v3) + PostgreSQL (JSONB Support).
* **Utilidades:** DatePipe (Localizado), CurrencyPipe, jwt-decode.

---

### 🏗️ Arquitectura de la Solución
La aplicación implementa una arquitectura desacoplada donde el frontend delega la persistencia al orquestador n8n:
1. **Capa de Seguridad:** Implementación de `auth.guard.ts` y `auth.interceptor.ts`.
2. **Gestión de Estado:** Uso de Angular Signals.
3. **Consumo de API:** Comunicación dinámica con el endpoint `/crud/v3/:model`.
4. **Validación:** Middleware de verificación cruzada en DB (`crud_models`).

---

## 🚀 Capacidades de AdminHotel
- **Room Rack Inteligente:** Visualización por colores de estados.
- **Calidad (QA):** Módulo de rondines diarios con historial de inspecciones.
- **Gestión de Huéspedes:** Registro robusto de identidad.
- **Validación de Inventario:** Check-out con validación de activos.
- **Caja y Ventas:** Reporte financiero integrado.

---

## 📊 Roadmap: Gestión de Hotel (17 Habitaciones)

| Módulo | Estado | Descripción | Integración n8n |
| :--- | :--- | :--- | :--- |
| Room Rack | ✅ Finalizado | Grid visual del estado de habitaciones. | Webhook SQL Real-time. |
| Check-out V2 | ✅ Finalizado | Validación de pago pendiente e inventario. | Update dinámico. |
| Reporte de Caja | ✅ Finalizado | Métricas de ventas por periodos. | Agregación MetaCRUD. |
| **Rondines (QA)**| ✅ **Finalizado**| **Inspección de calidad diaria.** | **Insert/Update JSONB.** |
| Booking Engine | ✅ Finalizado | Creación, consulta y eliminación de reservas. | Update schema. |
| AI WhatsApp Agent | ⏳ Próximo (v0.8) | Reservas automáticas vía Chatbot. | WhatsApp API + AI Agent. |

---

## 🛠️ Comandos de Desarrollo

1. **Requisitos**
    * Node.js (v20+)
    * Angular CLI v21.0.5

2. **Instalación y Servidor Local**
    ```bash
    # Instalar dependencias
    npm install

    # Iniciar servidor (con Proxy activo)
    ng serve
    ```

3. **Pruebas y Construcción**
    ```bash
    # Compilación para Producción (Plesk Ready)
    ng build --configuration=production
    ```

---

## 📦 Integración con n8n Enterprise Suite
Este dashboard es el componente `app/dashboard` dentro del ecosistema n8n Enterprise Suite. Se comunica directamente con los siguientes servicios:

* **JWT Service:** Para validación de tokens RS256.
* **PostgreSQL + pgvector:** Almacenamiento híbrido (Relacional + JSONB).
* **WhatsApp Bridge:** Webhook dedicado para alertas inmediatas.

---

## 📄 Licencia
Este proyecto está bajo la licencia **n8n Sustainable Use License**. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

**Desarrollado por:** Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computacionales y Maestro en Administración de Proyectos.