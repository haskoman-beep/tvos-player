#!/usr/bin/env python3
"""Empfängt Logzeilen der Player-App im Heimnetz und schreibt sie nach logs/player-JJJJ-MM-TT.log.
Kündigt sich per Bonjour (_playerlog._tcp) an, damit die App ihn ohne IP-Eingabe findet."""
import json, os, subprocess, sys, datetime, signal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PLAYERLOG_PORT", "8770"))
DIR = os.environ.get("PLAYERLOG_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "logs"))
os.makedirs(DIR, exist_ok=True)

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/log":
            self.send_response(404); self.end_headers(); return
        n = int(self.headers.get("Content-Length", "0"))
        if n > 4_000_000:
            self.send_response(413); self.end_headers(); return
        try:
            lines = json.loads(self.rfile.read(n))
        except Exception:
            self.send_response(400); self.end_headers(); return
        day = datetime.date.today().isoformat()
        with open(os.path.join(DIR, f"player-{day}.log"), "a", encoding="utf-8") as f:
            for e in lines:
                f.write(f"{e.get('t','')} [{e.get('s','')}] {e.get('l','info').upper():5} {e.get('c','')}: {e.get('m','')}\n")
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass

pub = subprocess.Popen(["avahi-publish", "-s", "Player-Log", "_playerlog._tcp", str(PORT)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def stop(*_):
    pub.terminate(); sys.exit(0)
signal.signal(signal.SIGTERM, stop)
try:
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
finally:
    pub.terminate()
