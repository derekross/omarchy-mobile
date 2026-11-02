#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check build-boot.py against the phone's own stock boot header, not invented numbers.

An optional stock header may be supplied with BOOT_HEADER_REFERENCE. Keep the
capture outside the repository; the comparison is skipped when it is unset.
"""
import gzip, importlib.util, os, struct, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
STOCK = Path(os.environ["BOOT_HEADER_REFERENCE"]) if os.environ.get("BOOT_HEADER_REFERENCE") else None

spec = importlib.util.spec_from_file_location("bb", HERE / "build-boot.py")
bb = importlib.util.module_from_spec(spec); spec.loader.exec_module(bb)

fails = []
def check(cond, msg):
    if not cond: fails.append(msg)

# 1. geometry must equal the stock image's, field by field
if STOCK is not None and STOCK.is_file():
    d = STOCK.read_bytes()
    ks, ka, rs, ra, ss, sa, tags, ps, hv, _ = struct.unpack_from("<10I", d, 8)
    hdr_size = struct.unpack_from("<I", d, 1644)[0]
    check(d[:8] == b"ANDROID!", "the capture is not an Android boot image")
    check(ka == bb.BASE + bb.KERNEL_OFF, f"kernel_addr {ka:#x} != ours {bb.BASE+bb.KERNEL_OFF:#x}")
    # We deliberately place the ramdisk higher than stock: stock's 0x1000000
    # leaves under 16 MiB for the kernel, and ours outgrew that once DRM was
    # built in, which ABL rejects outright. Assert the divergence is upward and
    # still leaves room, rather than requiring equality.
    check(bb.BASE + bb.RAMDISK_OFF >= ra,
          f"our ramdisk_addr {bb.BASE+bb.RAMDISK_OFF:#x} is below stock's {ra:#x}")
    # Stock's layout leaves 16 MiB minus the 32 KiB kernel offset, so assert the
    # room we actually have rather than a round number.
    check(bb.RAMDISK_OFF - bb.KERNEL_OFF >= 16 * 1024 * 1024 - bb.KERNEL_OFF,
          f"only {bb.RAMDISK_OFF - bb.KERNEL_OFF} bytes before the ramdisk")
    check(tags == bb.BASE + bb.TAGS_OFF, f"tags_addr {tags:#x} != ours {bb.BASE+bb.TAGS_OFF:#x}")
    check(ps == bb.PAGE, f"page size {ps} != ours {bb.PAGE}")
    check(hv == bb.HDR_VERSION, f"header_version {hv} != ours {bb.HDR_VERSION}")
    check(ss == 0, "stock uses a second stage; our packer assumes none")
    check(hdr_size == bb.HDR_SIZE, f"header_size {hdr_size} != ours {bb.HDR_SIZE}")
    print("stock geometry: matched field by field")
else:
    print("stock geometry: SKIPPED (set BOOT_HEADER_REFERENCE to a private stock header)")

# 2. pack a dummy image and read it back
with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    kern = t / "Image.gz"; kern.write_bytes(gzip.compress(b"not really a kernel" * 500))
    # a minimal but valid FDT, so the appended-DTB check has something to find
    dtb = t / "d.dtb"
    body = b"\x00" * 56
    dtb.write_bytes(b"\xd0\x0d\xfe\xed" + struct.pack(">I", 64) + body)
    rd = t / "initramfs.cpio.gz"; rd.write_bytes(gzip.compress(b"ramdisk" * 300))
    out = t / "images"
    r = subprocess.run([sys.executable, str(HERE / "build-boot.py"), "--kernel", str(kern),
                        "--dtb", str(dtb), "--ramdisk", str(rd), "--out", str(out)],
                       capture_output=True, text=True)
    check(r.returncode == 0, f"packer failed: {r.stderr.strip()}")
    img = (out / "boot.img").read_bytes()
    check(img[:8] == b"ANDROID!", "no magic")
    check(len(img) % bb.PAGE == 0, "image is not page aligned")
    kb = kern.read_bytes() + dtb.read_bytes()
    check(struct.unpack_from("<I", img, 8)[0] == len(kb), "kernel_size wrong")
    check(img[bb.PAGE:bb.PAGE + len(kb)] == kb, "kernel bytes misplaced")
    check((out / "Image.gz-dtb").read_bytes() == kb, "Image.gz-dtb is not kernel+dtb")
    check(b"\xd0\x0d\xfe\xed" in img, "appended DTB missing from the image")

    # 3. a kernel with no DTB appended must be refused, not silently shipped
    r2 = subprocess.run([sys.executable, str(HERE / "build-boot.py"), "--kernel", str(kern),
                         "--dtb", str(t / "empty.dtb"), "--ramdisk", str(rd), "--out", str(out)],
                        capture_output=True, text=True)
    check(r2.returncode != 0, "accepted a missing DTB file")

    # 3b. a kernel that would reach into the ramdisk must be refused
    big = t / "big.gz"; big.write_bytes(b"\x00" * (bb.RAMDISK_OFF - bb.KERNEL_OFF + 1))
    rb = subprocess.run([sys.executable, str(HERE / "build-boot.py"), "--kernel", str(big),
                         "--dtb", str(dtb), "--ramdisk", str(rd), "--out", str(out)],
                        capture_output=True, text=True)
    check(rb.returncode != 0, "packed a kernel that overlaps the ramdisk")
    check("fit between" in rb.stderr or "fit between" in rb.stdout,
          "the overlap refusal must say why")

    # 4. an oversized cmdline must be refused, not truncated into the header
    r3 = subprocess.run([sys.executable, str(HERE / "build-boot.py"), "--kernel", str(kern),
                         "--dtb", str(dtb), "--ramdisk", str(rd), "--out", str(out),
                         "--cmdline", "x" * 600], capture_output=True, text=True)
    check(r3.returncode != 0, "accepted a 600-byte cmdline into a 512-byte field")

if fails:
    print("FAIL:"); [print("   ", f) for f in fails]; sys.exit(1)
print("test-build-boot OK: image round-trips and bad inputs refused")
