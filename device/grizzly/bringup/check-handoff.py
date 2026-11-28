#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check the size and placement of unpacked Grizzly D1 boot payloads."""

import argparse
from pathlib import Path
import struct
import subprocess


KERNEL_START = 0x80000000
INITRD_START = 0x86000000
FDT_START = 0x8A000000
FDT_HEADER_SIZE = 40
FDT_MAGIC = 0xD00DFEED
FDT_MAX_SIZE = 2 * 1024 * 1024
FDT_FIXUP_SPACE = 0x4000
FDT_CONTAINER_MAX_SIZE = 0xF00000
BOOTCONFIG_SPACE = 0x8001
LZ4_MAGIC = (b"\x02\x21\x4c\x18", b"\x04\x22\x4d\x18")


def image_span(image):
    with image.open("rb") as source:
        header = source.read(64)
    size = image.stat().st_size
    if size <= 64 or len(header) < 64 or header[0x38:0x3C] != b"ARMd":
        raise ValueError(f"{image} needs an uncompressed arm64 Image with a kernel payload")

    text_offset, image_size = struct.unpack_from("<QQ", header, 8)
    if image_size == 0:
        text_offset = 0x80000
    if text_offset % 4:
        raise ValueError(f"arm64 Image text offset {text_offset:#x} is not instruction-aligned")
    end = KERNEL_START + text_offset + max(size, image_size)
    if end > INITRD_START:
        raise ValueError(f"kernel ends at {end:#x}, past {INITRD_START:#x}")
    return KERNEL_START + text_offset, end


def same_payload(expected, candidate):
    for block in iter(lambda: expected.read(1024 * 1024), b""):
        if candidate.read(len(block)) != block:
            return False
    return candidate.read(1) == b""


def check_packed_kernel(image, packed):
    if not 0 < packed.stat().st_size <= INITRD_START - KERNEL_START:
        raise ValueError("packed kernel must fit the 96 MiB input window")

    with image.open("rb") as expected, packed.open("rb") as source:
        if source.read(4) in LZ4_MAGIC:
            with subprocess.Popen(
                ["lz4", "-dc", str(packed.resolve())],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            ) as decoder:
                matches = same_payload(expected, decoder.stdout)
                if not matches:
                    decoder.kill()
                matches = decoder.wait() == 0 and matches
        else:
            source.seek(0)
            matches = same_payload(expected, source)
    if not matches:
        raise ValueError("packed kernel does not match the supplied arm64 Image as raw or LZ4")


def initrd_end(ramdisks):
    size = 0
    for fragment in ramdisks:
        if not fragment.is_file():
            raise ValueError(f"{fragment} needs a ramdisk file")
        fragment_size = fragment.stat().st_size
        if fragment_size == 0:
            continue
        remainder = size % 16
        if remainder:
            size += (16 if remainder <= 12 else 32) - remainder
        size += fragment_size
    end = INITRD_START + size + BOOTCONFIG_SPACE
    if end > FDT_START:
        raise ValueError(f"initrd and bootconfig end at {end:#x}, past {FDT_START:#x}")
    return end


def read_fdt_size(source, remaining, filename):
    offset = source.tell()
    header = source.read(FDT_HEADER_SIZE)
    if len(header) < FDT_HEADER_SIZE:
        raise ValueError(f"{filename}: incomplete FDT header at {offset:#x}")

    (
        magic, size, structure, strings, reservations, version, compatible, _,
        strings_size, structure_size,
    ) = struct.unpack(">10I", header)
    if magic != FDT_MAGIC or not FDT_HEADER_SIZE < size <= remaining:
        raise ValueError(f"{filename}: invalid FDT header at {offset:#x}")
    if version < 16 or compatible > min(version, 17):
        raise ValueError(f"{filename}: unsupported FDT version at {offset:#x}")
    if version < 17:
        structure_size = strings - structure
    if not (
        structure >= FDT_HEADER_SIZE
        and structure % 4 == 0
        and structure_size >= 16
        and structure + structure_size <= size
        and FDT_HEADER_SIZE <= strings <= size - strings_size
        and reservations % 8 == 0
        and FDT_HEADER_SIZE <= reservations <= size - 16
    ):
        raise ValueError(f"{filename}: FDT block outside its declared size at {offset:#x}")
    return size


def fdt_end(dtb):
    with dtb.open("rb") as source:
        size = read_fdt_size(source, dtb.stat().st_size, dtb)
    workspace = size + FDT_FIXUP_SPACE
    if workspace > FDT_MAX_SIZE:
        raise ValueError(f"FDT plus fixup space is {workspace:#x}, above {FDT_MAX_SIZE:#x}")
    return FDT_START + workspace


def check_fdt_container(container):
    remaining = container.stat().st_size
    if not 0 < remaining <= FDT_CONTAINER_MAX_SIZE:
        raise ValueError("DTB container must fit the 15 MiB input window")
    with container.open("rb") as source:
        while remaining:
            size = read_fdt_size(source, remaining, container)
            source.seek(source.tell() + size - FDT_HEADER_SIZE)
            remaining -= size


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="uncompressed arm64 Image")
    parser.add_argument("dtb", type=Path, help="board DTB with candidate overlays applied")
    parser.add_argument("vendor_kernel_boot_ramdisk", type=Path)
    parser.add_argument("vendor_boot_ramdisk", type=Path)
    parser.add_argument("init_boot_ramdisk", type=Path)
    parser.add_argument("--packed-kernel", type=Path, help="kernel payload as packed in boot.img")
    parser.add_argument("--dtb-container", type=Path, help="DTB payload before ABL board selection")
    args = parser.parse_args()

    try:
        start, kernel_end = image_span(args.image)
        if args.packed_kernel:
            check_packed_kernel(args.image, args.packed_kernel)
        if args.dtb_container:
            check_fdt_container(args.dtb_container)

        ramdisks = (args.vendor_kernel_boot_ramdisk, args.vendor_boot_ramdisk, args.init_boot_ramdisk)
        ramdisk_end = initrd_end(ramdisks)
        dtb_end = fdt_end(args.dtb)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"{exc}\n")

    print(f"Kernel entry {start:#x}, occupied through {kernel_end - 1:#x}")
    print(f"Initrd with bootconfig allowance [{INITRD_START:#x}, {ramdisk_end:#x})")
    print(f"FDT with fixup space [{FDT_START:#x}, {dtb_end:#x})")


if __name__ == "__main__":
    main()
