> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: written for review. Checked only with a Node harness. The WhatsApp rows of `116_n8n_tests.md` (54 to 61) and conversations C10 and C12 have NOT been run.**
> Part 1 (database) is the same as for the rest of this PR: `114`, `115` and `116_tag_change_chat_guard` applied and verified. This runbook covers the WhatsApp workflow, which is step 4 of Part 2 in `116_RUNBOOK.md` and is imported LAST, after the MCP server, notification and chat have run in production. It ships in the same PR as those because `check_repro_consistency.js` (CI) requires the chat and WhatsApp prompts to stay in sync; merging to `develop` deploys nothing.

# Runbook — WhatsApp agent: identifier tools and shared-phone rule

## What changes
| Workflow (id in production) | Change |
|---|---|
| `v6/WhatsApp Agent Catlte` (`lqgFIeTbSdPRT8zz`) | the three tools `assign_livestock_identifier`, `request_tag_change`, `cancel_tag_change` on the livestock `AI Agent` (same fixed queries as in the chat; identity from `$('Resolver Tenant').first()`, never from the model); the same prompt edits as the chat (Section C exception, B5 exception, D2, D3, new D5, dictionary); `Resolver Tenant` rewritten for the shared-phone rule; new nodes `IF - Teléfono único` and `Set - Mensaje Teléfono Compartido` |

No workflow id, `webhookId`, trigger, credential reference or `settings` changes. The real WhatsApp trigger and the send nodes are untouched.

### Shared-phone rule
`Resolver Tenant` selects the company as before (one entry per company). Then, **for the selected company only**: more than one distinct user behind the phone, or an entry without an e-mail, ends in `tenant_status = 'shared_phone'`
(no tenant, no e-mail) and the user gets a fixed message; the agent is not called and nothing is written. A phone shared by users of DIFFERENT companies keeps working: the selected company decides and its e-mail is used.
Production check (counts only, 2026-11-26): 0 phones shared by more than one active user.

## Preconditions
1. The database part and the MCP server, notification and chat workflows of this PR are deployed and verified.
2. The WhatsApp workflow was NOT changed by hand in production since `main`: compare the production export with the "before" fingerprint below (CLAUDE.md procedure, step 3).
3. The WhatsApp trigger credential is complete and unchanged (it is not touched by this import).

## Import (CLAUDE.md "Runbook de despliegue de workflows en n8n 2.x", one workflow)
| Workflow file | before (HEAD) | after (this PR) | Nodes whose `parameters` change | Connections that change |
|---|---|---|---|---|
| `v6_WhatsApp_Agent_Cattle.json` | `42c8c25d722bddb0` | `298a01a8d7353656` | `AI Agent`, `Resolver Tenant`; added: the three tools, `IF - Teléfono único`, `Set - Mensaje Teléfono Compartido` | `Resolver Tenant`, `IF - Teléfono único`, `Set - Mensaje Teléfono Compartido`, the three tools |

The fingerprint snippet is in `116_RUNBOOK.md`. After the import: confirm the name and the published state, re-export and compare with the `develop` JSON (`No differences.`), and run the behaviour checks of step 8 with the test company only.

## Verification (test company only, decided by the owner)
- A message from a phone with one user: normal flow.
- A phone shared by users of one company (create the case only in a test company): the fixed message, no agent run, nothing written.
- One chip assignment through the two-call flow, as in conversation C0 of `116_n8n_tests.md`.

## Rollback
Re-import the saved export of the production workflow (step 2 of the procedure), Save and Publish. No database change is involved.

## Local DEV tests (before production)
Generated and imported like the other DEV copies (`dev/make_dev.py`, git-ignored): the real WhatsApp trigger is replaced by a webhook (`POST v6/wa-dev`) and every send node by a node that sends nothing. Rows 54 to 61, C10 and C12 of `116_n8n_tests.md` are run on it with `python3 -I run_tool_tests.py --sections 5` and `chat_repl.py --wa <phone>`.

## Evidence
- `dev/code_harness.js` (Node): 12 `Resolver Tenant` scenarios (shared inside the company, shared across companies, missing e-mail, malformed input, cached selection): pass.
- `dev/qr_harness.js` (Node): the tool expressions of both agents: pass.
- Not run: anything inside n8n for this workflow.
