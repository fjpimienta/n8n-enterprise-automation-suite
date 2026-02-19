# UI PDF Export Shared Library 📄

## 📖 Executive Summary

**UI PDF Export** is a robust, client-side document generation engine designed for the Hosting3M Ecosystem. It abstracts the complexity of `jspdf` and `autotable`, providing a standardized, high-fidelity output for business documents without server-side rendering.

It is currently the core reporting module for:

* **Admin Hotel Dashboard** (Guest Quotes & Reservation Summaries).
* **Future Implementations** (Inventory Reports & Pista Hielo Tickets).

## ⚡ Key Features

* **Domain Agnostic:** Capable of rendering any list of items (Reservations, Products, Services) via a generic interface.
* **Financial Engine:** Built-in logic to automatically calculate and breakdown **Subtotal**, **IVA (16%)**, **ISH (2%)**, and **Total Net**.
* **Precision Layout:** Professional alignment for financial columns (Right-aligned currency) to ensure readability.
* **Zero UI:** purely logic-based. It does not render HTML; it generates binary PDF blobs directly in the browser.

## 🛠 Installation & Integration

### 1. Import the Service

Since this is a `root` scoped service, you can inject it directly into any Component, Service, or Store.

```typescript
import { Component, inject } from '@angular/core';
import { PdfExportService, PdfExportConfig } from 'ui-pdf-export';

@Component({
  // ...
})
export class ReservationManagerComponent {
  private pdfService = inject(PdfExportService); // <--- Injection

  downloadQuote() {
    // Logic to prepare data...
    this.pdfService.generate(myConfig);
  }
}

```

### 2. Data Preparation (The Contract) ⚠️

The library relies on a strict interface `PdfExportConfig`. You must map your domain data (e.g., Reservations) to the library's generic structure.

```typescript
const pdfConfig: PdfExportConfig = {
  fileName: 'Cotizacion_Cliente_X',
  title: 'PRESUPUESTO DE HOSPEDAJE',
  
  // Emisor & Client Data
  companyName: 'Hotel San José',
  companyAddress: 'Av. Juarez s/n, Centro...',
  clientName: 'PCP Construcciones',
  
  // The Data Payload
  items: [
    {
      concept: 'Habitación Doble',
      description: '7 Noche(s)',
      quantity: 3,
      unitPrice: 3500, // Total price for the period (Tax included logic)
      total: 10500
    }
    // ... more items
  ],

  // Footer (Optional)
  footerTitle: 'Forma de Pago',
  footerText: ['Banco: HSBC', 'CLABE: 1234...']
};

// Trigger Download
this.pdfService.generate(pdfConfig);

```

## 🧩 API Reference

### `PdfExportItem` Interface

Defines a single row in the PDF table.

| Property | Type | Required | Description |
| --- | --- | --- | --- |
| `concept` | `string` | ✅ | The main title of the item (e.g., "Room 101"). |
| `description` | `string` | ❌ | Subtitle text (e.g., dates, serial numbers). |
| `quantity` | `number` | ✅ | Count of items. |
| `unitPrice` | `number` | ✅ | Price per unit. |
| `total` | `number` | ✅ | `quantity * unitPrice`. |

### `PdfExportConfig` Interface

Defines the entire document structure.

| Property | Type | Default | Description |
| --- | --- | --- | --- |
| `fileName` | `string` | - | Name of the downloaded file (without .pdf). |
| `taxRate` | `number` | `0.16` | VAT rate (16%). |
| `ishRate` | `number` | `0.02` | Hotel Tax rate (2%). |
| `currencySymbol` | `string` | `$` | Symbol used for monetary formatting. |

## 🏗 Architecture

The library is structured to enforce separation of concerns between Data and Rendering:

* **`/interfaces`**: Contains the Data Contracts (`PdfExportConfig`).
* **`/services`**: Contains the Singleton Logic (`PdfExportService`) that handles the `jspdf` lifecycle (Header -> Table -> Totals -> Footer -> Save).

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

```
---
*Built with the assistance of AI-powered development tools.*

```