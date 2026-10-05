#!/usr/bin/env python3

import json
import os
import re
import socket
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent
TEMPLATES_DIR = BASE_DIR / "templates"
CORE_ENGINE = PROJECT_ROOT / "core" / "engine.sh"
STORAGE_CONF = Path("/etc/portlabel/domains.conf")

PORT = 2999
HOST = "127.0.0.1"


def run_bash_func(func_name, *args):
    cmd = [
        "bash",
        "-c",
        f'source "{CORE_ENGINE}" && {func_name} "$@"',
        "_",
        *args,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode == 0, res.stdout.strip(), res.stderr.strip()


def check_port_listening(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.2)
        return s.connect_ex(("127.0.0.1", port)) == 0


def get_all_domains():
    domains = []
    if not STORAGE_CONF.exists():
        return domains

    with open(STORAGE_CONF, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split("|")
            if len(parts) >= 3 and parts[0]:
                name, port_str, status = parts[0], parts[1], parts[2]
                try:
                    port = int(port_str)
                    is_listening = check_port_listening(port)
                except ValueError:
                    port = 0
                    is_listening = False

                domains.append(
                    {
                        "name": name,
                        "port": port,
                        "status": status,
                        "domain": f"{name}.local",
                        "online": is_listening,
                    }
                )
    return domains


class PortlabelHandler(BaseHTTPRequestHandler):
    def send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, message, status=400):
        self.send_json({"success": False, "error": message}, status=status)

    def read_json_body(self):
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            return {}
        raw_body = self.rfile.read(content_length)
        try:
            return json.loads(raw_body.decode("utf-8"))
        except Exception:
            return {}

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            index_path = TEMPLATES_DIR / "index.html"
            if not index_path.exists():
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"index.html not found.")
                return

            with open(index_path, "rb") as f:
                content = f.read()

            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        elif self.path == "/api/domains":
            self.send_json({"success": True, "domains": get_all_domains()})

        elif self.path == "/api/health":
            self.send_json({"success": True, "status": "ok"})

        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/api/domains":
            data = self.read_json_body()
            name = (data.get("name") or "").strip().lower()
            port = str(data.get("port") or "").strip()

            if not re.match(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name):
                return self.send_error_json("Invalid service name.")

            if not port.isdigit() or not (1 <= int(port) <= 65535):
                return self.send_error_json("Port must be between 1 and 65535.")

            ok, _, err = run_bash_func("storage_add", name, port, "enabled")
            if not ok:
                return self.send_error_json(err or f"{name}.local already exists.")

            run_bash_func("engine_apply_all")
            return self.send_json({"success": True})

        elif self.path == "/api/domains/toggle":
            data = self.read_json_body()
            name = (data.get("name") or "").strip().lower()

            ok, new_status, err = run_bash_func("storage_toggle_status", name)
            if not ok:
                return self.send_error_json(err or "Domain not found.")

            run_bash_func("engine_apply_all")
            return self.send_json({"success": True, "status": new_status})

        elif self.path == "/api/domains/update":
            data = self.read_json_body()
            name = (data.get("name") or "").strip().lower()
            port = str(data.get("port") or "").strip()

            if not port.isdigit() or not (1 <= int(port) <= 65535):
                return self.send_error_json("Port must be between 1 and 65535.")

            ok, _, err = run_bash_func("storage_update_port", name, port)
            if not ok:
                return self.send_error_json(err or "Domain not found.")

            run_bash_func("engine_apply_all")
            return self.send_json({"success": True})

        elif self.path == "/api/domains/delete":
            data = self.read_json_body()
            name = (data.get("name") or "").strip().lower()

            ok, _, err = run_bash_func("storage_remove", name)
            if not ok:
                return self.send_error_json(err or "Domain not found.")

            run_bash_func("engine_apply_all")
            return self.send_json({"success": True})

        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def run():
    run_bash_func("storage_init")
    server_address = (HOST, PORT)
    httpd = HTTPServer(server_address, PortlabelHandler)
    print(f"PortLabel Web Dashboard running at http://{HOST}:{PORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    run()