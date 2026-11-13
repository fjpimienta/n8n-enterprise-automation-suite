---
description: 'Architecture Decision Records (MADR-style)'
applyTo: 'docs/adr/**/*.md'
---

# ADR standard

- File name: `NNNN-short-kebab-title.md` (zero-padded sequence number).
- Never rewrite an accepted ADR. Supersede it with a new one and link both ways.
- Required sections, in order:
  1. **Title**
  2. **Status** — Proposed | Accepted | Deprecated | Superseded by ADR-NNNN
  3. **Date** — ISO 8601
  4. **Context** — forces, constraints, tenant-isolation and production-safety impact
  5. **Decision** — one clear statement
  6. **Alternatives considered** — with reasons for rejection
  7. **Consequences** — positive, negative, risks, rollback plan
- Record only decisions evidenced in the repo or provided by the author. Do not invent rationale; mark gaps as `TODO(verify)`.
