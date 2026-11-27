# 2026-11-27 — Identifier change control (RFID chip / SINIIGA ear tag / fire number)

Change record. Documentation only: this file changes no code, migration, workflow or other document.

**How to read the status labels.** *Verified* = checked by the author of this record in the repository (git history and files on `develop`) or by running the repository tests locally. *Owner-reported* = stated by the project owner, **not verified by this session**. *Inferred* = deduced from the files, not observed. *Done* = merged and/or applied where stated. *Designed, not applied* = exists as a file or plan only. *Proposed* / *pending* = not started.

**Status update (2026-11-27, deployed; all of this is reported by owner, not verifiable in repo).** Migrations 114, 115 and 116 are applied in production (reported by owner, not verifiable in repo). Verified read-only on a restored copy of production taken the same day (2026-11-27, reported by owner): all objects present, and a dry run of each migration ends OK and rolls back (idempotent). The four workflows (MCP server, notification, chat, WhatsApp) are imported in production and match the `develop` files by fingerprint (the chat matches after normalizing the palm sub-workflow id); the WhatsApp workflow was imported last, on 2026-11-27 (reported by owner). Behavior checks with the test company: reported by owner as done; the results are not recorded in the repo. The frontend part (2c) and the guard of 2d are not part of this change. The hosting panel deploys `main` in automatic mode for the suite sites; there is no agro-erp application code in this change, so the automatic rebuilds do not change those apps. `115_rollback.sql` still refuses to run once `CAMBIO_ARETE` rows exist. Statements below that describe the work as not applied or not imported are the state when this record was written and are superseded by this paragraph.

## 1. Goal and context

Control how the three animal identifiers (`electronic_rfid` chip, `rfid_siniiga` ear tag, `numero_fuego` fire number) are assigned and changed: assignment only when empty, any change as an authorized request, a history that cannot be edited, and no direct approval by the AI agent. A data-integrity issue in the identifier flow was reported; the review and fix are tracked privately.

Merged into `develop` on 2026-11-26 (verified from `git log`): PRs #1160, #1161, #1162 and #1163. CI results are owner-reported (green on all four); this session did not read the CI runs.

## 2. What changed

### 2.1 Repository files (verified on `develop`)

| Path | Purpose | PR |
|---|---|---|
| `database/migrations/114_identifier_history_tenant_guards.sql`, `114_rollback.sql`, `114_tests.sql`, `114_RUNBOOK.md` | Step 1: history table scoped by company and append-only | #1160 |
| `database/migrations/115_tag_change_authorization.sql`, `115_rollback.sql`, `115_tests.sql`, `115_concurrency_check.sh`, `115_RUNBOOK.md` | Step 2: assignment, change requests, cancellation, alias lookup, new authorization type | #1161 |
| `database/migrations/116_tag_change_chat_guard.sql`, `116_rollback.sql`, `116_tests.sql`, `116_RUNBOOK.md`, `116_whatsapp_RUNBOOK.md`, `116_n8n_tests.md` | Step 3: approval of a tag change refused from chat; runbooks and the n8n test table | #1162 |
| `workflows/09-MCP-Agent-Cattle/v6/v6_MCP_Server_Cattle.json`, `v6_ai_chat_cattle.json`, `v6_WhatsApp_Agent_Cattle.json`, `v6_Notificacion_Autorizaciones.json` | Workflow exports (see 2.3) | #1162 |
| `workflows/09-MCP-Agent-Cattle/v6/repro-phase5/check_repro_consistency.js` | CI consistency check updated for the new tools, levels, node counts and prompt-size limit | #1162, #1163 |
| `workflows/09-MCP-Agent-Cattle/v6/tests/test_palm_sale_route.mjs` | One assertion now accepts the chat error-handling wiring on the palm agent | #1163 |
| `workflows/09-MCP-Agent-Cattle/v6/v6_ai_chat_cattle.json`, `database/migrations/116_RUNBOOK.md` | Chat error handling brought from production into the repo; runbook section on the production comparison | #1163 |

Migration number 113 is intentionally unused (reserved for a separate, not yet written work item).

### 2.2 Database

