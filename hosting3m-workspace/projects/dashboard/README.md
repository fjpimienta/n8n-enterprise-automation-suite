# 🏨 AdminHotel Dashboard

### 🛠️ Integrated Frontend for Dynamic CRUD Engine

## 📝 Descripción
**AdminHotel** es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M.

Este dashboard actúa como el cliente principal del **Dynamic CRUD Engine**, permitiendo una gestión de datos en tiempo real (Reservas, Habitaciones, Check-ins, Calidad) mediante una capa de abstracción basada en n8n y PostgreSQL. Se especializa en la gestión operativa de flujos de hospitalidad mediante el uso intensivo de Angular Signals y una arquitectura de servicios desacoplados.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1** | `Stable` | `Auth & Architecture` | Tabler + Bootstrap | Estructura base, JWT Auth, Signals. |
| **v0.2** | `Stable` | `Room Rack v1` | CSS Grid / Cards | Gestión visual de 17 habitaciones. |
| **v0.3** | `Stable`| `Ops & Finance`| Modals / Reports | Checkout con inventario, Reporte de Caja (D/S/M/Y) y Gestión de Usuarios. |
| **v0.4** | `Stable` | `Pro UX & Patterns` | Skeletons / Services | Refactorización a Services, Skeletons de carga, Promesas (Async/Await).|
| **v0.5** | `Stable` | `Full Operation` | Interactive UI | Refresh Engine, Reservas dinámicas, Gestión avanzada de Huéspedes. |
| **v0.6** | `Stable` | `Accessibility` | Mobile Grid / CSS | Lógica de Descuentos, UX Accesible para Seniors (Fat-Finger Design). |
| **v0.7** | `Stable` | `Quality Assurance` | **JSONB / Forms** | **Módulo de Rondines, Persistencia Híbrida, Smart Save.** |
| **v0.8** | `Planned` | **AI Integration** | **WhatsApp API** | Agentes IA para reservas y notificaciones automatizadas. |


---

## 🆕 Novedades de la v0.7 (Changelog)

1. **📋 Módulo de Calidad (Rondines)**
    * **Inspección Digital:** Nuevo flujo operativo para validar el estado de las habitaciones (Limpieza, Baño, Tecnología, Seguridad) antes de entregarlas.
    * **Formulario Reactivo Agrupado:** Interfaz optimizada por zonas de inspección con interruptores (switches) grandes para uso rápido en móvil/tablet.
    * **Persistencia Híbrida:** Implementación de almacenamiento **JSONB** en PostgreSQL. Esto permite flexibilidad total: el checklist puede evolucionar (agregar/quitar items) sin necesidad de migraciones de base de datos complejas.

2. **🧠 Smart Data Handling**
    * **Lógica Create/Update:** El sistema detecta automáticamente si ya se realizó una inspección hoy. Si existe, carga los datos en "Modo Edición"; si no, inicia en "Modo Creación".
    * **Fusión Segura:** Algoritmo de frontend que combina datos históricos con la estructura actual del formulario, garantizando que los registros antiguos no rompan la aplicación si el checklist cambia.

3. **🔧 Ingeniería**
    * **Proxy Reverso Local:** Solución definitiva a problemas de CORS en desarrollo mediante configuración de proxy en Angular CLI.
    * **Payload Normalizado:** Ajuste en la capa de servicios para alineación estricta con los scripts de backend de n8n (`fields` property).

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