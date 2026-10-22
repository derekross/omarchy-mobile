#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Offline checks of the F3 boot payload, root, sparse transport and access path."""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("reference", Path(__file__).with_name("prepare-reference.py"))
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def check(condition, description):
    if not condition:
        raise SystemExit("FAILED: " + description)
    print("ok - " + description, flush=True)


def read_image_file(image, name):
    return subprocess.check_output(["debugfs", "-R", "cat " + name, str(image)], stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boot-only", action="store_true")
    parser.add_argument("--images", type=Path, default=ROOT / "out/alioth/images")
    args = parser.parse_args()
    images = args.images.resolve()
    manifest = json.loads((images / "BOOT-MANIFEST.json").read_text())
    release = manifest["kernel_release"]
    public = (ROOT / "keys/alioth_ed25519.pub").read_bytes()
    for filename, expected, rescue in (("boot.img", manifest["boot_sha256"], False),
                                       ("boot-rescue.img", manifest["rescue_boot_sha256"], True)):
        data = (images / filename).read_bytes()
        check(hashlib.sha256(data).hexdigest() == expected, filename + " checksum")
        fields = struct.unpack_from("<10I", data, 8)
        kernel, ramdisk, page, version = fields[0], fields[2], fields[7], fields[8]
        check(data[:8] == b"ANDROID!" and page == 4096 and version == 0, filename + " Android v0 / 4096-byte pages")
        check(data[page:page + kernel] == (images.parent / "reference/Image.gz-dtb").read_bytes(), filename + " exact pinned alioth kernel/DTB")
        offset = ((page + kernel + page - 1) // page) * page
        payload = data[offset:offset + ramdisk]
        check(hashlib.sha256(payload).hexdigest() == manifest["initramfs_sha256"], filename + " initramfs checksum")
        files = {n: (mode, content) for n, mode, content in reference.cpio_files(gzip.decompress(payload))}
        init = files["init"][1].decode()
        check(files["etc/omamobile-compatible"][1] == b"xiaomi,alioth\n", filename + " board guard")
        check(files["etc/omamobile-ufs-rw"][1] == b"userdata\n", filename + " userdata-only UFS write allowlist")
        check("etc/omamobile-simplefb-trig" not in files and "etc/omamobile-bringup-probe" not in files,
              filename + " no Pixel register probes")
        check(files["root/.ssh/authorized_keys"][1] == public and files["root/.ssh/authorized_keys"][0] & 0o777 == 0o600,
              filename + " dedicated SSH public key and permissions")
        hostkey = "etc/dropbear/dropbear_ed25519_host_key"
        check(files[hostkey][1] == (images.parent / "dropbear_ed25519_host_key").read_bytes()
              and files[hostkey][0] & 0o777 == 0o600,
              filename + " stable private rescue host identity")
        check("dropbear -R -E -s -p 172.16.42.1:22" in init and "02:10:42:00:00:02" in init,
              filename + " key-only SSH and predictable USB Ethernet")
        check('modprobe qcom-wdt' in init and 'watchdog -t 5 -T 30' in init, filename + " early matching watchdog")
        module_files = [(n, content) for n, (mode, content) in files.items()
                        if n.startswith("usr/lib/modules/") and n.endswith(".ko")]
        check(bool(module_files) and all(n.startswith(f"usr/lib/modules/{release}/")
                                        and b"vermagic=" + release.encode() + b" " in content
                                        for n, content in module_files), filename + " initramfs modules match release")
        if release != "6.15.1-sm8250":
            check('kernel-trial.pending' in init and 'unacknowledged kernel trial' in init,
                  filename + " trial hang marker and rescue fallback")
        check('blkid -s LABEL -o value' in init and '= omamobile-root' in init, filename + " root-label gate before mount")
        binaries = [(name, content) for name, (mode, content) in files.items()
                    if content.startswith(b"\x7fELF") and name.startswith(("bin/", "sbin/", "usr/bin/", "usr/sbin/"))]
        check(len(binaries) >= 5 and all(struct.unpack_from("<H", content, 18)[0] == 183 for _, content in binaries),
              filename + " executable payload is AArch64")
        cmdline = data[64:576].split(b"\0", 1)[0].decode()
        check(("omamobile.initramfs" in cmdline) == rescue, filename + " intended root/rescue boot mode")
    modules = images.parent / "reference" / f"modules-{release}.tar.zst"
    check(reference.digest(modules) == manifest["reference"]["modules_sha256"], "matching kernel module archive checksum")
    result = {"device": "alioth", "boot_payload_checked": True, "hardware_boot_tested": False,
              "boot_sha256": manifest["boot_sha256"], "rescue_boot_sha256": manifest["rescue_boot_sha256"]}
    if not args.boot_only:
        root_manifest = json.loads((images / "ROOT-MANIFEST.json").read_text())
        image = images / "rootfs.img"
        check(reference.digest(image) == root_manifest["rootfs_sha256"], "personalized root checksum")
        check(reference.digest(images / "rootfs-sparse.img") == root_manifest["rootfs_sparse_sha256"], "sparse root checksum")
        roundtrip = images / ".sparse-roundtrip.img"
        try:
            subprocess.run(["simg2img", str(images / "rootfs-sparse.img"), str(roundtrip)], check=True)
            check(reference.digest(roundtrip) == root_manifest["rootfs_sha256"], "Android sparse round-trip is byte-identical to ext4")
        finally:
            roundtrip.unlink(missing_ok=True)
        fsck = subprocess.run(["e2fsck", "-fn", str(image)], capture_output=True, text=True)
        (images / "rootfs-fsck-final.txt").write_text(fsck.stdout + fsck.stderr)
        check(fsck.returncode == 0, "root filesystem consistency")
        info = subprocess.check_output(["dumpe2fs", "-h", str(image)], stderr=subprocess.DEVNULL, text=True)
        check("omamobile-root" in info, "root filesystem label")
        check(read_image_file(image, "/root/.ssh/authorized_keys") == public, "installed-root SSH key")
        conf = read_image_file(image, "/etc/ssh/sshd_config.d/10-omamobile.conf").decode()
        check("PasswordAuthentication no" in conf and "PermitRootLogin prohibit-password" in conf, "installed-root key-only SSH policy")
        firstboot = read_image_file(image, "/etc/omamobile/firstboot.conf").decode()
        check("USERNAME=" + root_manifest["username"] + "\n" in firstboot and "SSH_KEY=" + public.decode().strip() in firstboot, "local first-boot provisioning")
        mask = subprocess.check_output(["debugfs", "-R", "stat /etc/systemd/system/systemd-firstboot.service", str(image)],
                                       stderr=subprocess.DEVNULL, text=True)
        check('Type: symlink' in mask and 'Fast link dest: "/dev/null"' in mask, "interactive setup masked before SSH")
        epoch = subprocess.check_output(["debugfs", "-R", "stat /usr/lib/clock-epoch", str(image)],
                                        stderr=subprocess.DEVNULL, text=True)
        check('Type: regular' in epoch, "build-time system clock lower bound")
        check(b'omamobile-firewall.service' in read_image_file(image, "/usr/bin/omamobile-device-firewall"),
              "device firewall provisioning hook")
        check(b'iifname "usb0" ip daddr 172.16.42.1 tcp dport { 22, 5900 } accept' in
              read_image_file(image, "/usr/share/omamobile/alioth/firewall.nft"), "native firewall USB control access")
        network = read_image_file(image, "/usr/lib/systemd/network/20-usb-gadget.network").decode()
        check("Address=172.16.42.1/24" in network and "DHCPServer=yes" in network, "USB IP and persistent host DHCP")
        check(read_image_file(image, "/etc/omamobile/monitor-scale").strip() == b"2.25", "1080x2400 phone display scale")
        installed = read_image_file(image, "/usr/share/omamobile/rootfs/MANIFEST").decode()
        check(any(line.startswith("omarchy ") for line in installed.splitlines()) and "omamobile-device-alioth " in installed, "Omarchy and F3 device package installed")
        check("omamobile-device-cheetah " not in installed and "vulkan-freedreno " in installed, "Qualcomm graphics profile")
        result.update(root_payload_checked=True, rootfs_sha256=root_manifest["rootfs_sha256"],
                      rootfs_sparse_sha256=root_manifest["rootfs_sparse_sha256"])
    report = images / ("BOOT-VALIDATION.json" if args.boot_only else "VALIDATION.json")
    payload = json.dumps(result, indent=2) + "\n"
    # Rechecking an already frozen, signed bundle must not rewrite its receipt.
    if not report.exists() or report.read_text() != payload:
        report.write_text(payload)


if __name__ == "__main__":
    main()
