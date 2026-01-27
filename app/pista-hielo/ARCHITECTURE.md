# ⛸️ Architecture Overview: PistaHielo Operations Center

## 📝 Descripción
**Project:** PistaHielo Dashboard (Módulo de la Suite Hosting3M)
**Version:** v0.5 (Beta Operativa)
**Stack:** Angular 21 (Signals & SSR Safe) | n8n v2.1.4 (Orquestador) | PostgreSQL (pgvector)
**Patrón Arquitectónico:** Layout Shell Pattern + Event-Driven State Machine.
**Author:** Francisco Jesus Pérez Pimienta

**Pista de Hielo** es una aplicación web progresiva (PWA) de alto rendimiento, diseñada como la interfaz administrativa oficial de la suite de automatización Hosting3M. Integra operaciones de tiempo real con control financiero estricto.

## 1. Diseño de Alto Nivel: Flujo de Navegación y Datos
La arquitectura implementa un **"Main Layout Shell"** que mantiene el contexto de navegación (Menú/Sidebar) mientras el usuario alterna entre operaciones de pista y administración financiera.

```mermaid
graph TD
    User[Operador / Admin] -->|HTTPS + JWT| SHELL[MainLayout Shell (Sidebar + Header Mobile)]
    
    subgraph "Frontend (Angular 21)"
    SHELL -->|Router Outlet| OPS[Módulo Operations]
    SHELL -->|Router Outlet| ADMIN[Módulo Admin]
    
    OPS -->|Signals| MON[IceMonitor (Live Rack)]
    OPS -->|Form| ENT[EntryForm (Touch UI)]
    OPS -->|Modal| CHK[CheckoutComponent]
    
    ADMIN -->|Service| REP[ShiftReport (Corte Z)]
    ADMIN -->|CRUD| CLI[ClientDirectory]
    end

    CHK -->|POST Update| N8N[n8n Automation Engine]
    REP -->|POST Filter| N8N
    
    N8N -->|SQL: Transactions/Clients| PG[(PostgreSQL)]
```

### Principios Clave:
1. **Layout Shell Architecture:** Un componente padre (MainLayout) gestiona la estructura visual, la responsividad móvil (hamburguesa) y la sesión, desacoplando la navegación de la lógica de negocio.

2. **SSR Safe Polling:** El monitor en vivo utiliza isPlatformBrowser para evitar fugas de memoria y errores de "Injector Destroyed" en entornos de Server-Side Rendering.

3. **Smart Date Filtering:** Solución al problema de Zona Horaria mediante el uso de formatos ISO locales (sv-SE) para garantizar la precisión de los reportes financieros diarios.

---

## 2. Frontend Structure (Modular Architecture)
La aplicación se ha reestructurado en dominios funcionales claros:

📂 src/app/core (The Singleton Layer)
Contiene elementos que se instancian una sola vez y son transversales a toda la app.
    * Auth: auth.interceptor (inyecta JWT), auth.guard (protección de rutas).
    * Models: Interfaces globales (hotel.types.ts, api-response).
    * Services: AuthService (manejo de sesión).

📂 src/app/features/pista
Aquí vive el negocio. Cada carpeta es un módulo autocontenido.

| Módulo | Componente | Responsabilidad | Componente Clave | 
| :--- | :--- | :--- | :--- | 
| Operations | IceMonitor | Visualización en tiempo real (Signals). Polling inteligente (30s). | 
| | EntryForm | Interfaz "Touch-First" para registro rápido de patines. | 
| | CheckoutModal | Cálculo de tiempo, regla "Zamboni" y cierre de transacción. |
| ShiftReport | Dashboard financiero. Suma de efectivo vs tarjeta en tiempo real. |
| | ClientList | Directorio de alumnos y gestión de membresías. |


📂 src/app/shared (Reusability)
    * MainLayout: Contenedor principal con lógica de menú responsivo (Tabler Vertical).

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

**Workflow 10:** ph-checkout-pricing-engine
    * Trigger: Acción de "Cierre" desde el Dashboard.
    * Lógica de Ingeniería:
        1. Calcula delta de tiempo (end_time - start_time).
        2. Filtro Zamboni: Resta automáticamente 15 min si el flag zamboni es TRUE.
        3. Promotions Engine: Aplica lógica de Hermanos (20%/30% desc) si hay múltiples IDs vinculados.
        4. Saneamiento: Registra el pago en ph_payments con el ID del Corte X actual.

---

## 4. Modelo de Datos (PostgreSQL Schema)
Aprovechando la migración que realizamos hoy, la base de datos es el ancla de la soberanía de datos:

**Entidades Principales (** *public* **schema)**
    * **ph_clients:** Maestro de identidades con soporte para membership_expiry y is_vip.
    * **ph_inventory:** Control dual de consumibles (venta) y activos (renta de patines).
    * **ph_transactions:** El log de actividad con estados ACT, PAG, CAN.
    * **ph_payments:** El flujo de efectivo real para auditoría.
    * **ph_closures:** El control jerárquico de Cortes X e Y.

---

## 5. Integración con la Suite n8n Enterprise (IA & WhatsApp)
Como experto en IA, esta arquitectura habilita casos de uso avanzados:
Separación de responsabilidades para la gestión de reservas:
    1. **WhatsApp Bot (Módulo 05):** Un padre de familia puede preguntar: "¿A qué hora sale mi hijo de la pista?". El agente de IA usa el MCP para consultar ph_transactions y responder en tiempo real.

    2. **Notificaciones Proactivas:** n8n monitorea ph_clients y envía un mensaje automático vía WhatsApp 3 días antes de que venza la mensualidad del alumno.

    3. **Análisis Predictivo:** Uso de los datos históricos para predecir cuántos patines de cada número se necesitarán en un sábado de alta afluencia.


## 6. 📈 Roadmap de Implementación
    Fase 1: Core Operativo (Semana 1)
        * Despliegue de los componentes de Angular: IceLiveMonitor y EntryForm.
        * Activación de los Workflows de n8n para Check-in/Check-out.

    Fase 2: Administración y Cierres (Semana 2)
        * Módulo de ph_closures para automatizar los Cortes X e Y.
        * Integración del sistema de "Clave de Supervisor" mediante roles de JWT (RBAC).
        * Fase 3: IA & Analytics (Futuro)
        * Dashboard de analítica sobre rentabilidad por hora y ocupación de pista.


Document generated regarding the v0.5 codebase state.