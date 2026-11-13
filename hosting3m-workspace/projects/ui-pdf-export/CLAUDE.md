# 🏛️ CLAUDE.md - UI PDF Export Library Governance & Technical Baseline

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Architect & Project Lead).
- **Claude's Operating Mode:** Core Engine Architect / Document Processing & Math Specialist.
- **Language Guardrail:** Accept rules, mapping schemas, and business directives in Spanish. ALWAYS generate engine code, TypeScript contracts, internal algorithms, and git logs strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **Zero-UI Enforcement (Logic Isolation):** Absolute restriction. This library must NEVER import Angular Material, Tailwind tokens, or render HTML elements into the browser DOM. It must only generate binary PDF blobs and trigger direct client-side downloads.
- **Domain Agnostic Rule:** Under no circumstances should this library reference specific models like `Reservation`, `Room`, or `Asset`. It must strictly consume the generic structural payload `PdfExportItem`.
  > **Known deviation (#1041):** the output is not domain-agnostic today. [`pdf-export.service.ts` L49](src/lib/services/pdf-export.service.ts) hard-codes "Cotización válida por 15 días", [L178](src/lib/services/pdf-export.service.ts) hard-codes the footer "Gracias por elegir el Hotel San José, Catazajá, Chiapas, México.", and the table labels "Precio / Noche", "Noches" and "Cant. Hab." are hotel terms ([L95](src/lib/services/pdf-export.service.ts)). The rule above is unchanged.
- **Financial Precision Guardrail:** The math engine must remain internal. To avoid client-side rounding errors, the library must receive the raw total amounts and process the fiscal breakdowns internally to derive Subtotal, Base Imponible, IVA (16%), and ISH (2%).
  - **Fiscal source (quoted, not recomputed here)**, in [`src/lib/services/pdf-export.service.ts`](src/lib/services/pdf-export.service.ts):
    - Defaults: `taxRate` is `0.16` and `ishRate` is `0.02` when not set ([L29–30](src/lib/services/pdf-export.service.ts)).
    - Base: `subtotal` is the sum of `item.total` and `baseAmount = subtotal` ([L87–89](src/lib/services/pdf-export.service.ts)). Base Imponible therefore equals the Subtotal in code.
    - Taxes: `ivaAmount = baseAmount * taxRate` and `ishAmount = baseAmount * ishRate` ([L90–91](src/lib/services/pdf-export.service.ts)).
    - Display: the IVA and ISH lines are drawn only when `showTaxes !== false && showTotals !== false` ([L134](src/lib/services/pdf-export.service.ts)).
    - TOTAL NETO is `subtotal + ivaAmount + ishAmount` ([L150](src/lib/services/pdf-export.service.ts)). It is not gated by the display flags, so it includes IVA and ISH even when those lines are hidden. RISK; see the owner decision in the library README.
  > **Known deviation (#1041):** the rates can be overridden through `PdfExportConfig`, so 16% and 2% are defaults, not fixed values. The item amounts are summed as received and are not validated. The rule above is unchanged.

## 💻 Tech Stack & Architectural Constraints
- **Core Engine:** Angular 21 Wrapper injecting `jspdf` and `jspdf-autotable` engines for vector drawing.
- **Design Pattern:** Adapter / Utility Service acting as a black box. Data flows strictly unidirectionally and synchronously: Input Contract Mapping -> Layout Calculation -> AutoTable Rendering -> Blob Download.
  - **Actual drawing order in `generate()`** ([`pdf-export.service.ts`](src/lib/services/pdf-export.service.ts)):
    1. Defaults for currency, `taxRate`, `ishRate` and today's date ([L28–31](src/lib/services/pdf-export.service.ts)).
    2. Header: `companyName`, `companyAddress`, issue date, validity line when `showValidity !== false`, and a rule line at y=34 ([L33–54](src/lib/services/pdf-export.service.ts)).
    3. Client block: "PREPARADO PARA:", `clientName`, and `clientSubtitle` when set ([L56–70](src/lib/services/pdf-export.service.ts)).
    4. `title` in upper case, centred at y=70 ([L72–75](src/lib/services/pdf-export.service.ts)).
    5. `autoTable` items table starting at y=76 ([L77–120](src/lib/services/pdf-export.service.ts)).
    6. Subtotal, then IVA and ISH when shown, then TOTAL NETO, positioned from `lastAutoTable.finalY` ([L122–150](src/lib/services/pdf-export.service.ts)).
    7. `footerTitle` and `footerText` lines, positioned from `lastAutoTable.finalY + 15` and pushed down when too close to the totals ([L152–172](src/lib/services/pdf-export.service.ts)).
    8. Fixed hotel line at the bottom of the page ([L174–178](src/lib/services/pdf-export.service.ts)).
    9. `doc.save()` with a sanitised file name ([L180–182](src/lib/services/pdf-export.service.ts)). The service does not create an explicit `Blob`; the download is performed by jsPDF.
- **Scope Alignment:** `PdfExportService` must be declared as a root-scoped singleton (`providedIn: 'root'`) to enable instantaneous cross-monorepo injection.

## 🔧 Build & Workspace Commands
- **Compile Module:** `ng build ui-pdf-export` (Must be executed and verified before compiling the `dashboard` or any host consumer app).

## 📝 Data Contracts & Layout Requirements
- **Strict Configuration Interface (`PdfExportConfig`):** Ensure any extension strictly satisfies parameters for `fileName`, `title`, `companyName`, `companyAddress`, `clientName`, and an array of `items`.
  - **Full field list** ([`pdf-export.interface.ts`](src/lib/interfaces/pdf-export.interface.ts)). Required: `fileName`, `title`, `companyName`, `companyAddress`, `clientName`, `items`. Optional: `clientSubtitle`, `currencySymbol` (default `$`), `taxRate` (default `0.16`), `ishRate` (default `0.02`), `footerTitle`, `footerText`, `showTaxes`, `showTotals`, `showValidity`. The boolean flags default to shown; only an explicit `false` hides their block ([L48](src/lib/services/pdf-export.service.ts), [L134](src/lib/services/pdf-export.service.ts)).
- **Row Mapping Structure (`PdfExportItem`):** Every document row must map exclusively to `concept` (Required), `description` (Optional), `quantity` (Required), `unitPrice` (Required), `total` (Required), `dailyRate` (Optional), and `nights` (Optional).
  - **Real field use** in [`pdf-export.service.ts`](src/lib/services/pdf-export.service.ts): `concept` and `description` form the "Descripción" cell ([L80](src/lib/services/pdf-export.service.ts)); `dailyRate` renders "Precio / Noche", `0` when absent ([L81](src/lib/services/pdf-export.service.ts)); `nights` renders "Noches", `1` when absent ([L82](src/lib/services/pdf-export.service.ts)); `quantity` renders "Cant. Hab." ([L83](src/lib/services/pdf-export.service.ts)); `total` renders "Importe" and feeds the subtotal ([L84](src/lib/services/pdf-export.service.ts), [L87](src/lib/services/pdf-export.service.ts)). `unitPrice` is declared as required but is not read anywhere in the service.
  > **Known deviation (#1041):** the item contract declares `unitPrice` as required but the engine does not use it, and `total` is trusted as given rather than checked against `quantity`, `dailyRate` or `nights`. The rule above is unchanged.
- **Precision Alignment Rules:** Layout routines must maintain strict architectural styling: Financial currency columns and total sheets must always be right-aligned for corporate readability, utilizing a clean, striped professional table layout theme.
- **Coordinates Safety:** Ensure vertical mapping strictly captures `lastAutoTable.finalY` to stack balances, total blocks, and custom banking footers dynamially without overlapping header lines or text blocks.
  > **Known deviation:** the service has no page-break check, and the header is drawn only on page 1 ([L33–54](src/lib/services/pdf-export.service.ts)). On long tables, totals or the footer can run off the page. This is not in the scope listed for #1041; TODO(verify) the tracking issue.