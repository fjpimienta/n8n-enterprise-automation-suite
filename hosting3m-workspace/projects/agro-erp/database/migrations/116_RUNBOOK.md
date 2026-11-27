> ⛔ **NO MERGEAR A `main` HASTA COMPLETAR LAS PARTES 1 Y 2** (base de datos y n8n, verificadas con sus huellas).
> `main` se despliega manualmente por Plesk con git: si el frontend se despliega antes, la pantalla nueva falla en producción.

> **Status: written for review. The workflow candidates were checked only with Node harnesses (see "Evidence"). NOT imported anywhere, NOT run in n8n.**
> Part 1 = database (PR 2a `115_tag_change_authorization` + `116_tag_change_chat_guard`, in that order). Part 2 = n8n (this PR: four workflows, imported in this order: MCP server, notification, chat and, LAST, WhatsApp; the WhatsApp-specific procedure is in `116_whatsapp_RUNBOOK.md`). The frontend (PR 2c) is last and is not needed for this PR to work;
> until 2c exists the Bitácora shows the new event type as the raw code `SOLICITUD_CAMBIO_ARETE`.

# Runbook — PR 2b: panel-only approval guard (database) and n8n changes for identifier assignment and change requests (MCP server, notification, chat, WhatsApp)

## What changes

| Workflow (id in production) | Change |
|---|---|
| `v6/MCP Server Cattle` (`pJ3CEaO70QEiGL0C`) | `update_livestock_tag` removed (node and connection); `get_livestock_info` resolves through `fn_resolve_identifier` (adds `identifier_match`); `list_pending_requests` also returns `tag_type`, `old_value`, `new_value`, `reason`; `review_pending_request` description and own-request message |
| `v6/ai/chat cattle` (`RM60Dm0e3r03dvnp`) | 3 new direct `postgresTool` nodes on the livestock `AI Agent`: `assign_livestock_identifier`, `request_tag_change`, `cancel_tag_change`; prompt edits (A5, identifier list, NIVEL 3, dictionary, D2, D3, new D5) |
| `V6/Notificación de Autorizaciones Pendientes` (`UrYaK5hHb9KLSp5L`) | label "Cambio de identificador", tag fields in the query and email; baja and venta emails are byte-identical (checked) |

No workflow id, `webhookId`, `typeVersion` of an existing node, credential reference or `settings` changes in the candidates.

Identity of the new tools is never a model parameter: chat uses `$('Resolver Empresa Chat').first()` and `$('Validar Token').first()`. Every query is fixed and parameterized (`$n::text`, `String(...)` in the expression).

### Tag-change approval is panel-only
`sp_review_pending_request` (the chat wrapper) refuses to approve a `CAMBIO_ARETE` (`P0136`, migration `116_tag_change_chat_guard.sql`). The tool description and the prompt state it as well; the rule itself lives in the database.

## Part 1 — database (must be done first, verified, before any import)
1. `115_tag_change_authorization.sql` (PR 2a) — its own runbook: `115_RUNBOOK.md`.
2. `116_tag_change_chat_guard.sql` — dry run, then `-v apply=true`. Precondition: the wrapper md5 is `69721334b082bdf3aa1f70a362e3440c` (the migration also refuses any other text).
3. Verify: `SELECT pg_get_functiondef('public.sp_review_pending_request(uuid,integer,character varying,character varying,text)'::regprocedure) LIKE '%chat-guard-cambio-arete%';` → `t`.
Rollback order for everything: this PR's workflows → `116_rollback.sql` → `115_rollback.sql` → step 1.

## Part 2 — n8n (procedure of CLAUDE.md, "Runbook de despliegue de workflows en n8n 2.x", applied to four workflows)
Import **one workflow at a time, in this order**, running steps 2 to 8 of that procedure for each; do not start the next until the previous one verified:

| # | Workflow | Why this order |
|---|---|---|
| 1 | `v6/MCP Server Cattle` | removes the old tool and changes `get_livestock_info`; needs the database part (it calls `fn_resolve_identifier`). The agents still list tools through MCP, so nothing breaks while the next ones are pending. |
| 2 | `V6/Notificación de Autorizaciones Pendientes` | independent; it only reads. Needs nothing from the agents. |
| 3 | `v6/ai/chat cattle` | adds the three tools + prompt |
| 4 | `v6/WhatsApp Agent Catlte` | same three tools and prompt as the chat, plus the shared-phone rule; imported LAST, after 1 to 3 verified in production; see `116_whatsapp_RUNBOOK.md` for its fingerprints, checks and rollback |

