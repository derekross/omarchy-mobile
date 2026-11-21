#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""device/hotdog/slot-a-mark against a disk image file (no phone, no root):
a GPT shaped like the OnePlus 7T Pro's sde (4096-byte blocks, boot_a active
and unmarked, boot_b empty). write sets boot_a's successful bit in both
copies and nothing else, and only against the dump it is given; a write that
stops after the backup copy leaves a split GPT that status reports (exit 2)
and dump and write refuse; restore with the dump taken before the write
puts the bytes back, also over a primary header that no longer reads, after
which write runs again; restore refuses a wrong sha256 and a dump of another
GPT."""
import hashlib
import os
import struct
import subprocess
import sys
import tempfile
import uuid
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "device/hotdog/slot-a-mark")
BS = 4096
BLOCKS = 2048
N = 128


def fail(msg):
    print(f"not ok - {msg}", file=sys.stderr)
    sys.exit(1)


def ok(msg):
    print(f"ok - {msg}")


def make_disk(path, extra=""):
    """A GPT with a few _a/_b entries; boot_a priority 3, active, tries 6."""
    parts = [("abl_a", 0x1044 << 48), ("boot_a", 0x37 << 48), ("abl_b", 0x1000 << 48),
             ("boot_b", 0), ("devinfo" + extra, 0x1000 << 48)]
    ents = bytearray(N * 128)
    for i, (name, attr) in enumerate(parts):
        e = struct.pack("<16s16sQQQ", uuid.UUID(int=1).bytes_le, uuid.UUID(int=100 + i).bytes_le,
                        16 + i * 8, 23 + i * 8, attr) + name.encode("utf-16le").ljust(72, b"\0")
        ents[i * 128:(i + 1) * 128] = e
    ents = bytes(ents)
    ent_blocks = len(ents) // BS
    last = BLOCKS - 1

    def header(my, alt, ent_lba):
        h = bytearray(struct.pack("<8sIIIIQQQQ16sQIII", b"EFI PART", 0x10000, 92, 0, 0, my, alt,
                                  2 + ent_blocks, last - 1 - ent_blocks, uuid.UUID(int=7).bytes_le,
                                  ent_lba, N, 128, zlib.crc32(ents) & 0xFFFFFFFF))
        struct.pack_into("<I", h, 16, zlib.crc32(bytes(h)) & 0xFFFFFFFF)
        return bytes(h).ljust(BS, b"\0")

    with open(path, "wb") as f:
        f.truncate(BLOCKS * BS)
        f.seek(BS)
        f.write(header(1, last, 2))
        f.write(ents)
        f.seek((last - ent_blocks) * BS)
        f.write(ents)
        f.write(header(last, 1, last - ent_blocks))


def run(disk, *args, stop=False):
    env = dict(os.environ, SLOT_A_MARK_TEST="1", SLOT_A_MARK_DISK=disk, SLOT_A_MARK_BS=str(BS))
    if stop:
        env["SLOT_A_MARK_STOP_AFTER_FIRST"] = "1"
    return subprocess.run([sys.executable, "-I", TOOL, *args], env=env, capture_output=True, text=True)


def dump(disk, tar):
    with open(tar, "wb") as f:
        env = dict(os.environ, SLOT_A_MARK_TEST="1", SLOT_A_MARK_DISK=disk, SLOT_A_MARK_BS=str(BS))
        r = subprocess.run([sys.executable, "-I", TOOL, "dump"], env=env, stdout=f,
                           stderr=subprocess.PIPE, text=True)
    if r.returncode:
        fail(f"dump: {r.stderr}")
    return r.stderr.split("sha256 ")[1].split()[0]


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def flags_of(out, name):
    return [l for l in out.splitlines() if l.startswith(f"{name}:")]


with tempfile.TemporaryDirectory() as t:
    disk, tar = os.path.join(t, "sde.img"), os.path.join(t, "gpt-sde.tar")
    make_disk(disk)
    original = sha(disk)
    r = run(disk, "status")
    if r.returncode or "successful 0" not in flags_of(r.stdout, "boot_a")[0] or "copies identical" not in r.stdout:
        fail(f"status reads the GPT: {r.stdout}{r.stderr}")
    s = dump(disk, tar)
    if run(disk, "write", "--sha256", "0" * 64).returncode == 0 or sha(disk) != original:
        fail("write refuses a sha256 other than the dump's and writes nothing")
    r = run(disk, "write", "--sha256", s)
    if r.returncode or "boot_a: priority 3 active 1 tries 6 successful 0 unbootable 0 -> priority 3 active 1 tries 6 successful 1" not in r.stdout:
        fail(f"write marks boot_a: {r.stdout}{r.stderr}")
    if "boot_b: priority 0 active 0 tries 0 successful 0 unbootable 0 -> priority 0 active 0 tries 0 successful 0 unbootable 0" not in r.stdout:
        fail("write leaves boot_b alone")
    marked = sha(disk)
    ok("write sets boot_a's successful bit in both copies, nothing else, only against its dump")

    # The restore puts a marked GPT back to the dump, and write runs again
    r = run(disk, "restore", tar, "--sha256", s)
    if r.returncode or sha(disk) != original:
        fail(f"restore puts a marked GPT back to the dump: {r.stdout}{r.stderr}")
    if run(disk, "restore", tar, "--sha256", "1" * 64).returncode == 0:
        fail("restore refuses a sha256 other than the dump's")
    ok("restore puts the dump's bytes back over a marked GPT, and refuses another sha256")

    # A write that stops after the backup copy: status says so, dump and
    # write refuse, restore undoes it, write finishes
    r = run(disk, "write", "--sha256", s, stop=True)
    if r.returncode == 0 or "stopped after the first copy" not in r.stderr:
        fail(f"the test stop works: {r.stderr}")
    r = run(disk, "status")
    if r.returncode != 2 or "copies differ" not in r.stdout or \
            "primary boot_a: priority 3 active 1 tries 6 successful 0" not in r.stdout or \
            "backup boot_a: priority 3 active 1 tries 6 successful 1" not in r.stdout:
        fail(f"status reports the split GPT, each copy's flags, and exits 2: {r.returncode} {r.stdout}{r.stderr}")
    if run(disk, "write", "--sha256", s).returncode == 0 or \
            run(disk, "dump").returncode == 0:
        fail("write and dump refuse a split GPT")
    r = run(disk, "restore", tar, "--sha256", s)
    if r.returncode or sha(disk) != original or "with boot_a marked successful" not in r.stderr:
        fail(f"restore undoes a half write: {r.stdout}{r.stderr}")
    r = run(disk, "write", "--sha256", s)
    if r.returncode or sha(disk) != marked:
        fail(f"write runs again after the restore: {r.stdout}{r.stderr}")
    ok("a write stopped after the backup copy: status reports it, dump and write refuse, restore undoes it, write finishes")

    # A primary header that no longer reads
    with open(disk, "r+b") as f:
        f.seek(BS)
        f.write(b"\xff" * 512)
    r = run(disk, "status")
    if r.returncode != 2 or "primary: unreadable" not in r.stdout:
        fail(f"status names an unreadable primary: {r.stdout}{r.stderr}")
    r = run(disk, "restore", tar, "--sha256", s)
    if r.returncode or sha(disk) != original:
        fail(f"restore replaces an unreadable primary: {r.stdout}{r.stderr}")
    ok("restore replaces a primary header that no longer reads")

    # A dump of another GPT is refused, and nothing is written
    other, other_tar = os.path.join(t, "other.img"), os.path.join(t, "other.tar")
    make_disk(other, extra="x")
    os_ = dump(other, other_tar)
    r = run(disk, "restore", other_tar, "--sha256", os_)
    if r.returncode == 0 or "other entries than the dump's" not in r.stderr or sha(disk) != original:
        fail(f"restore refuses a dump of another GPT: {r.stdout}{r.stderr}")
    ok("restore refuses a dump of another GPT and writes nothing")
