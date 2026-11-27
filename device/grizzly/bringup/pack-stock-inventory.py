# SPDX-License-Identifier: MIT
"""Build a local Grizzly D1 stock-kernel diagnostic prototype."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import runpy
import shutil
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory


HERE = Path(__file__).resolve().parent
FACTORY = {
    "boot": "7b5537d318aed78fe52538ce9e08c2dd9800bb25a0df501d94a816af5171603a",
    "init_boot": "8ee7899805bf18512cdce5781f50520a8c505754b7ac716d71f7007dafdb2d07",
    "vendor_boot": "43e5eb394fc4490c26e9c87f9dee7c7d4fde51920260b6340a588b51ae087f23",
    "vendor_kernel_boot": "9830d75882f143a9aad7e2416ec3a5d76c2c35d5a700b8a5aef6cf7cdab7310a",
    "dtbo": "af9aea143fd8bdb711d146292ef5fa273c001566d71743a24798491939adaf4f",
}
CAPACITY = 8 * 1024 * 1024
MODPROBE_SHA256 = "ce0df1807b5726d01838b9e738013f28ebb207bb25ac9776849670701ef784a9"
# kvm-arm.protected_modules in the exact D1 Grizzly boot arguments.
PROTECTED_ROOTS = (
    "goog-mba-ctrl.ko", "pinctrl.ko", "mbfs_cpm_backend.ko", "power_controller.ko",
    "irq-gia-google.ko", "arm_smmu_v3_kvm.ko",
)
CPM_TRACE_MODULES = ("google_thermal_cpm_mbox.ko", "fwtp_lib.ko", "fwtp_cpm_module.ko")
STOCK_UFS_SHA256 = "24463ad9d4f63b3f5672883468f8e8228c0bfc75e91cd62299ffae38469350b0"
PSM1_SAMPLER_SHA256 = "ca17e8708c219353529834b72c478b5e5105d5f46132857717b5c73944a584fa"
PSM1_PREP_SAMPLER_SHA256 = "6a2b75a802729fba0e8c387b2a2d037d96f0e323373f692ceef13c7f41d0222a"
USB2_MODULES = (
    "nvmem-rmem.ko", "i2c-designware-core.ko", "i2c-designware-platform.ko",
    "google-eusb2-repeater.ko", "google_icc.ko", "google-usb-phy.ko", "dwc3-google.ko",
)
USB2_FIRMWARE = "lib/firmware/usb_phy_fw_2.27.0.bin"
USB2_FIRMWARE_SHA256 = "723ff8e0e2aeda20c9b3b18277c93a6a69ddb4f45ff22a30838d7392ebb2b345"
USB2_ISOLATION_DTBO_SHA256 = "075c0d37e382253b58f50e5cac6cfdcfe5e0bad0f57964eb68c7146a921f33e9"
USB2_ISOLATION_BOARD_SHA256 = "e4507c31e1386a3d2a8459942d894743a439980cc32a10e5a5a10da98e250d3e"
NV_RESCUE_INIT_SHA256 = "00784a6ea41f53acdac36ed5c7b81cf6fb90f35067b138bb7c79c0757a6baa75"
# Byte boundary between the factory generic ramdisk and the overlay in this exact rescue.
NV_RESCUE_FACTORY_RAMDISK_SIZE = 2969964
DSI0_TRACE_BOARD_SHA256 = "df00e0d6736a3efefcb5bec99c1d7697bbf44830e0427fd3f889abd0f5bb37bb"
DSI0_CDPHY_SHA256 = "e758f127694b54b47a0dc4b51acf2fd65325ed8f253cabf5c4f9b2738e439df5"
DSI0_MODULES = (
    "tzprot.ko", "gs-drm-connector.ko", "mipi-cdphy.ko", "mipi-dsi2h.ko",
    "google_icc.ko", "drm_display_helper.ko", "vs_drm.ko",
)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def capture(*command):
    return subprocess.check_output(command)


def write_payload(path, content, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    path.chmod(mode)


def check_modules(cpio, manifest):
    audit = runpy.run_path(str(HERE / "audit-stock-ufs.py"))
    dep = capture("bsdtar", "-xOf", cpio, "lib/modules/modules.dep")
    dependencies = audit["module_dependencies"](dep.decode())
    members = set(capture("bsdtar", "-tf", cpio).decode().splitlines())
    loaded = set()
    for line in manifest.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, *parameters = line.split()
        if (not re.fullmatch(r"[a-zA-Z0-9_-]+\.ko", name)
                or name in {"sg.ko", "pixel-reboot.ko"} or "rpmb" in name
                or name in loaded or name not in dependencies
                or f"lib/modules/{name}" not in members):
            raise ValueError(f"invalid inventory module: {name}")
        if any(not re.fullmatch(r"[a-zA-Z0-9_]+=[a-zA-Z0-9_-]+", arg)
               for arg in parameters):
            raise ValueError(f"invalid parameters for {name}")
        if set(dependencies[name]) - loaded:
            raise ValueError(f"dependency order incomplete for {name}")
        loaded.add(name)
    if "ufs.ko" not in loaded:
        raise ValueError("inventory manifest is missing ufs.ko")

    protected = set()
    for root in PROTECTED_ROOTS:
        protected.update(audit["hard_closure"](dependencies, root))
    if protected - loaded:
        raise ValueError("inventory manifest is missing the protected module closure")
    preloads = sorted(name.removesuffix(".ko").replace("-", "_") for name in protected)
    if len(set(preloads)) != len(preloads):
        raise ValueError("protected module names collide after normalization")
    softdep = capture("bsdtar", "-xOf", cpio, "lib/modules/modules.softdep").decode()
    for line in softdep.splitlines():
        fields = line.split()
        if len(fields) > 1 and fields[0] == "softdep" and fields[1].replace("-", "_") in preloads:
            raise ValueError(f"unexpected soft dependency in protected closure: {fields[1]}")
    return len(loaded), preloads


def add_usb2_test(root, vendor_cpio, manifest, count, preloads, reader):
    usb_modules = "\n".join(USB2_MODULES) + "\n"
    full_count, full_preloads = check_modules(vendor_cpio, manifest.rstrip() + "\n" + usb_modules)
    if full_count != count + len(USB2_MODULES) or full_preloads != preloads:
        raise ValueError("USB2 modules must load separately after the NV guard")
    test = root / "grizzly-inventory"
    write_payload(test / "usb2-test", b"", 0o644)
    write_payload(test / "usb2-test.sh", (HERE / "stock-usb2-test.sh").read_bytes(), 0o644)
    write_payload(test / "usb2.modules", usb_modules.encode(), 0o644)
    if reader is None:
        write_payload(test / "usb2-test.bin", bytes(range(256)) * 256, 0o644)
    else:
        write_payload(test / "nv-reader-mode", b"", 0o644)
        write_payload(test / "nv-reader", reader, 0o755)


def read_nv_reader(path):
    reader = path.read_bytes()
    if len(reader) < 64 or reader[:6] != b"\x7fELF\x02\x01":
        raise ValueError("expected a static ARM64 NV reader executable")
    kind, machine = struct.unpack_from("<HH", reader, 16)
    headers = struct.unpack_from("<Q", reader, 32)[0]
    header_size, header_count = struct.unpack_from("<HH", reader, 54)
    if (kind != 2 or machine != 183 or header_size != 56 or not header_count
            or headers < 64 or headers + header_count * header_size > len(reader)):
        raise ValueError("invalid ARM64 NV reader ELF headers")
    segments = {struct.unpack_from("<I", reader, headers + i * header_size)[0]
                for i in range(header_count)}
    if 1 not in segments or segments & {2, 3}:
        raise ValueError("NV reader must be linked statically")
    return reader


def pack(args):
    sampler_path = args.ufs_psm1_prep_trace or args.ufs_psm1_trace
    power_trace = args.ufs_power_trace or args.ufs_pre_on_trace or sampler_path or args.ufs_cpm_trace
    stock = {name: args.factory / f"{name}.img" for name in FACTORY}
    expected_images = FACTORY
    if args.dsi0_trace:
        expected_images = dict(FACTORY, init_boot=NV_RESCUE_INIT_SHA256, dtbo=USB2_ISOLATION_DTBO_SHA256)
        if digest(args.board_dtb) != DSI0_TRACE_BOARD_SHA256:
            raise ValueError("DSI0 trace requires the audited B0 merge of NV rescue DTBO entry 19")
    for name, path in stock.items():
        if digest(path) != expected_images[name]:
            raise ValueError(f"{path} differs from the audited D1 factory image")
    sampler = None
    if sampler_path:
        sampler = sampler_path.read_bytes()
        expected = PSM1_PREP_SAMPLER_SHA256 if args.ufs_psm1_prep_trace else PSM1_SAMPLER_SHA256
        if hashlib.sha256(sampler).hexdigest() != expected:
            raise ValueError("PSM1 sampler differs from the loader-verified D1 module")
    reader = None
    isolation_dtbo = args.usb2_ep0_trace
    if args.usb2_nv_reader:
        reader_path, isolation_dtbo = args.usb2_nv_reader
        reader = read_nv_reader(reader_path)
    if isolation_dtbo:
        if (digest(isolation_dtbo) != USB2_ISOLATION_DTBO_SHA256
                or digest(args.board_dtb) != USB2_ISOLATION_BOARD_SHA256):
            raise ValueError("USB2 isolation requires the verified DWC3 isolation DTBO and merged board DTB")
        capture(sys.executable, "-I", args.avbtool, "verify_image", "--image", isolation_dtbo)

    args.output.mkdir(mode=0o700)
    images = args.output / "images"
    images.mkdir()
    with TemporaryDirectory(dir=args.output) as scratch:
        temp = Path(scratch)
        for name in ("boot", "vendor_boot", "vendor_kernel_boot"):
            capture(sys.executable, args.unpack, "--boot_img", stock[name], "--out", temp / name)
        vendor_kernel_ramdisk = temp / "vendor_kernel_boot/vendor_ramdisk00"
        vendor_kernel_cpio = temp / "vendor-kernel.cpio"
        vendor_kernel_cpio.write_bytes(capture("lz4", "-dc", vendor_kernel_ramdisk))
        if sampler is not None:
            ufs = capture("bsdtar", "-xOf", vendor_kernel_cpio, "lib/modules/ufs.ko")
            if hashlib.sha256(ufs).hexdigest() != STOCK_UFS_SHA256:
                raise ValueError("factory ufs.ko differs from the audited D1 module")
            print(f"Factory ufs.ko SHA-256 verified: {STOCK_UFS_SHA256}")
        root = temp / "root"
        write_payload(root / "init", (HERE / "stock-inventory-init").read_bytes(), 0o755)
        write_payload(root / "grizzly-inventory/scan.sh",
                      (HERE / "stock-inventory-scan.sh").read_bytes(), 0o644)
        archive_members = ["init", "grizzly-inventory", "lib"]
        count = 0
        factory_init_ramdisk = None
        if args.handoff_only or args.preinit_helper_only:
            write_payload(root / "grizzly-inventory/handoff-only", b"", 0o644)
        else:
            manifest = (HERE / "stock-inventory.modules").read_text()
            if args.ufs_cpm_trace:
                lines = manifest.splitlines()
                (ufs_index,) = (i for i, line in enumerate(lines)
                                if line.split()[:1] == ["ufs.ko"])
                lines[ufs_index:ufs_index] = CPM_TRACE_MODULES
                manifest = "\n".join(lines) + "\n"
            count, preloads = check_modules(vendor_kernel_cpio, manifest)
            write_payload(root / "grizzly-inventory/preloaded.modules",
                          ("\n".join(preloads) + "\n").encode(), 0o644)
            if args.preloads_only:
                write_payload(root / "grizzly-inventory/preloads-only", b"", 0o644)
            else:
                write_payload(root / "stock-inventory.modules", manifest.encode(), 0o644)
                archive_members.append("stock-inventory.modules")
                if args.nv_guard_only or args.ufs_refclk_only or power_trace or args.usb2_test or args.dsi0_trace:
                    write_payload(root / "grizzly-inventory/nv-guard.sh",
                                  (HERE / "stock-nv-guard.sh").read_bytes(), 0o644)
                if args.nv_guard_only or args.dsi0_trace:
                    write_payload(root / "grizzly-inventory/nv-guard-only", b"", 0o644)
                if args.dsi0_trace:
                    display_manifest = "\n".join(DSI0_MODULES) + "\n"
                    full_count, full_preloads = check_modules(
                        vendor_kernel_cpio, manifest.rstrip() + "\n" + display_manifest)
                    if full_count != count + len(DSI0_MODULES) or full_preloads != preloads:
                        raise ValueError("DSI0 closure must load separately after the NV guard")
                    write_payload(root / "grizzly-inventory/dsi0.modules",
                                  display_manifest.encode(), 0o644)
                    write_payload(root / "grizzly-inventory/stock-dsi0-trace.sh",
                                  (HERE / "stock-dsi0-trace.sh").read_bytes(), 0o755)
                    if args.dsi0_pll_trace or args.dsi0_genpd_trace:
                        cdphy = capture("bsdtar", "-xOf", vendor_kernel_cpio, "lib/modules/mipi-cdphy.ko")
                        if hashlib.sha256(cdphy).hexdigest() != DSI0_CDPHY_SHA256:
                            raise ValueError("factory mipi-cdphy.ko differs from the audited D1 module")
                    if args.dsi0_pll_trace:
                        write_payload(root / "grizzly-inventory/dsi0-pll-trace", b"", 0o644)
                    if args.dsi0_genpd_trace:
                        write_payload(root / "grizzly-inventory/dsi0-genpd-trace", b"", 0o644)
                if args.ufs_refclk_only:
                    write_payload(root / "grizzly-inventory/ufs-refclk-only", b"", 0o644)
                    write_payload(root / "grizzly-inventory/ufs-refclk.sh",
                                  (HERE / "stock-ufs-refclk.sh").read_bytes(), 0o644)
                if power_trace:
                    write_payload(root / "grizzly-inventory/ufs-power-trace", b"", 0o644)
                    write_payload(root / "grizzly-inventory/ufs-power-trace.sh",
                                  (HERE / "stock-ufs-power-trace.sh").read_bytes(), 0o644)
                if args.ufs_pre_on_trace:
                    write_payload(root / "grizzly-inventory/ufs-pre-on-trace", b"", 0o644)
                if sampler is not None:
                    write_payload(root / "grizzly-inventory/ufs-psm1-trace",
                                  f"{STOCK_UFS_SHA256}  /lib/modules/ufs.ko\n".encode(), 0o400)
                    write_payload(root / "grizzly-inventory/grizzly_stock_psm1.ko", sampler, 0o400)
                if args.ufs_psm1_prep_trace:
                    write_payload(root / "grizzly-inventory/ufs-psm1-prep-trace", b"", 0o400)
                if args.ufs_cpm_trace:
                    write_payload(root / "grizzly-inventory/ufs-cpm-trace", b"", 0o644)
                    for suffix in ("sh", "awk"):
                        name = f"stock-ufs-cpm-trace.{suffix}"
                        write_payload(root / "grizzly-inventory" / name, (HERE / name).read_bytes(), 0o644)
                if args.usb2_test:
                    add_usb2_test(root, vendor_kernel_cpio, manifest, count, preloads, reader)
                    if args.usb2_ep0_trace:
                        write_payload(root / "grizzly-inventory/usb2-ep0", b"", 0o644)
                        write_payload(root / "grizzly-inventory/usb2-ep0.sh",
                                      (HERE / "stock-usb2-ep0.sh").read_bytes(), 0o644)
        if not args.handoff_only:
            capture(sys.executable, args.unpack, "--boot_img", stock["init_boot"],
                    "--out", temp / "factory-init_boot")
            factory_init_ramdisk = temp / "factory-init_boot/ramdisk"
            if args.dsi0_trace:
                # Drop the known NV export overlay and retain the stock early-loader files.
                factory_init_ramdisk.write_bytes(
                    factory_init_ramdisk.read_bytes()[:NV_RESCUE_FACTORY_RAMDISK_SIZE])
        busybox = capture("bsdtar", "-xOf", args.rescue_cpio, "bin/busybox")
        if busybox[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", busybox, 18)[0] != 183:
            raise ValueError("expected the ARM64 BusyBox from Grizzly RAM rescue")
        write_payload(root / "grizzly-inventory/busybox", busybox, 0o755)
        libc_name = "libc.musl-aarch64.so.1"
        loader_name = "ld-musl-aarch64.so.1"
        loader = capture("bsdtar", "-xOf", args.rescue_cpio, f"lib/{loader_name}")
        if loader[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", loader, 18)[0] != 183:
            raise ValueError("expected the ARM64 loader from Grizzly RAM rescue")
        write_payload(root / f"lib/{loader_name}", loader, 0o755)
        (root / f"lib/{libc_name}").symlink_to(loader_name)
        (root / "lib").chmod(0o755)

        new_paths = ("grizzly-inventory", "stock-inventory.modules",
                     f"lib/{libc_name}", f"lib/{loader_name}")
        cpio_sources = [vendor_kernel_cpio]
        vendor_fragments = sorted((temp / "vendor_boot").glob("vendor_ramdisk[0-9][0-9]"))
        if len(vendor_fragments) != 2:
            raise ValueError("expected both D1 vendor ramdisk fragments")
        for fragment in vendor_fragments:
            cpio = temp / (fragment.name + ".cpio")
            cpio.write_bytes(capture("lz4", "-dc", fragment))
            cpio_sources.append(cpio)
        if args.usb2_test:
            firmware = capture("bsdtar", "-xOf", temp / "vendor_ramdisk00.cpio", USB2_FIRMWARE)
            if len(firmware) != 40960 or hashlib.sha256(firmware).hexdigest() != USB2_FIRMWARE_SHA256:
                raise ValueError("factory ramdisk USB2 PHY firmware differs from the audited D1 vendor image")
        if factory_init_ramdisk is not None:
            factory_init_cpio = temp / "factory-init.cpio"
            factory_init_cpio.write_bytes(capture("lz4", "-dc", factory_init_ramdisk))
            factory_paths = set(capture("bsdtar", "-tf", factory_init_cpio).decode().splitlines())
            required = {"init", "system/bin/modprobe", "dev/console", "dev/kmsg",
                        "dev/null", "dev/urandom"}
            if required - factory_paths:
                raise ValueError("factory generic ramdisk is missing early startup files")
            cpio_sources.append(factory_init_cpio)
            if args.preinit_helper_only:
                modprobe = capture("bsdtar", "-xOf", factory_init_cpio, "system/bin/modprobe")
                if hashlib.sha256(modprobe).hexdigest() != MODPROBE_SHA256:
                    raise ValueError("factory modprobe differs from the audited help path")
                write_payload(root / "grizzly-inventory/factory/modprobe", modprobe, 0o755)
                write_payload(root / "system/bin/modprobe",
                              (HERE / "stock-modprobe-probe").read_bytes(), 0o755)
                archive_members.append("system/bin/modprobe")
        for cpio in cpio_sources:
            members = capture("bsdtar", "-tf", cpio).decode().splitlines()
            if any(path == added or path.startswith(added + "/")
                   for path in members for added in new_paths):
                raise ValueError(f"new inventory path overlaps factory content in {cpio.name}")

        cpio = args.output / "inventory.cpio"
        capture("bsdtar", "--format", "newc", "--uid", "0", "--gid", "0",
                "-cf", cpio, "-C", root, *archive_members)
        ramdisk = args.output / "inventory.cpio.lz4"
        capture("lz4", "-l", "-12", cpio, ramdisk)
        if factory_init_ramdisk is not None:
            combined = temp / "stock-and-inventory.lz4"
            combined.write_bytes(factory_init_ramdisk.read_bytes() + ramdisk.read_bytes())
            if capture("lz4", "-dc", combined) != factory_init_cpio.read_bytes() + cpio.read_bytes():
                raise ValueError("factory and inventory archives do not decode in order")
            ramdisk = combined
        image = images / "init_boot.img"
        capture(sys.executable, args.mkbootimg, "--header_version", "4",
                "--os_version", "17.0.0", "--os_patch_level", "2026-11",
                "--ramdisk", ramdisk, "--output", image)

        private = temp / "test.pem"
        public = args.output / "AVB-PUBLIC-KEY.pem"
        capture("openssl", "genpkey", "-quiet", "-algorithm", "RSA",
                "-pkeyopt", "rsa_keygen_bits:4096", "-out", private)
        capture("openssl", "pkey", "-in", private, "-pubout", "-out", public)
        avb = (sys.executable, "-I", args.avbtool)
        capture(*avb, "add_hash_footer", "--image", image, "--partition_name", "init_boot",
                "--partition_size", str(CAPACITY), "--algorithm", "SHA256_RSA4096",
                "--rollback_index", "1793836800", "--key", private, "--salt", digest(image),
                "--prop", "com.android.build.init_boot.os_version:17",
                "--prop", "com.android.build.init_boot.security_patch:2026-11-05")
        capture(*avb, "verify_image", "--image", image, "--key", public)

        unpacked = temp / "init_boot"
        capture(sys.executable, args.unpack, "--boot_img", image, "--out", unpacked)
        if (unpacked / "ramdisk").read_bytes() != ramdisk.read_bytes():
            raise ValueError("packed inventory ramdisk differs")
        stock_kernel = temp / "boot/kernel"
        kernel = temp / "Image"
        kernel.write_bytes(capture("lz4", "-dc", stock_kernel))
        vendor_ramdisks = temp / "combined-vendor-boot.lz4"
        vendor_ramdisks.write_bytes(b"".join(fragment.read_bytes()
                                             for fragment in vendor_fragments))
        bounds = capture(sys.executable, HERE / "check-handoff.py", kernel, args.board_dtb,
                         vendor_kernel_ramdisk, vendor_ramdisks, ramdisk,
                         "--packed-kernel", stock_kernel,
                         "--dtb-container", temp / "vendor_kernel_boot/dtb")
        print(bounds.decode(), end="")

    for name, path in stock.items():
        if name != "init_boot":
            if name == "dtbo" and isolation_dtbo:
                path = isolation_dtbo
            shutil.copyfile(path, images / f"{name}.img")
    (images / "DEVICE").write_text("grizzly\n")
    checksums = images / "SHA256SUMS"
    checksums.write_text("".join(f"{digest(images / (name + '.img'))}  {name}.img\n"
                                 for name in FACTORY))
    fit = capture(sys.executable, HERE / "check-slot-b.py", images, checksums,
                  "--fastboot-vars", args.fastboot_vars, "--require-healthy-a")
    print(fit.decode(), end="")
    if args.handoff_only:
        print("Handoff-only prototype contains 0 stock module requests.")
    elif args.preinit_helper_only:
        print("Pre-init helper prototype replaces modprobe with the audited help-only wrapper.")
    elif args.preloads_only:
        print(f"Preloads-only prototype expects {len(preloads)} factory preloads "
              "and contains no PID 1 module manifest.")
    else:
        print(f"Inventory manifest has {count} modules: {len(preloads)} expected preloads, "
              f"{count - len(preloads)} subsequent module requests.")
        if args.nv_guard_only:
            print("NV guard prototype verifies read-only state without exporting block data.")
        if args.dsi0_trace:
            print("Stock DSI0 trace arms before the separate guarded display module load.")
        if args.ufs_refclk_only:
            print("UFS reference-clock prototype reads the stock attribute after the NV guard.")
        if args.ufs_power_trace:
            print("UFS power trace prototype records stock UFS MMIO reads and power votes.")
        if args.ufs_pre_on_trace:
            print("UFS PRE_ON trace prototype adds a register-only probe to the stock power trace.")
        if sampler is not None:
            print("UFS PSM1 trace prototype pairs the stock D1 sampler with stock AP power votes.")
        if args.ufs_psm1_prep_trace:
            print("UFS prep trace adds pre-load genpd counters and guarded pre/post-prep PSM1 samples.")
        if args.ufs_cpm_trace:
            print("UFS CPM trace prototype pairs stock MBFS votes and decoded firmware PSM1 events.")
        if reader is not None:
            host = args.output / "host-tools"
            write_payload(host / "tools/stock-nv-transport.py",
                          (HERE / "stock-nv-transport.py").read_bytes(), 0o700)
            write_payload(host / "tools/check-stock-usb2.py",
                          (HERE / "check-stock-usb2.py").read_bytes(), 0o600)
            print("USB2 NV reader serves guarded, read-only partitions over the tested ACM gadget.")
            print(f"Grizzly-only host backup tools: {host}")
        elif args.usb2_test:
            print(f"USB2 prototype loads {len(USB2_MODULES)} modules after the NV guard "
                  "and sends 65536 synthetic bytes on request.")
        if args.usb2_ep0_trace:
            print("EP0 trace prototype uses the tested DWC3 isolation DTBO.")
    print(f"Replacement init_boot SHA-256: {digest(image)}")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("factory", "board-dtb", "rescue-cpio", "mkbootimg", "unpack",
                   "avbtool", "fastboot-vars"):
        parser.add_argument(f"--{option}", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--handoff-only", action="store_true",
                      help="verify stock PID 1 and restart without any loaded modules")
    mode.add_argument("--preloads-only", action="store_true",
                      help="verify factory protected preloads without loading UFS suppliers")
    mode.add_argument("--preinit-helper-only", action="store_true",
                      help="check the early factory modprobe runtime with its help command")
    mode.add_argument("--nv-guard-only", action="store_true",
                      help="verify read-only NV devices before enabling a backup transport")
    mode.add_argument("--dsi0-trace", action="store_true",
                      help="stage the stock DSI0 trace from the audited NV rescue images")
    mode.add_argument("--dsi0-pll-trace", action="store_true",
                      help="also capture stock DSI0 PHY PLL lock if the driver polls it")
    mode.add_argument("--dsi0-genpd-trace", action="store_true",
                      help="correlate the early DSI0 OFF reply with genpd sync and its worker")
    mode.add_argument("--ufs-refclk-only", action="store_true",
                      help="read the stock UFS device's reference-clock attribute after the NV guard")
    mode.add_argument("--ufs-power-trace", action="store_true",
                      help="trace the stock UFS module probe and verify the NV guard")
    mode.add_argument("--ufs-pre-on-trace", action="store_true",
                      help="qualify the stock UFS PRE_ON sampling point without reading PSM1")
    mode.add_argument("--ufs-psm1-trace", type=Path, metavar="SAMPLER_KO",
                      help="capture a guarded stock PRE_ON PSM1 sample with the core vote")
    mode.add_argument("--ufs-psm1-prep-trace", type=Path, metavar="SAMPLER_KO",
                      help="trace prep PSM1 and snapshot stock genpd state before UFS loads")
    mode.add_argument("--ufs-cpm-trace", action="store_true",
                      help="correlate stock UFS MBFS votes with CPM firmware transition records")
    mode.add_argument("--usb2-test", action="store_true",
                      help="verify the NV guard and test USB2 with synthetic data")
    usb2_features = parser.add_mutually_exclusive_group()
    usb2_features.add_argument("--usb2-ep0-trace", type=Path, metavar="ISOLATION_DTBO",
                               help="arm EP0 tracing in --usb2-test with the verified isolation DTBO")
    usb2_features.add_argument("--usb2-nv-reader", type=Path, nargs=2,
                               metavar=("READER_ELF", "ISOLATION_DTBO"),
                               help="use the static NV reader in --usb2-test with the verified isolation DTBO")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.dsi0_trace |= args.dsi0_pll_trace or args.dsi0_genpd_trace
    if (args.usb2_ep0_trace or args.usb2_nv_reader) and not args.usb2_test:
        parser.error("USB2 isolation options require --usb2-test")
    try:
        pack(args)
    except subprocess.CalledProcessError as error:
        parser.exit(1, f"stock inventory packaging failed: {error.output.decode(errors='replace')}\n")
    except (OSError, ValueError) as error:
        parser.exit(1, f"stock inventory packaging failed: {error}\n")


if __name__ == "__main__":
    main()
