#!/usr/bin/env python3
"""Receives log lines from the Player app on the local network and writes them to logs/player-YYYY-MM-DD.log.
Announces itself via Bonjour (_playerlog._tcp, service name "Player-Log"), so the app finds it without an IP address;
choose that name once on the TV (Einstellungen > System > Fern-Log).

Every request must carry X-Player-Sig: hex HMAC-SHA256 of the body with the shared secret. The same secret goes into
the phone page of the app (System > "Fern-Log: gemeinsames Geheimnis"). The secret is read from the environment
variable PLAYERLOG_SECRET or from a file given with --secret-file PATH; it is never stored in this script.

Environment: PLAYERLOG_PORT (8770), PLAYERLOG_DIR (../../logs), PLAYERLOG_BIND (0.0.0.0), PLAYERLOG_NAME (Player-Log).
--no-announce skips avahi-publish (local tests)."""
import argparse, datetime, hashlib, hmac, json, os, re, signal, subprocess, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 4 * 1024 * 1024
SIG_HEADER = "X-Player-Sig"
CONTROL = re.compile("[\x00-\x1f\x7f-\x9f]")


def clean(value):
    """One log field as a single printable line: control characters (newlines, ESC sequences) become U+FFFD."""
    return CONTROL.sub("�", str(value))


def load_secret(path):
    if path:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    return os.environ.get("PLAYERLOG_SECRET", "").strip()


def make_handler(secret, log_dir):
    key = secret.encode("utf-8")

    class H(BaseHTTPRequestHandler):
        timeout = 10  # seconds per socket operation; idle connections do not hold a thread forever

        def reply(self, status):
            self.send_response(status)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()

        def do_POST(self):
            if self.path != "/log":
                return self.reply(404)
            try:
                n = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                return self.reply(400)
            if n < 0:
                return self.reply(400)
            if n > MAX_BODY:
                return self.reply(413)
            body = self.rfile.read(n)
            if len(body) != n:
                return self.reply(400)
            want = hmac.new(key, body, hashlib.sha256).hexdigest()
            got = (self.headers.get(SIG_HEADER) or "").strip().lower()
            if not hmac.compare_digest(want, got):
                return self.reply(401)
            try:
                lines = json.loads(body)
            except ValueError:
                return self.reply(400)
            if not isinstance(lines, list):
                return self.reply(400)
            out = []
            for e in lines:
                if not isinstance(e, dict):
                    continue
                level = clean(e.get("l", "info")).upper()
                out.append(f"{clean(e.get('t', ''))} [{clean(e.get('s', ''))}] {level:5} "
                           f"{clean(e.get('c', ''))}: {clean(e.get('m', ''))}\n")
            day = datetime.date.today().isoformat()
            with open(os.path.join(log_dir, f"player-{day}.log"), "a", encoding="utf-8") as f:
                f.writelines(out)
            self.reply(200)

        def do_GET(self):
            self.reply(404)

        def log_message(self, *a):
            pass

    return H


def main():
    ap = argparse.ArgumentParser(description="Player log receiver (signed requests only).")
    ap.add_argument("--secret-file", help="file with the shared secret (default: env PLAYERLOG_SECRET)")
    ap.add_argument("--no-announce", action="store_true", help="do not announce via avahi-publish")
    args = ap.parse_args()

    secret = load_secret(args.secret_file)
    if not secret:
        sys.exit("logcollector: no shared secret. Set PLAYERLOG_SECRET or pass --secret-file PATH "
                 "(the same value as on the app's phone page).")
    port = int(os.environ.get("PLAYERLOG_PORT", "8770"))
    bind = os.environ.get("PLAYERLOG_BIND", "0.0.0.0")
    name = os.environ.get("PLAYERLOG_NAME", "Player-Log")
    log_dir = os.environ.get("PLAYERLOG_DIR",
                             os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "logs"))
    os.makedirs(log_dir, exist_ok=True)

    pub = None
    if not args.no_announce:
        try:
            pub = subprocess.Popen(["avahi-publish", "-s", name, "_playerlog._tcp", str(port)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            print("logcollector: avahi-publish not found, not announcing via Bonjour", file=sys.stderr)

    def stop(*_):
        if pub:
            pub.terminate()
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    try:
        ThreadingHTTPServer((bind, port), make_handler(secret, log_dir)).serve_forever()
    finally:
        if pub:
            pub.terminate()


if __name__ == "__main__":
    main()
