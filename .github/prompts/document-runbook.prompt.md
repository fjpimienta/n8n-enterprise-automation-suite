---
description: 'Write a runbook from an operational script or procedure'
agent: agent
---

Write a runbook for `${input:target:e.g. infrastructure/update_n8n.sh}`.

1. Read the script and any file it sources. Do NOT execute it.
2. Create the runbook in `docs/runbooks/` following the runbook standard (backup step and rollback are mandatory).
3. Label every mutating command with `MUTATES`.
4. List assumptions and unclear behavior as `TODO(verify)` and ask me about them.
