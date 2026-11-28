#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify the Grizzly stock-D1 USB2 fixture from macOS."""

import argparse
from contextlib import nullcontext, suppress
import hashlib
import json
import math
import os
import plistlib
import re
import select
import stat
import subprocess
import sys
import termios
import time


USB_PRODUCT = "Grizzly USB2 Diagnostic"
USB_SERIAL = "grizzly-usb2-test"
PORT_PATTERN = re.compile(r"/dev/cu\.usbmodem[A-Za-z0-9._-]+")
REQUEST = b"GRIZZLY-USB2-PROBE\n"
HEADER = b"GRIZZLY-USB2-OK\n"
PAYLOAD = bytes(range(256)) * 256
PAYLOAD_SHA256 = "7daca2095d0438260fa849183dfc67faa459fdf4936e1bc91eec6b281b27e4c2"
DEVICE_FIELDS = (
    "Device Speed", "USBSpeed", "UsbLinkSpeed", "UsbEnumerationState",
    "kUSBAddress", "kUSBCurrentConfiguration", "kUSBPreferredConfiguration",
    "kUSBFailedRequestedPower", "bNumConfigurations", "bcdUSB",
    "bDeviceClass", "bDeviceSubClass", "bDeviceProtocol", "idVendor", "idProduct",
)
INTERFACE_FIELDS = (
    "bConfigurationValue", "bInterfaceNumber", "bAlternateSetting",
    "bInterfaceClass", "bInterfaceSubClass", "bInterfaceProtocol", "bNumEndpoints",
)
ENDPOINT_FIELDS = ("bEndpointAddress", "bmAttributes", "wMaxPacketSize", "bInterval")
SERIAL_SERVICES = (
    "AppleUSBCDCCompositeDevice", "AppleUSBACMControl", "AppleUSBACMData",
    "AppleUSBCDCACMControl", "AppleUSBCDCACMData", "IOSerialBSDClient",
    "IOSerialStreamSync",
)
MAX_OBSERVATION_RECORDS = 64
MAX_OBSERVED_FIXTURES = 4
MAX_OBSERVED_SERVICES = 32


def is_usb_device(node):
    return node.get("IOObjectClass") in ("IOUSBHostDevice", "IOUSBDevice") or all(
        key in node for key in ("bDeviceClass", "idVendor", "idProduct")
    )


def is_fixture(node):
    return (
        node.get("USB Product Name") == USB_PRODUCT
        and node.get("USB Serial Number") == USB_SERIAL
    )


def matching_ports(registry):
    identities = {}

    def visit(node, target=False):
        # Descendants can inherit the identity of their nearest USB device only.
        if is_usb_device(node):
            target = is_fixture(node)

        port = node.get("IOCalloutDevice")
        if isinstance(port, str) and PORT_PATTERN.fullmatch(port):
            identities.setdefault(port, []).append(target)

        for child in node.get("IORegistryEntryChildren", []):
            visit(child, target)

    for root in registry if isinstance(registry, list) else [registry]:
        visit(root)
    return sorted(port for port, matches in identities.items() if matches == [True])


def descriptor_fields(node, fields):
    expected = {}
    for key in fields:
        value = node.get(key)
        if isinstance(value, int) and 0 <= value <= 65535:
            expected[key] = value
    return expected


def fixture_snapshot(registry, ports):
    fixtures = []

    def visit(node, fixture=None, interface=None):
        if is_usb_device(node):
            fixture = None
            interface = None
            if is_fixture(node) and len(fixtures) < MAX_OBSERVED_FIXTURES:
                fixture = {
                    "device": descriptor_fields(node, DEVICE_FIELDS),
                    "interfaces": [], "endpoints": [], "services": [],
                    "callouts": 0, "usbmodem_callouts": 0,
                }
                fixtures.append(fixture)

        if fixture is not None:
            node_class = node.get("IOObjectClass")
            if node_class in ("IOUSBHostInterface", "IOUSBInterface"):
                details = descriptor_fields(node, INTERFACE_FIELDS)
                if len(fixture["interfaces"]) < MAX_OBSERVED_SERVICES:
                    fixture["interfaces"].append(details)
                interface = details.get("bInterfaceNumber")
            if "bEndpointAddress" in node and len(fixture["endpoints"]) < MAX_OBSERVED_SERVICES:
                fixture["endpoints"].append({
                    "interface": interface, **descriptor_fields(node, ENDPOINT_FIELDS),
                })
            if node_class in SERIAL_SERVICES and len(fixture["services"]) < MAX_OBSERVED_SERVICES:
                fixture["services"].append({"interface": interface, "class": node_class})
            callout = node.get("IOCalloutDevice")
            if isinstance(callout, str):
                fixture["callouts"] += 1
                if PORT_PATTERN.fullmatch(callout):
                    fixture["usbmodem_callouts"] += 1

        for child in node.get("IORegistryEntryChildren", []):
            visit(child, fixture, interface)

    for root in registry if isinstance(registry, list) else [registry]:
        visit(root)
    return {"fixtures": fixtures, "verified_callouts": len(ports)}


def open_observation(path):
    # Exclusive creation avoids changing an existing file or following a link.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    return os.fdopen(fd, "w", encoding="utf-8")


