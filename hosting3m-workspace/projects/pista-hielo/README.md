# ⛸️ PistaHielo Operations Center

### 🛠️ High-Precision Frontend for Time-Based Operations & Dual-Stage Billing

## 📝 Descripción
**PistaHielo Dashboard** es la evolución de la gestión operativa para centros de entretenimiento. Construida sobre **Angular 21**, reemplaza sistemas legacy con una **WebApp Progresiva (PWA)** capaz de gestionar rentas por tiempo, control de inventario y cortes de caja en tiempo real.

El sistema implementa una arquitectura de **"Caja de Cristal"**: Total transparencia en quién está en la pista, cuánto tiempo lleva y cuánto dinero ha ingresado al negocio, accesible desde cualquier dispositivo.

---

## 🚦 Versiones del Proyecto

| Versión | Estado | Módulo Principal | Cambios Clave |
| :--- | :--- | :--- | :--- |
| **v0.1** | `Stable` | `Auth & Architecture` | Estructura base, JWT Auth, Conexión a BD Legacy. |
| **v0.2** | `Stable` | `Ice Live Monitor` | Visualización reactiva (Signals), Grid de Patines. |
| **v0.3** | `Stable` | `Checkout Engine` | Cobro, Regla Zamboni, Modal de Pago. |
| **v0.4** | `Stable` | `Financial Ops` | Reporte de Turno (Corte Z), Filtros de Fecha ISO. |
| **v0.5** | `Released` | `UX & Shell` | **MainLayout**, Menú Móvil, Navegación Jerárquica. |
| **v0.5.2** | `Current` | `Stability Patch` | **Fix Medianoche**, Fix Reportes n8n, Mini-Sidebar, Global Icons. |
| **v0.6** | `In Dev` | `VIP Membership` | Directorio de Alumnos, Historial de Clases. |
---

## 🆕 Características Desplegadas (v0.6)

### 1. ⏱️ Motor de Cobro de Alta Precisión
Se eliminaron los errores de cálculo en turnos nocturnos.
* **Midnight-Proof:** El sistema detecta automáticamente si un ticket cruza la medianoche (ej: entrada ayer, salida hoy) y calcula el tiempo exacto.
* **Reactive UI:** Los cronómetros y totales se actualizan instantáneamente al abrir el modal de cobro, gracias al uso de Angular Signals.

### 2. 📱 UX Refinada (Mini Sidebar)
Mejor aprovechamiento del espacio en pantalla.
* **Colapsable:** El menú lateral puede minimizarse a 5rem, dejando más espacio para el Monitor de Pista o reportes extensos.
* **Dark Mode Nativo:** Corrección total de colores y contrastes en formularios y menús desplegables.

### 3. 💰 Reportes Financieros Confiables
* **Corrección Backend:** Se optimizó el motor de consultas en n8n para interpretar correctamente las fechas sin hora, asegurando que el "Corte del Día" traiga todas las ventas, sin importar la hora de registro.

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
1.  **Global Icon Providers:** Estrategia de inyección única en `app.config.ts` para estabilidad y rendimiento.
2.  **CRUD Security:** Configuración de `allowed_ops` en base de datos.
3.  **Smart Date Filtering:** Lógica frontend-backend para manejo de zonas horarias locales.

---

## 🚦 Stack Tecnológico
* **Core:** Angular v21.0.0 (Signals, Computed, Effects).
* **UI Framework:** @tabler/core + Bootstrap 5.
* **Orquestador:** n8n v2.3.6 (Enterprise Edition).
* **Base de Datos:** PostgreSQL + pgvector.
### 🏗️ Arquitectura de la Solución
La aplicación implementa una arquitectura desacoplada donde el frontend delega la persistencia al orquestador n8n:
1. **Capa de Seguridad:** Implementación de `auth.guard.ts` y `auth.interceptor.ts` para comunicación segura vía JWT con el Módulo 01 (Auth Gateway).
2. **Gestión de Estado:** Uso de Angular Signals para un manejo reactivo y eficiente del estado del usuario y la UI.
3. **Consumo de API:** Comunicación dinámica con el endpoint `/crud/v3/:model` para operaciones atómicas.
4. **Validación:** Middleware de verificación cruzada entre el rol del usuario (`x-jwt-claim-role`) y permisos del backend.
5. **Logging:** `Logger.service.ts` integrado para depuración en modo desarrollo sin ensuciar la consola de producción.
## 🚀 Capacidades de PistaHielo Dashboard
- **Monitoreo en Tiempo Real:** Quién está en el hielo, con qué patín y cuánto tiempo le queda.
- **Gestión de Alumnos VIP:** Seguimiento de mensualidades con cálculo de vigencia automático.
- **Ajuste de Zamboni:** Botón global para pausar/ajustar tiempos de todos los patinadores activos durante el mantenimiento.
- **POS Integrado:** Venta de artículos (calcetas, dulces) y servicios (clases particulares) en la misma transacción.
---

## 🛠️ Comandos de Desarrollo

1. **Requisitos**
    * Node.js (v20+)
    * Angular CLI v21.0.5

2. **Instalación y Servidor Local**
    ```bash
    npm install
    ng serve
    ```

3. **Compilación para Producción**
    ```bash
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