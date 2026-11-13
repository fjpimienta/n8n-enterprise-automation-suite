---
description: 'Standards for Markdown documentation and project READMEs'
applyTo: 'docs/**/*.md,plans/**/*.md,hosting3m-workspace/projects/**/README.md,microservices/**/README.md'
---

# Markdown documentation standard

## Language and tone
- English, concise, imperative. No marketing language.

## Angular project README structure (in this order)
1. **Purpose** — one paragraph: what it does and what it does NOT do.
2. **Public API** — exported components, services, tokens, types (table: name, kind, description).
3. **Setup** — how to provide it (DI tokens, config objects) with a minimal example.
4. **Usage** — one realistic example per main use case.
5. **Multi-tenant behavior** — how `id_company` is received, validated and propagated. State the fail-closed behavior.
6. **Error handling** — error shapes, states, and edge cases. For anything calling the Meta-CRUD gateway, state how `error: true` payloads (HTTP 200), `data: [{}]` empty collections, and numeric strings are handled.
7. **Testing** — how to run the tests for this project.
8. **Limitations / TODO(verify)** — known gaps and unverified claims.

## Microservice README structure
Purpose, API/endpoints, configuration (variable names only, never values), how it is called from n8n, tenant handling, error contract, local run, tests, limitations.

## Formatting
- One H1 per file. Heading levels never skip.
- Fenced code blocks always declare a language (`ts`, `html`, `bash`, `json`, `mermaid`).
- Use Mermaid for flows and sequence diagrams (client -> webhook -> n8n -> database).
- Use relative links to source files.
- Config examples use placeholders only (`<COMPANY_ID>`, `https://api.example.com`, `<SECRET>`).
- Shell examples must be non-destructive; show a dry-run or backup first when a command mutates data.
- Audit reports and plans (`docs/AUDIT_*`, `plans/`) are historical records: append a dated note instead of rewriting them.
