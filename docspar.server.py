#!/usr/bin/env python3
"""
Serveur HTTP local pour POC PAR - avec headers CORS
Usage: python3 server.py [port]
Defaut: port 8080
"""

from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
import sys
import webbrowser
import threading

class CORSHandler(SimpleHTTPRequestHandler):

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def log_message(self, format, *args):
        print(f"[SERVER] {self.address_string()} - {format % args}")


PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

os.chdir(DIRECTORY)

print(f"")
print(f"  Serveur POC PAR demarre")
print(f"  http://localhost:{PORT}/index.html")
print(f"  Repertoire : {DIRECTORY}")
print(f"  CTRL+C pour arreter")
print(f"")

# Ouvre le navigateur automatiquement apres 1 seconde
def open_browser():
    webbrowser.open(f"http://localhost:{PORT}/index.html")

threading.Timer(1.0, open_browser).start()

httpd = HTTPServer(("localhost", PORT), CORSHandler)
httpd.serve_forever()
