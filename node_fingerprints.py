#!/usr/bin/env python3
"""Read-only fingerprints of an n8n workflow export, used to verify CRUD and error-handler deployments.

Usage:
    python3 -I node_fingerprints.py <workflow-export.json> [<workflow-export.json> ...]

It only reads the given files and prints, per workflow: id, name, active flag, versionId, an MD5 of the
code/query of the nodes that the v1.17.1 / v1.17.2 / v1.18.3 deployments change (plus a separate MD5 of
`options.queryReplacement` when a tracked node has one), the webhook path and webhookId, and the NAMES of
the Postgres credentials. It never writes anything and never prints credential values, URLs, tokens,
pinned data or message texts: the ntfy alert node is reported only as where its URL comes from
(environment vs. literal) plus booleans, and email nodes only as disabled or not.

Chat / MCP workflows (palm phase 2b): every Postgres tool of an MCP server (`postgresTool`, by name) gets an MD5 of
its query and of its queryReplacement; every AI Agent an MD5 of its systemMessage; every MCP client only the KIND of
endpoint it calls (production / localhost / unknown, by exact host), never the URL; MCP triggers their path. Workflows with an AI Agent
also get an MD5 of their connections (routing changes, such as the palm short-circuit, are connection changes).
"""
import hashlib
import json
import sys
from urllib.parse import urlparse

# Nodes whose code/query is fingerprinted (v5/CRUD, v6/CRUD, the Global Error Handler and the
# Public Booking Engine).
TRACKED_NODES = (
    'Get Model Name', 'Model Allowlist', 'Is Allowed Model', 'Model Not Registered',
    'Get Model Config', 'Build Query', 'Normalize Data', 'Execute a SQL query',
    'Check Availability SQL', 'Get Specific Room SQL', 'Upsert Guest & Book', 'Site Config', 'Is Lead Request?',
    # Web Chat / WhatsApp agents (palm phase 2b)
    'Resolver Empresa Chat', 'Get User Role', 'Resolver Tenant', 'Set Prompt Final',
    'Es Empresa de Palma', 'Respond Empresa Palma', 'Set - Mensaje Empresa Palma',
    'Simple Memory',  # session key of the agents (Web Chat: per sessionId and company)
)
TOOL_TYPE = 'n8n-nodes-base.postgresTool'
AGENT_TYPE = '@n8n/n8n-nodes-langchain.agent'
MCP_CLIENT_TYPE = '@n8n/n8n-nodes-langchain.mcpClientTool'
MCP_TRIGGER_TYPE = '@n8n/n8n-nodes-langchain.mcpTrigger'


PRODUCTION_HOSTS = frozenset({'n8n.hosting3m.com'})
LOCAL_HOSTS = frozenset({'localhost', '127.0.0.1', 'n8n-enterprise-core'})
NTFY_HOSTS = frozenset({'ntfy.sh'})


def url_host(url):
    """Exact, lower-case host of a URL ('' when there is none). A leading '=' (n8n expression marker) is ignored."""
    text = str(url or '').strip()
    if text.startswith('='):
        text = text[1:].strip()
    try:
        return (urlparse(text).hostname or '').lower()
    except ValueError:
        return ''


def endpoint_kind(url):
    host = url_host(url)
    if host in PRODUCTION_HOSTS:
        return 'production'
    if host in LOCAL_HOSTS:
        return 'localhost'
    return 'unknown'
ALERT_NODE = 'Alerta (Webhook/HTTP)'
# Reported only as disabled or not: a production test may disable them and must re-enable them.
EMAIL_NODES = ('Send Email',)


def md5(text):
    return hashlib.md5(text.encode('utf-8')).hexdigest()


def fingerprint(path):
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh)
    wf = data[0] if isinstance(data, list) else data
    nodes = wf.get('nodes', [])

    print(f"workflow {wf.get('id')} {wf.get('name')} active={wf.get('active')} versionId={wf.get('versionId')}")
    for n in sorted(nodes, key=lambda x: x.get('name', '')):
        name = n.get('name')
        params = n.get('parameters', {})
        if name in TRACKED_NODES:
            source = params.get('jsCode') or params.get('query') or json.dumps(params, sort_keys=True)
            print(f"  {name:<22} {md5(source)}")
            replacement = params.get('options', {}).get('queryReplacement')
            if replacement is not None:
                print(f"  {name:<22} queryReplacement {md5(str(replacement))}")
        elif n.get('type') == TOOL_TYPE:
            print(f"  tool {name:<30} {md5(params.get('query', ''))}")
            print(f"  tool {name:<30} queryReplacement {md5(str(params.get('options', {}).get('queryReplacement', '')))}")
        elif n.get('type') == AGENT_TYPE:
            system = params.get('options', {}).get('systemMessage', params.get('systemMessage', ''))
            print(f"  {name:<22} systemMessage {md5(str(system))}")
        elif n.get('type') == MCP_CLIENT_TYPE:
            print(f"  {name:<22} endpoint={endpoint_kind(params.get('endpointUrl'))}")
        elif n.get('type') == MCP_TRIGGER_TYPE:
            print(f"  {name:<22} mcp path={params.get('path')}")
        elif name in EMAIL_NODES:
            print(f"  {name:<22} disabled={bool(n.get('disabled'))}")
        elif name == ALERT_NODE:
            url = str(params.get('url', ''))
            if url.replace(' ', '') == '={{$env.NTFY_ALERT_URL}}':
                url_source = 'env:NTFY_ALERT_URL'
            elif url_host(url) in NTFY_HOSTS:
                url_source = 'LITERAL-NTFY-URL'
            else:
                url_source = 'other'
            message = ' '.join(
                str(p.get('value', ''))
                for p in params.get('bodyParameters', {}).get('parameters', [])
                if p.get('name') == 'message'
            )
            print(f"  {name:<22} url_source={url_source} "
                  f"message_has_error_text={'error_message' in message} "
                  f"onError={n.get('onError')} disabled={bool(n.get('disabled'))}")

    webhooks = [n for n in nodes if str(n.get('type', '')).endswith('.webhook')]
    for wh in webhooks:
        print(f"  webhook path={wh.get('parameters', {}).get('path')} webhookId={wh.get('webhookId')}")

    pg_creds = sorted({
        str((n.get('credentials') or {}).get('postgres', {}).get('name'))
        for n in nodes if n.get('type') == 'n8n-nodes-base.postgres'
    })
    pg_count = sum(1 for n in nodes if n.get('type') == 'n8n-nodes-base.postgres')
    print(f"  postgres nodes={pg_count} credential names={pg_creds}")

    if any(n.get('type') == AGENT_TYPE for n in nodes):
        print(f"  connections {md5(json.dumps(wf.get('connections', {}), sort_keys=True))}")

    tools = [n for n in nodes if n.get('type') == TOOL_TYPE]
    if tools:
        tool_creds = sorted({str((n.get('credentials') or {}).get('postgres', {}).get('name')) for n in tools})
        print(f"  postgres tools={len(tools)} credential names={tool_creds}")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit('usage: python3 -I node_fingerprints.py <workflow-export.json> [...]')
    for arg in sys.argv[1:]:
        fingerprint(arg)
