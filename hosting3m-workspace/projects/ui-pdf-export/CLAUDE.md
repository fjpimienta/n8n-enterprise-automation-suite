# 🏛️ CLAUDE.md - UI PDF Export Library Governance & Technical Baseline

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Architect & Project Lead).
- **Claude's Operating Mode:** Core Engine Architect / Document Processing & Math Specialist.
- **Language Guardrail:** Accept rules, mapping schemas, and business directives in Spanish. ALWAYS generate engine code, TypeScript contracts, internal algorithms, and git logs strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **Zero-UI Enforcement (Logic Isolation):** Absolute restriction. This library must NEVER import Angular Material, Tailwind tokens, or render HTML elements into the browser DOM. It must only generate binary PDF blobs and trigger direct client-side downloads.
- **Domain Agnostic Rule:** Under no circumstances should this library reference specific models like `Reservation`, `Room`, or `Asset`. It must strictly consume the generic structural payload `PdfExportItem`.
- **Financial Precision Guardrail:** The math engine must remain internal. To avoid client-side rounding errors, the library must receive the raw total amounts and process the fiscal breakdowns internally to derive Subtotal, Base Imponible, IVA (16%), and ISH (2%).

## 💻 Tech Stack & Architectural Constraints
- **Core Engine:** Angular 21 Wrapper injecting `jspdf` and `jspdf-autotable` engines for vector drawing.
- **Design Pattern:** Adapter / Utility Service acting as a black box. Data flows strictly unidirectionally and synchronously: Input Contract Mapping -> Layout Calculation -> AutoTable Rendering -> Blob Download.
- **Scope Alignment:** `PdfExportService` must be declared as a root-scoped singleton (`providedIn: 'root'`) to enable instantaneous cross-monorepo injection.

## 🔧 Build & Workspace Commands
- **Compile Module:** `ng build ui-pdf-export` (Must be executed and verified before compiling the `dashboard` or any host consumer app).

## 📝 Data Contracts & Layout Requirements
- **Strict Configuration Interface (`PdfExportConfig`):** Ensure any extension strictly satisfies parameters for `fileName`, `title`, `companyName`, `companyAddress`, `clientName`, and an array of `items`.
- **Row Mapping Structure (`PdfExportItem`):** Every document row must map exclusively to `concept` (Required), `description` (Optional), `quantity` (Required), `unitPrice` (Required), and `total` (Required).
- **Precision Alignment Rules:** Layout routines must maintain strict architectural styling: Financial currency columns and total sheets must always be right-aligned for corporate readability, utilizing a clean, striped professional table layout theme.
- **Coordinates Safety:** Ensure vertical mapping strictly captures `lastAutoTable.finalY` to stack balances, total blocks, and custom banking footers dynamially without overlapping header lines or text blocks.