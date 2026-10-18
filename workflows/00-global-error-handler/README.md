# Global Error Handler (`9SrVXdATmlrZemJT`)

Error workflow (`settings.errorWorkflow`) of `v5/CRUD`, `v6/CRUD` and other workflows. On every failed
execution it formats the error and then runs two branches, **alert first** (with `executionOrder: v1`
n8n runs branches top to bottom by canvas position, so the alert node must stay above the SQL node):

1. **Alerta (Webhook/HTTP)** — posts a short alert to ntfy: workflow, failed node and execution link.
   The raw error text is **never** sent (Postgres errors can carry row values, e.g.
   `Key (email)=(…) already exists`). `onError: continueRegularOutput`, so a ntfy failure never blocks the log.
2. **Execute a SQL query** — inserts the full error into `n8n_error_logs` (`hosting3m_db`), with bound
   parameters (`queryReplacement`), `NULL`/empty-safe and truncated to the column sizes. If it fails, the
   alert has already gone out.

> **Parameters are text in both layers (v1.18.2).** n8n passes an array `queryReplacement` with its JS
> types and pg-promise formats the query client-side, so a number goes in unquoted: the Error Trigger's
> manual-mode example data (`execution.id: 231`) turned `NULLIF($2, '')` into `NULLIF(231, '')` →
> `invalid input syntax for type integer: ""`. The query casts `$1::text … $4::text` and the expression
> maps every value to `String(...)` (objects to JSON, `null`/`undefined` to `null`, never dropped).

> n8n 2.x only runs an error workflow that is **active**. An inactive handler is skipped
> ("is not active and cannot be executed"): no alert and no `n8n_error_logs` row.

## Configuration: `NTFY_ALERT_URL`

The ntfy topic is a secret and is **not versioned**. The alert node reads it from the environment:
`={{ $env.NTFY_ALERT_URL }}`.

- Set `NTFY_ALERT_URL=https://ntfy.sh/<random-topic>` in `infrastructure/.env` (loaded by the `n8n`
  service through `env_file`; never committed) and restart the n8n container so it reads it.
- Requires `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` (current value) and the variable must **not** be listed in
  `N8N_BLOCK_ENV_VARS_INCLUDE`.
- If the variable is missing or ntfy is down, the alert node fails but does not stop the workflow
  (`onError: continueRegularOutput`): the `n8n_error_logs` row is still written.
- Use a random, non-guessable topic name and never paste it in chats, logs or commits (same rule as any
  secret, see `CONTRIBUTING.md`).

## Proposal (not implemented): protected topic with an access token

A random topic name only hides the topic; anyone who learns it can read it. To protect it:

1. Reserve the topic in an ntfy account (or a self-hosted ntfy) with anonymous read/write denied.
2. Create an access token (`tk_…`) with write permission on that topic.
3. In n8n, create a **Bearer Auth** credential (e.g. "ntfy alerts") holding the token, and set the alert
   node to Authentication → Generic credential type → Bearer Auth → that credential. The token then
   lives encrypted in n8n, never in the workflow JSON or in `.env`.
4. Subscribe the phones/clients with the same account or a read-only token.
