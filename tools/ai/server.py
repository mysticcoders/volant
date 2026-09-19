"""Fictional loopback-only API fixture. Never logs request text, keys or headers."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, sys, time
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        if self.path.startswith('/redirect/'):
            self.send_response(302); self.send_header('Location', 'https://example.invalid/do-not-follow'); self.end_headers(); return
        data = json.dumps({'data': [{'id': 'fixture-model'}]}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        prompt = body['messages'][-1]['content']
        if prompt == 'unauthorized':
            self.send_response(401); self.end_headers(); self.wfile.write(b'fictional secret error body'); return
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
        try:
            if prompt == 'slow': time.sleep(1)
            text = 'OLD cancelled response' if prompt == 'slow' else 'Hello caf\u00e9 \u2615'
            payload = json.dumps({'choices': [{'delta': {'content': text}}]}, ensure_ascii=False)
            self.wfile.write(('data: '+payload+'\n\n').encode()); self.wfile.flush()
            if prompt != 'truncated': self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError): pass
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
