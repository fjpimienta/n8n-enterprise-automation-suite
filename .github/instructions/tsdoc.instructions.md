---
description: 'TSDoc rules for the Angular workspace public API (comments only in documentation tasks)'
applyTo: 'hosting3m-workspace/projects/**/*.ts'
---

# TSDoc standard

- Applies to documentation tasks. In feature or refactoring work, write TSDoc only for the public API you add or change.
- In a documentation task, add or improve `/** ... */` TSDoc comments ONLY. Do not change code, imports, names, or formatting.
- Do not touch `*.spec.ts`, config files, or generated files.
- Document the public API first: exported classes, services, components, injection tokens, interfaces, and functional interceptors.
- Use `@param`, `@returns`, `@throws`, `@remarks`, `@example`, `@see`. Skip tags that add no information.
- Describe Signals as such: state whether a member is a `signal`, `computed`, or `input`/`output`, and what drives it.
- Injection tokens (`CHAT_CONFIG_TOKEN`, `AUTH_ENV_CONFIG`): document the expected shape and where it must be provided.
- Anything touching tenant data: add a `@remarks` line stating how `id_company` is validated or propagated.
- Anything touching fiscal math (IVA, ISH): describe the rule as implemented; never restate rates from memory.
- Explain WHY and the contract, not WHAT the code visibly does.
- Unknown behavior: write `TODO(verify)` rather than guessing.
