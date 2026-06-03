# Changelog Principal: n8n Enterprise Automation Suite 🚀

Todos los cambios notables en esta suite de automatización serán documentados en este archivo. El sistema se adhiere estrictamente a **Semantic Versioning** para la gestión de dependencias entre microservicios, flujos de n8n y frontends.

---

## [1.5.0] - 2026-06-02

### 🏢 Arquitectura Multi-Tenant & 🤖 AI Zero-Hallucination (Suite Core Update)
Esta liberación representa una actualización estructural transversal (Cross-Cutting) en la suite, abstrayendo la seguridad a nivel monorepo y certificando los protocolos de grado empresarial para los Agentes IA.

* **Librería `@hosting3m/core-auth`:** Extracción de toda la lógica de autenticación (Guards, Interceptors, Services) hacia una librería Angular centralizada. Implementación de un *Context Switcher* reactivo (Signals) que orquesta el ruteo de usuarios con acceso a múltiples unidades de negocio (ej. Rancho y Hotel).
* **Zero-Hallucination Firewall:** Inyección de directivas restrictivas en el *System Prompt* del Agente IA (`v6_ai_chat_cattle`) para prohibir la inferencia algorítmica de parámetros faltantes y mitigar la inyección de datos "basura" (GIGO).
* **Anti-Jailbreak Protocol (Human-in-the-Loop):** Implementación de un candado estricto de doble confirmación (Sí/No) que bloquea el `Tool Calling` del LLM ante instrucciones autoritarias, garantizando la supervisión humana en cada escritura transaccional.
* **MCP Strongly Typed Schemas:** Refactorización del Servidor MCP (`v6_MCP_Server_Cattle`) implementando casting determinista (`$fromAI`) para asegurar el tipado fuerte hacia PostgreSQL y corrección del desfase de columnas mediante `CURRENT_TIMESTAMP`.
* **Data Pipeline Resilience:** Programación defensiva con operadores RxJS (`catchError`, `map`) en las llamadas al MetaCRUD, previniendo colapsos de UI (`TypeError`) al desenvolver cargas útiles (payloads) anidadas.

---

## [1.3.0] - 2026-05-21

### 🐄 Ganadería Digital: BI Engine & Clinical Metadata
Integración oficial del módulo ERP para el sector agropecuario, enfocado en trazabilidad bovina, biometría y reproducción inteligente.

* **SQL Analytical Engine:** Implementación de Vistas SQL (`vw_cattle_kpi`) para cómputo de Inteligencia de Negocios en el servidor (Server-Side Computation). Cálculo en tiempo real de la Ganancia Diaria de Peso (ADG), Días Abiertos y Tasa de Preñez sin sobrecargar el cliente Angular.
* **Clinical JSONB Persistence:** Refactorización del MetaCRUD para admitir metadata veterinaria dinámica. Los eventos de palpación ahora guardan diagnósticos complejos (días de gestación, condición uterina, ovarios) en una estructura JSON anidada y blindada.
* **Triple Identificación (Censo Biológico):** Soporte en base de datos e interfaz gráfica para manejar la realidad operativa del campo: Arete Visual (SINIIGA), Número a Fuego (Manejo Interno) y Chip RFID (15 dígitos).
* **Reactividad Visual UI:** Implementación de Tabler UI con semáforos biológicos reactivos. El estado de salud ("Óptimo", "Preventivo", "Crítico") se auto-calcula cruzando el historial clínico con el tiempo transcurrido.

---

## [1.2.0] - 2026-03-25

### 🛡️ Dashboard Resilience & Financial Engine (AdminHotel v0.11.0)
Transformación crítica en la capa de datos y lógica de negocio del ERP Hotelero, implementando un escudo estricto contra errores de concurrencia y un nuevo motor de estados financieros.

* **MetaCRUD Error Boundary:** Implementación de un escudo de validación que intercepta falsos positivos (`HTTP 200 OK` con bandera interna `error: true`) desde n8n. Las violaciones de base de datos de PostgreSQL (ej. índices únicos) ahora detienen la ejecución en el cliente, previniendo la desincronización entre el estado físico de la habitación y el *ledger* contable.
* **Soft-Booking & Workflow Evolution:** Arquitectura dual que permite registrar "Cotizaciones" (`pending`) con bloqueo de inventario sin afección fiscal, evolucionando automáticamente a "Reservas Confirmadas" al detectar peticiones de cobro.
* **Bulk Waterfall Payments:** Integración de lógica de pagos en cascada. Permite seleccionar múltiples estancias de un grupo corporativo y distribuir un abono maestro matemáticamente entre todas las reservas.
* **Timezone Armor:** Reemplazo de métodos genéricos de parseo ISO por constructores de tiempo local estricto, erradicando el "bug vespertino" que inhabilitaba operaciones y adelantaba calendarios después de las 18:00 hrs (UTC-6).

