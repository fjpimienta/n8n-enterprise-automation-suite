# Changelog

All notable changes to the `core-auth` library will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2026-06-04
### 🚀 Initial Release
First release of the authentication and multi-tenant management module for the Hosting3M Ecosystem[cite: 26]. 
Designed to act as a unified security bridge for applications like the Hotel App.

### ✨ Features
- **Tenant Management:** Created `CompanyContext` interface and `TenantService` for multi-company operations[cite: 27, 29].
- **UI Components:** Implemented `TenantSelectorComponent` for dynamic context switching[cite: 27].
- **Security:** Added `AuthGuard` to protect application routes[cite: 27].
- **HTTP Interception:** Shipped functional `AuthInterceptor` to automatically inject authentication tokens[cite: 27].

### 🏗 Architecture
- **Dependency Injection:** Defined `AUTH_ENV_CONFIG` and `AuthEnvironmentConfig` to pass configuration variables (`apiUrl_crud`, `apiUrl_token`, `system_id`) dynamically from the host app[cite: 29].

### 📦 Integration
- Exported all core authentication modules in `public-api.ts` making them available for external consumption[cite: 27].

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---
*Built with the assistance of AI-powered development tools.*
