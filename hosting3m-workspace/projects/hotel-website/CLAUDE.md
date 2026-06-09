# 🏛️ CLAUDE.md - Hotel Eco-Website Governance & Technical Baseline

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Architect & Project Lead).
- **Claude's Operating Mode:** Frontend Conversion Architect / UI UX Specialist.
- **Language Guardrail:** Accept prompts, business logic, and UI requests in Spanish. ALWAYS generate code, components, layout parameters, inline comments, and git history strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **PRODUCTION ENVIRONMENT SAFETY:** Absolute restriction. Never modify, test, or drop elements directly against deployment servers or active production APIs.
- **Performance Budget (Core Web Vitals):** Every new component, heavy image asset, or library inclusion must respect the strict load budget of < 1.2 seconds. Enforce Angular AOT (Ahead-of-Time) compilation and Tailwind tree-shaking.
- **CORS & Payload Sanitization:** Ensure HTTP requests directed to n8n webhooks strictly comply with structured payloads and include required safety headers to avoid CORS blocking or 500 errors during lead injection.

## 💻 Tech Stack & Architectural Constraints
- **Core Framework:** Angular 21 Single Page Application (SPA) inside the monorepo workspace.
- **Design System:** Biophilic "Eco-Boutique" styling powered natively by Tailwind CSS v3 using custom design tokens (`eco`, `tierra`).
- **Visual Pattern:** Immersive layouts utilizing fluid responsive scaling, "Fat-Finger Design" rules for forms, and Glassmorphism layers via backdrop filters (`backdrop-filter`).
- **State Management:** Strict lifecycle management tracking explicit asynchronous UI states (`isSubmitting`, `success`, `error`) for interactive user feedback.
- **Shared Modules Integration:** - `@hosting3m/ui-chat` (AI Concierge): Injected cleanly via `CHAT_CONFIG_TOKEN`.
  - `@hosting3m/ui-pdf-export` (Optional): Pre-allocated for public quotation previews.

## 🔧 Build & Workspace Commands
Always execute these scripts from the workspace root:
- **Prerequisite Dependency Build:** `ng build ui-chat`
- **Run Local Development Server:** `ng serve hotel-website`
- **Production Build Artifact:** `ng build hotel-website --configuration=production`

## 📝 Code Style & UI Optimization Checklist
- **AI Chat Provisioning:** Never instantiate `<lib-ai-chat>` without checking its `CHAT_CONFIG_TOKEN` token definition providing `apiUrl_ai`, `title: 'Hotel Assistant'`, `logoUrl`, and `primaryColor: '#003366'`.
- **SEO & Semantics:** All content structures must maintain high HTML5 semantic readability, layout hierarchy (Inter font for body / Merriweather for headings), and dynamic metadata binding.
- **Lead Capture Pattern:** Form handlers must interact via Angular's `HttpClient` forwarding reactive data models straight to the n8n orchestrator webhooks.

## 🗺️ Roadmap Awareness & Future Readiness
Keep codebase decoupled and highly modularized to facilitate the implementation of imminent Phase II milestones:
- **A/B Testing Frameworks:** Structures prepared for future split-testing on the main Hero-Section.
- **Direct Payment Gateways:** API abstractions ready to bind Stripe or PayPal endpoints via n8n automation workflows.
- **Internationalization (i18n):** String architectures scalable to accept English/Spanish dynamic toggling.