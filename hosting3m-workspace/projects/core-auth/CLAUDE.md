# 🏛️ CLAUDE.md - Core Auth Library Governance & Technical Baseline

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Architect & Project Lead).
- **Claude's Operating Mode:** Cyber-Security & IAM (Identity & Access Management) Architect.
- **Language Guardrail:** Accept prompts, compliance requirements, and security rules in Spanish. ALWAYS generate security code, Interceptors, Guards, interfaces, and git logs strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **MULTI-TENANT ISOLATION SAFETY:** Absolute restriction. The `AuthInterceptor` must fail-closed. If an outgoing HTTP request lacks a resolved `id_company` inside the active `CompanyContext` or missing JWT, it must halt or throw an immediate context initialization exception before escaping to the central Hosting3M API to prevent cross-tenant data contamination.
- **Zero-Config Security Logic:** Under no circumstances should this library store hardcoded API URLs, Client Secrets, or default system keys. Environment integration must rely exclusively on the `AUTH_ENV_CONFIG` InjectionToken provided by the host application (`apiUrl_crud`, `apiUrl_token`, `system_id`).
- **Token Leakage Guard:** Never expose plain-text JWT tokens or internal session states to global `window` logs or insecure client-side diagnostic outputs.

## 💻 Tech Stack & Security Constraints
- **Core Framework:** Angular 21 utilizing modern functional Interceptors and Standalone Security Guards (strictly No NgModules).
- **State Architecture:** Multi-tenant state and token resolution handled reactively via `AuthService` and `TenantService`. 
- **Egress Pipeline:** Centralized dynamic header injection appending `Authorization: Bearer <token>` and the custom Active Tenant ID header dynamically to all downstream REST requests hitting the central PostgreSQL/n8n gateway.

## 🔧 Build & Workspace Commands
- **Compile Module:** `ng build core-auth` (Critical prerequisite for building or local servicing the `dashboard` or any consumer app).

## 📝 IAM Contracts & Token Checklist
- **Environment Interface (`AuthEnvironmentConfig`):** Ensure compliance mapping covers `apiUrl_crud` (Dynamic CRUD endpoint), `apiUrl_token` (JWT Auth endpoint), and `system_id` (Unique identifier for context switching, e.g., `'hotel_app'`).
- **Tenant Context Schema (`CompanyContext`):** The operational runtime identity must map strictly to `id_company` (Required), `company_name` (Required), and `role` (Required IAM scope).
- **Tenant Selector UI Pattern:** The `TenantSelectorComponent` must operate stateless-ready. It should listen directly to `TenantService` company arrays to trigger safe context switching via full reactive state propagation, forcing the host view layer to cleanly re-evaluate permissions without reloading the layout wrapper.