---

## [1.1.0] - 2026-03-02

### 🌍 Lanzamiento: Hotel Eco-Website (Public Frontend)
Integración oficial de la Landing Page pública orientada al cliente al ecosistema Monorepo, diseñada para la conversión y atención automatizada.

* **Angular SPA & Tailwind Nativo:** Migración de HTML estático a un proyecto Angular nativo (`projects/hotel-website`). Implementación de Tailwind v3 con compilación JIT, optimizando Core Web Vitals mediante *tree-shaking*.
* **Lead Capture Reactivo:** Conexión directa y segura del formulario de reservas con Webhooks de n8n mediante `HttpClient`, reemplazando el `fetch` tradicional para un inicio de flujo de ventas robusto.
* **Shared AI Concierge:** Inyección de la librería corporativa `@hosting3m/ui-chat` para habilitar el asistente de Inteligencia Artificial directamente en la landing page sin duplicidad de código.
* **Diseño Biófilo (Eco-Boutique):** Implementación de tokens de diseño personalizados, tipografía dual y efectos de *Glassmorphism* alineados con la identidad de la marca.
* **Optimización y Seguridad:** Reducción del tamaño del bundle, SEO dinámico y configuración de políticas CORS estrictas para la comunicación con el orquestador backend.

---

## [0.10.0] - 2026-02-19

### 📄 Documentación Digital & Exportación
Integración de capacidades avanzadas de exportación de documentos en el Dashboard Administrativo.

* **Librería UI PDF Export:** Creación de `projects/ui-pdf-export` para la generación Client-Side de reportes vectoriales (jsPDF + AutoTable).
* **Motor Financiero Fiscal:** Cálculo automatizado de Base Imponible, IVA (16%) e ISH (2%) en las cotizaciones de hospedaje corporativo.
* **Batch Booking UI:** Checkboxes y selección múltiple inteligente para agrupar habitaciones idénticas en un solo folio PDF.

---

## [0.9.0] - 2026-02-18

### 🚀 CloudFree Infrastructure & Distributed Performance

Esta versión consolida la soberanía de datos con el lanzamiento de la infraestructura **Self-Hosted v4** y optimiza radicalmente la experiencia de usuario mediante una **Arquitectura Distribuida**.

#### ☁️ Infraestructura "CloudFree" (Backend & n8n)

* **Sovereign Media Service:** Despliegue de un nuevo microservicio (`upload-service`) en Node.js/Docker para el alojamiento persistente de imágenes, eliminando la dependencia de enlaces temporales externos.
* **Social Orchestrator v4:** Refactorización total del motor de publicación.
* **GenAI Upgrade:** Migración a **OpenAI DALL-E 3** para generación visual de alta fidelidad.
* **Native Graph API:** Implementación de nodos nativos de Instagram/Facebook con manejo de tokens de larga duración.
* **Persistencia Binaria:** Nueva lógica de "Reach Back" en n8n para asegurar la integridad de archivos en flujos complejos.


* **Security Hardening:** Eliminación de credenciales estáticas ("Hardcoded Secrets") en favor de inyección estricta de variables de entorno (`$env`) en todos los workflows críticos.

#### 🏨 AdminHotel Dashboard: Performance & Routing

* **Arquitectura Distribuida:** Transición de un diseño monolítico de Modales a un sistema de **Rutas Hijas (Child Routes)** (`/dashboard/finanzas`, `/dashboard/inventario`), mejorando la separación de responsabilidades.
* **Optimización de TTI (Time-to-Interactive):** Implementación de **Carga Asíncrona Diferida**. El hilo principal prioriza el `Room Rack`, mientras que datos secundarios (CRM, Reservas) se cargan en segundo plano.
* **Centralized Inventory:** Nuevo módulo polimórfico gestionado por `AssetService` que permite administrar activos tanto a nivel Global (Bodega) como Local (Habitación).
* **Smart Services Pattern:** Migración de lógica de negocio compleja (Cálculos Financieros, Balances) desde los componentes hacia **Servicios Reactivos** basados en `Angular Signals`.

