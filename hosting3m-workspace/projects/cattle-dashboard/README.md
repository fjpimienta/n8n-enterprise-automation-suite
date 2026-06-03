# 🐄 Cattle Dashboard (Ganadería Digital)

### 🌾 Agro ERP & Sistema de Trazabilidad Biométrica

## 📝 Descripción

**cattle-dashboard** es el módulo agropecuario de grado industrial dentro de la Hosting3M Automation Suite. Está diseñado para modernizar la gestión ganadera mediante la trazabilidad de biomasa, reproducción inteligente y gobernanza de datos en tiempo real.

Desarrollada como una **Angular 21 SPA** (Single Page Application) dentro del monorepo, esta aplicación interactúa con un motor analítico en PostgreSQL a través de la capa Meta-CRUD de **n8n**, eliminando la carga computacional en el cliente y operando bajo el principio de "Soberanía de Datos".

---

## 🚀 Key Features (v1.5.0)

### 1. 🧬 Trazabilidad y Triple Identificación
* **Identidad Resiliente:** Soporte nativo para tres capas de identificación bovina: Arete Oficial (SINIIGA), Número a Fuego (Manejo Interno) y Chip RFID (Lectura electrónica de 15 dígitos).
* **Historial Inmutable:** Relación estricta mediante UUID para asociar eventos de peso y sanidad a lo largo de toda la vida del animal.

### 2. 🧠 Server-Side Business Intelligence (BI)
* **SQL Analytical Engine:** Uso de Vistas SQL (`vw_cattle_kpi`) para calcular la Ganancia Diaria de Peso (ADG) y los "Días Abiertos" directamente en el servidor.
* **Semáforo Biológico Reactivo:** La UI clasifica el hato en estado *Óptimo, Preventivo o Crítico* basándose en reglas matemáticas computadas desde el backend.

### 3. 🤖 Inteligencia Artificial & Captura en Campo (Fase 12-Meses)
* **WhatsApp Field Agent:** Integración directa con n8n y Model Context Protocol (MCP) para la recolección natural de datos. Garantiza la ejecución de la **Fase Obligatoria de 12 Meses de Recolección de Datos** antes de implementar hardware físico de pesaje.
* **Zero-Hallucination Protocol:** El sistema emplea un estricto proceso de validación *Human-in-the-Loop* y esquemas fuertemente tipados, eliminando el riesgo de inyección de datos "basura" (GIGO) en la base de datos de producción.

### 4. 🏢 Arquitectura Multi-Tenant Abstraída
* **Core-Auth Library:** Consumo de la librería transversal `@hosting3m/core-auth` para garantizar un aislamiento seguro de sesión. Incluye un `Context Switcher` reactivo que orquesta el ruteo de usuarios con acceso a múltiples unidades de negocio.

---

## 🏗️ Arquitectura Técnica

El proyecto está optimizado para entornos de baja conectividad (ranchos) garantizando un rendimiento extremo:

* **Framework:** Angular 21 (Standalone Components, Signals).
* **Styling:** Tabler UI + SCSS.
* **Communication:** REST API via n8n Meta-CRUD & Webhooks.
* **Data Processing:** Delegado a PostgreSQL (Views & JSONB).

---

## 🛠️ Configuración y Desarrollo

Para levantar el módulo ganadero en entorno local:

### 1. Servidor de Desarrollo
Ejecuta el proyecto aisladamente desde la raíz del monorepo:
```bash
ng serve cattle-dashboard

```

### 2. Build de Producción

Genera el compilado AOT para despliegue en el VPS:

```bash
ng build cattle-dashboard --configuration=production

```

---

## 📋 Roadmap del Proyecto

* [x] **WhatsApp Field Agent:** Integración de flujos (v6) vía n8n para permitir altas y reportes operativos mediante lenguaje natural desde el campo (`workflows/09-MCP-Agent-Cattle`).
* [ ] **Módulo de Gastos (CAPEX/OPEX):** Integración completa en UI de `cattle_expenses` para calcular el costo de producción por kilo de biomasa.
* [ ] **IoT Scale Integration:** Recepción automatizada de archivos `.csv` o tramas Bluetooth desde básculas Tru-Test/Gallagher (Post-Fase 12 Meses).

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite
