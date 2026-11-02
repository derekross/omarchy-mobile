#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Make the stage 2 DTB for the dodge kexec chain-loader.

Usage: stage2-dtb.py <built dodge.dtb> <live.dtb> <out.dtb> [ramoops] [splash] [fb] [peripheral] [hs] [rscpd]

ABL fills the `memory` node at boot and kexec does not, so its reg is
taken from the phone's live FDT (/sys/firmware/fdt from a rooted
capture, kept outside git). The upstream DTS carries another phone's
map. `memory@a0000000` keeps size 0.

ramoops  add a ramoops node at OxygenOS's ramoops address and layout
splash   reserve ABL's splash buffer with an identity map on mdss
fb       add a simple-framebuffer over ABL's splash buffer, reusing
         splash's reservation if set. Works on our DTB with splash
ramoops was booted on 2026-10-15, also on stock's DTB, so it has not
really been tried either.
peripheral  dr_mode = "peripheral" and no usb-role-switch on the dwc3
            node. The role otherwise comes from pmic_glink, which this
            initramfs does not load. Not needed: otg works on our DTB.
hs          peripheral, and drop the usb3-phy so dwc3 does not wait
            on the combo PHY. Also drops the dwc3 iommus entry, which
            blocks its DMA under ARM_SMMU_DISABLE_BYPASS_BY_DEFAULT.
rscpd       drop power-domains from the apps RSC, so RPMh does not wait
            on PSCI's cpuidle genpd, which does not bind after kexec.
"""
import re
import subprocess
import sys


def dts(path):
    return subprocess.run(["dtc", "-q", "-I", "dtb", "-O", "dts", path],
                          capture_output=True, text=True, check=True).stdout


def node_span(s, header):
    i = s.index(header)
    depth = 0
    for k in range(i, len(s)):
        if s[k] == "{":
            depth += 1
        elif s[k] == "}":
            depth -= 1
            if depth == 0:
                return i, k
    raise ValueError(header)


def memory_span(s):
    """ABL / live FDT uses `memory {`; the dodge DTS uses `memory@…`."""
    for header in ("\n\tmemory {",):
        try:
            return node_span(s, header)
        except ValueError:
            pass
    m = re.search(r"\n\tmemory@[0-9a-fA-F]+ \{", s)
    if not m:
        raise ValueError("no memory node")
    return node_span(s, m.group(0))


def insert_in(s, header, text):
    _, j = node_span(s, header)
    line = s.rindex("\n", 0, j)
    return s[:line] + text.rstrip("\n") + s[line:]


built, live, out, *opts = sys.argv[1:]
ours, theirs = dts(built), dts(live)

i, j = memory_span(theirs)
live_reg = re.search(r"reg = <[^>]*>;", theirs[i:j]).group(0)
i, j = memory_span(ours)
block = ours[i:j]
ours = ours[:i] + block.replace(re.search(r"reg = <[^>]*>;", block).group(0), live_reg) + ours[j:]

# One top-level memory node only. A second hardcoded map beside
# memory@a0000000 (filled above) hung a 2026-10-30 tip RAM boot.
extras = list(re.finditer(r"\n\tmemory@[0-9a-fA-F]+ \{", ours))
# memory_span already picked one; drop any other memory@… at root depth.
if len(extras) > 1:
    keep = memory_span(ours)[0]
    for m in reversed(extras):
        if m.start() == keep:
            continue
        a, b = node_span(ours, m.group(0))
        # include the trailing newline after the closing brace line
        end = b + 1
        if end < len(ours) and ours[end] == "\n":
            end += 1
        ours = ours[:a] + ours[end:]

if "ramoops" in opts:
    ours = insert_in(ours, "reserved-memory {", """
		ramoops@880000000 {
			compatible = "ramoops";
			reg = <0x08 0x80000000 0x00 0x240000>;
			record-size = <0x00>;
			console-size = <0x40000>;
			ftrace-size = <0x00>;
			pmsg-size = <0x200000>;
			ecc-size = <0x00>;
			no-map;
		};
""")

def force_peripheral(s):
    if s.count('dr_mode = "otg";') != 1 or s.count("usb-role-switch;") != 1:
        raise SystemExit("expected exactly one otg dr_mode and one usb-role-switch")
    s = s.replace('dr_mode = "otg";', 'dr_mode = "peripheral";', 1)
    return re.sub(r"\n[ \t]*usb-role-switch;\n", "\n", s, count=1)


if "peripheral" in opts or "hs" in opts:
    ours = force_peripheral(ours)

if "hs" in opts:
    m = re.search(
        r'phys = <(0x[0-9a-fA-F]+)[^>]*>;\n(\s*)phy-names = "usb2-phy", "usb3-phy";',
        ours)
    if not m:
        raise SystemExit("expected usb2-phy and usb3-phy on one phys entry")
    ours = (ours[:m.start()]
            + f'phys = <{m.group(1)}>;\n{m.group(2)}phy-names = "usb2-phy";'
            + ours[m.end():])
    # The dwc3 node is the only one with this SID. Dropping it avoids
    # waiting on apps_smmu after kexec.
    if 'iommus = <0x23 0x40 0x00>;' not in ours:
        raise SystemExit("expected the dwc3 iommus entry")
    ours = ours.replace('\n\t\t\t\tiommus = <0x23 0x40 0x00>;\n', '\n', 1)

if "splash" in opts:
    # SID 0x800 is mdss. ABL leaves it scanning 0xfc800000. The identity
    # map is what arm-smmu installs from iommu-addresses.
    if "qcom,sm8750-mdss" not in ours:
        raise SystemExit("no mdss node")
    ours = ours.replace(
        "display-subsystem@ae00000 {",
        "mdss: display-subsystem@ae00000 {",
        1)
    ours = ours.replace(
        'compatible = "qcom,sm8750-mdss";',
        'compatible = "qcom,sm8750-mdss";\n\t\t\tmemory-region = <&cont_splash_mem>;',
        1)
    ours = insert_in(ours, "reserved-memory {", """
		cont_splash_mem: splash@fc800000 {
			reg = <0x00 0xfc800000 0x00 0x2b00000>;
			no-map;
			iommu-addresses = <&mdss 0x00 0xfc800000 0x00 0x2b00000>;
		};
""")

# The apps RSC's only supplier is PSCI's power-domain-system genpd. After
# kexec the PSCI cpuidle domain does not bind, so fw_devlink holds the RSC
# (and RPMh clocks, GCC, regulators, everything after) unprobed. Without
# power-domains rpmh-rsc uses its CPU PM notifier instead
if "rscpd" in opts:
    i, j = node_span(ours, "\n\t\trsc@16500000 {")
    # Three tabs: the RSC's own property, not a child's.
    m = re.search(r"\n\t\t\tpower-domains = <0x[0-9a-f]+>;", ours[i:j])
    if not m:
        raise SystemExit("expected power-domains on the apps RSC")
    ours = ours[:i + m.start()] + ours[i + m.end():]

if "fb" in opts:
    # splash already reserves this region and asks for the identity map.
    # A second node at the same address is a broken DTB.
    if "splash" not in opts:
        ours = insert_in(ours, "reserved-memory {", """
		splash@fc800000 {
			reg = <0x00 0xfc800000 0x00 0x2b00000>;
			no-map;
		};
""")
    ours = insert_in(ours, "\n\tchosen {", """
		framebuffer@fc800000 {
			compatible = "simple-framebuffer";
			reg = <0x00 0xfc800000 0x00 0x1167000>;
			width = <1440>;
			height = <3168>;
			stride = <5760>;
			format = "a8r8g8b8";
		};
""")

subprocess.run(["dtc", "-q", "-I", "dts", "-O", "dtb", "-o", out, "-"],
               input=ours, text=True, check=True)
