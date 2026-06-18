# 🏛️ Architecture Overview: Agro ERP Suite

## 📝 Descripción

**Project:** Hosting3M Automation Suite (Agro ERP)
**Version:** v1.7.0 (Multi-Domain & Hybrid Telemetry)
**Stack:** Angular 21 (Signals) | n8n (API Gateway / MCP) | PostgreSQL (JSONB & Views) | Tabler UI
**Author:** Francisco Jesus Pérez Pimienta

El módulo **agro-erp** evoluciona la plataforma hacia un modelo Multi-Negocio. Se diseñó bajo el principio de "Lean Architecture" y "Feature-Driven Routing", asegurando que el cliente web sea ultra-ligero y asilado por dominio de negocio (Ganadería vs Agricultura).

---

## 1. 🗺️ High-Level Design (Data Flow)

El sistema utiliza un patrón de acceso a datos híbrido: relacional estricto para la integridad multi-tenant, y columnas JSONB para la telemetría dinámica de campo, orquestado por el motor Meta-CRUD.

```mermaid
graph TD
    subgraph "Frontend Layer (Angular 21 - Lazy Loaded)"
        CS["Context Switcher (TenantService)"]
        UI_Cattle["Livestock Features (Biomasa, Sanidad)"]
        UI_Palm["Agriculture Features (Drones, Hectáreas)"]
        Signals["State Management (Computed Signals)"]
        
        CS -->|Inyecta ID & Theme| Signals
        UI_Cattle <--> Signals
        UI_Palm <--> Signals
    end

    subgraph "Integration Layer (n8n Meta-CRUD v3)"
        Auth["JWT Validator (core-auth)"]
        Router["Dynamic Model Router"]
        
        Signals -->|HTTP POST + tenant_id| Auth
        Auth --> Router
    end
    
    subgraph "Persistence & BI Layer (PostgreSQL 15)"
        Table_Cattle[("Raw Tables: cattle_livestock, health")]
        Table_Palm[("Hybrid Tables: agriculture_telemetry (JSONB)")]
        View_BI{{"BI Engine: vw_cattle_kpi, vw_palm_kpi"}}
        
        Router -->|Insert/Update| Table_Cattle
        Router -->|Insert/Update| Table_Palm
        Router -->|Select/GetAll| View_BI
    end