Step 3 of that procedure (compare production with `main`) is the stop gate. Fingerprints of the **current `main` files** ("before"; the production export must give the same, otherwise stop and incorporate the manual change into `main` first, as happened on 2026-10-24):

| Workflow file | before (HEAD) | after (this PR) | Nodes whose `parameters` change | Connections that change |
|---|---|---|---|---|
| `v6_MCP_Server_Cattle.json` | `387e7f85e9f087db` | `872d4f3c352044e4` | `get_livestock_info`, `list_pending_requests`, `review_pending_request`, `move_livestock`; `update_livestock_tag` removed | `update_livestock_tag` |
| `v6_Notificacion_Autorizaciones.json` | `204266516f301f8d` | `4849b0d6b4092d3c` | `Buscar Pendientes Sin Notificar`, `Preparar Contenido de Correo` | none |
| `v6_ai_chat_cattle.json` | `664bead7c53f1e05` (**production export of 2026-11-26**; `main` alone is `cdc83e7f1eb11264`, see the next section) | `3cbd57ecdd0d94e3` raw, `36f1d693709bb268` normalized | `AI Agent` (prompt); added: `assign_livestock_identifier`, `request_tag_change`, `cancel_tag_change`. Compared with the production export, nothing else changes once the palm sub-workflow id is normalized | the three new tools |

### Chat workflow: production already differs from `main` (checked 2026-11-26)
The production chat export (`664bead7c53f1e05`) differs from `main` (`cdc83e7f1eb11264`) by manual changes that this PR brings into the repository, so that the import does not remove them:
- three nodes that exist only in production: `Classify Chat Error`, `Fail After Reply`, `Respond Chat Error`, and the second output (error output) of `AI Agent` and `AI Agent Palma` that feeds them (`onError: continueErrorOutput` on both agents);
- `maxRetries: 1` in the options of `OpenAI Chat Model` and `OpenAI Chat Model Palma`;
- the workflow setting `saveDataSuccessExecution: "all"`, which is **deliberately not brought into the repository**: the production instance already saves everything (`EXECUTIONS_DATA_SAVE_ON_SUCCESS=all`, `EXECUTIONS_DATA_SAVE_ON_ERROR=all`, pruned after 336 hours), so the chat inherits the same behaviour from the instance variables without a workflow-level override. Importing the file removes that override from the production workflow; executions are still saved;
- the id of the palm sale sub-workflow in `Venta Palma XML` (see below).
A different canvas layout and the order of the tags also differ; neither is part of the fingerprint.

**The palm sub-workflow id is not copied into the repository.** The file keeps the placeholder `PalmSaleXml0001a` (the id of `v6_palm_sale_from_xml.json` in the repo); production has its own id. So a raw comparison of the production export against the candidate always reports `Venta Palma XML` as different; that is the ONLY accepted difference. To compare the rest, normalize both exports first (the three values below) and compare the normalized fingerprints; the production export must give `e9139639cb41544a` and the candidate `36f1d693709bb268`:
```sh
python3 -I - /path/to/export.json <<'EOF'
import json, hashlib, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
nodes = {n['name']: json.loads(json.dumps(n.get('parameters', {}))) for n in d['nodes']}
w = nodes['Venta Palma XML']['workflowId']
w['value'] = 'PalmSaleXml0001a'; w.pop('cachedResultUrl', None); w.pop('cachedResultName', None)
print(hashlib.sha256(json.dumps({'nodes': nodes, 'connections': d.get('connections', {})}, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()[:16])
EOF
```

**After importing the chat workflow (a required post-import step):** open the node `Venta Palma XML` and set its sub-workflow to the production palm sale workflow (select `v6/palm sale from xml` from the list), Save and Publish, then confirm with a re-export that its `workflowId.value` is the production id and nothing else changed (compare the normalized fingerprint above). Until this is done, a palm XML sale in the chat fails. Also confirm that the chat has no workflow-level success-saving override (`Settings` → "Save successful production executions" is "Default") and that executions are still saved (open the Executions list and check that a new test execution appears), and that both agents show an error output.

