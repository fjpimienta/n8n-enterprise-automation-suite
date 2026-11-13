---
description: 'Generate or update the README and TSDoc for an Angular project in the workspace'
agent: agent
---

Document the Angular project `${input:projectName:ui-chat | ui-pdf-export | core-auth | dashboard | hotel-website | agro-erp}`. Do not use this prompt for `pista-hielo` (legacy).

Steps:
1. Locate `hosting3m-workspace/projects/<projectName>` and read its public entry point (`public-api.ts` / `main.ts` / `app.config.ts`) and main sources.
2. Create or update its `README.md` following the Angular project README structure.
3. Add or improve TSDoc on exported symbols only (comments only, no code changes).
4. Fill the "Multi-tenant behavior" section from the actual code. If `id_company` handling is unclear, stop and ask me.
5. Mark anything you cannot verify as `TODO(verify)`.

Output: list the files you changed and every `TODO(verify)` you left.
