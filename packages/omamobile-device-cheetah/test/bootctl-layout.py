# SPDX-License-Identifier: MIT
"""Exercise the packaged tool on synthetic, regular-file devinfo images."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


def image(major=3, minor=19, a_flags=0x88, b_flags=0x8c):
    # Nonzero opaque and reserved bytes make a clobber anywhere visible.
    data = bytearray(bytes(range(256)) * 32)
    struct.pack_into("<4sHH", data, 0, b"DEVI", major, minor)
    data[0x30:0x38] = bytes([2, a_flags, 0xaa, 0xbb, 1, b_flags, 0xcc, 0xdd])
    return data


def main(binary):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "devinfo"

        def check(data, operation, args, status, message, expected=None):
            path.write_bytes(data)
            result = subprocess.run([binary, operation, path, *args], capture_output=True, text=True)
            output = result.stdout + result.stderr
            if result.returncode != status or message not in output:
                raise AssertionError(f"{operation} {args}: exit {result.returncode}\n{output}")
            if path.read_bytes() != (data if expected is None else expected):
                raise AssertionError(f"{operation} {args}: unexpected change to the image")

        original = image()
        confirm = "--i-understand"
        marked = original.copy()
        marked[0x35] |= 0x02
        check(original, "dump", [], 0, "only mark-successful on active, bootable slot B")
        check(original, "mark-successful", ["b"], 1, "0x35: 8c -> 8e")
        check(original, "mark-successful", ["b", confirm], 0, "written and verified", marked)
        check(marked, "mark-successful", ["b", confirm], 0, "nothing to change")

        for operation, slot in [("mark-successful", "a"), ("set-active", "a"), ("set-active", "b")]:
            check(original, operation, [slot, confirm], 1, "refusing to write")
        for a, b in [(0x04, 0), (0, 0), (0x04, 0x04), (0, 0x05)]:
            check(image(a_flags=a, b_flags=b), "mark-successful", ["b", confirm], 1, "refusing to write")
        for major, minor in [(3, 18), (3, 20), (4, 19)]:
            check(image(major, minor), "mark-successful", ["b", confirm], 1, "refusing to write")

        # General slot updates remain available on the reference 3.15 layout.
        reference = image(minor=15)
        active_a = reference.copy()
        active_a[0x30] = 3
        active_a[0x31] = 0x84
        active_a[0x35] = 0x88
        check(reference, "set-active", ["a", confirm], 0, "written and verified", active_a)


if __name__ == "__main__":
    main(sys.argv[1])
