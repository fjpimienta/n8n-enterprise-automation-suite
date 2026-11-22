# Pending content after phase 2

A **production** build fails while any `TODO_*` token is in the output (`scripts/check-todo.mjs`). Beta and development builds only warn.
Tokens present in the build today, and what resolves each one:

| Token | Where | Needs from the owner |
|---|---|---|
| `TODO_PRICE` (x4) | `src/app/data/plans.json` | Approved price per package (number, MXN, with/without IVA stated) |
| `TODO_BILLING` (x4) | `plans.json` | Billing period per package (mensual, anual, único) |
| `TODO_FEATURES` (x4) | `plans.json` | Package contents (specs, what is included) |
| `TODO_CFDI_CLAIM_TITLE`, `TODO_CFDI_CLAIM_TEXT` | `data/content.ts` | Card hidden until the invoicing service exists (flag in `content.ts`); needs the exact, verifiable claim in `data/cfdi-claim.ts` before switching it on |

## Not tokens, but still need your approval before production
- **Fallback news** (`data/news-fallback.json`): 3 own cards about the GitHub suite. Drafted by Claude from `CLAUDE.md`; review wording.
- **Services, differentiators and process copy** (`data/content.ts`): reworded from the old site; "uptime", "24/7" and "enterprise security" claims were removed.
- **Legal texts** migrated verbatim from the old site (dates kept: privacy 30/08/2025, terms and deletion 29/08/2025). Only change: the deletion page no longer says "Alternativamente" because it lists a single option. Have it reviewed legally.
- **Trust section** (`TRUSTED_CLIENTS`) is empty and therefore not rendered. Add real clients only with written approval.
- **Brand** (`TODO_BRAND`, comment in `styles.css`): logo, palette, typography. Also an `og:image` (none is set yet).
- **Contact form**: which fields are mandatory on the server is unknown to the client. It requires names, lastname, email, message and the privacy checkbox; phone and middlename are optional. Confirm against the workflow.
- **Street address and opening hours** for `LocalBusiness` (currently city/state only).
