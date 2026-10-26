#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""SSH, screenshots and input for the F3 image; no Android or flashing commands."""
import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import time
from rfb import RFB

ROOT = Path(__file__).resolve().parents[2]
ADDRESS = "172.16.42.1"


def ssh_options():
    # Initramfs and the installed root have different host keys. Select their
    # independent TOFU records from the protocol banner, before authentication.
    with socket.create_connection((ADDRESS, 22), timeout=5) as stream:
        reader = stream.makefile("rb")
        banner = b""
        for _ in range(8):
            banner = reader.readline(512).lower()
            if banner.startswith(b"ssh-"):
                break
        if not banner.startswith(b"ssh-") or not any(x in banner for x in (b"dropbear", b"openssh")):
            raise ConnectionError("Unexpected SSH server banner on the phone link")
    phase = "initramfs" if b"dropbear" in banner else "system"
    return ["ssh", "-F", "/dev/null", "-i", str(ROOT / "keys/alioth/alioth_ed25519"), "-o", "IdentitiesOnly=yes",
            "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", f"HostKeyAlias=alioth-{phase}",
            "-o", f"UserKnownHostsFile={ROOT}/keys/alioth/alioth_known_hosts",
            "-o", "ConnectTimeout=6", "-o", "ServerAliveInterval=10",
            "-o", "ExitOnForwardFailure=yes", f"root@{ADDRESS}"]


def run_ssh(command):
    return subprocess.run(ssh_options() + [shlex.join(command)], check=True)


def guarded_mirror(action):
    # alioth's native firewall already permits VNC on USB only. Stop the
    # mirror on failure without disabling the firewall or changing its rules.
    unit = f"alioth-mirror-deadman-{time.time_ns()}"
    run_ssh(["systemd-run", "--unit=" + unit, "--on-active=90", "/usr/bin/omamobile-mirror", "off"])
    run_ssh(["omamobile-mirror", action])
    run_ssh(["true"])
    run_ssh(["systemctl", "stop", unit + ".timer"])


def wake():
    owner = json.loads((ROOT / "out/alioth/images/ROOT-MANIFEST.json").read_text())["username"]
    run_ssh(["systemd-run", "--user", "--machine=" + owner + "@", "--wait", "--pipe", "--collect",
             "--setenv=OMARCHY_PATH=/usr/share/omarchy", "/usr/bin/bash", "-c",
             '[[ $(omarchy-shell lock wake 2>/dev/null) == ok ]] || omarchy-brightness-display on'])


def screenshot(path):
    # Compressed compositor capture is faster than raw RFB over USB and avoids
    # wayvnc's placeholder/stalled capture during screen blanking transitions.
    owner = json.loads((ROOT / "out/alioth/images/ROOT-MANIFEST.json").read_text())["username"]
    command = ["systemd-run", "--user", "--machine=" + owner + "@", "--wait", "--pipe", "--collect", "--quiet",
               "/usr/bin/grim", "-"]
    result = subprocess.run(ssh_options() + [shlex.join(command)], check=True, stdout=subprocess.PIPE, timeout=25)
    if not result.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Compositor did not return a PNG screenshot")
    path.touch(mode=0o600)
    path.chmod(0o600)
    path.write_bytes(result.stdout)
    print(path)


@contextmanager
def screen():
    guarded_mirror("on")
    with socket.socket() as allocator:
        allocator.bind(("127.0.0.1", 0))
        port = allocator.getsockname()[1]
    options = ssh_options()
    tunnel = subprocess.Popen(options[:-1] + ["-N", "-L", f"127.0.0.1:{port}:{ADDRESS}:5900", options[-1]])
    try:
        stream = None
        for _ in range(50):
            if tunnel.poll() is not None:
                raise ConnectionError("SSH tunnel failed")
            try:
                stream = socket.create_connection(("127.0.0.1", port), timeout=2)
                stream.settimeout(20)
                break
            except OSError:
                time.sleep(0.2)
        if stream is None:
            raise ConnectionError("USB mirror did not become reachable")
        with stream:
            yield RFB(stream)
    finally:
        tunnel.terminate()
        try:
            tunnel.wait(timeout=5)
        except subprocess.TimeoutExpired:
            tunnel.kill()
            tunnel.wait()


