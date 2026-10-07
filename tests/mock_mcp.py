"""Loopback fixture only. Records no request headers, tokens or vault data."""
import http.server
import json
import pathlib
import sys

port_file, mode_file = map(pathlib.Path, sys.argv[1:3])


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.send_response(200 if self.path == '/readyz' else 404)
        self.end_headers()
        self.wfile.write(b'fixture ready')

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        mode = mode_file.read_text().strip() if mode_file.exists() else "ok"
        status = {"unauthorized": 401, "forbidden": 403, "redirect": 302}.get(mode, 200)
        self.send_response(status)
        if status == 302:
            self.send_header("Location", "http://127.0.0.1:1/stolen")
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        body = {"jsonrpc": "2.0", "id": 1, "result": {"protocolVersion": "2025-06-18", "serverInfo": {"name": "fixture", "version": "1"}}}
        if mode == "invalid":
            body = {"ok": True}
        self.wfile.write(json.dumps(body).encode())


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(str(server.server_port))
server.serve_forever()
