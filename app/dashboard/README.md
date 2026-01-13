# 🏨 AdminHotel Dashboard

🛠️ Integrated Frontend for Dynamic CRUD Engine

## 📝 Descripción
AdminHotel es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M.

Este dashboard actúa como el cliente principal del Dynamic CRUD Engine, permitiendo una gestión de datos en tiempo real (Reservas, Habitaciones, Check-ins) mediante una capa de abstracción basada en n8n y PostgreSQL.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1** | `Develop` | `Auth & Architecture` | Tabler + Bootstrap | `Estructura base, JWT Auth, Signals.` |
| **v0.2** | `Planned` | `Room Rack v1` | CSS Grid / Cards | `Gestión visual de 17 habitaciones.` |

---

## 🏗️ Arquitectura Técnica
La aplicación implementa una arquitectura desacoplada donde el frontend delega la lógica de negocio y persistencia al orquestador n8n.

1. Flujo de Datos y Seguridad
    * API Gateway (n8n): Comunicación directa con Webhooks v3 para operaciones atómicas.
    * Seguridad: Implementación de auth.guard.ts que protege la ruta /dashboard.
    * Persistencia: Los formularios (como Checkin-form) envían payloads JSON que son procesados por flujos de trabajo en n8n y almacenados en PostgreSQL.
2. Componentes Principales
|Componente|Ruta|Descripción|
|Login|/login|Puerta de entrada. Gestiona la obtención del JWT contra el servicio de Hosting3M.|
|Dashboard|/dashboard|(Protegido) Contenedor principal. Renderiza la UI basada en Tabler.|
|Checkin-form|(Child)|Formulario reactivo para el registro de huéspedes y asignación de habitaciones.|

## 🚦 Stack Tecnológico
    * Core: Angular v21.0.0 (Signals, Standalone Components).
    * UI Framework: @tabler/core (Diseño administrativo responsive).
    * Testing: vitest (Unit Testing de alta velocidad).
    * Utilidades: jwt-decode (Manejo de claims de seguridad), rxjs.
    * Backend Interface: Webhooks n8n (API v3).

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

---

## 📄 Licencia
Este proyecto está bajo la licencia n8n Sustainable Use License. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

Desarrollado por: Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computacionales y Maestro en Administración de Proyectos.