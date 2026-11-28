# SPDX-License-Identifier: MIT
"""Inspect the stock ARM64 kernel and UFS module archive without a phone."""

import argparse
from collections import Counter
import gzip
import hashlib
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile


LZ4_MAGICS = (bytes.fromhex("02214c18"), bytes.fromhex("04224d18"))
CONFIG_FLAGS = (
    "DEVTMPFS", "BLK_DEV_SD", "BLK_DEV_BSG", "SCSI_UFS_BSG", "CHR_DEV_SG",
    "RPMB", "SCSI_UFS_CRYPTO", "MODULE_SIG", "MODULE_SIG_FORCE",
    "MODULE_SIG_PROTECT", "MODVERSIONS", "SECCOMP_FILTER", "PSTORE_RAM", "PSTORE_CONSOLE",
    "USB_CONFIGFS", "USB_CONFIGFS_NCM",
)


def unpack(path):
    data = path.read_bytes()
    if data[:4] in LZ4_MAGICS:
        return subprocess.check_output(["lz4", "-dc", path])
    return data


def kernel_config(image):
    start = image.find(b"IKCFG_ST\x1f\x8b")
    if start < 0:
        raise ValueError("embedded kernel config is missing")
    start += len(b"IKCFG_ST")
    end = image.find(b"IKCFG_ED", start)
    if end < 0:
        raise ValueError("embedded kernel config has no end marker")
    config = gzip.decompress(image[start:end]).decode()
    options = dict(re.findall(r"^CONFIG_([A-Z0-9_]+)=(.*)$", config, re.M))
    if options.get("ARM64") != "y":
        raise ValueError("kernel config is missing ARM64")
    return options


def module_dependencies(text):
    dependencies = {}
    for line in text.splitlines():
        name, rest = line.split(":", 1)
        module = PurePosixPath(name).name
        if module in dependencies:
            raise ValueError(f"duplicate module in modules.dep: {module}")
        dependencies[module] = tuple(PurePosixPath(path).name for path in rest.split())
    return dependencies


def hard_closure(dependencies, target):
    visiting = set()
    ordered = {}

    def visit(module):
        if module in ordered:
            return
        if module in visiting:
            raise ValueError(f"dependency cycle at {module}")
        if module not in dependencies:
            raise ValueError(f"missing dependency record for {module}")
        visiting.add(module)
        for dependency in dependencies[module]:
            visit(dependency)
        visiting.remove(module)
        ordered[module] = None

    visit(target)
    return tuple(ordered)


def audit(kernel, ramdisk):
    image = unpack(kernel)
    release = re.search(rb"Linux version (\S+)", image)
    if release is None:
        raise ValueError("kernel release banner missing")
    config = kernel_config(image)

    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / "modules.cpio"
        archive.write_bytes(unpack(ramdisk))
        listing = subprocess.check_output(["bsdtar", "-tf", archive], text=True)
        files = Counter(listing.splitlines())

        def member(name):
            path = f"lib/modules/{name}"
            if files[path] != 1:
                raise ValueError(f"expected one ramdisk file {path}")
            return subprocess.check_output(["bsdtar", "-xOf", archive, path])

        dependencies = module_dependencies(member("modules.dep").decode())
        load = [PurePosixPath(line).name for line in member("modules.load").decode().splitlines()
                if line and not line.startswith("#")]
        closure = hard_closure(dependencies, "ufs.ko")
        for name in closure:
            if files[f"lib/modules/{name}"] != 1:
                raise ValueError(f"expected one UFS dependency file for {name}")
        module = member("ufs.ko")
        vermagic = re.search(rb"(?:^|\x00)vermagic=([^\x00]+)\x00", module)
        if vermagic is None:
            raise ValueError("UFS module vermagic missing")

    print(f"Kernel release: {release[1].decode()}")
    for flag in CONFIG_FLAGS:
        print(f"CONFIG_{flag}={config.get(flag, 'n')}")
    print(f"Modules indexed: {len(dependencies)}")
    print(f"Modules in stock load list: {len(load)}")
    for name in ("sg.ko", "ufs.ko", "power_controller.ko"):
        position = load.index(name) + 1 if name in load else "absent"
        print(f"{name} stock load position: {position}")
    print(f"UFS module SHA-256: {hashlib.sha256(module).hexdigest()}")
    print(f"UFS module vermagic: {vermagic[1].decode()}")
    signature_trailer = module.endswith(b"~Module signature appended~\n")
    print(f"UFS module has signature trailer: {signature_trailer}")
    print(f"UFS hard closure, including ufs.ko ({len(closure)} modules):")
    for name in closure:
        print(f"  {name}")
    print("Supplier modules selected by the stock device tree require a separate check.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kernel", type=Path, help="stock kernel payload extracted from boot.img")
    parser.add_argument("ramdisk", type=Path, help="stock vendor_kernel_boot module ramdisk")
    args = parser.parse_args()
    try:
        audit(args.kernel, args.ramdisk)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"stock UFS audit failed: {error}\n")


if __name__ == "__main__":
    main()
