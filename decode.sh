#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <subscription_url>"
    exit 1
fi

SUB_URL="$1"
echo "Generating fixed config for sing-box 1.13.13..."

curl -s -L --compressed "$SUB_URL" | python3 -c "
import sys, re, json, base64
from urllib.parse import parse_qsl

raw = sys.stdin.read().strip()
raw = raw.replace('-', '+').replace('_', '/')
raw += '=' * (-len(raw) % 4)
try:
    decoded = base64.b64decode(raw).decode('utf-8')
except Exception:
    decoded = raw

try:
    line = [l for l in decoded.split('\n') if l.startswith('vless://') and 'reality' in l and 'type=tcp' in l][0]
except IndexError:
    print('Error: No matching vless:// reality tcp link found.', file=sys.stderr)
    sys.exit(1)

m = re.match(r'vless://([^@]+)@([^:]+):(\d+)\?([^#]+)', line)
if not m:
    print('Error: Failed to parse VLESS URI.', file=sys.stderr)
    sys.exit(1)

uuid, host, port, qs = m.groups()
p = dict(parse_qsl(qs))

vless_outbound = {
    'type': 'vless',
    'tag': 'proxy',
    'server': host,
    'server_port': int(port),
    'uuid': uuid,
    'network': 'tcp',
    'tls': {
        'enabled': True,
        'server_name': p.get('sni'),
        'utls': {'enabled': True, 'fingerprint': p.get('fp', 'chrome')},
        'reality': {
            'enabled': True,                 # FIX: was missing -> reality was silently inert
            'public_key': p.get('pbk'),
            'short_id': p.get('sid', '')
        }
    }
}
if p.get('flow'):
    vless_outbound['flow'] = p['flow']        # only set when present/non-empty

cfg = {
    'log': {'level': 'info'},
    'dns': {
        'servers': [
            {'tag': 'remote', 'type': 'tcp', 'server': '8.8.8.8', 'detour': 'proxy'},
            {'tag': 'local', 'type': 'https', 'server': '1.1.1.1'}
            # FIX: removed 'detour': 'direct' here -> pointing at a bare/empty
            # direct outbound is rejected by 1.13.13 ('detour to an empty
            # direct outbound makes no sense'). Omitting it = direct by default.
        ],
        'final': 'remote',
        'strategy': 'ipv4_only'
    },
    'inbounds': [{
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'tun0',
        'address': ['172.19.0.1/30'],
        'auto_route': True,
        'strict_route': True,
        'mtu': 1350
    }],
    'outbounds': [
        vless_outbound,
        {'type': 'direct', 'tag': 'direct'}
    ],
    'route': {
        'rules': [
            {'inbound': 'tun-in', 'action': 'sniff'},
            {'inbound': 'tun-in', 'action': 'resolve'},
            {'protocol': 'dns', 'action': 'hijack-dns'},
            {'port': 123, 'network': 'udp', 'outbound': 'direct'}
        ],
        'final': 'proxy',
        'auto_detect_interface': True,
        # FIX: this is the exact thing your screenshot's FATAL is about.
        # Resolves the proxy server's own address (if it's a domain) via the
        # 'local' resolver instead of 'remote' (which dials through 'proxy'
        # itself -> circular dependency).
        'default_domain_resolver': 'local'
    }
}
print(json.dumps(cfg, indent=2))
" > cfg.json

echo "Config generated. Run with: sudo sing-box run -c cfg.json"
