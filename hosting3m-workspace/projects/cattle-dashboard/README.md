# 🐄 Cattle Dashboard (Ganadería Digital)

### 🌾 Agro ERP & Sistema de Trazabilidad Biométrica

## 📝 Descripción

**cattle-dashboard** es el módulo agropecuario de grado industrial dentro de la Hosting3M Automation Suite. Está diseñado para modernizar la gestión ganadera mediante la trazabilidad de biomasa, reproducción inteligente y gobernanza de datos en tiempo real.

Desarrollada como una **Angular 21 SPA** (Single Page Application) dentro del monorepo, esta aplicación interactúa con un motor analítico en PostgreSQL a través de la capa Meta-CRUD de **n8n**, eliminando la carga computacional en el cliente y operando bajo el principio de "Soberanía de Datos".

---

## 🚀 Key Features (v1.6.0)

### 1. 🐾 Arquitectura Multi-Especie (Bovinos, Búfalos, Borregos)
* **Gestión Universal:** Soporte de primera clase para la segmentación y análisis de hatos mixtos, permitiendo el aislamiento de biomasa y KPIs de capitalización por especie sin alterar la API genérica.
* **Filtrado Reactivo (Signals):** Interfaz ultra-rápida basada en `computed` signals que recalcula el valor del hato y ganancias diarias de peso al instante en el lado del cliente.

### 2. 🧬 Trazabilidad y Triple Identificación
* **Identidad Resiliente:** Soporte nativo para tres capas de identificación: Arete Oficial (SINIIGA), Número a Fuego (Manejo Interno) y Chip RFID (Lectura electrónica de 15 dígitos).
* **Historial Inmutable:** Relación estricta mediante UUID para asociar eventos de peso y sanidad a lo largo de toda la vida del animal.

### 3. 🧠 Server-Side Business Intelligence (BI)
* **SQL Analytical Engine:** Uso de Vistas SQL (`vw_cattle_kpi`) para calcular la Ganancia Diaria de Peso (ADG) y los "Días Abiertos" directamente en el servidor.
* **Semáforo Biológico Reactivo:** La UI clasifica el hato en estado *Óptimo, Preventivo o Crítico* basándose en reglas matemáticas computadas desde el backend.

### 4. 🤖 Inteligencia Artificial Contextual & Captura en Campo
* **WhatsApp & Web Field Agents:** Integración con n8n y MCP (Model Context Protocol). Ejecución de la **Fase Obligatoria de 12 Meses de Recolección de Datos** antes de implementar hardware físico.
* **Stateful Context Injection:** Desambiguación contextual dinámica. El Agente aísla automáticamente las consultas y registros transaccionales basándose en el `tenant_id` de la sesión activa del usuario, impidiendo la contaminación cruzada entre socios inversores.
* **Zero-Hallucination & Anti-Jailbreak:** Protocolo estricto *Human-in-the-Loop* que requiere confirmación explícita antes de inyectar datos en la base de datos de producción.

### 5. 🏢 Arquitectura Multi-Tenant Abstraída
* **Core-Auth Library:** Consumo de la librería transversal `@hosting3m/core-auth` para garantizar un aislamiento seguro de sesión. Incluye un `Context Switcher` reactivo que orquesta el ruteo de usuarios con acceso a múltiples unidades de negocio.

---

## 🏗️ Arquitectura Técnica

El proyecto está optimizado para entornos de baja conectividad garantizando un rendimiento extremo:
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

* [x] **WhatsApp Field Agent:** Integración de flujos vía n8n para permitir altas y reportes operativos mediante lenguaje natural desde el campo.
* [x] **Multi-Species Support:** Migración a columnas físicas y soporte reactivo para múltiples familias biológicas.
* [ ] **Módulo de Gastos (CAPEX/OPEX):** Integración completa en UI de `cattle_expenses` para calcular el costo de producción por kilo de biomasa.
* [ ] **IoT Scale Integration:** Recepción automatizada de archivos `.csv` o tramas Bluetooth desde básculas Tru-Test/Gallagher (Post-Fase 12 Meses).

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite