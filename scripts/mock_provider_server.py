#!/usr/bin/env python3
"""Synthetic-only UI transport fixture. This does not call Gemini, OpenAI, or ElevenLabs."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json

MODEL = 'mock-transport-only'

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log bodies, records, or tokens.

    def send_json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authenticated(self):
        if self.headers.get('Authorization') != 'Bearer reva-local-demo-token':
            self.send_json(401, {'reason': 'Fixture token required.'})
            return False
        return True

    def do_GET(self):
        if not self.authenticated():
            return
        if self.path == '/v1/providers':
            self.send_json(200, {'gemini': {'configured': True, 'model': MODEL},
                'transcription': {'configured': False, 'model': MODEL},
                'booking': {'configured': False, 'model': MODEL}, 'liveCallsEnabled': False})
        else:
            self.send_json(404, {'reason': 'No fixture for this route.'})

    def do_POST(self):
        if not self.authenticated():
            return
        size = int(self.headers.get('Content-Length', '0'))
        if not 0 < size <= 1024 * 1024:
            self.send_json(413, {'reason': 'Fixture input limit is 1 MiB.'})
            return
        try:
            body = json.loads(self.rfile.read(size))
            if self.path == '/v1/ai/summarize':
                self.send_json(200, {'summary': 'MOCK TRANSPORT CHECK. Original text received for ' + body['title'] + '. Review the source; no AI service ran.', 'model': MODEL})
            elif self.path == '/v1/ai/prepare':
                ids = [item['id'] for item in body['records'] if 'tibia-procedure' in item['id'] or 'history' in item['id']]
                self.send_json(200, {'overview': 'MOCK TRANSPORT CHECK. The native app received a structured preparation response; no AI service ran.',
                    'questions': ['Which original details should we review?'], 'selectedRecordIDs': ids, 'model': MODEL})
            else:
                self.send_json(404, {'reason': 'No fixture for this route.'})
        except (ValueError, KeyError, TypeError):
            self.send_json(400, {'reason': 'Malformed fixture request.'})

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8082)
    args = parser.parse_args()
    print(f'SYNTHETIC UI FIXTURE ONLY: http://127.0.0.1:{args.port}; model {MODEL}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
