# ⛸️ PistaHielo Operations Center

### 🛠️ High-Precision Frontend for Time-Based Operations & Dual-Stage Billing

## 📝 Descripción
**PistaHielo Dashboard** es la evolución de la gestión operativa para centros de entretenimiento. Construida sobre **Angular 21**, reemplaza sistemas legacy con una **WebApp Progresiva (PWA)** capaz de gestionar rentas por tiempo, control de inventario y cortes de caja en tiempo real.

El sistema implementa una arquitectura de **"Caja de Cristal"**: Total transparencia en quién está en la pista, cuánto tiempo lleva y cuánto dinero ha ingresado al negocio, accesible desde cualquier dispositivo (Desktop o Móvil).

---

## 🚦 Versiones del Proyecto

| Versión | Estado | Módulo Principal | Cambios Clave |
| :--- | :--- | :--- | :--- |
| **v0.1** | `Stable` | `Auth & Architecture` | Estructura base, JWT Auth, Conexión a BD Legacy. |
| **v0.2** | `Stable` | `Ice Live Monitor` | Visualización reactiva (Signals), Grid de Patines. |
| **v0.3** | `Stable` | `Checkout Engine` | Cobro, Cálculo de Tiempos, Regla Zamboni, Modal de Pago. |
| **v0.4** | `Stable` | `Financial Ops` | Reporte de Turno (Corte Z), Filtros de Fecha ISO, UI Financiera. |
| **v0.5** | `Released` | `UX & Shell` | **MainLayout**, Menú Móvil Responsivo, Navegación Jerárquica. |
| **v0.6** | `In Dev` | `VIP Membership` | Directorio de Alumnos, Historial de Clases. |
---

## 🆕 Características Desplegadas (v0.5)

### 1. 📱 Mobile-First Operations Shell
Implementación de un **MainLayout** responsivo.
* **Desktop:** Menú lateral vertical fijo (Estilo Tabler).
* **Móvil:** Header exclusivo con menú "Off-canvas" y lógica de auto-cierre al navegar. Permite a los monitores operar la pista desde una tablet o celular mientras caminan.

### 2. 💰 Ciclo Financiero Cerrado
El sistema ahora gestiona el ciclo de vida completo del dinero:
* **Entrada:** Registro rápido (Touch UI).
* **Salida:** Modal de cobro con desglose de tiempo y método de pago.
* **Auditoría:** Pantalla de "Corte de Caja" que concilia en tiempo real el efectivo en cajón vs. vouchers de tarjeta.

### 3. 🛠️ Ingeniería de Software Robusta
* **SSR Safety:** Solución de conflictos de "Hydration" y Timers en el servidor usando `PLATFORM_ID`.
* **Timezone Intelligence:** Manejo de fechas ISO (`sv-SE`) para asegurar que los reportes coincidan con la hora local de la pista, no la del servidor UTC.

---

## 🏗️ Arquitectura Técnica
> 🚀 **Estrategia:** Frontend "Rico" (Angular) + Backend "Flexible" (n8n + Postgres).
<p align="center">
  <a href="./ARCHITECTURE.md">
    <img src="https://img.shields.io/badge/🏛️_Leer_Guía_de_Arquitectura-206bc4?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Architecture Guide">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Angular-DD0031?style=for-the-badge&logo=angular&logoColor=white" />
  <img src="https://img.shields.io/badge/n8n-FF6584?style=for-the-badge&logo=n8n&logoColor=white" />
  <img src="https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white" />
</p>

### Componentes Clave:
1.  **ClientService & CashRegisterService:** Servicios desacoplados que inyectan datos a la vista mediante Signals.
2.  **CRUD Security:** Configuración de `allowed_ops` en base de datos para permitir transacciones (`INSERT/UPDATE`) mientras se protege la integridad histórica.
3.  **One-Liner Deploy:** Script de despliegue optimizado para entornos Plesk/cPanel que gestiona la compilación y rotación de archivos.

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