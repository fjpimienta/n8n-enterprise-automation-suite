# ⛸️ Architecture Overview: PistaHielo Operations Center

## 📝 Descripción
**Project:** PistaHielo Dashboard (Módulo de la Suite Hosting3M)
**Version:** v0.6.0 (Stable Production)
**Stack:** Angular 21 (Signals, Computed) | n8n v2.1.4 (Orquestador) | PostgreSQL (pgvector)
**Patrón Arquitectónico:** Layout Shell Pattern + Reactive Signal Engine.
**Author:** Francisco Jesus Pérez Pimienta

**Pista de Hielo** es una aplicación web progresiva (PWA) de alto rendimiento, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M. Integra operaciones de tiempo real con control financiero estricto.

## 1. Diseño de Alto Nivel: Flujo de Navegación y Datos
La arquitectura implementa un **"Main Layout Shell"** que mantiene el contexto de navegación (Menú/Sidebar) mientras el usuario alterna entre operaciones de pista y administración financiera.

```mermaid
graph TD
    User["Operador / Admin"] -->|"HTTPS + JWT"| SHELL["MainLayout Shell (Sidebar + Header Mobile)"]
    
    subgraph "Frontend (Angular 21)"
    SHELL -->|"Global Providers"| ICONS["Lucide Icons Registry"]
    SHELL -->|"Router Outlet"| OPS["Módulo Operations"]
    SHELL -->|"Router Outlet"| ADMIN["Módulo Admin"]
    
    OPS -->|Signals| MON["IceMonitor (Live Rack)"]
    OPS -->|Form| ENT["EntryForm (Touch UI)"]
    OPS -->|"Computed Signals"| CHK["CheckoutComponent (Reactive Pricing)"]
    
    ADMIN -->|Service| REP["ShiftReport (Corte Z)"]
    ADMIN -->|CRUD| CLI["ClientDirectory"]
    end

    CHK -->|"POST Update"| N8N["n8n Automation Engine"]
    REP -->|"POST Filter"| N8N
    
    N8N -->|"SQL: Transactions/Clients"| PG[("PostgreSQL")]
```

### Principios Clave:

1. **Layout Shell Architecture:** Un componente padre (MainLayout) gestiona la estructura visual, la responsividad móvil (hamburguesa) y la sesión, desacoplando la navegación de la lógica de negocio.
2. **Reactive Pricing Engine:** El cálculo de costos ya no depende de eventos estáticos. Se utilizan `computed()` signals para recalcular el tiempo transcurrido y el monto a pagar en tiempo real al abrir el modal, solucionando problemas de latencia o "stale data".
3. **Global Icon Strategy:** Para evitar errores de ejecución y reducir el boilerplate, los iconos (Lucide) se inyectan globalmente en `app.config.ts`, asegurando disponibilidad en todos los componentes dinámicos.

---

## 2. Frontend Structure (Modular Architecture)

La aplicación se ha reestructurado en dominios funcionales claros:

📂 src/app/core (The Singleton Layer)
Contiene elementos que se instancian una sola vez y son transversales a toda la app.
* **Config:** `app.config.ts` (Global Providers, Icon Registry).
* **Auth:** auth.interceptor (inyecta JWT), auth.guard (protección de rutas).
* **Services:** AuthService (manejo de sesión), LayoutService (Estado del Sidebar).

📂 src/app/features/pista
Aquí vive el negocio. Cada carpeta es un módulo autocontenido.

| Módulo | Componente | Responsabilidad | Componente Clave |
| --- | --- | --- | --- |
| Operations | IceMonitor | Visualización en tiempo real (Signals). Polling inteligente (30s). |  |
|  | EntryForm | Interfaz "Touch-First" para registro rápido de patines. |  |
|  | CheckoutModal | **Cálculo de "Medianoche"** (soporte para turnos que cruzan de día) y regla Zamboni. |  |
| ShiftReport | Dashboard financiero. Filtros de fecha ISO compatibles con n8n. |  |  |
|  | ClientList | Directorio de alumnos y gestión de membresías. |  |

📂 src/app/shared (Reusability)
* **Sidebar:** Componente inteligente con estado colapsable (Mini-Sidebar) y gestión de temas (Dark/Light).

---

## 3. Capa de Negocio: Workflows de n8n Especializados

La lógica pesada reside en el backend, permitiendo cambios en reglas de negocio sin redesplegar el frontend.

**Workflow: ** Transaction Engine
* Trigger: Llamadas API desde Angular.
* Lógica:
1. Valida disponibilidad de patín (ph_inventory).
2. Si es ALUMNO, verifica membership_expiry.
3. Registra start_time en ph_transactions.
* Output: Confirmación y generación de ticket de entrada.

**Workflow 10:** MetaCRUD & Reporting
* Trigger: Consulta de reportes diarios.
* **Build Query Logic:** Nodo Javascript personalizado capaz de detectar fechas ISO (`YYYY-MM-DD`) y aplicar casting `::date` en PostgreSQL para ignorar horas en los filtros de reporte.

---

## 4. Modelo de Datos (PostgreSQL Schema)

Aprovechando la migración que realizamos hoy, la base de datos es el ancla de la soberanía de datos:

**Entidades Principales (** *public* **schema)**
* **ph_clients:** Maestro de identidades con soporte para membership_expiry y is_vip.
* **ph_transactions:** El log de actividad. Soporta `metadata` (JSONB) para flexibilidad futura (ej: notas, promociones aplicadas).
* **ph_inventory:** Control dual de consumibles y activos.

---

## 5. 📈 Roadmap de Implementación

```
Fase 1: Core Operativo (Completado)
    * Despliegue de los componentes de Angular: IceLiveMonitor y EntryForm.
    * Activación de los Workflows de n8n para Check-in/Check-out.

Fase 2: Estabilización y Finanzas (Completado - v0.5.2)
    * Solución de bugs críticos de tiempo (Midnight Crossing).
    * Reportes financieros precisos con filtros de fecha corregidos en backend.
    * UX Refinada: Sidebar colapsable y Dark Mode nativo.

Fase 3: IA & Analytics (Futuro)
    * Dashboard de analítica sobre rentabilidad por hora.
    * Agente de IA para consultas de disponibilidad vía WhatsApp.

Document generated regarding the v0.6.0 codebase state.