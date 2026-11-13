# Copilot documentation workflow

> This file is documentation for humans. It is NOT the instruction file Copilot reads.
> The instruction file is `.github/copilot-instructions.md`.
> `.vscode/settings.json` is ignored by git in this repo; each developer sets `chat.useClaudeMdFile` to `false` locally.

## Purpose
Defines how GitHub Copilot is used in this repository: documentation only, reviewed by a human before merge.

## Customization files
| File | Role |
|---|---|
| `.github/copilot-instructions.md` | Repository-wide rules (short) |
| `.github/instructions/*.instructions.md` | Path-specific standards (Markdown, TSDoc, ADR) |
| `.github/prompts/*.prompt.md` | Reusable tasks, invoked as `/document-lib`, `/document-component`, `/new-adr` |
| `.github/agents/docs-writer.agent.md` | Restricted documentation agent |

## Model configuration
Models are configured per developer in VS Code (Bring Your Own Key). API keys are never committed.

## Review checklist
- [ ] Only comments and Markdown changed (`git diff` shows no runtime code changes)
- [ ] No secrets, real hosts, or real `id_company` values
- [ ] Fiscal rules (IVA, ISH) match the source
- [ ] Every `TODO(verify)` is resolved or tracked
- [ ] Commit follows Conventional Commits, e.g. `docs(core-auth): document CompanyContext flow`
