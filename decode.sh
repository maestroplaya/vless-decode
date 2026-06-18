#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <subscription_url>"
    exit 1
fi

SUB_URL="$1"
echo "Downloading, decoding, and generating TUN config for sing-box 1.13+..."

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

lines = decoded.split('\n')
try:
    line = [l for l in lines if l.startswith('vless://') and 'reality' in l and 'type=tcp' in l][0]
except IndexError:
    print('Error: No matching vless:// reality tcp link found.', file=sys.stderr)
    sys.exit(1)

m = re.match(r'vless://([^@]+)@([^:]+):(\d+)\?([^#]+)', line)
uuid, host, port, qs = m.groups()
p = dict(parse_qsl(qs))

# Generate System-Wide TUN Configuration (Updated for sing-box 1.13+)
cfg = {
    'log': {'level': 'info'},
    'dns': {
        'servers': [
            {'tag': 'remote', 'type': 'https', 'server': '1.1.1.1', 'path': '/dns-query'},
            {'tag': 'local', 'type': 'udp', 'server': '223.5.5.5', 'detour': 'direct'}
        ],
        'rules': [{'outbound': 'any', 'server': 'remote'}],
        'strategy': 'ipv4_only'
    },
    'inbounds': [{
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'tun0',
        'inet4_address': '172.19.0.1/30',
        'auto_route': True,
        'stack': 'system',
        'sniff': True
    }],
    'outbounds': [
        {
            'type': 'vless',
            'tag': 'proxy',
            'server': host,
            'server_port': int(port),
            'uuid': uuid,
            'tls': {
                'enabled': True,
                'server_name': p.get('sni'),
                'utls': {'enabled': True, 'fingerprint': p.get('fp', 'chrome')},
                'reality': {
                    'enabled': True,
                    'public_key': p.get('pbk'),
                    'short_id': p.get('sid')
                }
            }
        },
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'}
        # REMOVED: {'type': 'dns', 'tag': 'dns-out'}
    ],
    'route': {
        # CHANGED: Replaced outbound routing with the 'hijack-dns' rule action
        'rules': [{'action': 'hijack-dns'}],
        'auto_detect_interface': True
    }
}

print(json.dumps(cfg, indent=2))
" > cfg.json

echo "Done! System-wide config saved to cfg.json"
