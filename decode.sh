#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <subscription_url>"
    exit 1
fi

SUB_URL="$1"
echo "Generating fixed config..."

# We decode the URL once and pass the parameters to the template
curl -s -L --compressed "$SUB_URL" | python3 -c "
import sys, re, json, base64
from urllib.parse import parse_qsl

raw = sys.stdin.read().strip()
raw = raw.replace('-', '+').replace('_', '/')
raw += '=' * (-len(raw) % 4)
try:
    decoded = base64.b64decode(raw).decode('utf-8')
except:
    decoded = raw

line = [l for l in decoded.split('\n') if l.startswith('vless://') and 'reality' in l][0]
m = re.match(r'vless://([^@]+)@([^:]+):(\d+)\?([^#]+)', line)
uuid, host, port, qs = m.groups()
p = dict(parse_qsl(qs))

# Generate JSON
cfg = {
    'log': {'level': 'info'},
    'dns': {
        'servers': [
            {'tag': 'remote', 'type': 'tcp', 'server': '8.8.8.8', 'detour': 'proxy'},
            {'tag': 'local', 'type': 'https', 'server': '1.1.1.1', 'detour': 'direct'}
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
        {'type': 'direct', 'tag': 'direct'},
        {
            'type': 'vless',
            'tag': 'proxy',
            'server': host,
            'server_port': int(port),
            'uuid': uuid,
            'flow': p.get('flow', ''),
            'network': 'tcp',
            'tls': {
                'enabled': True,
                'server_name': p.get('sni'),
                'utls': {'enabled': True, 'fingerprint': p.get('fp', 'chrome')},
                'reality': {'public_key': p.get('pbk'), 'short_id': p.get('sid', '')}
            }
        }
    ],
    'route': {
        'rules': [
            {'inbound': 'tun-in', 'action': 'sniff'},
            {'inbound': 'tun-in', 'action': 'resolve'},
            {'protocol': 'dns', 'action': 'hijack-dns'},
            {'port': 123, 'network': 'udp', 'outbound': 'direct'}
        ],
        'final': 'proxy',
        'auto_detect_interface': True
    }
}
print(json.dumps(cfg, indent=2))
" > cfg.json

echo "Config generated. Run with: sudo sing-box run -c cfg.json"
