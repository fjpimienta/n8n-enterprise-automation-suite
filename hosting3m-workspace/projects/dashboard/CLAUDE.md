# 🏛️ CLAUDE.md - AdminHotel Governance & Technical Baseline

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Architect & Project Lead).
- **Claude's Operating Mode:** Assistant Technical Lead & Senior PMO Agent.
- **Language Guardrail:** Accept prompts, business rules, and instructions in Spanish. ALWAYS generate code, TypeScript interfaces, variables, internal documentation, and git artifacts strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **PRODUCTION ENVIRONMENT SAFETY:** Absolute restriction. NEVER execute drop, delete, or structural purge commands against production databases or deployment VPS.
- **Data Sovereignty:** All architectures must align with the self-hosted, multi-tenant framework of the Hosting3M Automation Suite.
- **MetaCRUD Resilience Shield:** When interacting with n8n API webhooks via HTTP, ensure responses with `HTTP 200 OK` containing an internal flag `error: true` are caught, parsed, and thrown as clean exceptions to the UI boundary layer to avoid ghost states.
- **Timezone Armor:** NEVER use native `toISOString()` for checkout/checkin date calculations. Always use local time evaluators (`getFullYear()`, `getMonth()`, etc.) to protect UTC-6 (CDMX/Mérida) operations from skipping days after 18:00 hrs.

## 💻 Tech Stack & Architectural Constraints
- **Frontend Core:** Angular v21.0.0 utilizing Standalone Components and Distributed Child Routes (`/mantenimiento`, `/finanzas`, `/inventario`).
- **State Management:** Strict reactive pattern using Angular Signals (`signal`, `computed`, `effect`). Avoid traditional RxJS subscribe/unsubscribe loops for local state.
- **Styling Architecture:** Tailwind CSS (with native CSS variables in `:root` for seamless Dark Mode) and Tabler UI.
- **Backend/API Gateway:** n8n Enterprise Automation Suite (Dynamic Meta-CRUD engine).
- **Database Engine:** PostgreSQL (Relational + JSONB Hybrid persistence).

## 🔧 Build & Development Commands
Always use these exact scripts within the development shell:
- **Install dependencies:** `npm install`
- **Build Core Libraries (Prerequisite):** `ng build ui-pdf-export` && `ng build ui-chat`
- **Run Local Dev Server:** `ng serve dashboard`
- **Production Build Artifact:** `ng build dashboard --configuration=production`

## 📝 Code Style & Patterns Checklist
- **Computed Reactivity:** Totalizations or balances (e.g., in `ReportService`) must never be calculated in the HTML templates. Use `readonly total = computed(() => ...)`.
- **Async Critical Path:** Prioritize rendering the `Room Rack (Grid)` first. Defer secondary lookups (Reservations, Users, Guests) using asynchronous loading patterns to secure fast Time-to-Interactive (TTI).
- **Polymorphic UI:** Form modals (like `AssetFormModal`) must detect contextual scope to switch gracefully between Global (Warehouse) and Local (Room assignment) logic.

## 🏷️ Source Control Standards
- **Conventional Commits:** Suggest git messages strictly following the template: `<type>(<scope>): <short imperative description in english>`.
- **Allowed Types:** `feat` (new features), `fix` (bug fixes), `refactor` (code restructuring), `security` (shields/validation updates), `docs` (readme/changelog).