Fingerprint = first 16 hex of SHA-256 over `{node name: parameters}` + `connections` (sorted keys, compact separators, UTF-8). Reproduce with:
```sh
python3 -I - /path/to/export.json <<'EOF'
import json, hashlib, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
nodes = {n["name"]: n.get("parameters", {}) for n in d["nodes"]}
blob = json.dumps({"nodes": nodes, "connections": d.get("connections", {})}, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
print(hashlib.sha256(blob.encode()).hexdigest()[:16])
EOF
```
(`~/node_fingerprints.py`, named in CLAUDE.md, does not exist on this machine; the snippet above is self-contained.) The CLAUDE.md comparison snippet prints exactly the nodes and connections that differ, which must equal the two right-hand columns of the table.

For each workflow, after import: confirm name and published state, re-export and compare with the `develop` JSON (`No differences.`), then the behaviour checks of step 8 (a request without authentication denied; one normal authenticated action works). Behaviour of the new tools is tested in the DEV copies first (below), not for the first time in production. Production tests, when done, use the test company only (`id_company = 3`).

### Rollback
Re-import the backups of step 2 (one per workflow), Save and Publish, in the reverse order (4, 3, 2, 1). Then the database rollbacks in the order given above. Pending `CAMBIO_ARETE` requests that already exist are unaffected by the workflow rollback (they expire at midnight or are rejected in the panel).

## Local test setup (DEV copies, `hosting3m_rehearsal`)
Verified by the owner on 2026-11-26: the local n8n uses the database `n8n_db`, has no mail/WhatsApp variables and **0** smtp / whatsApp / bearer credentials. Still, before importing:
1. Credentials that must exist locally for the DEV copies: the Postgres credential for `hosting3m_rehearsal` (the owner creates it and gives id and name) and an **OpenAI** credential for the agents. No mail, WhatsApp or bearer credential is needed or wanted: the generator strips them.
2. Generate the copies (git-ignored directory): `cd workflows/09-MCP-Agent-Cattle/v6/dev && DEV_PG_CRED_ID=<id> DEV_PG_CRED_NAME='<name>' [DEV_OPENAI_CRED_ID=<id> DEV_OPENAI_CRED_NAME='<name>'] python3 -I make_dev.py`.
   It refuses to finish if an enabled WhatsApp/mail node, a production host, a workflow id or a production Postgres credential remains.
3. Import the DEV files of this PR (MCP server, notification, chat, WhatsApp) in the same order as above (they are inactive; activate the MCP server, chat and WhatsApp copies when testing, never the notification copy: run that one manually). In the WhatsApp copy the audio media `Download` node is disabled by the generator (it would ask for a WhatsApp credential). Details of the WhatsApp copy: `116_whatsapp_RUNBOOK.md`.
4. After importing, open each DEV workflow and check: no node says "credential not found" except OpenAI if you did not set it; `SMTP` and `Marcar como Notificado` are disabled in the notification copy.
5. The rehearsal database holds production-derived e-mails and phone numbers: **nothing in the DEV copies may send**. That is why the send nodes and SMTP are replaced or disabled; do not re-enable them.
6. Fixtures (git-ignored): `rfid_tags_test_fixtures.sql` then `rfid_tags_wa_fixtures.sql`; reset with `rfid_tags_test_fixtures_cleanup.sql`.
7. Tests: `116_n8n_tests.md`. Stop criteria are at its end.

## Evidence (what was actually run)
- `dev/qr_harness.js` (Node): the `queryReplacement` of the three tools in both agents, with stubs for `$fromAI` and `$()`: 34 checks pass (a one-sentence chip assignment, dropped or altered digits, dictated digits, empty message, confirmation without message check, fire numbers, leading zeros, comma, null-like strings, quote-and-semicolon reason, cancel).
- `dev/code_harness.js` (Node): the notification builder (baja and venta output compared with the original from `git HEAD`: byte-identical; tag change: label, fields, no price sentence, HTML escaped): 15 checks pass.
- JSON integrity of the candidates: loads, no dangling connection, unique node ids, no mention of `update_livestock_tag`.
- Not run: anything inside n8n.
