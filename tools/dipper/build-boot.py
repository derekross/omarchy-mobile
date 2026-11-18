#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Pack dipper's kernel + appended DTB and the initramfs into an Android v1 boot image.

Every offset here was read off the phone's own stock boot image (header v1,
page 4096, kernel 0x8000, ramdisk 0x1000000, tags 0x100, base 0), so the image
we hand ABL has the same geometry as the one it already boots. The DTB is
appended to the kernel because dipper's stock image carries its FDTs that way
(two concatenated FDTs at the end of the kernel blob, selected by msm-id).

No mkbootimg dependency: the v1 header is 1648 bytes of fixed layout and we
verify what we wrote before returning.
"""
import argparse, hashlib, json, struct, sys
from pathlib import Path

PAGE = 4096
BASE = 0x00000000
KERNEL_OFF = 0x00008000
# Stock's own value, and the only one seen to boot on this phone. It leaves
# 16 MiB - 32 KiB for the kernel; check_layout() refuses anything larger rather
# than letting ABL answer with
#   Failed to load/authenticate boot image: 00000050
# which it does with no kernel output and no clue.
RAMDISK_OFF = 0x01000000
SECOND_OFF = 0x00f00000
TAGS_OFF = 0x00000100
HDR_VERSION = 1
HDR_SIZE = 1648
# From the phone: console on the framebuffer, early console on the SoC's UART
# (stock passes earlycon=msm_geni_serial,0xA84000), then the shared init.
CMDLINE = ("console=tty0 earlycon=msm_geni_serial,0xa84000 rdinit=/init "
           "panic=10 printk.devkmsg=on rootwait")
# dipper's boot partition, measured: 65536 blocks of 1 KiB.
BOOT_PARTITION_BYTES = 64 * 1024 * 1024
# This ABL refuses a larger kernel with only
#   Booting FAILED (remote: 'Failed to load/authenticate boot image: 00000050')
# Measured on the phone: 16,247,767 bytes boots, 16,343,459 does not.
KERNEL_MAX = 0xF80000


def pad(b: bytes) -> bytes:
    r = len(b) % PAGE
    return b + (b"\0" * (PAGE - r) if r else b"")


def check_layout(kernel: bytes, ramdisk: bytes) -> None:
    """The kernel must end before the ramdisk begins, or ABL rejects the image."""
    if len(kernel) > KERNEL_MAX:
        raise SystemExit(
            f"kernel+dtb is {len(kernel)} bytes; this phone's ABL refuses more "
            f"than {KERNEL_MAX} ({KERNEL_MAX / 1048576:.2f} MiB) and says only "
            "'Failed to load/authenticate boot image: 00000050'. Move drivers "
            "to modules.")
    room = RAMDISK_OFF - KERNEL_OFF
    if len(kernel) > room:
        raise SystemExit(
            f"kernel+dtb is {len(kernel)} bytes but only {room} fit between "
            f"kernel_offset {KERNEL_OFF:#x} and ramdisk_offset {RAMDISK_OFF:#x}; "
            "raise RAMDISK_OFF or shrink the kernel")
    end = RAMDISK_OFF + len(ramdisk)
    if end > BOOT_PARTITION_BYTES * 4:
        raise SystemExit(f"the loaded image would reach {end:#x}, which is implausible")


def build_header(kernel: bytes, ramdisk: bytes, cmdline: str) -> bytes:
    cmd = cmdline.encode()
    if len(cmd) > 511:
        raise SystemExit(f"cmdline is {len(cmd)} bytes; the v1 header holds 512 with its NUL")
    h = bytearray(PAGE)
    h[0:8] = b"ANDROID!"
    struct.pack_into("<10I", h, 8,
                     len(kernel), BASE + KERNEL_OFF,
                     len(ramdisk), BASE + RAMDISK_OFF,
                     0, BASE + SECOND_OFF,           # no second stage: the DTB is appended
                     BASE + TAGS_OFF, PAGE, HDR_VERSION, 0)
    h[48:64] = b"\0" * 16                            # product name: stock leaves it empty too
    h[64:64 + len(cmd)] = cmd
    # id[32] at 576 and extra_cmdline[1024] at 608 stay zero.
    struct.pack_into("<IQI", h, 1632, 0, 0, HDR_SIZE)  # recovery_dtbo_size/offset, header_size
    return bytes(h)


def verify(img: bytes, kernel: bytes, ramdisk: bytes, cmdline: str) -> None:
    """Re-read what we wrote: a wrong header silently bricks a boot attempt."""
    if img[:8] != b"ANDROID!":
        raise SystemExit("bad magic in the image we just built")
    ks, ka, rs, ra, ss, sa, tags, ps, hv, _ = struct.unpack_from("<10I", img, 8)
    if (ks, rs, ss) != (len(kernel), len(ramdisk), 0):
        raise SystemExit(f"sizes disagree: {(ks, rs, ss)}")
    if (ka, ra, tags, ps, hv) != (BASE + KERNEL_OFF, BASE + RAMDISK_OFF, BASE + TAGS_OFF, PAGE, HDR_VERSION):
        raise SystemExit(f"geometry disagrees with the stock image: {(ka, ra, tags, ps, hv)}")
    if struct.unpack_from("<I", img, 1632 + 12)[0] != HDR_SIZE:
        raise SystemExit("header_size disagrees")
    if img[64:64 + len(cmdline.encode())].decode() != cmdline:
        raise SystemExit("cmdline did not survive")
    k0 = PAGE
    if img[k0:k0 + len(kernel)] != kernel:
        raise SystemExit("kernel payload misplaced")
    r0 = k0 + len(pad(kernel))
    if img[r0:r0 + len(ramdisk)] != ramdisk:
        raise SystemExit("ramdisk payload misplaced")
    # The appended DTB must be findable, or ABL has no device tree to hand on.
    if kernel.rfind(b"\xd0\x0d\xfe\xed") < 0:
        raise SystemExit("no FDT magic in the kernel blob: the DTB was not appended")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", type=Path, required=True, help="Image.gz")
    ap.add_argument("--dtb", type=Path, required=True, help="sdm845-xiaomi-dipper.dtb")
    ap.add_argument("--ramdisk", type=Path, required=True, help="initramfs.cpio.gz")
    ap.add_argument("--out", type=Path, required=True, help="output directory")
    ap.add_argument("--cmdline", default=CMDLINE)
    a = ap.parse_args()

    a.out.mkdir(parents=True, exist_ok=True)
    kernel = a.kernel.read_bytes() + a.dtb.read_bytes()   # Image.gz-dtb
    ramdisk = a.ramdisk.read_bytes()
    (a.out / "Image.gz-dtb").write_bytes(kernel)

    check_layout(kernel, ramdisk)
    img = build_header(kernel, ramdisk, a.cmdline) + pad(kernel) + pad(ramdisk)
    verify(img, kernel, ramdisk, a.cmdline)
    if len(img) > BOOT_PARTITION_BYTES:
        raise SystemExit(f"image is {len(img)} bytes; dipper's boot partition holds "
                         f"{BOOT_PARTITION_BYTES}")

    out = a.out / "boot.img"
    out.write_bytes(img)
    manifest = {
        "device": "dipper",
        "header_version": HDR_VERSION,
        "pagesize": PAGE,
        "cmdline": a.cmdline,
        "kernel_bytes": len(kernel),
        "dtb_bytes": a.dtb.stat().st_size,
        "ramdisk_bytes": len(ramdisk),
        "boot_bytes": len(img),
        "boot_partition_bytes": BOOT_PARTITION_BYTES,
        "headroom_bytes": BOOT_PARTITION_BYTES - len(img),
        "kernel_sha256": hashlib.sha256(kernel).hexdigest(),
        "ramdisk_sha256": hashlib.sha256(ramdisk).hexdigest(),
        "boot_sha256": hashlib.sha256(img).hexdigest(),
        "hardware_boot_tested": False,
    }
    (a.out / "BOOT-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"packed {out} ({len(img)} bytes, {manifest['headroom_bytes']} spare in the partition)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
