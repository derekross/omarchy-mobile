#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Back up Grizzly NV partitions through the guarded macOS USB reader."""

import argparse
from contextlib import ExitStack, contextmanager, suppress
from dataclasses import dataclass
from datetime import datetime, timezone
import fcntl
import hashlib
import os
from pathlib import Path
import re
import runpy
import select
import socket
import stat
import struct
import subprocess
import sys
import termios
import time


LABELS = frozenset((
    "persist", "nvdata", "nvram", "protect_f", "protect_s",
    "modemdp", "modem_a", "modem_b", "devinfo",
))
MAX_CHUNK = 8 * 1024 * 1024
# Full-size 8 MiB replies have stalled the Grizzly ACM stream during backups.
COPY_CHUNK = 4 * 1024 * 1024
MAX_PARTITION = 1 << 40
MAX_PROBE = 4096
MAX_LINE = 96
SECTOR_SIZE = 512
TIMEOUTS = {b"PROBE": 15, b"READ": 40, b"SHA256": 300, b"DONE": 15}
OK = re.compile(rb"NV1 OK (0|[1-9][0-9]{0,7})\n")
ERROR = re.compile(rb"NV1 ERR [A-Z][A-Z0-9_]{0,31}\n")
DECIMAL = re.compile(rb"(?:0|[1-9][0-9]{0,12})")
COMPATIBLE = b"compatible google,malibu-grizzly\n"


class TransportError(Exception):
    """A failure whose message contains only local protocol descriptions."""


class DeviceRejected(TransportError):
    """A complete, recoverable refusal without a response body."""


class SerialTimeout(TransportError):
    """A transfer timed out and may have left part of its reply queued."""


@dataclass(frozen=True)
class Request:
    wire: bytes
    operation: bytes
    label: str = ""
    offset: int = 0
    length: int = 0


def decimal(field):
    if not DECIMAL.fullmatch(field):
        raise TransportError("invalid decimal argument")
    return int(field)


def parse_request(line):
    if len(line) > MAX_LINE or not line.endswith(b"\n"):
        raise TransportError("invalid request frame")
    fields = line[:-1].split(b" ")
    if len(fields) < 2 or fields[0] != b"NV1":
        raise TransportError("invalid request version")
    operation = fields[1]
    if operation in (b"PROBE", b"DONE") and len(fields) == 2:
        return Request(line, operation)
    if not (operation == b"READ" and len(fields) == 5
            or operation == b"SHA256" and len(fields) == 3):
        raise TransportError("invalid request operation or argument count")
    label = fields[2].decode("ascii", errors="replace")
    if label not in LABELS:
        raise TransportError("invalid partition label")
    if operation == b"SHA256":
        return Request(line, operation, label)
    offset, length = (decimal(field) for field in fields[3:])
    if (offset > MAX_PARTITION or not 0 < length <= MAX_CHUNK
            or offset % SECTOR_SIZE or length % SECTOR_SIZE):
        raise TransportError("invalid partition read range")
    return Request(line, operation, label, offset, length)


def check_probe(body):
    body = bytes(body)
    if not body.startswith(COMPATIBLE) or not body.endswith(b"\n"):
        raise TransportError("unexpected board or malformed partition inventory")
    parts = {}
    nodes = set()
    for line in body[len(COMPATIBLE):-1].split(b"\n"):
        fields = line.split(b" ")
        if len(fields) != 6 or fields[2:5] != [b"block", b"1", b"0"]:
            raise TransportError("invalid or unguarded partition inventory")
        label = fields[0].decode("ascii", errors="replace")
        node = fields[1]
        size = decimal(fields[5])
        if (label not in LABELS or label in parts or node in nodes
                or not re.fullmatch(rb"sd[a-e][1-9][0-9]{0,3}", node)
                or not 0 < size <= MAX_PARTITION or size % SECTOR_SIZE):
            raise TransportError("unexpected partition identity or size")
        parts[label] = (node, size)
        nodes.add(node)
    if parts.keys() != LABELS:
        raise TransportError("incomplete partition inventory")
    return parts


def response_size(header, request):
    if ERROR.fullmatch(header):
        raise DeviceRejected("backup reader refused the request")
    match = OK.fullmatch(header)
    if match is None:
        raise TransportError("invalid response header")
    size = int(match[1])
    if request.operation == b"PROBE":
        valid = 0 < size <= MAX_PROBE
    elif request.operation == b"READ":
        valid = size == request.length
    else:
        valid = size == (65 if request.operation == b"SHA256" else 0)
    if not valid:
        raise TransportError("unexpected response length")
    return size