| Object | Change | Migration | Status |
|---|---|---|---|
| `cattle_identifier_history` | New `id_company` column (backfilled from the animal, then `NOT NULL`), indexes by company; `BEFORE INSERT` trigger that always takes the company from the animal; append-only (UPDATE, DELETE, TRUNCATE refused, `P0131`; company mismatch `P0130`) | 114 | Applied in LOCAL rehearsal (verified, tests pass); **applied in PRODUCTION (owner-reported)** |
| `trg_log_identifier_changes()` | Rewritten: real actor, validated reason (`P0132`), free text in `notes`, `'UNKNOWN'` when no actor was set, no row for NULL ↔ empty or edge-space changes | 114 | same |
| History reasons | Added `INITIAL_ASSIGNMENT`, `AUTHORIZED_CHANGE` | 114 | same |
| `crud_models` row for the history model | INSERT removed, `id_company` added to `allowed_fields` (readable by every role, filtered by company) | 114 | same |
| `pending_authorizations.tipo_evento` | CHECK accepts `CAMBIO_ARETE` | 115 | LOCAL verified; PRODUCTION owner-reported |
| `sp_resolver_autorizacion` | One new dispatcher branch, patched in place, text-fingerprint gated | 115 | same |
| `fn_pending_auth_one_pending_guard` | Message names the type for `CAMBIO_ARETE`, patched in place | 115 | same |
| `vw_cattle_event_log` | A tag-change request shows as `SOLICITUD_CAMBIO_ARETE` instead of an empty event type, patched in place | 115 | same |
| `sp_assign_livestock_identifier` | Chip or fire number, only when empty; ADMIN or EDITOR; two calls (preview, then execute with a single-use value) | 115 | same |
| `sp_request_tag_change` | Ear tag (empty or not), replacement of a chip, change of a fire number; always creates a pending request, never touches the animal; reason mandatory | 115 | same |
| `sp_cancel_tag_change` | Requester or an active ADMIN, same local day; state `CANCELADO` | 115 | same |
| `sp_apply_tag_change` | Internal; runs only when called by the dispatcher; revalidates everything at approval time | 115 | same |
| `fn_resolve_identifier` | Current value wins; a retired value still finds the animal and is flagged as a previous identifier | 115 | same |
| `tag_change_previews` (table) | Single-use, 10-minute preview values bound to company, e-mail, animal and exact parameters | 115 | same |
| Helper functions (`fn_tag_*`, `fn_normalize_identifier`) | Rules (chip 15 digits; 10-digit ear tag only for bovine or unknown species) and normalization | 115 | same |
| `sp_review_pending_request` | Chat-only wrapper patched in place: a decision other than `RECHAZADO` on a `CAMBIO_ARETE` request raises `P0136`; the web-panel path is untouched | 116 | LOCAL verified; PRODUCTION owner-reported |

Error codes introduced: `P0130`, `P0131`, `P0132`, `P0135`, `P0136`. Expected business outcomes of the new functions are returned as a `status` value, not raised.

### 2.3 n8n workflows and MCP tools (names only)

| Workflow | Change | Status |
|---|---|---|
| `v6/MCP Server Cattle` | Tool `update_livestock_tag` **removed** (55 → 54 tool nodes, verified); `get_livestock_info` resolves through `fn_resolve_identifier`; `list_pending_requests` shows the tag-change fields; descriptions of `review_pending_request` and `move_livestock` updated | file on `develop` (verified); imported in PRODUCTION (owner-reported) |
| `v6/ai/chat cattle` | Three **new direct tool nodes**: `assign_livestock_identifier`, `request_tag_change`, `cancel_tag_change` (fixed query, `queryReplacement` as an array); new prompt level for tools whose first call is the preview; error-handling nodes `Classify Chat Error`, `Respond Chat Error`, `Fail After Reply`, error output on both agents, `maxRetries = 1` on both chat models | file on `develop` (verified); imported in PRODUCTION (owner-reported) |
| `V6/Notificación de Autorizaciones Pendientes` | Label and fields for the new request type; baja and venta e-mails unchanged | file on `develop` (verified); imported in PRODUCTION (owner-reported) |
| `v6/WhatsApp Agent Catlte` | Same three direct tools and prompt changes; `Resolver Tenant` rule for a phone shared by several users of the selected company | file on `develop` (verified); imported in PRODUCTION last, on 2026-11-27 (owner-reported) |

