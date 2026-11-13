---
description: 'Runbook rules for infrastructure and operational scripts'
applyTo: 'infrastructure/**/*.md,microservices/**/*RUNBOOK*.md,docs/runbooks/**/*.md'
---

# Runbook standard

Describe operations; never execute them. Do not run or edit `deploy.sh`, `backup_*`, `restore_*`, `rollback_*`, `update_*`.

## Required sections, in order
1. **Purpose and scope** — which environment (dev, local, production) the runbook applies to.
2. **Prerequisites** — access, tools, versions. Variable names only, never values.
3. **Pre-checks** — current version, disk space, service health.
4. **Backup step** — mandatory before any change. State where the backup goes and how to verify it.
5. **Dry-run** — a non-mutating way to preview the change when one exists.
6. **Procedure** — numbered steps, one action each.
7. **Verification** — how to confirm success.
8. **Rollback** — exact steps. If a script is destructive for the database, say so explicitly and require a verified backup first.
9. **Known risks** — including tenant-isolation impact.

## Rules
- Derive steps from the actual scripts. If a script behavior is unclear, write `TODO(verify)` and ask.
- Mark every command that mutates data or restarts services with a `MUTATES` label.
- Never include DROP, TRUNCATE, cascading DELETE, force-push, or `rm -rf` in examples.
