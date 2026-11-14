# 🏛️ CLAUDE.md - Core Auth Library Governance & Technical Baseline

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Architect & Project Lead).
- **Claude's Operating Mode:** Cyber-Security & IAM (Identity & Access Management) Architect.
- **Language Guardrail:** Accept prompts, compliance requirements, and security rules in Spanish. ALWAYS generate security code, Interceptors, Guards, interfaces, and git logs strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **MULTI-TENANT ISOLATION SAFETY:** Absolute restriction. The `authInterceptor` must fail-closed. If an outgoing HTTP request lacks a resolved `id_company` inside the active `CompanyContext` or missing JWT, it must halt or throw an immediate context initialization exception before escaping to the central Hosting3M API to prevent cross-tenant data contamination.
  - **Current behavior (#1037):** protected requests on allowed origins now fail closed: `authInterceptor` rejects `401 No auth token` when no JWT is present, and `tenantInterceptor` rejects `403 No active tenant` when there is no valid active tenant (`id_company` must be a positive integer). Both interceptors still attach credentials only to exact-origin matches for `apiUrl_crud`, `apiUrl_token`, `apiUrl_ai` or `apiUrl_upload` via `isAllowedOrigin` in [`allowed-origin.ts`](src/lib/allowed-origin.ts). Only two public routes are exempt, matched per request (method, exact origin and path, body fields): the exact `apiUrl_token` POST (login) and the CRUD `POST <apiUrl_crud>/companys` with `operation: 'getall'` on `companys` (see [`allowed-origin.ts`](src/lib/allowed-origin.ts)). Every other request, including other `companys` operations, must carry a JWT and an active tenant. `login()` also maps HTTP 200 with `error: true` to an error. `setActiveTenant()` still does not validate against `availableTenants` or the JWT, so the server remains the final arbiter of tenant membership. See [`README.md`](README.md#multi-tenant-behavior).
- **Zero-Config Security Logic:** Under no circumstances should this library store hardcoded API URLs, Client Secrets, or default system keys. Environment integration must rely exclusively on the `AUTH_ENV_CONFIG` InjectionToken provided by the host application (`apiUrl_crud`, `apiUrl_token`, `apiUrl_ai`, `system_id`).
- **Token Leakage Guard:** Never expose plain-text JWT tokens or internal session states to global `window` logs or insecure client-side diagnostic outputs.

## 💻 Tech Stack & Security Constraints
- **Core Framework:** Angular 21 utilizing modern functional Interceptors and Standalone Security Guards (strictly No NgModules).
- **State Architecture:** Multi-tenant state and token resolution handled reactively via `AuthService` and `TenantService`. 
- **Egress Pipeline:** Centralized dynamic header injection appending `Authorization: Bearer <token>` and the custom Active Tenant ID header dynamically to all downstream REST requests hitting the central PostgreSQL/n8n gateway.

## 🔧 Build & Workspace Commands
- **Compile Module:** `ng build core-auth` (Critical prerequisite for building or local servicing the `dashboard` or any consumer app).

## 📝 IAM Contracts & Token Checklist
- **Environment Interface (`AuthEnvironmentConfig`):** Ensure compliance mapping covers `apiUrl_crud` (Dynamic CRUD endpoint), `apiUrl_token` (JWT Auth endpoint), `apiUrl_ai` (required, AI endpoint), and `system_id` (Unique identifier for context switching, e.g., `'hotel_app'`). `apiUrl_upload` is optional (upload-file service); `authInterceptor` attaches the JWT to it only when the host sets it. Source: [`auth.config.ts`](src/lib/auth.config.ts).
- **Tenant Context Schema (`CompanyContext`):** The operational runtime identity must map strictly to `id_company` (Required), `company_name` (Required), and `role` (Required IAM scope).
- **Tenant Selector UI Pattern:** The `TenantSelectorComponent` must operate stateless-ready. It should listen directly to `TenantService` company arrays to trigger safe context switching via full reactive state propagation, forcing the host view layer to cleanly re-evaluate permissions without reloading the layout wrapper. Current state: no `TenantSelectorComponent` exists under `src/lib`, and none is exported from [`src/public-api.ts`](src/public-api.ts); in the workspace, only `agro-erp` defines its own `TenantSelectorComponent` ([`tenant-selector.component.ts`](../agro-erp/src/app/shared/components/tenant-selector/tenant-selector.component.ts), used in `header.component.ts`); no other app defines one.