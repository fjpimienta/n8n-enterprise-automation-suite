# 🏛️ Architecture Overview: Cattle Dashboard

## 📝 Descripción

**Project:** Hosting3M Automation Suite (Cattle Dashboard / Ganadería Digital)
**Version:** v1.6.0 (Multi-Species & Stateful AI)
**Stack:** Angular 21 (Signals) | n8n (API Gateway / MCP) | PostgreSQL (JSONB & Views) | Tabler UI
**Author:** Francisco Jesus Pérez Pimienta

El módulo **agro-erp** introduce capacidades de ERP Agropecuario al Monorepositorio de Hosting3M. Se diseñó bajo el principio de "Lean Architecture" y delegación computacional, asegurando que el cliente web sea ultra-ligero y el servidor asuma la carga analítica.

---

## 1. 🗺️ High-Level Design (Data Flow)

El sistema utiliza un patrón de acceso a datos híbrido: transaccional puro para escrituras, y vistas pre-computadas para lecturas, orquestado completamente por n8n.

```mermaid
graph TD
    subgraph "Frontend Layer (Angular 21)"
        UI["Tabler Dashboards & Modals"]
        Forms["Reactive Forms (Alta, Peso, Salud)"]
        Signals["State Management (Signals)"]
        
        UI <--> Signals
        Forms --> Signals
    end

    subgraph "Integration Layer (n8n Meta-CRUD)"
        Auth["JWT Validator"]
        Router["Dynamic Table Router"]
        
        Signals -->|HTTP POST| Auth
        Auth --> Router
    end
    
    subgraph "Persistence & BI Layer (PostgreSQL 15)"
        Tables[("Raw Tables: cattle_livestock, health, weight")]
        View{{"BI Engine: vw_cattle_kpi"}}
        
        Router -->|Insert/Update| Tables
        Router -->|Select/GetAll| View
        Tables -.->|Pre-compute ADG & Gestation| View
    end