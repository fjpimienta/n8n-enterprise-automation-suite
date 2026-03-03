# ⛸️ PistaHielo Operations Center

### 🛠️ High-Precision Frontend for Time-Based Operations & Dual-Stage Billing

## 📝 Descripción

**PistaHielo Dashboard** es la evolución de la gestión operativa para centros de entretenimiento. Construida sobre **Angular 21**, reemplaza sistemas legacy con una **WebApp Progresiva (PWA)** capaz de gestionar rentas por tiempo, control de inventario y cortes de caja en tiempo real.

El sistema implementa una arquitectura de **"Caja de Cristal"**: Total transparencia en quién está en la pista, cuánto tiempo lleva y cuánto dinero ha ingresado al negocio, accesible desde cualquier dispositivo.

---

## 🚦 Versiones del Proyecto

| Versión | Estado | Módulo Principal | Cambios Clave |
| :--- | :--- | :--- | :--- |
| **v0.1.0** | `Stable` | `Auth & Architecture` | Estructura base, JWT Auth, Conexión a BD Legacy. |
| **v0.2.0** | `Stable` | `Ice Live Monitor` | Visualización reactiva (Signals), Grid de Patines. |
| **v0.3.0** | `Stable` | `Checkout Engine` | Cobro, Regla Zamboni, Modal de Pago. |
| **v0.4.0** | `Stable` | `Financial Ops` | Reporte de Turno (Corte Z), Filtros de Fecha ISO. |
| **v0.5.0** | `Stable` | `UX & Shell` | **MainLayout**, Menú Móvil, Navegación Jerárquica. |
| **v0.6.0** | `Stable` | `Stability Patch` | **Fix Medianoche**, Fix Reportes n8n, Mini-Sidebar, Global Icons. |
| **v0.7.0** | `Stable` | `AI & MCP` | Directorio de Alumnos, Agente gpt-4o-mini, MCP Tools. |
| **v0.7.1** | `Current` | **Shared Architecture** | **Migración a `ui-chat` Library, Inyección de Tokens, DRY Refactor.** |

---

## 🆕 Novedades Arquitectónicas (v0.7.1)

### 1. 🤖 Unificación de IA (Shared Library)

Siguiendo el principio **DRY (Don't Repeat Yourself)**, se eliminó el componente de chat local para integrar la librería corporativa `@hosting3m/ui-chat`.

* **Configuración Dinámica:** Uso de `CHAT_CONFIG_TOKEN` para inyectar la identidad visual de la pista y el Webhook específico de n8n.
* **Asistente Especializado:** Aunque la interfaz es compartida, la lógica inyectada permite al asistente identificar si un cliente ha excedido su tiempo rentado y aplicar la **Regla Zamboni**.

### 2. 📊 MCP Server (Tools de Pista)

Conjunto de herramientas de alta precisión que permiten a la IA interactuar con la base de datos `ph_transactions`:

* **Ver Pista Activa:** Reporte detallado de patinadores actuales con tiempos calculados al segundo.
* **Ventas Real-time:** Conciliación inmediata de ingresos por Efectivo y Tarjeta.

---

## 🏗️ Arquitectura Técnica

> 🚀 **Estrategia:** Frontend "Rico" (Angular Signals) + Backend "Flexible" (n8n + Postgres).

### 🧩 Componentes de IA:

1. **AiService (Shared):** Gestiona la comunicación reactiva entre la UI y el orquestador n8n.
2. **MCP Trigger:** Punto de entrada en el servidor n8n para que el LLM ejecute herramientas sobre el esquema `public`.

### 🛠️ Stack Tecnológico:

* **Core:** Angular v21.0.0 (Signals, Computed, Effects).
* **UI Framework:** @tabler/core + Bootstrap 5.
* **Orquestador:** n8n v2.3.6 (Enterprise Edition).
* **Base de Datos:** PostgreSQL + pgvector.

---

## 🚀 Capacidades de PistaHielo Dashboard

* **Monitoreo en Tiempo Real:** Quién está en el hielo, con qué patín y cuánto tiempo le queda (Ice Monitor).
* **Gestión de Alumnos VIP:** Seguimiento de mensualidades con cálculo de vigencia automático.
* **Ajuste de Zamboni:** Botón global para ajustar tiempos de todos los patinadores activos durante el mantenimiento.
* **POS Integrado:** Venta de artículos (calcetas, dulces) y servicios (clases particulares) en la misma transacción.

---

## 🛠️ Comandos de Desarrollo

1. **Instalación y Servidor Local**
```bash
npm install
# Requisito: Construir librería compartida si hay cambios
ng build ui-chat
# Iniciar App
ng serve pista-hielo

```


2. **Compilación para Producción**
```bash
ng build pista-hielo --configuration=production

```



---

## 📦 Integración con n8n Enterprise Suite

Este app es el componente `app/pistahielo` dentro del ecosistema n8n Enterprise Suite. Se comunica directamente con los siguientes servicios:

* **JWT Service:** Validación de tokens RS256 para seguridad RBAC.
* **PostgreSQL + pgvector:** Persistencia transaccional y memoria de la IA.
* **WhatsApp Bridge:** Alertas inmediatas para reportes de cierre de caja o incidencias en pista.

---

## 📄 Licencia

Este proyecto está bajo la licencia **n8n Sustainable Use License**. Desarrollado para optimizar la presencia digital y la inteligencia de contenidos de Hosting3m.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```