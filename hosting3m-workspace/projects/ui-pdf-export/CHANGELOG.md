# Changelog

All notable changes to the `ui-pdf-export` library will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-19
### 🚀 Initial Release
First stable release of the shared PDF generation module for Hosting3M Ecosystem.
Designed to provide a standardized, domain-agnostic engine for exporting documents (Quotes, Reports, Inventories).

### ✨ Features
- **PDF Generation:** Powered by `jspdf` and `jspdf-autotable` for high-quality vector output.
- **Smart Tables:** Automated table rendering with striped themes and dynamic column sizing.
- **Financial Engine:**
    - Automatic calculation of Subtotal, Base, IVA (16%), and ISH (2%).
    - **Precision Layout:** Right-aligned financial columns and totals for professional readability.
    - Currency and Date formatting support (MXN/Locale).
- **Customizable Layout:**
    - Dynamic Company & Client headers.
    - Configurable Footer for Banking Information or Disclaimers.

### 🏗 Architecture
- **Domain Agnostic:** Decoupled from specific business logic (e.g., "Reservations" or "Rooms"). Operates on generic `PdfExportItem` concepts (Concept, Quantity, Unit Price).
- **Type Safety:** Strict contracts via `PdfExportConfig` and `PdfExportItem` interfaces to ensure data integrity.
- **Service-Based:** `PdfExportService` provided as a root singleton for easy injection across the monorepo.

### 📦 Integration
- Exposed `PdfExportService` for direct consumption by `dashboard` and future apps (e.g., `pista-hielo`).
- Validated integration with `ReservationManager` for Guest Quote generation.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```