def wait_for_port(requested, seconds, observation=None):
    started = time.monotonic()
    deadline = started + seconds
    previous = None
    records = 0
    while (remaining := deadline - time.monotonic()) > 0:
        result = subprocess.run(
            ["/usr/sbin/ioreg", "-a", "-l", "-w", "0", "-p", "IOService", "-r", "-c", "IOUSBHostDevice"],
            capture_output=True,
            check=True,
            timeout=min(remaining, 5),
        )
        registry = plistlib.loads(result.stdout)
        ports = matching_ports(registry)
        if observation is not None and records < MAX_OBSERVATION_RECORDS:
            sample = fixture_snapshot(registry, ports)
            if sample != previous:
                record = {"elapsed_s": round(time.monotonic() - started, 3)}
                if records == MAX_OBSERVATION_RECORDS - 1:
                    record["observation_limit_reached"] = True
                else:
                    record.update(sample)
                print(json.dumps(record), file=observation, flush=True)
                records += 1
                previous = sample
        if requested:
            if requested in ports:
                return requested
        elif len(ports) == 1:
            return ports[0]
        elif ports:
            raise ValueError(f"multiple Grizzly diagnostic ports, choose --port from {', '.join(ports)}")
        time.sleep(max(0, min(0.25, deadline - time.monotonic())))
    raise TimeoutError(f"no verified Grizzly diagnostic endpoint for {requested or '/dev/cu.usbmodem*'}")


def configure_tty(fd):
    mode = termios.tcgetattr(fd)
    mode[0] = mode[1] = mode[3] = 0
    mode[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    mode[4] = mode[5] = termios.B115200
    mode[6][termios.VMIN] = 1
    mode[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, mode)
    termios.tcflush(fd, termios.TCIOFLUSH)


def write_request(fd, deadline):
    unsent = memoryview(REQUEST)
    while unsent:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([], [fd], [], remaining)[1]:
            raise TimeoutError("timed out sending the Grizzly probe request")
        try:
            sent = os.write(fd, unsent)
        except BlockingIOError:
            continue
        if not sent:
            raise OSError("diagnostic tty closed while sending the probe request")
        unsent = unsent[sent:]


def read_exact(fd, size, label, deadline):
    data = bytearray()
    while len(data) < size:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
            raise TimeoutError(f"timed out reading {label} ({len(data)}/{size} bytes)")
        try:
            chunk = os.read(fd, size - len(data))
        except BlockingIOError:
            continue
        if not chunk:
            raise OSError(f"diagnostic tty closed while reading {label} ({len(data)}/{size} bytes)")
        data.extend(chunk)
    return data


def exchange(fd, seconds):
    old_mode = termios.tcgetattr(fd)
    try:
        configure_tty(fd)
        started = time.monotonic()
        deadline = started + seconds
        write_request(fd, deadline)
        if read_exact(fd, len(HEADER), "response header", deadline) != HEADER:
            raise ValueError("unexpected Grizzly diagnostic response header")
        payload = read_exact(fd, len(PAYLOAD), "synthetic payload", deadline)
        elapsed = time.monotonic() - started
    finally:
        # A fixture restart can remove the tty before it can be restored.
        with suppress(OSError, termios.error):
            termios.tcsetattr(fd, termios.TCSANOW, old_mode)

    digest = hashlib.sha256(payload).hexdigest()
    if payload != PAYLOAD or digest != PAYLOAD_SHA256:
        raise ValueError("synthetic payload bytes or SHA-256 do not match")
    return digest, elapsed


def positive_seconds(value):
    seconds = float(value)
    if not math.isfinite(seconds) or not 0 < seconds <= 300:
        raise argparse.ArgumentTypeError("expected seconds greater than zero and at most 300")
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="select a descriptor-verified /dev/cu.usbmodem port")
    parser.add_argument("--wait", type=positive_seconds, default=30, help="discovery timeout in seconds (default 30)")
    parser.add_argument("--timeout", type=positive_seconds, default=8, help="probe timeout in seconds (default 8)")
    parser.add_argument("--observe", metavar="PATH", help="write a new private JSONL file of USB discovery changes")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("this checker requires macOS")
    if args.port and not PORT_PATTERN.fullmatch(args.port):
        parser.error("--port must be a /dev/cu.usbmodem path")

    try:
        observation = open_observation(args.observe) if args.observe else nullcontext()
        with observation as stream:
            port = wait_for_port(args.port, args.wait, stream)
        fd = os.open(port, os.O_RDWR | os.O_NONBLOCK | os.O_NOCTTY | os.O_NOFOLLOW)
        try:
            if not stat.S_ISCHR(os.fstat(fd).st_mode):
                raise ValueError(f"{port} is not a tty character device")
            digest, elapsed = exchange(fd, args.timeout)
        finally:
            os.close(fd)
    except KeyboardInterrupt:
        parser.exit(130, "Grizzly USB2 diagnostic interrupted\n")
    except (OSError, ValueError, termios.error, subprocess.SubprocessError) as exc:
        parser.exit(1, f"Grizzly USB2 diagnostic failed ({exc})\n")

    rate = len(PAYLOAD) / elapsed / 1024
    print(
        f"Grizzly USB2 diagnostic passed on {port}. Received {len(PAYLOAD)} bytes "
        f"in {elapsed:.3f} s ({rate:.1f} KiB/s request to response). SHA-256 {digest}"
    )


if __name__ == "__main__":
    main()
