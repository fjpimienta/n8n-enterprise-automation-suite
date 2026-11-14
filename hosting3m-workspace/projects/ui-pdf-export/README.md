# UI PDF Export Shared Library 📄

## 📖 Executive Summary

**UI PDF Export** is a robust, client-side document generation engine designed for the Hosting3M Ecosystem. It abstracts the complexity of `jspdf` and `autotable`, providing a standardized, high-fidelity output for business documents without server-side rendering.

It is currently the core reporting module for:

* **Admin Hotel Dashboard** (Guest Quotes & Reservation Summaries).
* **Daily finance report** (cash-closing PDF, `daily-report-modal`).
* **Future Implementations** (Inventory Reports).

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
      unitPrice: 3500, // Required by the interface; not read by the engine (see Limitations)
      dailyRate: 500,  // Net price per night (rendered in "Precio / Noche")
      nights: 7,       // Rendered in "Noches"
      total: 10500     // Used as given: the engine does not recompute quantity × dailyRate × nights
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
| `unitPrice` | `number` | ✅ | Price per unit. Required by the interface but **not read** by `PdfExportService`. |
| `total` | `number` | ✅ | Row amount, used as given. The service sums `total` for the subtotal and does not recompute `quantity * unitPrice`. |
| `dailyRate` | `number` | ❌ | Net price per night, rendered in "Precio / Noche" (`0` when omitted). |
| `nights` | `number` | ❌ | Nights, rendered in "Noches" (`1` when omitted). |

### `PdfExportConfig` Interface

Defines the entire document structure.

| Property | Type | Default | Description |
| --- | --- | --- | --- |
| `fileName` | `string` | - | Name of the downloaded file (without .pdf). Characters other than letters, digits, `-` and `_` are replaced by `_`. |
| `title` | `string` | - | Document title, upper-cased and centred. |
| `companyName` | `string` | - | Issuer name, drawn as the header. Free text; not validated. |
| `companyAddress` | `string` | - | Issuer address, drawn under the name. |
| `clientName` | `string` | - | Client name under "PREPARADO PARA:". |
| `clientSubtitle` | `string` | - | Optional extra line under the client name. Omitted when empty. |
| `items` | `PdfExportItem[]` | - | Rows of the table. |
| `taxRate` | `number` | `0.16` | VAT rate (16%). |
| `ishRate` | `number` | `0.02` | Hotel Tax rate (2%). |
| `currencySymbol` | `string` | `$` | Symbol used for monetary formatting. |
| `footerTitle` | `string` | - | Optional bold line above `footerText`. |
| `footerText` | `string[]` | - | Optional lines below the totals, one per row. |
| `showTaxes` | `boolean` | `true` | When `false`, the IVA and ISH lines are hidden. TOTAL NETO still includes both taxes (see Limitations). |
| `showTotals` | `boolean` | `true` | When `false`, the IVA and ISH lines are hidden (same as `showTaxes`). TOTAL NETO is not affected. |
| `showValidity` | `boolean` | `true` | When `false`, hides "Cotización válida por 15 días". |

## 🏗 Architecture

The library is structured to enforce separation of concerns between Data and Rendering:

* **`/interfaces`**: Contains the Data Contracts (`PdfExportConfig`).
* **`/services`**: Contains the Singleton Logic (`PdfExportService`) that handles the `jspdf` lifecycle (Header -> Client -> Table -> Totals -> Footer -> Disclaimer -> Save).
* **`src/public-api.ts`**: Entry point. Re-exports the interfaces and `PdfExportService`. The `ui-pdf-export` import path is mapped in the workspace `tsconfig.json`.

## 🔒 Multi-tenant Behavior

- The library has no tenant context. `PdfExportConfig` has no `id_company` field, and `PdfExportService` performs no data access or network calls. It renders only what the host passes.
- Tenant validation is the host's responsibility: the host must build `items` only from rows of the active company before calling `generate()`. TODO(verify) that each caller ([reservation-manager](../dashboard/src/app/features/booking/components/reservation-manager/reservation-manager.component.ts), [daily-report-modal](../dashboard/src/app/features/finance/components/daily-report-modal/daily-report-modal.component.ts)) filters by `id_company` upstream.
- `companyName` and `companyAddress` are free text supplied by the host. Nothing checks them against the active company, so a wrong mapping prints another issuer's name without an error.

