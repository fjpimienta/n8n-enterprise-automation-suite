# Core Auth Shared Library 🔐

![Angular](https://img.shields.io/badge/Angular-21%2B-red) ![Pattern](https://img.shields.io/badge/Architecture-Standalone-orange) ![Status](https://img.shields.io/badge/Status-Beta-blue)

## 📖 Executive Summary
**Core Auth** is a reusable, multi-tenant Angular library designed to manage authentication, route guarding, and IAM (Identity and Access Management) context across Hosting3M applications. 

It abstracts the complexity of token management and tenant selection (Multi-empresa), ensuring a standardized security layer for applications like the Hotel Dashboard and agro-erp.

## ⚡ Key Features
* **Multi-Tenant Context:** Built-in `CompanyContext` management supporting multi-company environments (`id_company`, `company_name`, `role`)[cite: 29].
* **Standalone Architecture:** Fully compatible with modern Angular using standalone components and functional interceptors.
* **Zero-Config Logic:** Relies on the consuming app to provide environment variables via the `AUTH_ENV_CONFIG` InjectionToken[cite: 29].
* **Integrated Security:** Ships with `authGuard`, `roleGuard`, `authInterceptor` and `tenantInterceptor`. `authInterceptor` attaches the JWT only to requests under the configured API base URLs; `tenantInterceptor` attaches the active company header to all outgoing requests. Both must be registered by the host (see Setup). Neither one is fail-closed (see [Multi-tenant behavior](#multi-tenant-behavior)).

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
| `UserPayload` | interface | `id`, `email`, `role`, `id_company`, `name`. Decoded from the JWT ([`auth.service.ts`](src/lib/services/auth.service.ts)) |
| `AuthService` | service | `login()`, `logout()`, `getStoredToken()`, `hasRole()`, signals `currentUser` and `isAuthenticated` |
| `TenantService` | service | `availableTenants`, `activeTenant`, `activeTenantId`, `setAvailableTenants()`, `setActiveTenant()`, `clearContext()`, `hydrate()` |
| `authGuard` | `CanActivateFn` | Allows navigation when a non-expired token exists; otherwise redirects to `/login` |
| `roleGuard(roles)` | factory returning `CanActivateFn` | Requires an authenticated user whose JWT role is in `roles` (case-insensitive); otherwise redirects to `/login` or `/unauthorized` |
| `authInterceptor` | `HttpInterceptorFn` | Adds `Authorization: Bearer <token>` to requests under the configured API base URLs; handles HTTP 401 |
| `tenantInterceptor` | `HttpInterceptorFn` | Adds `X-Tenant-ID` and `x-tenant-id` when an active tenant is set |
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
    // TODO(verify): exact payload shape of the select_company response.
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
  must be enforced server-side by the gateway. TODO(verify): confirm the `x-tenant-id` membership
  check in the n8n gateway workflows for this suite.
- **Propagation.** [`tenant.interceptor.ts`](src/lib/interceptors/tenant.interceptor.ts)
  sets `X-Tenant-ID` and `x-tenant-id` on every outgoing `HttpClient` request when an active tenant
  exists. It does not filter by URL, so the header is sent to any host the app calls.
- **Fail-closed: not implemented.** The project governance requires fail-closed behavior, but the
  code does not provide it:
  - [`auth.interceptor.ts`](src/lib/auth/auth.interceptor.ts)
    sends the request without `Authorization` when there is no token or the URL is not a protected
    base URL.
  - `tenantInterceptor` sends the request without tenant headers when there is no active tenant.

  In both cases the request is sent unchanged, without the missing credential or header. See RISK-1.
- **Logout** clears the active tenant and the available tenant list.
- **Isolation statement.** Client-side headers and guards are not a data isolation boundary. Do not
  rely on them for tenant isolation.

## Error handling

- **HTTP 401** (`authInterceptor`): if `getStoredToken()` returns no token (missing or expired, which
  also logs out), the interceptor calls `logout()` and navigates to `/login`. If a token still exists,
  it logs a `console.warn` and does not log out. The error is always re-thrown to the caller.
- **Other HTTP errors** are re-thrown unchanged.
- **`login()`** stores the token and sets the signals only when `res.status === 'success'` and
  `res.data.token` is present. Any other response, including HTTP 200 with `error: true` from the
  Meta-CRUD gateway, is passed to the subscriber without an error. The caller must inspect `status`.
  The library does not handle the `error: true` contract (see RISK-2).
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

The project has seven spec files under [`src/lib`](src/lib/).
TODO(verify): confirm that the suite passes on the current `main` branch.

## Limitations and TODO(verify)

- **RISK-1 (fail-closed).** See [Multi-tenant behavior](#multi-tenant-behavior). The governance rule
  and the implementation differ.
- **RISK-2 (gateway errors).** `login()` and the interceptors do not treat HTTP 200 with `error: true`
  as an error.
- **RISK-3 (token storage).** The JWT is stored in `localStorage` under `authToken`. Any script running
  in the page can read it.
- **RISK-4 (prefix match).** `authInterceptor` uses `req.url.startsWith(baseUrl)`. A base URL without a
  trailing slash also matches look-alike hosts, which would receive the token. Keep base URLs as exact
  origins and paths.
- **RISK-5 (missing peer dependencies).** `package.json` declares only `@angular/common` and
  `@angular/core` as peers. The source imports `@angular/router`, `rxjs` and `jwt-decode`.
  TODO(verify): confirm how consumers get `jwt-decode` and whether the build bundles it.
- **Placeholder component.** `CoreAuth` (`lib-core-auth`) is re-exported by
  [`src/lib/core-auth.ts`](src/lib/core-auth.ts) and renders
  placeholder text. TODO(verify): remove it from the public API in a separate change.
- **Two company shapes.** `CompanyContext` (`auth.config.ts`) and `TenantContext` (`tenant.service.ts`)
  describe the same concept with different fields. TODO(verify): confirm which one the login response uses.
- **Role source.** `roleGuard` reads the JWT role, not the active company role. TODO(verify): confirm
  the intended behavior with consuming apps.
- **`localStorage.role`** is removed on logout but never written by the library. TODO(verify): confirm
  whether a consuming app writes it.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---

*Built with the assistance of AI-powered development tools.*
