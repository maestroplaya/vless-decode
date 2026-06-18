#!/bin/bash

# Check if a URL was provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <subscription_url>"
    echo "Example: $0 'https://your-durev.com/sub/Kk6Z1VoK0PWn0JyxK6TRwR/'"
    exit 1
fi

SUB_URL="$1"

echo "Downloading, decoding, and generating config..."

# Pipe curl directly into Python to avoid temp files and OS-specific base64 issues
curl -s -L --compressed "$SUB_URL" | python3 -c "
import sys, re, json, base64
from urllib.parse import parse_qsl

raw = sys.stdin.read().strip()

# Handle URL-safe base64 and missing padding
raw = raw.replace('-', '+').replace('_', '/')
raw += '=' * (-len(raw) % 4)

try:
    decoded = base64.b64decode(raw).decode('utf-8')
except Exception:
    decoded = raw  # Fallback if the sub is already plain text

lines = decoded.split('\n')
try:
    # Find the first matching vless reality tcp link
    line = [l for l in lines if l.startswith('vless://') and 'reality' in l and 'type=tcp' in l][0]
except IndexError:
    print('Error: No matching vless:// reality tcp link found in subscription.', file=sys.stderr)
    sys.exit(1)

m = re.match(r'vless://([^@]+)@([^:]+):(\d+)\?([^#]+)', line)
if not m:
    print('Error: Failed to parse the VLESS URI.', file=sys.stderr)
    sys.exit(1)

uuid, host, port, qs = m.groups()
p = dict(parse_qsl(qs))

cfg = {
    'log': {'level': 'info'},
    'inbounds': [{'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': 2080}],
    'outbounds': [{
        'type': 'vless',
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
    }]
}

print(json.dumps(cfg, indent=2))
" > cfg.json

echo "Done! Configuration saved to cfg.json"
