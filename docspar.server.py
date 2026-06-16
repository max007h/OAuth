#!/usr/bin/env python3
"""
Serveur HTTP local pour POC PAR - proxy transparent vers PingFederate
Usage: python3 server.py [port]
Le HTML n'a pas besoin d'etre modifie - le proxy intercepte /as/*
"""

from http.server import HTTPServer, SimpleHTTPRequestHandler
import os, sys, ssl, urllib.request
import webbrowser, threading

PF_BASE   = "https://localhost:9031"
PORT      = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))
os.chdir(DIRECTORY)

ssl_ctx = ssl.create_default_context()
ssl_ctx.check_hostname = False
ssl_ctx.verify_mode    = ssl.CERT_NONE

class Handler(SimpleHTTPRequestHandler):

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        # Force le navigateur a toujours recharger le fichier complet
        # (evite les 304 Not Modified qui servent une version en cache)
        if 'If-Modified-Since' in self.headers:
            del self.headers['If-Modified-Since']
        if 'If-None-Match' in self.headers:
            del self.headers['If-None-Match']
        super().do_GET()

    def do_POST(self):
        # Intercepte /as/par.oauth2 et /as/token.oauth2
        if self.path.startswith("/as/"):
            self._proxy(PF_BASE + self.path)
        else:
            self.send_error(404)

    def _proxy(self, target_url):
        length = int(self.headers.get("Content-Length", 0))
        body   = self.rfile.read(length)
        req    = urllib.request.Request(
            target_url, data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            method="POST"
        )
        try:
            with urllib.request.urlopen(req, context=ssl_ctx) as resp:
                data, status = resp.read(), resp.status
        except urllib.error.HTTPError as e:
            data, status = e.read(), e.code

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        print(f"[SERVER] {format % args}")

def open_browser():
    webbrowser.open(f"http://localhost:{PORT}/index.html")

print(f"\n  Serveur POC PAR demarre sur le port {PORT}")
print(f"  http://localhost:{PORT}/index.html")
print(f"  Proxy transparent : /as/* → {PF_BASE}/as/*")
print(f"  CTRL+C pour arreter\n")

threading.Timer(1.0, open_browser).start()
HTTPServer(("localhost", PORT), Handler).serve_forever()
