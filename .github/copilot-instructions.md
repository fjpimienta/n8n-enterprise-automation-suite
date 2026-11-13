# COPILOT WORKSPACE INSTRUCTIONS

## LANGUAGE & COMMIT RULES
- Accept inputs and conversations in Spanish.
- ALWAYS generate code, TS interfaces, variable names, comments, and PR descriptions strictly in English.
- Conventional Commits in English, imperative mood: `<type>(<scope>): <description>`, scoped to the affected app/lib.
- Allowed types: `feat`, `fix`, `refactor`, `chore`, `docs`, `security`.
- Examples: `fix(ui-pdf-export): correct finalY offset on multi-page tables`, `docs(core-auth): document CompanyContext flow`.

## TECH STACK & ARCHITECTURE
- Framework: Angular 21 (Standalone Components ONLY, Signal-based state management).
- NO NgModules. Avoid RxJS unless handling complex async streams/interceptors.
- UI: Tailwind CSS v4 (`hotel-website`, via `@tailwindcss/postcss`) / Tabler UI (`dashboard`; `hotel-website` also loads Tabler from the CDN).
- DB / Backend: PostgreSQL (JSONB + pgvector), Node.js, n8n Enterprise webhooks.

## REPOSITORY MAP
- Angular projects: `hosting3m-workspace/projects/` (`dashboard`, `hotel-website`, `agro-erp`, `ui-chat`, `ui-pdf-export`, `core-auth`).
- `pista-hielo` is LEGACY and unused. Do not generate documentation for it beyond a deprecation note.
- `workflows/NN-name/vN/`: exported n8n workflows. The highest `vN` is current unless a README says otherwise.
- `microservices/`, `infrastructure/`, `docs/`, `plans/`.
- The full module list lives in `README.md`. Do not duplicate it elsewhere.
- Some projects have their own `CLAUDE.md`: use it as a source of context, verify it against the code, and never copy it verbatim.

## CRITICAL SAFETY & ISOLATION
- Never write destructive commands (DROP, TRUNCATE, cascading DELETE, force-push, rm -rf) against production DB or the VPS. Always propose a backup or dry-run step first, even if not asked.
- Multi-Tenant Isolation (fail-closed): every query, egress pipeline, and component layer MUST filter/validate by `id_company`. If tenant context is ambiguous, stop and ask. Never assume the active tenant.
- `n8n_user` is a PostgreSQL superuser. Real isolation depends on the `crud_models` whitelist, not on RLS. Never state or imply that isolation is guaranteed at database level.
- Fiscal calculations (IVA 16%, ISH 2%) must keep 100% precision with no backend dependency in `ui-pdf-export`. If a request could affect fiscal calculations, ask first.
- Secrets: never write, paste, or echo real secret values (tokens, API keys, internal or JWT secrets). Use placeholders or `****`. Never open `.env*`, `export_credentials.js`, keys, or certificates. If a secret is exposed, treat it as compromised and flag rotation.
- Do not run or modify operational scripts (`deploy.sh`, `backup_*`, `restore_*`, `rollback_*`, `update_*`). Documenting them is allowed.

## META-CRUD GATEWAY CONTRACT
- Data mutations go through the n8n Meta-CRUD gateway, not ad-hoc SQL, unless a project documents a verified exception.
- Postgres errors arrive as HTTP 200 with `error: true`. Always inspect the payload; never trust the HTTP status alone (`dashboard` intercepts this with the MetaCRUD Silent Error Shield).
- Empty collections return `data: [{}]`, not `[]`. Filter by identifier before counting or rendering.
- Numeric values arrive as strings. Parse explicitly; never compare or sort them as text.

## DOCUMENTATION TASKS (Markdown, TSDoc, ADRs, runbooks)
Applies when the task is documentation. Detailed standards live in `.github/instructions/`.
- Documentation changes are comments and Markdown only. Never alter runtime logic, signatures, or imports.
- Document only what is verifiable in the source. Link files by relative path. Mark anything unverified as `TODO(verify)`.
- Use placeholders (`<COMPANY_ID>`, `https://api.example.com`). Never include secrets, real hosts, production URLs, customer data, or real `id_company` values.
- When documenting data access, state how `id_company` is validated. When documenting fiscal logic, quote the rule and link the source; never recompute it.
- Prefer the `docs-writer` agent for documentation and the `Enterprise Architect` agent for design and implementation work.
