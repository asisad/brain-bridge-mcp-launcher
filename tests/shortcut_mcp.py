"""Authenticated loopback fixture for the shortcut example; no vault or external network."""
import http.server
import json
import pathlib
import sys

port_file, mode_file = map(pathlib.Path, sys.argv[1:3])


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        mode = mode_file.read_text().strip() if mode_file.exists() else "ok"
        authorized = self.headers.get("Authorization") == "Bearer synthetic-shortcut-token"
        status = 200 if authorized and mode == "ok" else 401
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        reply = {"jsonrpc": "2.0", "id": body.get("id"), "result": {"protocolVersion": "2024-11-05"}}
        self.wfile.write(json.dumps(reply if status == 200 else {"error": "unauthorized"}).encode())


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(str(server.server_port))
server.serve_forever()
