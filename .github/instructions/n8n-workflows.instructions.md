---
description: 'Documentation rules for exported n8n workflows'
applyTo: 'workflows/**/README.md'
---

# n8n workflow documentation standard

## Reading the source
- Workflow JSON files are large and may contain credential references, webhook paths and tenant data. Search for node names, types and webhook paths instead of reading whole files.
- Never copy credential IDs, tokens, API keys, phone numbers, or real webhook URLs into documentation. Use placeholders.
- The highest `vN` folder is the current version unless the README states otherwise.

## README structure per workflow folder
1. **Purpose** — what business process it automates.
2. **Versions** — table of `vN`: what changed and whether it is current, deprecated, or experimental. Mark unknowns as `TODO(verify)`.
3. **Triggers** — webhook method and relative path (placeholder host), schedule, or MCP entry point.
4. **Inputs / outputs** — payload fields and response shape, including the internal `error: true` convention when applicable.
5. **Tenant isolation** — where `id_company` enters and which nodes filter by it. Note whether the `crud_models` whitelist applies. `n8n_user` is a PostgreSQL superuser and there is no RLS, so never claim database-level isolation. If a path does not filter by tenant, flag it as a RISK item. Do not fix it.
6. **Data stores** — tables or collections touched, read vs write.
7. **Error handling** — link to `00-global-error-handler`.
8. **Flow diagram** — a Mermaid diagram of the main path.
9. **Operations** — import/export steps. Always recommend a backup before importing a new version.