## ⚠️ Error Handling

- `generate()` returns `void`. There is no error object, Promise, or input validation.
- Required fields are not validated. `config.title.toUpperCase()` and `config.items.map()` throw a `TypeError` in the caller's context when `title` or `items` is undefined. A missing `fileName` throws a `TypeError` at [pdf-export.service.ts](src/lib/services/pdf-export.service.ts) line 181, after the document is built and before `save()`, so nothing is downloaded. Other missing fields are not validated; how jsPDF renders them is TODO(verify).
- `total` is summed with `+` and is not parsed. The Meta-CRUD gateway returns numerics as strings (root `CLAUDE.md`), so callers must convert them to `number` before mapping. Otherwise the subtotal is concatenated as text.
- `dailyRate || 0` and `nights || 1` treat falsy values as absent.
- `doc.save()` triggers the browser download. A blocked download is not reported to the caller. TODO(verify).
- Empty `items`: TODO(verify) how the table and totals render.

## 🧪 Testing

- No spec files exist under `projects/ui-pdf-export/`. `tsconfig.spec.json` and a `test` target in [angular.json](../../angular.json) exist, but there are no tests to run.
- Build check (required before building any consumer, see [CLAUDE.md](CLAUDE.md)): `ng build ui-pdf-export` from `hosting3m-workspace/`.
- Manual check: generate a quote from the reservation manager with and without an invoice, and the daily cash report from the finance module.

## 🚧 Limitations & TODO(verify)

- **Hard-coded text.** Labels are fixed in Spanish ("PREPARADO PARA:", "Fecha de emisión", table headers, "Cotización válida por 15 días"). The footer line "Gracias por elegir el Hotel San José, Catazajá, Chiapas, México." is always drawn ([pdf-export.service.ts](src/lib/services/pdf-export.service.ts)). The library is therefore not domain-agnostic for other hosts, and there is no option to change these strings. RISK.
- **Taxes and totals.** IVA (`taxRate`, default `0.16`) and ISH (`ishRate`, default `0.02`) are applied to the sum of `total` ([pdf-export.service.ts](src/lib/services/pdf-export.service.ts)). `showTaxes` and `showTotals` only hide the breakdown lines; TOTAL NETO still includes both taxes. The daily cash report sets `showTaxes: false` and `showTotals: false` without `taxRate`/`ishRate` ([daily-report-modal.component.ts](../dashboard/src/app/features/finance/components/daily-report-modal/daily-report-modal.component.ts)), so its TOTAL NETO includes 16% + 2% that the PDF does not itemize. RISK; owner decision required.
- **Rounding.** Each figure is formatted separately with `DecimalPipe` (`1.2-2`). The displayed IVA, ISH and TOTAL NETO may differ by 0.01 from the sum of the displayed lines. TODO(verify) with a test case.
- **Pagination.** Totals and footer are placed at `lastAutoTable.finalY` with no page-break check, and the header is drawn only on page 1. Long tables may push totals or the disclaimer off the page. TODO(verify) visually.
- **Unused field.** `unitPrice` is not read by the service.
- **Locale.** Dates use `es-MX`. Amounts use `en-US` separators with the symbol from `currencySymbol` (default `$`).
- **Filename.** Accents, spaces and symbols become `_`, so "Cotización Juan" becomes "Cotizaci_n_Juan".
- **Package metadata.** [package.json](hosting3m-workspace/projects/ui-pdf-export/package.json) declares peer dependencies on Angular `^17 || ^18`, while the workspace runs Angular 21. It also does not list `jspdf-autotable`, which the service imports. The workspace resolves it from the root [package.json](../../package.json), which declares `jspdf-autotable` `^5.0.9`. Its version is `0.10.0`, while the top [CHANGELOG.md](CHANGELOG.md) entry is `1.0.0`. TODO(verify) which one is authoritative.

## 📦 Authors

**Francisco Jesus Pérez Pimienta**
*Senior Systems Architect & Project Lead*
Hosting3M Automation Suite

---
*Built with the assistance of AI-powered development tools.*