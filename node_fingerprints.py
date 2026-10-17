#!/usr/bin/env python3
"""Read-only fingerprints of an n8n workflow export, used to verify CRUD and error-handler deployments.

Usage:
    python3 -I node_fingerprints.py <workflow-export.json> [<workflow-export.json> ...]

It only reads the given files and prints, per workflow: id, name, active flag, versionId, an MD5 of the
code/query of the nodes that the v1.17.1 / v1.17.2 deployments change, the webhook path and webhookId,
and the NAMES of the Postgres credentials. It never writes anything and never prints credential values,
URLs, tokens, pinned data or message texts: the ntfy alert node is reported only as where its URL comes
from (environment vs. literal) plus booleans.
"""
import hashlib
import json
import sys

# Nodes whose code/query is fingerprinted (v5/CRUD, v6/CRUD and the Global Error Handler).
TRACKED_NODES = (
    'Get Model Name', 'Model Allowlist', 'Is Allowed Model', 'Model Not Registered',
    'Get Model Config', 'Build Query', 'Normalize Data', 'Execute a SQL query',
)
ALERT_NODE = 'Alerta (Webhook/HTTP)'


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
        elif name == ALERT_NODE:
            url = str(params.get('url', ''))
            if url.replace(' ', '') == '={{$env.NTFY_ALERT_URL}}':
                url_source = 'env:NTFY_ALERT_URL'
            elif 'ntfy' in url:
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


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit('usage: python3 -I node_fingerprints.py <workflow-export.json> [...]')
    for arg in sys.argv[1:]:
        fingerprint(arg)