The three new tools are direct nodes of each agent workflow, not MCP server tools. The other MCP tools are unchanged except as listed above (verified from the diff of PR #1162).

### 2.4 Frontend

No frontend change was made. A search of `src` on `develop` finds no reference to the new request type or to the `SOLICITUD_CAMBIO_ARETE` event type (the existing event-log screen labels the older `CAMBIO_ARETE` movement only). Status: **proposed / pending** (follow-up PR).

### 2.5 Infrastructure and configuration

None in the repository. Workflow-level and instance-level execution-saving settings: see section 6 and section 7. The production import order, backups and comparisons were performed by the owner (owner-reported).

## 3. Business rules decided

Decisions were taken by the project owner during the design review of this work (exact dates not recorded in this session).

1. **Ear tag (SINIIGA)** cannot be changed directly. Any set or change, including filling an empty ear tag, is a request approved by an active ADMIN of the company in the web panel. Valid until the end of the same calendar day (America/Mexico_City). A reason is mandatory. The old value stays searchable as an alias. The AI agent never approves: from chat an ADMIN can only reject.
2. **Chip and fire number:** assignable without approval only when the animal has none (ADMIN or EDITOR). Replacing a chip or changing a fire number follows the request flow. Fire numbers may repeat inside a company (the preview warns).
3. **Who approves:** an active company ADMIN (the existing function is unchanged). OWNER does not approve in this work (separate decision, open).
4. **Self-approval** works as it already does for mortality and sale requests.
5. **Cancelling** a pending change: the requester or an active ADMIN, the same day.
6. **History** is readable by every role, filtered by company; written only by the trigger; append-only.
7. **One pending request per animal** (existing rule); a second request gets a message naming the pending type.
8. **Validation:** a chip is 15 digits; a 10-digit ear tag is required only for bovine or unknown species. "Cannot use this value" is a single generic outcome that does not reveal who holds it (global unique indexes).
9. **Policy conformity (inferred from the files):** the new functions follow the policy above. **Deviation / not yet enforced:** the three identifier columns are not yet blocked at database level against writes made outside the new functions; that guard is planned as migration 117, last. Until then the policy is enforced by the new functions, the fixed workflow queries and the web panel path (not verified for every other write path).

**Unresolved questions:** ear-tag rule for BUFALO (client pending); whether an OWNER role may approve; chips containing spaces; bulk assignment; the frontend labels PR; migration 117; a clean 403 before the chat company-resolution node; the WhatsApp rollout; a neutral CHANGELOG entry.

## 4. How to test

Run only on the rehearsal and DEV copies, company `id_company = 3` (the project rules document company 3 as the test company; the owner also states company 10 is a test company: *owner-stated, not verified in the docs*). Never against production data.

**Database (verified, run locally against a throwaway rehearsal database restored from a dump):** `114_tests.sql`, `115_tests.sql` and `116_tests.sql`, each ending with "ALL TESTS PASSED" and rolling back (re-run on 2026-11-27 with the exact candidate, in that order); `115_concurrency_check.sh` (two real sessions; leaves no rows). `115_tests.sql` needs the shared fixtures removed first (a guard aborts otherwise).

**Tool level (verified, local DEV copies, 2026-11-27):** 108 of 108 checks for assignment, request, cancellation, the MCP queries and the Node harnesses; 3 of 3 WhatsApp resolver rows. The checks drive the tools through a DEV-only entry that runs the tool's own expression and query without the model. The git-ignored dev harness exists for this purpose only (generator of the DEV copies, fixtures, a tool-level runner, a conversation client).

**Conversations with the model (verified, local DEV copies):** first assignment (preview, then confirm), ear-tag change request, cancellation by the requester and by an admin, forced errors through the error-handling nodes. Approval refused from chat (conversation C7) passed earlier according to the owner (owner-reported, not re-run in the last session). Two behaviours deviate and are tracked as follow-ups (section 6).

**CI (verified locally for the five scripts of the consistency job):** `check_repro_consistency.js` 211 passed; `test_palm_sale_route.mjs` 138; `test_xml_router.mjs` 45; `test_palm_expense_xml.mjs` 74; `test_agri_sale_sp.mjs` 61.

**Production smoke tests (owner-reported, not verified by this session), test company only:** preview, request and cancel without changing an animal; first chip assignment through the chat (one preview, one confirmation); a request created through the chat, refused for approval in chat, approved by an ADMIN in the web panel, old tag found as an alias, history rows written. One test animal's ear tag and chip were changed permanently as test data.

**Value classes and what is actually covered**

| Class | Covered by | Not verified |
|---|---|---|
| Values with quotes and semicolons | tool rows (chip value, identifier), Node harness (reason text) | Through the real tool node end to end with the model |
| Empty, null, text `"null"` / `"undefined"` | tool rows for identifier, value and preview value (empty and null variants, both text variants) | Reason field with those text values |
| Commas | one tool row (`123,456` refused as one value); harness | Commas inside a free-text reason through the real node |
| Leading zeros | tool row and harness (kept as text) | Leading zeros in an ear tag |
| Cross-company attempts | database tests (isolation, preview of another company's animal, approvals), tool rows (another company's chip, other e-mails), WhatsApp rows with a phone in two companies | Production-level cross-company attempts |
| Very long and full-width digit strings | tool rows (refused, no crash) | — |
| WhatsApp conversations (dictated digits, shared phone with the model) | — | Owner-reported as done with the test company on 2026-11-27; results not recorded in the repo (rows 55, 56, 58 and conversations C10, C12) |

## 5. Rollback

| Change | Rollback | Notes |
|---|---|---|
| 114 | `114_rollback.sql` | Restores a hardened version of the previous logger (not the byte-exact old text) and the gateway INSERT; keeps the new column, its trigger and written rows. Roll back 115 first |
| 115 | `115_rollback.sql` | Restores the three patched objects to their measured text, restores the CHECK, turns the four public functions into stubs that answer "disabled". **Refuses to run while any `CAMBIO_ARETE` row exists** (owner reports at least one now exists in production, so it would refuse until those are resolved) |
| 116 | `116_rollback.sql` | Removes exactly the inserted block; the chat can approve a tag change again if 115 stays applied. Roll back the workflows first |
| Workflows | Re-import the saved exports | Stored outside the repository (owner-reported) |
| Frontend | No change, nothing to roll back | |

Order when several are applied: workflows → 116 → 115 → 114. No script drops data.

## 6. Known gaps and risks, pending work, follow-up PRs

Neutral list; owner-reported items are labelled.

- Some older MCP tools still take the tenant or e-mail from model-chosen values and are to be migrated to session-injected values (tracked privately). The new tools take both from the session-resolution nodes of their workflow, never from the model (verified from the node expressions).
- Database guard so the three identifier columns change only through the new functions (migration 117, last). Not part of this work.
- Web panel shows the new request type without a label or details until the frontend PR exists (owner-reported).
- The chat sometimes words the animal category differently from the data (owner-reported).
- The mortality tool can receive an ear tag in the fire-number parameter, so the animal is not found; verified locally with and without the chat error-handling change; no write happens.
- Cancelling a tag change as a user other than the requester: the agent asks for a reason the tool does not use and does not reach the "forbidden" answer; no write happens (verified locally).
- A phone with several companies and no selection receives "no property found" instead of the "several properties" message (behaviour identical to `develop` before this work; follow-up PR).
- Follow-up: return a clean 403 before company resolution in the chat workflow.
- Execution saving: the instance default saves every execution; one workflow-level override remains in the production chat workflow (owner-reported; which override is not verified).
- WhatsApp workflow rollout: done on 2026-11-27 (owner-reported); its resolver rows and conversations are reported as run, results not in the repo.
- OWNER approval, BUFALO ear-tag rule, chips containing spaces, bulk assignment (section 3).
- A CHANGELOG entry for migrations 114–116 does not exist (verified by search); a neutral entry is pending.
- A separate docs PR will align `docs/ARCHITECTURE.md`, `docs/DATABASE_SCHEMA.md` and rule 15 of the agro-erp `CLAUDE.md` with the ten mismatches listed in section 8.
- This record is tracked on `develop`.

## 7. Objects in the live system that are not in the repository

Read them from the live system before changing the related files:

- The id of the palm-sale sub-workflow in the production chat workflow. The repo keeps the placeholder `PalmSaleXml0001a`; after each import the node `Venta Palma XML` must be pointed by hand at the production sub-workflow (documented in `116_RUNBOOK.md`).
- The remaining workflow-level setting of the production chat workflow (see section 6).
- The production export of each workflow before every import: production has differed from the repository more than once (the chat workflow differed until PR #1163). Compare by fingerprint first (root `CLAUDE.md`).
- The WhatsApp production workflow: reported identical to `main` by the owner (not verified here).
- Whether other production objects (functions, triggers, models) differ from the migrations: not verified; the migrations are gated by text fingerprints of the objects they patch.

## 8. Mismatches with `docs/ARCHITECTURE.md` and `docs/DATABASE_SCHEMA.md` (list only)

**How they were read.** Section headings of both files were listed. Read in full: `ARCHITECTURE.md` section 4 passage on `cattle_identifier_history`, the whole of section 5 (async authorization) and the whole of section 8 (advanced herd management) plus the model table row for the history table; `DATABASE_SCHEMA.md` "Identifier History Subsystem", `pending_authorizations`, `sp_solicitar_autorizacion`, `sp_resolver_autorizacion`, the `update_livestock_tag` and `list_pending_requests` entries, `vw_cattle_event_log`, and `trg_log_identifier_changes`. Both files were also searched for every mention of the identifier objects. Other sections (palm, CFDI, reproduction, hotel) were not read and are not assessed.

Mismatches (no document was edited):

1. `DATABASE_SCHEMA.md`, "Identifier History Subsystem": no `id_company` column; reasons list lacks `INITIAL_ASSIGNMENT` and `AUTHORIZED_CHANGE`; the trigger is described with fallbacks to `NULL` / `CAPTURE_CORRECTION` and no reason validation, no `'UNKNOWN'` actor, no `notes`; no mention of append-only behaviour.
2. `DATABASE_SCHEMA.md`, `trg_log_identifier_changes` entry: same differences as item 1.
3. `DATABASE_SCHEMA.md`, `pending_authorizations`: `tipo_evento` CHECK documented as `BAJA_MORTANDAD` / `VENTA`; it now also accepts `CAMBIO_ARETE`. The "one request per animal and type is reused" note is not re-checked against the new type.
4. `DATABASE_SCHEMA.md`, `sp_resolver_autorizacion`: no dispatcher branch for `CAMBIO_ARETE`; the "chat wrapper adds the tenant check" text does not mention the new refusal of approvals (`P0136`).
5. `DATABASE_SCHEMA.md` and `ARCHITECTURE.md` section 8: `update_livestock_tag` is documented as an existing tool with a direct `UPDATE`; it no longer exists in the MCP server. The three new direct tools and the new functions are not documented.
6. `ARCHITECTURE.md` section 5 (and the model table): the authorization subsystem is described as two event types; the `cattle_identifier_history` model is documented with `INSERT` for ADMIN and EDITOR, which was removed.
7. `ARCHITECTURE.md` section 4 and section 8: the statement that history rows written by an agent tool use the default reason and no actor no longer holds for the new flow (reason and actor are set); the older statement refers to the removed tool.
8. `DATABASE_SCHEMA.md`, `vw_cattle_event_log`: no `SOLICITUD_CAMBIO_ARETE` event type.
9. Counts in `ARCHITECTURE.md` section 8 and the root project notes that cite a number of MCP tools (15, 23) predate the removal and the three direct tools; they were not recounted here.
10. The agro-erp `CLAUDE.md` still lists `update_livestock_tag` in its rule 15: mentioned here for completeness; it was not part of the requested comparison.
