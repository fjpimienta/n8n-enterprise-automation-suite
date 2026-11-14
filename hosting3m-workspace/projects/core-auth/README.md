# Core Auth Shared Library 🔐

![Angular](https://img.shields.io/badge/Angular-21%2B-red) ![Pattern](https://img.shields.io/badge/Architecture-Standalone-orange) ![Status](https://img.shields.io/badge/Status-Beta-blue)

## 📖 Executive Summary
**Core Auth** is a reusable, multi-tenant Angular library designed to manage authentication, route guarding, and IAM (Identity and Access Management) context across Hosting3M applications. 

It abstracts the complexity of token management and tenant selection (Multi-empresa), ensuring a standardized security layer for applications like the Hotel Dashboard and agro-erp.

## ⚡ Key Features
* **Multi-Tenant Context:** Built-in `CompanyContext` management supporting multi-company environments (`id_company`, `company_name`, `role`)[cite: 29].
* **Standalone Architecture:** Fully compatible with modern Angular using standalone components and functional interceptors.
* **Zero-Config Logic:** Relies on the consuming app to provide environment variables via the `AUTH_ENV_CONFIG` InjectionToken[cite: 29].
* **Integrated Security:** Ships with `authGuard`, `roleGuard`, `authInterceptor` and `tenantInterceptor`. Both interceptors attach the JWT / the active company header only to requests whose origin exactly matches the origin of `apiUrl_crud`, `apiUrl_token`, `apiUrl_ai` or `apiUrl_upload`. Both must be registered by the host (see Setup). Neither one is fail-closed (see [Multi-tenant behavior](#multi-tenant-behavior)).

## 🛠 Installation & Integration

### 1. Configuration & Provisioning (Crucial Step) ⚠️
Since the library is stateless, you **MUST** provide the configuration token in your `app.config.ts`.

```typescript
import { ApplicationConfig } from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { AUTH_ENV_CONFIG, AuthEnvironmentConfig, authInterceptor, tenantInterceptor } from 'core-auth';
import { environment } from '../environments/environment';

const authConfig: AuthEnvironmentConfig = {
  apiUrl_crud: environment.apiUrl_crud,
  apiUrl_token: environment.apiUrl_token,
  apiUrl_ai: environment.apiUrl_ai,
  apiUrl_upload: environment.apiUrl_upload, // Optional: only for apps that upload files
  system_id: 'hotel_app' // Unique identifier for the consuming app
};

export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(withInterceptors([authInterceptor, tenantInterceptor])),
    {
      provide: AUTH_ENV_CONFIG,
      useValue: authConfig
    }
  ]
};

```

### 2. Tenant context and exported API

`core-auth` exports `TenantService` and the `CompanyContext` type for managing the active
company context. It does **not** export a `TenantSelectorComponent`; host applications
provide their own selection UI when needed.

```typescript
import { CompanyContext, TenantService } from 'core-auth';
```

The public API also exports `AuthService`, `authGuard`, `roleGuard`, `authInterceptor`, and
`tenantInterceptor` (all re-exported from [`src/public-api.ts`](src/public-api.ts)).
Register `authInterceptor` and `tenantInterceptor` explicitly with
`provideHttpClient(withInterceptors([...]))`; the library does not register them automatically.

| Name | Kind | Description |
|------|------|-------------|
| `AUTH_ENV_CONFIG` | `InjectionToken<AuthEnvironmentConfig>` | Host-provided configuration. Source: [`auth.config.ts`](src/lib/auth.config.ts) |
| `AuthEnvironmentConfig` | interface | `apiUrl_crud`, `apiUrl_token`, `apiUrl_ai`, `apiUrl_upload?`, `system_id` |
| `CompanyContext` | interface | `id_company`, `company_name`, `role` |
| `TenantContext` | interface | `id_company`, `company_name`, `role`, `industry`, `business_type`. Shape stored by `TenantService` ([`tenant.service.ts`](src/lib/services/tenant.service.ts)) |
| `UserPayload` | interface | `id`, `email`, `role`, `id_company`, `name`. Decoded from the JWT ([`auth.service.ts`](src/lib/services/auth.service.ts)). The JWT issued by `jwt-service` carries `user`, `name`, `id_company`, `role` and `system_id` (`jwt-service/index.js:151-158`): it has no `id` and no `email`, so those fields are not set from login. |
| `AuthService` | service | `login()`, `logout()`, `getStoredToken()`, `hasRole()`, signals `currentUser` and `isAuthenticated` |
| `TenantService` | service | `availableTenants`, `activeTenant`, `activeTenantId`, `setAvailableTenants()`, `setActiveTenant()`, `clearContext()`, `hydrate()` |
| `authGuard` | `CanActivateFn` | Allows navigation when a non-expired token exists; otherwise redirects to `/login` |
| `roleGuard(roles)` | factory returning `CanActivateFn` | Requires an authenticated user whose JWT role is in `roles` (case-insensitive); otherwise redirects to `/login` or `/unauthorized` |
| `authInterceptor` | `HttpInterceptorFn` | Adds `Authorization: Bearer <token>` to requests whose origin matches a configured API origin; handles HTTP 401 |
| `tenantInterceptor` | `HttpInterceptorFn` | Adds `X-Tenant-ID` and `x-tenant-id` when an active tenant is set and the request origin matches a configured API origin |
| `CoreAuth` | component (`lib-core-auth`) | Placeholder generated with the library. Not a feature; see [Limitations](#limitations-and-todoverify) |

`TenantSelectorComponent` is not part of the public API. Host applications provide their own
selection UI.

## Usage

### Route protection

```ts
import { Routes } from '@angular/router';
import { authGuard, roleGuard } from 'core-auth';

export const routes: Routes = [
  {
    path: 'admin',
    canActivate: [authGuard, roleGuard(['ADMIN', 'EDITOR'])],
    loadComponent: () => import('./admin/admin.component').then(m => m.AdminComponent)
  }
];
```

`roleGuard` compares the role from the JWT (`AuthService.currentUser()`), not the role of the
active company.

### Login and company selection

```ts
import { AuthService, TenantService } from 'core-auth';

this.authService.login({ user: email, pass: password }).subscribe(res => {
  if (res.status === 'select_company') {
    // The host shows its own selector, then calls login() again with id_company.
    // Payload: res.data.companies, an array of { id_company, company_name, role, industry }; no token (jwt-service/index.js:132).
    return;
  }
  // status === 'success': the token is stored and currentUser() is set.
});

this.tenantService.setAvailableTenants(tenants); // TenantContext[]
this.tenantService.setActiveTenant({
  id_company: <COMPANY_ID>, // number
  company_name: '<COMPANY_NAME>',
  role: '<ROLE>',
  industry: '<INDUSTRY>',
  business_type: '<BUSINESS_TYPE>' // 'AGRICULTURE' | 'LIVESTOCK' | 'ADMIN'
});
```

### Logout

```ts
this.authService.logout();
```

`logout()` removes the `authToken` and `role` keys from `localStorage`, resets the user and
authentication signals, and calls `TenantService.clearContext()`.

## Multi-tenant behavior

- **Where `id_company` comes from.** Two sources, not reconciled by the library: the JWT claim
  (`UserPayload.id_company`, decoded in [`auth.service.ts`](src/lib/services/auth.service.ts))
  and the active tenant set by the host with `TenantService.setActiveTenant()`, persisted in
  `localStorage` under `active_tenant_context`
  ([`tenant.service.ts`](src/lib/services/tenant.service.ts)).
- **Validation.** The library does not validate `id_company`. `setActiveTenant()` accepts any object
  and does not check that the company is in `availableTenants` or matches the JWT. `activeTenantId`
  is `activeTenant()?.id_company || null`, so `0` is treated as no tenant. The authoritative check
  must be enforced server-side by the gateway. The `v6/CRUD` gateway checks `x-tenant-id` against an
  active `user_companies` membership (`Get Membresia` and `Existe Membresia` in
  `workflows/06-dynamic-crud-engine/v6/v6-crud.json`; non-members get `403 TENANT_FORBIDDEN`).
- **Propagation.** [`tenant.interceptor.ts`](src/lib/interceptors/tenant.interceptor.ts)
  sets `X-Tenant-ID` and `x-tenant-id` on an outgoing `HttpClient` request when an active tenant
  exists and the request origin exactly matches the origin of `apiUrl_crud`, `apiUrl_token`,
  `apiUrl_ai` or `apiUrl_upload`. Other, relative or unparseable URLs get no header (a warning is
  logged in dev mode only).
  Note: `companys getall` is public in the gateway (`v6/CRUD`) and uses neither tenant nor membership, so the missing header does not affect it (Refs #1064).
- **Fail-closed behavior.** Protected requests on allowed origins now fail closed:
  - [`auth.interceptor.ts`](src/lib/auth/auth.interceptor.ts) rejects the request with `401 No auth token`
    when no JWT is present.
  - [`tenant.interceptor.ts`](src/lib/interceptors/tenant.interceptor.ts) rejects the request with `403 No active tenant`
    when there is no valid positive `id_company` in the active tenant context.
  - Two public routes are exempt from both checks, and only these: (1) `POST` to the exact `apiUrl_token` endpoint (login);
    (2) `POST` to `<apiUrl_crud>/companys` with a body where `operation` is `getall` and `entity` and/or `table_name` are
    `companys` (the public company directory). Exemption is decided per request by method, exact origin and path, and
    body fields (`isExemptRoute` in [`allowed-origin.ts`](src/lib/allowed-origin.ts)); a shared origin does not exempt
    other routes, and other `companys` operations (`getone`, `insert`, `update`, `delete`) or other tables are not exempt.
    Exempt requests get neither the JWT nor the tenant header.

  The server remains the final authority for membership validation and authorization. See RISK-1.
- **Logout** clears the active tenant and the available tenant list.
- **Isolation statement.** Client-side headers and guards are not a data isolation boundary. Do not
  rely on them for tenant isolation.

## Error handling

- **HTTP 401** (`authInterceptor`): if `getStoredToken()` returns no token (missing or expired, which
  also logs out), the interceptor calls `logout()` and navigates to `/login`. If a token still exists,
  it logs a `console.warn` and does not log out. The error is always re-thrown to the caller.
- **Other HTTP errors** are re-thrown unchanged.
- **`login()`** stores the token and sets the signals only when `res.status === 'success'` and
  `res.data.token` is present. An HTTP 200 response with a top-level `error: true` is turned into an
  error (`Error` with `error: true` and the raw `body`). Any other response is passed to the
  subscriber without an error, so the caller must inspect `status`. The interceptors do not handle
  the `error: true` contract (see RISK-2).
- **Token expiry** is evaluated at construction, on login, and on `getStoredToken()`. There is no timer,
  so `isAuthenticated()` can stay `true` after the token expires until a request reads the token.
- **Malformed storage**: an unparseable `authToken` is treated as expired. Unparseable
  `user_tenants` or `active_tenant_context` values are logged with `console.error` and ignored.
- **Numeric values**: `id_company` is typed as `number` in the library. The library does not parse
  numeric strings from the gateway; the host must do so when it reads gateway data.
- **Empty collections** (`data: [{}]`) are not handled by the library; it does not read collections.

## Testing

From the workspace root (`hosting3m-workspace/`):

```bash
ng test core-auth   # unit tests, target "test" in angular.json
ng build core-auth  # library build (ng-packagr)
```

The project has eight spec files under [`src/lib`](src/lib/). The runner is Vitest, configured by the
`@angular/build:unit-test` builder (`test` target in `angular.json`). On `fix/1037-core-auth-fail-closed`,
`ng test core-auth --watch=false` passes 46 of 46 tests. TODO(verify): confirm the same on `main`.

## Limitations and TODO(verify)

- **RISK-1 (fail-closed).** See [Multi-tenant behavior](#multi-tenant-behavior). The governance rule
  and the implementation differ.
- **RISK-2 (gateway errors) — partly mitigated (#1037).** `login()` now maps an HTTP 200 response whose
  top-level `error` is `true` to an error (message from `message`, `error_message` or a fixed fallback;
  nothing is stored). The interceptors still do not inspect response bodies.
- **RISK-3 (token storage).** The JWT is stored in `localStorage` under `authToken`. Any script running
  in the page can read it.
- **RISK-4 (prefix match) — mitigated (#1037).** Both interceptors compare the exact origin
  (`new URL(...).origin`) instead of a string prefix, so look-alike hosts and other ports or schemes get
  no token or tenant header. Matching is by origin only, not by path: any path on an allowed origin
  receives the credentials.
- **RISK-5 (missing peer dependencies).** `package.json` declares only `@angular/common` and
  `@angular/core` as peers. The source imports `@angular/router`, `rxjs` and `jwt-decode`.
  TODO(verify): confirm how consumers get `jwt-decode` and whether the build bundles it.
- **Placeholder component.** `CoreAuth` (`lib-core-auth`) is re-exported by
  [`src/lib/core-auth.ts`](src/lib/core-auth.ts) and renders
  placeholder text. TODO(verify): remove it from the public API in a separate change.
- **Two company shapes.** `CompanyContext` (`auth.config.ts`) and `TenantContext` (`tenant.service.ts`)
  describe the same concept with different fields. The `companies` list in the `select_company` response carries `id_company`, `company_name`, `role` and `industry` (`jwt-service/index.js:122-126`): `TenantContext` is the closer match (it also requires `business_type`), and `CompanyContext` has no `industry`.
- **Role source.** `roleGuard` reads the JWT role, not the active company role. TODO(verify): confirm
  the intended behavior with consuming apps.
- **`localStorage.role`** is removed on logout but never written by the library. No file in this repository writes it;
  `agro-erp` only reads it (`sidebar.component.ts:42`, fallback `EDITOR`). Writers outside this repository are not checked.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---

*Built with the assistance of AI-powered development tools.*
