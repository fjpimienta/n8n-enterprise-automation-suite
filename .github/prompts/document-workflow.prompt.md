---
description: 'Generate or update the README of an n8n workflow folder'
agent: agent
---

Document the n8n workflow folder `workflows/${input:workflowFolder:e.g. 06-dynamic-crud-engine}`.

1. List its `vN` subfolders and identify the current version.
2. Search the workflow JSON for webhook nodes, tenant filters (`id_company`), data store nodes and error handling. Do not read entire files and do not copy credentials or real URLs.
3. Write or update the folder `README.md` following the n8n workflow documentation standard.
4. In the Versions table, describe differences between versions only when they are visible in the JSON. Otherwise use `TODO(verify)`.
5. Flag any path that does not filter by tenant as a RISK item. Do not change workflows.

Output: files changed, RISK items found, and `TODO(verify)` list.