def check_body(body, request):
    if request.operation == b"PROBE":
        return check_probe(body)
    if request.operation == b"SHA256" and not re.fullmatch(rb"[0-9a-f]{64}\n", body):
        raise TransportError("invalid partition digest")
    return None


def remaining(deadline):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise TimeoutError("backup transport timed out")
    return seconds


def read_line(receive):
    line = bytearray()
    while len(line) < MAX_LINE:
        line += receive(1)
        if line.endswith(b"\n"):
            return bytes(line)
    raise TransportError("oversized transport header")


def read_body(receive, length):
    body = bytearray()
    while len(body) < length:
        body += receive(min(65536, length - len(body)))
    return body


def serial_reply(fd, request, deadline):
    outgoing = memoryview(request.wire)
    while outgoing:
        if not select.select([], [fd], [], remaining(deadline))[1]:
            raise TimeoutError("serial write timed out")
        try:
            written = os.write(fd, outgoing)
        except BlockingIOError:
            continue
        if written == 0:
            raise TransportError("serial endpoint closed while writing")
        outgoing = outgoing[written:]

    def receive(count):
        while True:
            if not select.select([fd], [], [], remaining(deadline))[0]:
                raise TimeoutError("serial reply timed out")
            try:
                data = os.read(fd, count)
            except BlockingIOError:
                continue
            if not data:
                raise TransportError("serial reply ended early")
            return data

    return read_body(receive, response_size(read_line(receive), request))


def socket_receive(conn, count, deadline):
    conn.settimeout(remaining(deadline))
    data = conn.recv(count)
    if not data:
        raise TransportError("local reply or request ended early")
    return data


def socket_send(conn, data, deadline):
    conn.settimeout(remaining(deadline))
    conn.sendall(data)


def expect_socket_eof(conn, deadline):
    conn.settimeout(remaining(deadline))
    if conn.recv(1):
        raise TransportError("unexpected data after local frame")