---

## [0.8.0] - 2026-02-14

### 🚀 Eco-Hotel Transformation & Workspace Consolidation

Esta versión marca un hito en la madurez del proyecto, transformando el Dashboard de un gestor de reservas a un **ERP Hotelero** y unificando el frontend bajo una arquitectura de **Librerías Compartidas**.

#### 🏗️ Arquitectura de Workspace (Frontend)

* **Refactorización a Monorepo:** Implementación oficial de la librería `@hosting3m/ui-chat`. Se eliminó la duplicidad de código en `dashboard` y `pista-hielo`.
* **Patrón de Inyección de Dependencias:** Desacoplamiento total de los frontends mediante `CHAT_CONFIG_TOKEN`, permitiendo que una misma librería de IA se comporte de forma distinta según el contexto (Hotel vs Pista).
* **Standalone API:** Migración a componentes Standalone puros en toda la suite, eliminando la sobrecarga de `NgModules`.

#### 🏨 AdminHotel: Transformación Eco-Hotel (Fase I)

* **Gestión de CAPEX/OPEX:** Nueva lógica financiera para separar gastos operativos de inversión en remodelación ecológica.
* **Módulo de Mantenimiento:** Sistema de tickets con máquina de estados vinculada al inventario de habitaciones.
* **Inventario de Activos (Assets):** Control de equipos críticos, garantías y ubicación física por habitación.

#### ⛸️ PistaHielo: Integración & Estabilidad

* **Unificación de IA:** Integración de la nueva librería compartida.
* **Fixes Críticos:** Resolución de errores de inyección (`NullInjectorError`) y ajustes de selectores para compatibilidad con la librería del workspace.

---

## [0.7.0] - 2026-02-09

### 🤖 AI Revolution & MCP Protocol

Introducción de capacidades cognitivas avanzadas y estandarización de la comunicación IA-Base de Datos.

#### 🧠 Inteligencia Artificial

* **Protocolo MCP (Model Context Protocol):** Implementación de la arquitectura Cliente-Servidor para que el LLM ejecute herramientas SQL de forma segura.
* **Agentes Especializados:** Despliegue de los asistentes "San José" (Hotel) y "Ops Agent" (Pista) con personalidades y reglas de negocio diferenciadas.
* **RAG & Memory:** Implementación de memoria a corto plazo y búsqueda vectorial mediante `pgvector` para el Hub de WhatsApp.

#### 🛠️ Backend (n8n & DB)

* **Dynamic CRUD Engine v3:** Soporte para persistencia híbrida. Ahora el motor procesa objetos JSONB dinámicos para formularios flexibles de calidad y mantenimiento.
* **Security Hardening:** Rotación de llaves RS256 en el servicio de JWT y validación estricta de roles por modelo de datos.

---

## [0.6.1] - 2026-02-03

### 🛡️ Quality Assurance & Persistence

* **Módulo de Rondines (Hotel):** Implementación de inspecciones digitales con persistencia JSONB.
* **Smart Merge Algorithm:** Lógica de frontend para fusionar esquemas de datos antiguos con nuevas definiciones de formularios.
* **Fix "Midnight Bug":** Corrección en el cálculo de tiempos de renta de patines para turnos que cruzan la medianoche.

---

## [0.6.0] - 2026-01-27

### 📱 Mobile Experience & Accessibility

* **Senior-First Design:** Rediseño de interfaces táctiles con botones de alta visibilidad y layouts simplificados.
* **PWA Capabilities:** Activación de Service Workers para mejorar la persistencia en dispositivos móviles en la Pista de Hielo.
* **Financial Audit:** Inclusión de trazabilidad de descuentos y notas de crédito en los flujos de cobro.

---

## [0.5.0] - 2026-01-13

### 🧱 Core Architecture Release

* **Auth Gateway v2:** Lanzamiento del microservicio centralizado de seguridad basado en Node.js.
* **Omnichannel Social:** Orquestador de publicaciones para X, LinkedIn y Facebook con lógica de idempotencia.
* **News Curator:** Primer motor de ingesta de noticias con filtrado semántico y generación de imágenes IA.

---

## [0.1.0] - 2025-12-20

### 🎉 Initial Infrastructure

* Despliegue de la arquitectura de contenedores Docker.
* Configuración inicial de PostgreSQL con extensiones vectoriales.
* MVP de flujos de contacto y automatización básica de leads.

---

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*

---

*Built with the assistance of AI-powered development tools.*
