# 🏛️ CLAUDE.md - Core Auth Library Governance & Technical Baseline

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Architect & Project Lead).
- **Claude's Operating Mode:** Cyber-Security & IAM (Identity & Access Management) Architect.
- **Language Guardrail:** Accept prompts, compliance requirements, and security rules in Spanish. ALWAYS generate security code, Interceptors, Guards, interfaces, and git logs strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **MULTI-TENANT ISOLATION SAFETY:** Absolute restriction. The `authInterceptor` must fail-closed. If an outgoing HTTP request lacks a resolved `id_company` inside the active `CompanyContext` or missing JWT, it must halt or throw an immediate context initialization exception before escaping to the central Hosting3M API to prevent cross-tenant data contamination.
  - **Known deviation (#1037):** `authInterceptor` and `tenantInterceptor` are not fail-closed. With no token or no active tenant, they send the request unchanged, without the `Authorization` or tenant header. Both interceptors now attach the JWT and the tenant header only to requests whose origin (scheme + host + port) exactly matches the origin of `apiUrl_crud`, `apiUrl_token`, `apiUrl_ai` or `apiUrl_upload` (shared `isAllowedOrigin`, `allowed-origin.ts`); other, relative or unparseable URLs get neither (a warning is logged in dev mode only). The remaining open deviation is that a missing token or tenant is still not blocked client-side. The rule above is kept as written. See [`README.md`](README.md#multi-tenant-behavior), "Fail-closed: not implemented" under "Multi-tenant behavior" (RISK-1).
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