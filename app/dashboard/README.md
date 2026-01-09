# 🏨 AdminHotel Dashboard

🛠️ Integrated Frontend for Dynamic CRUD Engine

## 📝 Descripción
AdminHotel es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M.

Este dashboard no solo gestiona la lógica hotelera (reservas, habitaciones, pagos), sino que actúa como el cliente principal del Dynamic CRUD Engine (Módulo 06), permitiendo una gestión de datos en tiempo real mediante una capa de abstracción basada en n8n y PostgreSQL.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1** | `Develop` | `Auth & Architecture` | Tabler + Bootstrap | `Estructura base, JWT Auth, Signals.` |
| **v0.2** | `Planned` | `Room Rack v1` | CSS Grid / Cards | `Gestión visual de 17 habitaciones.` |

---

### 🏗️ Arquitectura de la Solución
La aplicación implementa una arquitectura desacoplada donde el frontend delega la persistencia al orquestador n8n:
1. **Capa de Seguridad:** mplementación de auth.guard.ts y auth.interceptor.ts para comunicación segura vía JWT con el Módulo 01 (Auth Gateway).
2. **Gestión de Estado:** Uso de Angular Signals para un manejo reactivo y eficiente del estado del usuario y la UI.
3. **Consumo de API:** Comunicación dinámica con el endpoint /crud/v2/:model para operaciones atómicas.
4. **Validación:** Middleware de verificación cruzada entre el rol del usuario (x-jwt-claim-role) y permisos del backend.
5. **Logging:** Logger.service.ts integrado para depuración en modo desarrollo sin ensuciar la consola de producción.

---

## 🚀 Capacidades de AdminHotel
- **Seguridad Enterprise:** Autenticación robusta con jwt-decode y protección de rutas.
- **UI Premium:** Interfaz basada en Tabler, optimizada para visualización de métricas y gestión de inventario.
- **Testing de Alta Velocidad:** Configuración nativa con Vitest para un ciclo de desarrollo ágil.
- **Dynamic CRUD Ready:** Formulario y servicios preparados para interactuar con cualquier tabla de PostgreSQL a través del motor n8n.

---

## 📊 Roadmap: Gestión de Hotel (17 Habitaciones)
|Módulo|Descripción|Integración n8n|
|Room Rack|Grid visual del estado de las 17 habitaciones (Libre/Ocupada).|Webhook en tiempo real.|
|Smart Booking|CRUD de reservaciones conectado a la lógica de IA.|AI WhatsApp Agent (Módulo 05).|
|Auto-Billing|Generación de recibos y control de pagos mediante Tabler UI.|CRM Bridge (Módulo 07).|

---

## 🛠️ Comandos de Desarrollo
1. Requisitos
    * Node.js (v20+)
    * Angular CLI v21.0.5

2. Instalación y Servidor Local
    ```
        # Instalar dependencias
        npm install

        # Iniciar servidor de desarrollo
        ng serve
    ```
3. Pruebas y Construcción
    ```
        # Ejecutar Unit Tests con Vitest
        ng test

        # Compilación para Producción (Plesk Ready)
        ng build --configuration=production
    ```

---

## 📦 Integración con n8n Enterprise Suite
Este dashboard es el componente app/dashboard dentro del ecosistema n8n Enterprise Suite. Se comunica directamente con los siguientes servicios:

* JWT Service: Para validación de tokens RS256.
* PostgreSQL + pgvector: Almacenamiento de metadatos de habitaciones y búsqueda semántica.
* Nginx Proxy: Terminación SSL y endurecimiento de cabeceras.

## 📄 Licencia
Este proyecto está bajo la licencia n8n Sustainable Use License. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computacionales y Maestro en Administración de Proyectos.