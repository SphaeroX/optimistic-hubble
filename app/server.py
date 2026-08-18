import http.server
import socketserver
import urllib.request
import urllib.error
import os
import sys

PORT = 8000
DIRECTORY = os.path.dirname(os.path.abspath(__file__))
ESP32_HOST = "http://192.168.4.1"

class ProxyAndStaticHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, DELETE")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/api/"):
            self.proxy_to_esp32("GET")
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith("/api/"):
            self.proxy_to_esp32("POST")
        else:
            self.send_error(404, "Not found")

    def proxy_to_esp32(self, method):
        target_url = f"{ESP32_HOST}{self.path}"
        try:
            req = urllib.request.Request(target_url, method=method)
            req.add_header("User-Agent", "XIAO-Companion-Proxy")
            with urllib.request.urlopen(req, timeout=5) as response:
                content = response.read()
                self.send_response(response.status)
                for header, val in response.headers.items():
                    if header.lower() not in ["content-length", "server", "date", "transfer-encoding"]:
                        self.send_header(header, val)
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            print(f"[Proxy Error] {target_url} -> {e}")
            self.send_response(502)
            self.end_headers()
            err_msg = f'{{"error":"ESP32 unreachable at {ESP32_HOST}","detail":"{str(e)}"}}'
            self.wfile.write(err_msg.encode("utf-8"))

if __name__ == "__main__":
    os.chdir(DIRECTORY)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), ProxyAndStaticHTTPRequestHandler) as httpd:
        print(f"XIAO Companion Proxy Server running at http://localhost:{PORT}")
        print(f"Proxying /api/* directly to {ESP32_HOST}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down.")
            sys.exit(0)
