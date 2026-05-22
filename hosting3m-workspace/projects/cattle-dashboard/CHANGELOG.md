# Changelog

Todos los cambios notables en el proyecto **n8n Enterprise Automation Suite** serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/), y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

# Changelog - Cattle Dashboard (Ganadería Digital)

## [1.0.0] - 2026-05-21

### 🚀 Lanzamiento Inicial (Core Architecture)

Establecimiento del sistema transaccional y analítico para la gestión de ranchos ganaderos, enfocado en los ciclos de Cría (Cow-Calf) y Engorda (Feedlot).

#### 🏗️ Arquitectura & Base de Datos
* **Multi-Tenancy:** Aislamiento de datos a nivel de base de datos (`tenant_id`), permitiendo gestionar múltiples ranchos desde una sola instancia. Migración de llaves foráneas a `Integer` para compatibilidad con sistemas legados.
* **Meta-CRUD Integration:** Conexión fluida con el API Gateway de n8n, implementando reglas estrictas de integridad (`Check Constraints`) para modelos de negocio y estatus del animal (ACTIVO, PREÑADA, VACÍA, FINALIZADO).

#### 📊 Business Intelligence & Server-Side Computing
* **Vista `vw_cattle_kpi`:** Creación del motor de cálculo en PostgreSQL para resolver la Ganancia Diaria de Peso (ADG) y extraer el último diagnóstico reproductivo directamente desde campos JSONB (`medicines_json`).
* **Supresión de Mock Data:** Transición exitosa del `CattleDataService` simulado a conexiones en tiempo real usando Angular Signals y el `HttpClient`.

#### 🎨 UI/UX y Flujos Operativos
* **Tabler UI Integration:** Implementación de modales reactivos con `FormGroup` para Altas, Control de Biomasa (Pesajes) y Eventos Sanitarios.
* **Captura Flexible:** Rediseño del formulario de alta para admitir SINIIGA, Número de Fuego y Chip RFID, soportando la realidad operativa donde los animales pierden sus identificadores físicos.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite