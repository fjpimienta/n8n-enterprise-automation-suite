# Core Auth Shared Library 🔐

![Angular](https://img.shields.io/badge/Angular-21%2B-red) ![Pattern](https://img.shields.io/badge/Architecture-Standalone-orange) ![Status](https://img.shields.io/badge/Status-Beta-blue)

## 📖 Executive Summary
**Core Auth** is a reusable, multi-tenant Angular library designed to manage authentication, route guarding, and IAM (Identity and Access Management) context across Hosting3M applications. 

It abstracts the complexity of token management and tenant selection (Multi-empresa), ensuring a standardized security layer for applications like the Hotel Dashboard.

## ⚡ Key Features
* **Multi-Tenant Context:** Built-in `CompanyContext` management supporting multi-company environments (`id_company`, `company_name`, `role`)[cite: 29].
* **Standalone Architecture:** Fully compatible with modern Angular using standalone components and functional interceptors.
* **Zero-Config Logic:** Relies on the consuming app to provide environment variables via the `AUTH_ENV_CONFIG` InjectionToken[cite: 29].
* **Integrated Security:** Ships with a ready-to-use `AuthGuard` and `AuthInterceptor` to secure routes and outgoing HTTP requests automatically[cite: 27].

## 🛠 Installation & Integration

### 1. Configuration & Provisioning (Crucial Step) ⚠️
Since the library is stateless, you **MUST** provide the configuration token in your `app.config.ts`.

```typescript
import { ApplicationConfig } from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { AUTH_ENV_CONFIG, AuthEnvironmentConfig, authInterceptor } from 'core-auth';
import { environment } from '../environments/environment';

const authConfig: AuthEnvironmentConfig = {
  apiUrl_crud: environment.apiUrl_crud,
  apiUrl_token: environment.apiUrl_token,
  apiUrl_ai: environment.apiUrl_ai,
  system_id: 'hotel_app' // Unique identifier for the consuming app
};

export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(withInterceptors([authInterceptor])),
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

The public API also exports `AuthService`, `authGuard`, `roleGuard` (where available through
the public auth module), `authInterceptor`, and `tenantInterceptor`. Register
`authInterceptor` explicitly with `provideHttpClient(withInterceptors([...]))`; the tenant
header interceptor is a separate export and is not automatically registered by the library.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---

*Built with the assistance of AI-powered development tools.*
