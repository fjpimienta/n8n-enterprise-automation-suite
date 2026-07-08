# 🌾 Agro ERP Suite (Ganadería & Agricultura Digital)

### 🚜 Sistema de Trazabilidad Biométrica, Meta-CRUD y Telemetría Agrícola

## 📝 Descripción

**agro-erp** es el sistema de planificación de recursos empresariales de grado industrial dentro de la Hosting3M Automation Suite. Está diseñado para modernizar la gestión agropecuaria mediante la trazabilidad biométrica inmutable, telemetría y gobernanza de datos en tiempo real.

Desarrollada como una **Angular 21 SPA** estructurada por dominios (*Feature-Driven*), interactúa con un motor analítico en PostgreSQL a través de la capa Meta-CRUD de **n8n**. Toda la lógica de mutación de datos está encapsulada en el servidor (PL/pgSQL), eliminando la carga computacional en el cliente y operando bajo estricta "Soberanía de Datos".

---

## 🚀 Key Features (v1.8.0)

### 1. 🐾 Trazabilidad Multi-Especie y Biométrica (RFID / Bolo Ruminal)
* **Identidad Resiliente:** El sistema está diseñado en torno al uso de **Bolos Ruminales y Microchips Subcutáneos** (`electronic_rfid`) como estándar de retención física. Los aretes plásticos tradicionales (SINIIGA) se mantienen únicamente como metadato normativo secundario debido a su alta tasa de pérdida en campo.
* **Soporte Universal:** Aislamiento de biomasa y KPIs de capitalización para hatos mixtos (Bovinos, Búfalos, Borregos) mediante la columna física `species`.

### 2. 🧠 Server-Side Business Intelligence (BI) y Meta-CRUD transaccional
* **Dynamic Gateway:** La función `execute_metacrud_write` orquesta todas las inyecciones de datos (INSERT/UPDATE) desde n8n de forma dinámica, validando permisos contra la tabla `crud_models`.
* **Reglas Sanitarias Estrictas:** El procedimiento `sp_procesar_salida_ganado` bloquea ventas si el animal no cuenta con pruebas de Tuberculosis o Brucelosis vigentes (menos de 60 días de antigüedad).
* **Sincronización de Biomasa:** Triggers en base de datos (`update_current_weight`) automatizan la actualización de la biomasa actual del animal cada vez que se registra un pesaje.

### 3. 🏢 Escalabilidad Multi-Dominio (Context Switcher)
* **Aislamiento de Negocios:** Capacidad nativa para gestionar simultáneamente Ranchos Ganaderos y Plantaciones desde una misma sesión mediante un selector reactivo, aislando el DOM y el estado en memoria.

### 4. 🤖 Inteligencia Artificial Contextual & Anti-Jailbreak
* **Desambiguación Contextual:** Inyección silenciosa del `tenant_id`. Protocolo estricto *Human-in-the-Loop* que requiere confirmación explícita para el Agente IA durante la fase de recolección de datos operativos de 12 meses.

---

## 🚀 Key Features (v1.7.0)

### 1. 🏢 Escalabilidad Multi-Dominio (Context Switcher)
* **Aislamiento de Negocios:** Capacidad nativa para gestionar simultáneamente Ranchos Ganaderos y Plantaciones (ej. Palma Africana) desde una misma sesión mediante un selector reactivo, aislando el DOM y el estado en memoria.
* **Lazy Loading:** Enrutamiento inteligente que solo descarga los módulos necesarios para la vertical operativa seleccionada.

### 2. 🚁 Arquitectura Híbrida para Telemetría (IoT & Drones)
* **Ingesta Flexible (JSONB):** Capacidad para absorber reportes de vuelo de aspersión agrícola, variables de clima y uso de agroquímicos sin romper esquemas relacionales.
* **Server-Side BI:** Delegación de cálculos pesados de rendimiento (litros por hectárea, OPEX) a Vistas Materializadas en PostgreSQL.

### 3. 🐾 Trazabilidad Multi-Especie y Biométrica
* **Identidad Resiliente:** Soporte nativo para lectura de Chip RFID (subcutáneo/ruminal) y Número a Fuego.
* **Filtrado Reactivo (Signals):** Interfaz ultra-rápida basada en `computed` signals que recalcula el valor del hato y ganancias de peso al instante.

### 4. 🤖 Inteligencia Artificial Contextual & Anti-Jailbreak
* **WhatsApp & Web Field Agents:** Desambiguación contextual dinámica inyectando silenciosamente el `tenant_id`. Protocolo estricto *Human-in-the-Loop* que requiere confirmación explícita para registrar información en la base de datos de producción.

---

## 🏗️ Arquitectura Técnica

El proyecto está optimizado para entornos rurales de baja conectividad garantizando un rendimiento extremo:
* **Framework:** Angular 21 (Standalone Components, Signals).
* **Styling:** Tabler UI + SCSS dinámico (`theme-cattle` / `theme-palm`).
* **Communication:** REST API via n8n Meta-CRUD & Webhooks.
* **Data Processing:** PostgreSQL 15+ (Views & JSONB GIN Indexes).

---

## 🛠️ Configuración y Desarrollo

Para levantar el módulo ganadero en entorno local:

### 1. Servidor de Desarrollo
Ejecuta el proyecto aisladamente desde la raíz del monorepo:
```bash
ng serve agro-erp

```

### 2. Build de Producción

Genera el compilado AOT para despliegue en el VPS:

```bash
ng build agro-erp --configuration=production

```
---

## 📋 Roadmap del Proyecto (Hito Q3 2026)

* [x] **Refactoring Estructural (Fase 1):** Migración a `agro-erp` y aislamiento Multi-Negocio.
* [x] **Adaptación del Backend (Fase 2):** Tablas JSONB y despliegue del modelo `PalmTelemetry` en Meta-CRUD.
* [x] **Frontend Multi-Dominio (Fase 3):** Implementación de menús reactivos y Context Switcher.
* [ ] **Motor Financiero (Fase 4):** Integración transversal del OPEX para calcular costo por kilo de biomasa vs. costo por litro de agroquímico.
* [ ] **Dashboards Consolidados (Fase 5):** Estabilización final y pruebas E2E.


---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite