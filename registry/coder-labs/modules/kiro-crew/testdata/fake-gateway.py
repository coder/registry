import http.server
import json
import os

PORT = int(os.environ["KIROCREW_PORT"])
SECRET_PATH = os.path.expanduser("~/.kiro/crew/.local_secret")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"fake-gateway")
            return
        if self.path.startswith("/api/token/local"):
            with open(SECRET_PATH) as f:
                secret = f.read().strip()
            if self.headers.get("X-Local-Secret") != secret:
                self.send_response(401)
                self.end_headers()
                return
            body = json.dumps({"token": "test-token"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