@contextmanager
def socket_directory(path):
    path = Path(path)
    if (not path.is_absolute() or path.parent == path
            or not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,63}", path.name)
            or path.parent.resolve(strict=True) != path.parent):
        raise TransportError("use a canonical absolute socket path in a private directory")
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(directory)
        if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise TransportError("socket directory must be owned by this user with mode 0700")
        # Hold the directory open and use a relative AF_UNIX address.
        previous = os.open(".", os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fchdir(directory)
            yield path.name
        finally:
            os.fchdir(previous)
            os.close(previous)
    finally:
        os.close(directory)


def socket_identity(name):
    info = os.lstat(name)
    if not (stat.S_ISSOCK(info.st_mode) and info.st_uid == os.geteuid()
            and stat.S_IMODE(info.st_mode) == 0o600):
        raise TransportError("local endpoint must be an owned mode-0600 socket")
    return info.st_dev, info.st_ino


def check_peer(conn):
    # Darwin SOL_LOCAL=0 and xucred starts with XUCRED_VERSION and uid_t.
    credentials = conn.getsockopt(0, socket.LOCAL_PEERCRED, 128)
    if len(credentials) < 8 or struct.unpack_from("@II", credentials) != (0, os.geteuid()):
        raise TransportError("local peer is not the same user")


@contextmanager
def listen(name):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        old_umask = os.umask(0o177)
        try:
            server.bind(name)
        finally:
            os.umask(old_umask)
        identity = socket_identity(name)
        try:
            server.listen(1)
            yield server
        finally:
            with suppress(OSError, TransportError):
                if socket_identity(name) == identity:
                    os.unlink(name)


@contextmanager
def open_serial(port, configure_tty):
    fd = os.open(port, os.O_RDWR | os.O_NONBLOCK | os.O_NOCTTY | os.O_NOFOLLOW)
    try:
        if not stat.S_ISCHR(os.fstat(fd).st_mode) or not os.isatty(fd):
            raise TransportError("discovered device is not a serial endpoint")
        fcntl.ioctl(fd, termios.TIOCEXCL)
        mode = termios.tcgetattr(fd)
        try:
            configure_tty(fd)
            yield fd
        finally:
            with suppress(OSError, termios.error):
                termios.tcsetattr(fd, termios.TCSANOW, mode)
            with suppress(OSError):
                fcntl.ioctl(fd, termios.TIOCNXCL)
    finally:
        os.close(fd)


def serve_requests(server, fd, inventory, deadline):
    while True:
        ready = select.select([server, fd], [], [], remaining(deadline))[0]
        if fd in ready:
            raise TransportError("serial endpoint disconnected or sent unsolicited data")
        if server not in ready:
            raise TimeoutError("backup session expired")
        client, _ = server.accept()
        with client:
            try:
                check_peer(client)
                input_deadline = min(deadline, time.monotonic() + 3)
                request = parse_request(read_line(lambda n: socket_receive(client, n, input_deadline)))
                expect_socket_eof(client, input_deadline)
            except (OSError, TransportError):
                with suppress(OSError):
                    socket_send(client, b"NV1 ERR REQUEST\n", time.monotonic() + 1)
                continue

            if (request.operation == b"READ"
                    and request.offset + request.length > inventory[request.label][1]):
                with suppress(OSError):
                    socket_send(client, b"NV1 ERR RANGE\n", time.monotonic() + 1)
                continue

            request_deadline = min(deadline, time.monotonic() + TIMEOUTS[request.operation])
            try:
                body = serial_reply(fd, request, request_deadline)
            except DeviceRejected:
                with suppress(OSError):
                    socket_send(client, b"NV1 ERR DEVICE\n", time.monotonic() + 1)
                continue
            except TimeoutError as error:
                if request.operation == b"DONE":
                    raise
                raise SerialTimeout("serial transfer timed out") from error
            checked = check_body(body, request)
            if request.operation == b"PROBE" and checked != inventory:
                raise TransportError("partition inventory changed during the session")
            output_deadline = min(deadline, time.monotonic() + 8)
            with suppress(OSError):
                socket_send(client, f"NV1 OK {len(body)}\n".encode("ascii"), output_deadline)
                socket_send(client, body, output_deadline)
            if request.operation == b"DONE":
                return


def drain_serial(fd):
    deadline = time.monotonic() + 18
    discarded = 0
    while select.select([fd], [], [], min(2, remaining(deadline)))[0]:
        try:
            stale = os.read(fd, 65536)
        except BlockingIOError:
            continue
        if not stale:
            raise TransportError("serial endpoint closed during recovery")
        discarded += len(stale)
        if discarded > MAX_CHUNK + 4096:
            raise TransportError("unexpected data while recovering serial framing")


def serve(name, requested, wait):
    checker = runpy.run_path(str(Path(__file__).resolve().with_name("check-stock-usb2.py")))
    if requested and not checker["PORT_PATTERN"].fullmatch(requested):
        raise TransportError("--port must be a descriptor-verified usbmodem path")
    with socket_directory(name) as endpoint, ExitStack() as serial:
        if os.path.lexists(endpoint):
            raise TransportError("local endpoint already exists")
        def connect(timeout):
            port = checker["wait_for_port"](requested, timeout)
            fd = serial.enter_context(open_serial(port, checker["configure_tty"]))
            drain_serial(fd)
            request = parse_request(b"NV1 PROBE\n")
            return fd, check_probe(serial_reply(fd, request, time.monotonic() + TIMEOUTS[b"PROBE"]))

        fd, inventory = connect(wait)
        deadline = time.monotonic() + 1200
        with listen(endpoint) as server:
            print("Grizzly NV reader ready", file=sys.stderr, flush=True)
            while True:
                try:
                    serve_requests(server, fd, inventory, deadline)
                    return
                except SerialTimeout:
                    serial.close()
                    fd, checked = connect(min(12, remaining(deadline)))
                    if checked != inventory:
                        raise TransportError("partition inventory changed during serial recovery")
                    print("Grizzly NV serial framing recovered", file=sys.stderr, flush=True)


def request_local(path, request):
    deadline = time.monotonic() + TIMEOUTS[request.operation] + 15
    with socket_directory(path) as endpoint, socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        before = socket_identity(endpoint)
        client.settimeout(remaining(deadline))
        client.connect(endpoint)
        if socket_identity(endpoint) != before:
            raise TransportError("local endpoint changed while connecting")
        check_peer(client)
        socket_send(client, request.wire, deadline)
        client.shutdown(socket.SHUT_WR)
        receive = lambda n: socket_receive(client, n, deadline)
        body = read_body(receive, response_size(read_line(receive), request))
        expect_socket_eof(client, deadline)
        check_body(body, request)
        return body


def backup_request(path, operation, *arguments):
    fields = ["NV1", operation, *map(str, arguments)]
    request = parse_request((" ".join(fields) + "\n").encode("ascii"))
    for attempt in range(5):
        try:
            return request_local(path, request)
        except (OSError, TransportError):
            if attempt == 4:
                raise
            time.sleep(2)


def copy_backup(path, destination):
    """Publish the manifest after all partition images have been verified."""
    before = check_probe(backup_request(path, "PROBE"))
    destination.mkdir(mode=0o700)
    written = []
    hashes = {}

    def save_file(name, data):
        target = destination / name
        with target.open("xb") as out:
            written.append(target)
            out.write(data)

    try:
        for label, (_, size) in sorted(before.items()):
            target = destination / f"{label}.img"
            with target.open("xb") as out:
                written.append(target)
                for offset in range(0, size, COPY_CHUNK):
                    length = min(COPY_CHUNK, size - offset)
                    chunk = backup_request(path, "READ", label, offset, length)
                    if len(chunk) != length or out.write(chunk) != length:
                        raise TransportError(f"incomplete copy of {label}")

            saved_hash = hashlib.sha256()
            with target.open("rb") as saved:
                for chunk in iter(lambda: saved.read(MAX_CHUNK), b""):
                    saved_hash.update(chunk)
            digest = saved_hash.hexdigest()
            expected = backup_request(path, "SHA256", label)
            if expected != f"{digest}\n".encode("ascii"):
                raise TransportError(f"independent digest mismatch for {label}")
            hashes[label] = digest

        if check_probe(backup_request(path, "PROBE")) != before:
            raise TransportError("partition identity, size or guard changed during backup")

        save_file("partitions.txt", "".join(
            f"{label} {node.decode('ascii')} ro=1 mounted=0 {size}\n"
            for label, (node, size) in sorted(before.items())).encode("ascii"))
        date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        checked = " ".join(sorted(before.keys() - {"devinfo"}))
        save_file("NV-BACKUP", (
            "# Grizzly stock RAM rescue: read-only NV backup\n"
            f"device: grizzly\ndate: {date}\nchecked: {checked}\ncopied, may change: devinfo\n"
        ).encode("ascii"))
        save_file("SHA256SUMS", "".join(
            f"{digest}  {label}.img\n" for label, digest in hashes.items()).encode("ascii"))
    except BaseException:
        for target in written:
            with suppress(OSError):
                target.unlink()
        with suppress(OSError):
            destination.rmdir()
        raise


def discovery_timeout(value):
    try:
        seconds = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("enter a timeout in seconds") from error
    if not 0 < seconds <= 300:
        raise argparse.ArgumentTypeError("discovery timeout must be above zero and at most 300 seconds")
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    boot = commands.add_parser("serve", help="hold one verified USB connection on a private local socket")
    boot.add_argument("socket")
    boot.add_argument("--port")
    boot.add_argument("--wait", type=discovery_timeout, default=100)
    commands.add_parser("probe")
    chunk = commands.add_parser("read")
    chunk.add_argument("label")
    chunk.add_argument("offset")
    chunk.add_argument("length")
    commands.add_parser("sha256").add_argument("label")
    commands.add_parser("finish")
    backup = commands.add_parser("backup", help="copy and verify all nine partitions into a new private directory")
    backup.add_argument("directory", type=Path)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("this transport requires macOS")
    try:
        if args.command == "serve":
            serve(args.socket, args.port, args.wait)
            return
        path = os.environ.get("GRIZZLY_NV_SOCKET")
        if not path:
            raise TransportError("set GRIZZLY_NV_SOCKET to the private bridge socket")
        if args.command == "backup":
            os.umask(0o077)
            copy_backup(path, args.directory)
            print("Grizzly NV backup complete. All nine partitions verified.")
            return
        operation = "DONE" if args.command == "finish" else args.command.upper()
        fields = ["NV1", operation]
        if args.command in ("read", "sha256"):
            if sys.stdout.isatty():
                raise TransportError("send partition data and digests to a private destination")
            fields.append(args.label)
        if args.command == "read":
            fields.extend((args.offset, args.length))
        request = parse_request((" ".join(fields) + "\n").encode("ascii", errors="replace"))
        sys.stdout.buffer.write(request_local(path, request))
    except KeyboardInterrupt:
        parser.exit(130, "Grizzly NV transport interrupted\n")
    except TransportError as error:
        parser.exit(1, f"Grizzly NV transport failed ({error})\n")
    except (OSError, ValueError, termios.error, subprocess.SubprocessError):
        parser.exit(1, "Grizzly NV transport failed (device, local socket, or timeout error)\n")


if __name__ == "__main__":
    main()
