#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the real Quickshell hosts with bounded output and local HTTP."""
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time


class Replies(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        try:
            if self.path == "/large":
                # No Content-Length, and fewer than 1 MB of characters:
                # the byte limit must be checked during receipt.
                for _ in range(12):
                    self.wfile.write(("é" * 65536).encode())
                    self.wfile.flush()
                    time.sleep(0.025)
                time.sleep(10)
            else:
                if self.path == "/slow":
                    time.sleep(0.5)
                self.wfile.write("small café ☕".encode())
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    qs = shutil.which("quickshell") or shutil.which("qs")
    if not qs:
        print("widget-host: no Quickshell")
        return 77
    here = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory() as tmp, http.server.ThreadingHTTPServer(("127.0.0.1", 0), Replies) as server:
        work = Path(tmp)
        plugin = here.parent / "plugins/omamobile.home"
        (work / "home/owl").mkdir(parents=True)
        for filename in ("OwlPhoneHost.qml", "WidgetHost.qml", "BoundedProcess.qml", "HomeModel.js", "UserWidgets.js",
                         "owl/phone.js", "owl/values.js", "owl/terminal.js"):
            shutil.copyfile(plugin / filename, work / "home" / filename)
        shutil.copyfile(here / "widget-host.qml", work / "shell.qml")
        (work / "runtime").mkdir(mode=0o700)
        environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                           QML_DISABLE_DISK_CACHE="1", XDG_RUNTIME_DIR=str(work / "runtime"),
                           XDG_STATE_HOME=str(work / "state"), XDG_CACHE_HOME=str(work / "cache"),
                           FIXTURE_URL=f"http://127.0.0.1:{server.server_port}", FIXTURE_DIR=tmp)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run([qs, "-p", str(work / "shell.qml")], env=environment,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15)
        except subprocess.TimeoutExpired as error:
            print((error.stdout or b"").decode(errors="replace"))
            print("widget-host: Quickshell did not finish")
            return 1
        finally:
            server.shutdown()
        if result.returncode or "widget-host: PASS" not in result.stdout:
            print(result.stdout)
            return 1
        assert not (work / "cancelled-command-finished").exists(), "cancel must terminate the child command"
        print("widget-host: PASS (bounded commands/HTTP, cancellation, state)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
