# COPILOT WORKSPACE INSTRUCTIONS

## LANGUAGE & COMMIT RULES
- Accept inputs and conversations in Spanish.
- ALWAYS generate code, TS interfaces, comments, and Git commit messages strictly in English.
- Use Conventional Commits in English (e.g., `feat(ui-pdf-export): add tax retention logic`).

## TECH STACK & ARCHITECTURE
- Framework: Angular 21 (Standalone Components ONLY, Signal-based state management).
- NO NgModules. Avoid RxJS unless handling complex async streams/interceptors.
- UI: Tailwind CSS v3 / Tabler UI.
- DB / Backend: PostgreSQL (JSONB + pgvector), Node.js, n8n Enterprise webhooks.

## CRITICAL SAFETY & ISOLATION
- Never write destructive commands (DROP, TRUNCATE, rm -rf).
- Multi-Tenant Isolation: Every query and service logic MUST filter by `id_company`.
- Fiscal calculations (IVA 16%, ISH 2%) must maintain 100% precision without backend dependencies in `ui-pdf-export`.