def host_up():
    links = json.loads(subprocess.check_output(["ip", "-j", "link", "show"], text=True))
    found = [l["ifname"] for l in links if l.get("address", "").lower() == "02:10:42:00:00:02"]
    if len(found) != 1:
        raise SystemExit("The F3 Omarchy USB interface is not connected; no host network changes made")
    interface, name = found[0], "omarchy-poco-f3"
    exists = subprocess.run(["nmcli", "connection", "show", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if exists.returncode:
        subprocess.run(["nmcli", "connection", "add", "type", "ethernet", "con-name", name,
                        "ifname", interface, "ipv4.method", "manual", "ipv4.addresses", "172.16.42.2/24",
                        "ipv4.never-default", "yes", "ipv6.method", "disabled"], check=True)
    else:
        subprocess.run(["nmcli", "connection", "modify", name, "connection.interface-name", interface], check=True)
    subprocess.run(["nmcli", "connection", "up", name, "ifname", interface], check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="action", required=True)
    sub.add_parser("host-up", help="Configure only the matching USB Ethernet interface")
    sub.add_parser("doctor", help="Read kernel, USB, SSH and boot-service state")
    sub.add_parser("shell", help="Interactive SSH shell with the dedicated key")
    sub.add_parser("wake", help="Wake the screen through the logged-in user's Omarchy session")
    sub.add_parser("mirror-off", help="Stop mirroring with a timed firewall undo around the change")
    cmd = sub.add_parser("exec"); cmd.add_argument("command", nargs=argparse.REMAINDER)
    shot = sub.add_parser("screenshot"); shot.add_argument("path", type=Path)
    tap = sub.add_parser("tap"); tap.add_argument("x", type=int); tap.add_argument("y", type=int)
    text = sub.add_parser("type"); text.add_argument("text")
    key = sub.add_parser("key"); key.add_argument("combination", help="For example Return, Ctrl+l, Super+Space")
    a = p.parse_args()
    if a.action == "host-up":
        host_up()
    elif a.action == "shell":
        subprocess.run(ssh_options(), check=True)
    elif a.action == "wake":
        wake()
    elif a.action == "mirror-off":
        guarded_mirror("off")
    elif a.action == "exec":
        if not a.command:
            p.error("exec requires a command")
        run_ssh(a.command)
    elif a.action == "doctor":
        run_ssh(["sh", "-c", "uname -r; ip -4 -br address show usb0; "
                 "if command -v systemctl >/dev/null; then systemctl --failed --no-pager; "
                 "systemctl is-active sshd systemd-networkd; fi"])
    elif a.action == "screenshot":
        screenshot(a.path)
    else:
        with screen() as client:
            if a.action == "tap":
                client.tap(a.x, a.y)
            elif a.action == "type":
                client.type(a.text)
            else:
                named = {"return": 0xff0d, "enter": 0xff0d, "tab": 0xff09, "escape": 0xff1b,
                         "esc": 0xff1b, "backspace": 0xff08, "space": 0x20, "ctrl": 0xffe3,
                         "alt": 0xffe9, "shift": 0xffe1, "super": 0xffeb, "left": 0xff51,
                         "up": 0xff52, "right": 0xff53, "down": 0xff54}
                symbols = []
                for name in a.combination.split("+"):
                    value = named.get(name.lower(), ord(name) if len(name) == 1 else None)
                    if value is None:
                        p.error(f"Unknown key {name}")
                    symbols.append(value)
                for value in symbols:
                    client.key(value, True)
                for value in reversed(symbols):
                    client.key(value, False)
            # Allow the SSH tunnel to forward the final input before closing.
            time.sleep(0.2)


if __name__ == "__main__":
    try:
        main()
    except (ConnectionError, OSError, subprocess.CalledProcessError, ValueError) as e:
        sys.exit(str(e))
