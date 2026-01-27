# 🏨 AdminHotel Dashboard

### 🛠️ Integrated Frontend for Dynamic CRUD Engine

## 📝 Descripción
**AdminHotel** es una aplicación web de alto rendimiento construida sobre Angular 21, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M.

Este dashboard actúa como el cliente principal del **Dynamic CRUD Engine**, permitiendo una gestión de datos en tiempo real (Reservas, Habitaciones, Check-ins) mediante una capa de abstracción basada en n8n y PostgreSQL. Se especializa en la gestión operativa de flujos de hospitalidad mediante el uso intensivo de Angular Signals y una arquitectura de servicios desacoplados.

---

## 🚦 Versiones del Workflow

| Versión | Estado | Módulo Principal | Stack de UI | Cambios Principales |
| :--- | :--- | :--- | :--- | :--- |
| **v0.1** | `Stable` | `Auth & Architecture` | Tabler + Bootstrap | Estructura base, JWT Auth, Signals. |
| **v0.2** | `Stable` | `Room Rack v1` | CSS Grid / Cards | Gestión visual de 17 habitaciones. |
| **v0.3** | `Stable`| `Ops & Finance`| Modals / Reports | Checkout con inventario, Reporte de Caja (D/S/M/Y) y Gestión de Usuarios. |
| **v0.4** | `Stable` | `Pro UX & Patterns` | Skeletons / Services | Refactorización a Services, Skeletons de carga, Promesas (Async/Await).|
| **v0.5** | `Stable` | Full Operation | Interactive UI | Refresh Engine, Reservas dinámicas, Gestión avanzada de Huéspedes, Emojis & Traducciones. |
| **v0.6** | `Stable` | Accessibility & Finance | Mobile Grid / CSS | Lógica de Descuentos, UX Accesible para Seniors (Fat-Finger Design), Filtros Grid. |
| **v0.7** | `Planned` | **AI Integration** | **WhatsApp API** | Agentes IA para reservas y notificaciones automatizadas. |


---

## 🆕 Novedades de la v0.6 (Changelog)
1. 📱 UX Móvil & Accesibilidad (Senior-First Design)
    * Diseño "Fat Finger": Reestructuración completa de la interfaz para pantallas táctiles. Los botones ahora son bloques grandes ("ladrillos") de fácil interacción, eliminando enlaces pequeños o difíciles de tocar.

    * Semáforo Visual Inmersivo: Las tarjetas de habitación ya no dependen solo de texto; el fondo completo cambia de color (Verde/Rojo/Naranja) para una identificación cognitiva inmediata del estado.

    * Grid Navigation: Se eliminó el scroll horizontal oculto en los filtros. Ahora se utiliza un CSS Grid Layout que despliega todas las opciones de filtrado y menús administrativos en una cuadrícula visible y ordenada automáticamente según el dispositivo.

2. 💸 Lógica Financiera & Descuentos
    * Cálculo Dinámico de Tarifas: Implementación de algoritmo que calcula automáticamente el precio de lista vs. el monto cobrado.

    * Auditoría de Descuentos: Nueva lógica de base de datos (discount_amount) que registra la diferencia entre la tarifa oficial y el cobro real sin perder la trazabilidad financiera.

    * Validación Condicional: Regla de negocio estricta implementada con Reactive Forms: si existe un descuento > 0, el campo de "Notas" se vuelve obligatorio para justificar la rebaja (ej. "Autorizado por Gerencia").

3. ⚡ Mejoras Visuales y de Rendimiento
Optimización de Espacio: Layout responsivo mejorado que pasa de columnas múltiples en escritorio a tarjetas de ancho completo en móviles para evitar errores de selección.

    * Tipografía Jerárquica: Aumento significativo en el tamaño de fuentes para números de habitación y estados críticos.

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
* **Core:** Angular v21.0.0 (Signals, Standalone Components, Signal Queries).
* **UI Framework:** @tabler/core (Diseño administrativo responsive) + Bootstrap 5.
* **State Management:** Angular Signals (Reactividad fina sin Zone.js en componentes críticos).
* **Backend Interface:** Webhooks n8n (API v3) operando sobre PostgreSQL.
* **Utilidades:** DatePipe (Localizado para México), CurrencyPipe, jwt-decode.
* **UX:** Implementación de Skeleton Screens para estados de carga asíncronos.

---

### 🏗️ Arquitectura de la Solución
La aplicación implementa una arquitectura desacoplada donde el frontend delega la persistencia al orquestador n8n:
1. **Capa de Seguridad:** Implementación de `auth.guard.ts` y `auth.interceptor.ts` para comunicación segura vía JWT con el Módulo 01 (Auth Gateway).
2. **Gestión de Estado:** Uso de Angular Signals para un manejo reactivo y eficiente del estado del usuario y la UI.
3. **Consumo de API:** Comunicación dinámica con el endpoint `/crud/v2/:model` para operaciones atómicas.
4. **Validación:** Middleware de verificación cruzada entre el rol del usuario (`x-jwt-claim-role`) y permisos del backend.
5. **Logging:** `Logger.service.ts` integrado para depuración en modo desarrollo sin ensuciar la consola de producción.

---

## 🚀 Capacidades de AdminHotel
- **Room Rack Inteligente:** Visualización por colores de estados (Verde: Disponible, Rojo: Ocupado, Amarillo: Check-out, Gris: Mantenimiento).
- **Gestión de Huéspedes:** Registro robusto que captura datos de identidad, procedencia y notas especiales.
- **Validación de Inventario:** Check-out con validación de activos (Llaves, TV, A/C).
- **Caja y Ventas:** Reporte financiero integrado que segmenta Ventas Totales, Cobrado (Efectivo) y Por Cobrar en tiempo real.
- **Gestión de Personal:** Panel administrativo para el alta y edición de roles de empleados.

---

## 📊 Roadmap: Gestión de Hotel (17 Habitaciones)

| Módulo | Estado | Descripción | Integración n8n |
| :--- | :--- | :--- | :--- |
| Room Rack | ✅ Finalizado | Grid visual del estado de habitaciones. | Webhook SQL Real-time. |
| Check-out V2 | ✅ Finalizado | Validación de pago pendiente e inventario. | Update dinámico de hotel_rooms. |
| Reporte de Caja | ✅ Finalizado | Métricas de ventas por periodos (Día/Semana/Mes/Año). | Agregación vía MetaCRUD. |
| UX Skeletons | ✅ Finalizado | Feedback visual durante la carga de datos. | UI Reactiva (Signals). |
| Booking Engine | ✅ Finalizado | Creación, consulta y eliminación de reservas. | Update schema hotel_bookings. |
| AI WhatsApp Agent | ⏳ Próximo (v0.7) | Reservas automáticas vía Chatbot conectadas al nuevo Form. | WhatsApp API + AI Agent. |

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
Este dashboard es el componente `app/dashboard` dentro del ecosistema n8n Enterprise Suite. Se comunica directamente con los siguientes servicios:

* **JWT Service:** Para validación de tokens RS256.
* **PostgreSQL + pgvector:** Almacenamiento de metadatos de habitaciones y búsqueda semántica.
* **WhatsApp Bridge:** Webhook dedicado para alertas inmediatas de limpieza o fallas técnicas reportadas desde el dashboard.

---

## 📄 Licencia
Este proyecto está bajo la licencia **n8n Sustainable Use License**. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

**Desarrollado por:** Francisco Jesus Pérez Pimienta - Ingeniero en Sistemas Computacionales y Maestro en Administración de Proyectos.