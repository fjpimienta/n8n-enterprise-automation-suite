# 🌾 Agro ERP Suite (Ganadería & Agricultura Digital)

### 🚜 Sistema de Trazabilidad Biométrica, Meta-CRUD, Telemetría Agrícola y Movilización REEMO

## 📝 Descripción

**agro-erp** es el sistema de planificación de recursos empresariales de grado industrial dentro de la Hosting3M Automation Suite. Está diseñado para modernizar la gestión agropecuaria mediante la trazabilidad biométrica inmutable, telemetría, gobernanza de datos en tiempo real y cumplimiento normativo SENASICA-SINIIGA para movilización de ganado.

Desarrollada como una **Angular 21 SPA** estructurada por dominios (*Feature-Driven*), interactúa con un motor analítico en PostgreSQL a través de la capa Meta-CRUD de **n8n**. Toda la lógica de mutación de datos está encapsulada en el servidor (PL/pgSQL), eliminando la carga computacional en el cliente y operando bajo estricta "Soberanía de Datos" — incluyendo el almacenamiento de archivos, servido por un microservicio propio (`upload-file`) en vez de depender de terceros.

---

## 🚀 Key Features (v1.10.0)

### 1. 🚚 Motor de Movimientos SENASICA-REEMO
* **Reglas de movimiento confirmadas:** el catálogo de reglas UPP↔PSG, creado como borrador meses atrás, ya está poblado con reglas de negocio reales del cliente (audio grabado + documentos REEMO/CZM/permiso reales). `PSG → UPP` queda permanentemente prohibido; los requisitos varían según el movimiento sea local o interestatal.
* **Bitácora real de movimientos:** cada traslado queda registrado con origen, destino, folio REEMO, y aislamiento multi-tenant fail-closed — un movimiento entre tenants distintos se rechaza automáticamente.
* **Cadena documental de cumplimiento:** guía de tránsito, Certificado Zoosanitario, constancia de gusano barrenador (GBG), permiso de internación estatal y carta de cesión de derechos, todos enlazados al movimiento que respaldan.
* **Historial automático de identificadores:** cualquier cambio de arete, número a fuego o chip queda registrado solo, sin depender de que un script se acuerde de hacerlo.

### 2. 🔐 Almacenamiento de Archivos Endurecido ("Sovereign Media Service")
* El microservicio propio de archivos (`upload-file`) pasó de ser completamente público a exigir autenticación JWT o secreto interno, reutilizando la infraestructura de `core-auth`/`jwt-service` ya existente — sin inventar un mecanismo de seguridad paralelo.
* Nombres de archivo aleatorios (antes predecibles), hash SHA-256 calculado en servidor, y credenciales fuera del control de versiones.

---

## 🚀 Key Features (v1.9.0)

### 1. 🏛️ Registro Normativo SENASICA-SINIIGA
* **Multi-UPP por tenant:** un rancho (`companys`) puede sostener múltiples unidades de producción registradas ante SENASICA — la equivalencia "una empresa = un predio" ya no aplica.
* **Propiedad independiente de ubicación:** el fierro de marca (`brand_registrations`) es un catálogo global, independiente de en qué UPP esté parado el animal — modela la realidad real del padrón (ganado de un titular pastando en tierra del otro).
* **Dictámenes de hato libre:** exención de la ventana de 60 días de pruebas TB/BR para hatos con certificado vigente de hasta 24 meses.
* **Linaje materno y herencia de fierro:** la cría hereda automáticamente el fierro de la madre al registrar un parto.

---

## 🚀 Key Features (v1.8.0)

### 1. 🐾 Trazabilidad Multi-Especie y Biométrica (RFID / Bolo Ruminal)
* **Identidad Resiliente:** El sistema está diseñado en torno al uso de **Bolos Ruminales y Microchips Subcutáneos** (`electronic_rfid`) como estándar de retención física. Los aretes plásticos tradicionales (SINIIGA) se mantienen únicamente como metadato normativo secundario debido a su alta tasa de pérdida en campo.
* **Soporte Universal:** Aislamiento de biomasa y KPIs de capitalización para hatos mixtos (Bovinos, Búfalos, Borregos) mediante la columna física `species`.

### 2. 🧠 Server-Side Business Intelligence (BI) y Meta-CRUD transaccional
* **Dynamic Gateway:** La función `execute_metacrud_write` orquesta todas las inyecciones de datos (INSERT/UPDATE) desde n8n de forma dinámica, validando permisos contra la tabla `crud_models`.
* **Reglas Sanitarias Estrictas:** El procedimiento `sp_procesar_salida_ganado` bloquea ventas si el animal no cuenta con pruebas de Tuberculosis o Brucelosis vigentes (menos de 60 días de antigüedad).
* **Auditoría de Movimientos:** Cada venta, baja o traslado queda registrado de forma inmutable en `historico_movimientos`, preservando el `upp_origen` (rancho/centro de costos) del animal al momento del evento.
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
* **File Storage:** Microservicio propio (`upload-file`, Node/Express) autenticado vía JWT compartido con `core-auth`/`jwt-service` — sin dependencia de almacenamiento externo.

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
* [x] **Registro Normativo SENASICA-SINIIGA:** UPP/PSG multi-tenant, propiedad por fierro, dictámenes de hato libre (v1.9.0).
* [x] **Motor de Movimientos SENASICA-REEMO:** reglas de movimiento confirmadas, bitácora de traslados, cadena documental de cumplimiento (v1.10.0).
* [x] **Endurecimiento de Almacenamiento de Archivos:** autenticación JWT/secreto interno en `upload-file` (v1.10.0).
* [ ] **Motor Financiero (Fase 4):** Integración transversal del OPEX para calcular costo por kilo de biomasa vs. costo por litro de agroquímico.
* [ ] **Dashboards Consolidados (Fase 5):** Estabilización final y pruebas E2E.
* [ ] **Enforcement activo de reglas de movimiento:** pendiente de una sola confirmación del cliente (`requires_destination_ack`) para activar el bloqueo automático de movimientos no permitidos.
* [ ] **Digitalización de expediente documental:** `compliance_documents` sigue en 0 archivos cargados — estructura y seguridad listas, sin datos reales aún.


---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite