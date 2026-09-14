"""Synthetic schema-3 archive; never reads a personal export. Requires cryptography."""
import gzip, hashlib, json, struct, sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
salt = bytes(range(16))
iv = bytes(range(16, 32))
header = gzip.compress(json.dumps({'schemaVersion': 3, 'encryption': {'iv': iv.hex(), 'salt': salt.hex()}}).encode(), mtime=0)
payload = {'snippets': {'snippets': [{'title': 'Daily update', 'text': 'Today {date}: {clipboard}', 'keyword': ';daily'}]}, 'notes': {'notes': [{'title': 'Fixture', 'markdown': 'Only fictional data.'}]}}
key = hashlib.scrypt(b'fictional-password', salt=salt, n=16384, r=8, p=1, dklen=32, maxmem=64*1024*1024)
body = AESGCM(key).encrypt(iv, gzip.compress(json.dumps(payload).encode(), mtime=0), None)
with open(sys.argv[1], 'wb') as output:
    output.write(b'RAYCFG3\n' + struct.pack('<I', len(header)) + header + body)

# Malformed unauthenticated header: 32 UTF-8 bytes, but 31 grapheme clusters.
malformed = gzip.compress(json.dumps({'schemaVersion': 3, 'encryption': {'iv': '0' * 30 + 'é', 'salt': salt.hex()}}).encode(), mtime=0)
with open(sys.argv[1] + '.badhex', 'wb') as output:
    output.write(b'RAYCFG3\n' + struct.pack('<I', len(malformed)) + malformed + body)
