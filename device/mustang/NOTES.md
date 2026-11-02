<!-- SPDX-License-Identifier: MIT -->
# Pixel 10 Pro XL (mustang) bring-up notes

Findings for the Pixel 10 Pro XL port (SoC laguna, Tensor G5), newest first. Tracking issue: [#18](https://github.com/derekross/omarchy-mobile/issues/18). Nothing here has booted or flashed anything of ours: stage 0 is read-only.

The parts below are a fact dump. A fact that a tool printed is marked [V], with its source. Every inference, hypothesis and open question is kept out of them and collected in "Interpretation and open questions" near the end, as items I1 to I21; a fact that has one points to it. Anything about the Tensor G5 that is not marked [V] is unverified.

**This phone is not running stock.** It runs GrapheneOS (build `CP3A.261005.005`) with a locked bootloader, and it is a dedicated test phone. So there are no stock captures of a live device. The notes separate three kinds of source, and a GrapheneOS reading is never presented as stock:

- `F/`: Google's factory image for the same build ID, `mustang-cp3a.261005.005-factory-099acc44.zip` (SHA-256 `099acc44e2f87fe2735d92952081d64550ff08b4a6390bb6b001c8451695657e`, checked against Google's page), read on the laptop with `unzip`, `unpack_bootimg`, `avbtool`, `dtc` and `mkdtboimg`. Nothing was run on the phone for these.
- `R/`: read-only `adb` and `fastboot` queries of the phone, by exact name (no `getprop` dump, no `fastboot getvar all`, no shell with write access): facts only, no serial, IMEI or MACs. The phone runs GrapheneOS's own build, so a build fact (the kernel string, say) can differ from Google's. Hardware facts (SoC, board revision, which `dtbo` entry) don't.
- `K/`: `arch/arm64/boot/dts/exynos/google/gs201.dtsi` from the `omamobile` branch of [linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile), as the reference for the comparison in part 4.

## How this was produced

**AI assistance.** This file was written with AI assistance (Claude, through Claude Code). The contributor chose what to read from the phone, approved each query, and did the on-device steps (restarting the phone into and out of the bootloader). The analysis commands below were run by the AI agent, and the interpretation is the agent's. The contributor is not a kernel developer and has not re-run them independently. Anyone can re-check a [V] line with the commands below.

**Tools** (Arch Linux): android-tools 37.0.0 (`adb`, `fastboot`, `unpack_bootimg`, `mkdtboimg`, `avbtool` 1.4.0), dtc 1.8.1 (`dtc`, `fdtget`, `fdtoverlay`), unzip 6.00, curl 8.23, Python 3.14 (only to split the concatenated DTBs), and coreutils (`sort`, `comm`, `grep`). Nothing from Google's package is in this repository: only facts are quoted.

**Factory image** (`F/`, parts 1 and 4), run on the laptop:

```
sha256sum -c SHA256.expected                         # the zip against Google's published value
unzip -l image-mustang-cp3a.261005.005.zip           # the image list (inner zip)
unpack_bootimg --boot_img boot.img --out OUT         # header version, ramdisks, dtb section
avbtool info_image --image boot.img                  # rollback index, security patch, chained partitions
dtc -I dtb -O dts -o 00.dts 00.dtb                   # decompile a base DTB
mkdtboimg dump dtbo.img -b entry                     # the board dtbo table, one file per entry
```

The `dtb` section of `vendor_kernel_boot` is several DTBs back to back. Each starts with the magic `0xd00dfeed` and carries its total size as a big-endian 32-bit number at offset 4, so a short loop splits them (two DTBs here). Compatible strings were collected with `grep -o 'compatible = "[^;]*;'` on the decompiled files and compared with `comm` on the sorted lists. `gs201.dtsi` came from `raw.githubusercontent.com/derekross/linux-omarchy-mobile/omamobile/arch/arm64/boot/dts/exynos/google/gs201.dtsi` (`K/`).

**Phone** (`R/`, parts 2, 3 and 5), read-only, by exact name:

```
adb shell getprop <name>        # only the properties named in part 2; never a bare getprop
adb shell cat /proc/version     # also: grep 'CPU part' /proc/cpuinfo, grep MemTotal /proc/meminfo
adb shell ls /dev/block/by-name
adb shell ls /proc/device-tree  # names only; every property is refused. Nodes via a [ -d ] loop
fastboot getvar <name>          # only the variables named in part 3; never getvar all
```

**The live-versus-factory comparison** (part 5): `fdtoverlay -i 01.dtb -o merged_01.dtb entry.30` merges the B0 base tree with the MP board overlay, `fdtget -l merged_01.dtb /` lists its top-level nodes, and `comm` against the phone's node names (sorted) shows what is only live (`-13`) and what is only in the factory tree (`-23`). Repeat with `00.dtb` for A0.

## What the maintainer asked for in #18

| Request | Status | Where |
| --- | --- | --- |
| Everything in CONTRIBUTING §5.1 | Partly: properties, CPU, memory and partition names read; the live device tree's node names read without root, but its values, `dmesg`, `/proc/iomem` and the vendor module list need root | parts 2 and 5 |
| `fastboot getvar all` from both slots' bootloaders | Partly: named variables read one at a time (never `all`, which prints the serial). The bootloader reports only the running slot's version | part 3 |
| `cat /proc/version` | Done, but it is GrapheneOS's kernel; Google's string comes from the factory image | parts 1 and 2 |
| The factory image for the exact build | Done: the package named for `CP3A.261005.005` exists and matches the phone's build ID | part 1 |
| Device trees from `boot`, `vendor_boot`/`vendor_kernel_boot`, `dtbo` | Done from the factory image, no root | part 1 |
| Do `init_boot` and `vendor_kernel_boot` exist; boot image header versions | Done: both exist, header version 4 | part 1 |
| `ro.boot.hardware.platform`, `ro.soc.model`, `dtb_idx`, `dtbo_idx` | Done; `dtb_idx` is unset on this build | part 2 |

## 2026-10-30: stage 0, part 5: the live device tree's node names, without root

Over `adb`, as the shell user, on the GrapheneOS phone [V] (R/). `/proc/device-tree` can be listed, but SELinux refuses to read any property: `compatible`, `reg`, `device_type` and the root cell sizes all fail with "Permission denied", and so does listing `chosen`. So only node names are readable, and those carry the unit addresses. Nothing identifying was read; the name lists are kept outside the repository.

- **718 top-level nodes** are live [V]. Merging the factory base DTB (part 1) with the MP board overlay (`dtbo` entry 30) offline with `fdtoverlay` gives 710 for both A0 and B0.
- **Against B0, nothing is missing from the live tree and 8 nodes are extra; against A0, one node is missing and 9 are extra** [V]. The distinguishing pair is `ehld-coreinstr`, which only B0's tree has and which is live, and `pmu-ehld`, which only A0's tree has and which is not. What this says about the phone's revision: I15.
- **What the bootloader adds** [V as names]: an `avf` node, and seven `memory@…` nodes beyond the one in the base tree. That makes eight RAM banks, at `0x80000000`, `0x880000000`, `0x900000000`, `0x980000000`, `0xa00000000`, `0xa80000000`, `0xb00000000` and `0xb80000000`. Their sizes are not readable (I2, I16).
- **`reserved-memory`** [V as names]: 52 live children against 49 in the merged B0 tree. The bootloader adds `bl31_dram`, `sec_dram` and `pkvm_guest_firmware`, and two nodes that carry a fixed address in the factory tree (`gsa-gme@a2400000`, `gsa_reserved_log@a61b0000`) appear live without one (I17).
- **No child named like a framebuffer** (`splash`, `fb`, `display`) exists in `reserved-memory` [V as names]. Where the carve-out is: I18.

## 2026-10-30: stage 0, part 4: laguna's base device tree against gs201.dtsi

Asked for on #18. Method: the two base DTBs from `vendor_kernel_boot` (part 1) decompiled with `dtc`, compared by structure and by compatible string with `gs201.dtsi` from the `omamobile` branch of linux-omarchy-mobile (`K/`, fetched 2026-10-30, 1,163 lines). It is not a line-by-line diff: `gs201.dtsi` is a compact mainline-style description, while laguna's A0 DTB decompiles to about 29,100 lines of Google's Android device tree. A0 and B0 share 218 of their 221 distinct compatible strings (the differences are per-revision `*_dvfs` and `*_ptde` strings and an EHLD debug string each) and have the same GIC [V].

- **Layout** [V]. Laguna's tree is flat: there is no `soc` bus node, and peripherals are direct children of the root. `gs201.dtsi` puts them under `soc@0` (`simple-bus`).
- **Almost no names carry over** [V]. Laguna has 221 distinct compatible strings and `gs201.dtsi` has 56. They share only 9, all generic: `arm,armv8-timer`, `arm,gic-v3`, `arm,idle-state`, `arm,psci-1.0`, `fixed-clock`, `operating-points-v2`, `simple-bus`, `snps,dwc3`, `syscon`. Of laguna's 143 `google,*` strings only one carries a gs101 name, `google,gs101-gsa-v1` (the security processor interface); 24 are `google,lga-*`.
- **Blocks that gs201 describes with Samsung-derived names are named differently here** [V]. Watchdog `google,wdt` (gs201: `google,gs201-wdt`, falling back to `google,gs101-wdt`); UFS `google,ufshc` (gs201: `google,gs201-ufs`, plus a separate `google,gs201-ufs-phy`); USB PHY `google,usb_phy-lga`; UART `goog,goog-dw-apb-uart` (I4). Pin control is split into per-domain nodes, `google,lga-<domain>-pinctrl` (`aoc`, `cpm`, `dpu`, `gdmc`, `hsion`, `hsios`, `hsios-stby`, `lsioe`, `lsion`, `lsios`), where gs201 has one `google,gs201-pinctrl`. No clock-controller node was found under the usual names, `clock` and `cmu` (I6).
- **Display, memory management and tracing** [V]. The display compatibles are `verisilicon,dc9x00`, `dc9x00-mipi-dsi2h`, `dpu_fe0`, `dpu_fe1`, `dpu_be`, `dpu_wb` and `dp-encoder`, not Samsung's DECON and DSIM. Memory management uses `arm,smmu-v3`; DMA uses `arm,pl330`; tracing uses `arm,coresight-*`; the interconnect is `arm,ci-700`.
- **GPU** [V]. The node is `gpu0@34800000` with compatibles `google,lga-gpu` and `img,gpu`, and register names starting `rgx`. The node does not name a GPU model (I3).
- **CPUs** [V]. Eight, all `"gem5,armv8", "arm,armv8"` with `enable-method = "psci"`, and `capacity-dmips-mhz` 258 (two cores), 891 (three), 892 (two), 1024 (one). That is the same 2 + 5 + 1 split as the `CPU part` counts read from the phone in part 2, from two independent sources. Idle uses PSCI power domains (`CPU_PD0`, cluster idle states), which `gs201.dtsi` does not have.
- **GIC** [V]. `arm,gic-v3` at `0x5880000` (distributor, `0x10000`) with the redistributors at `0x5900000` (`0x200000`) and `#interrupt-cells = <4>`. gs201: `0x10400000`, redistributors at `0x10440000` (`0x100000`), `#interrupt-cells = <3>`. What the fourth cell carries: I5. The maintainer's warning on #18 about the interrupt map is that no interrupt number or address carries over.

## 2026-10-30: stage 0, part 3: named `fastboot getvar` variables

Read-only, from the bootloader, one named variable per call (never `getvar all`), with the owner's go; facts only, no serial or other identifier. The phone showed "Fastboot Mode" and "Device State: Locked" [V] (R/, on a GrapheneOS phone).

- **State** [V]: `current-slot` is `b`, `unlocked` is `no`, `secure` is `yes`, `version-bootloader` is `deepspace-17.4-16119390`, the version the factory image requires. Only the current slot's bootloader version is reported, as on husky; the other slot's is unknown (I19).
- **Slot flags** [V]:

  | Slot | `slot-successful` | `slot-retry-count` | `slot-unbootable` |
  | --- | --- | --- | --- |
  | A | yes | 2 | **yes** |
  | B | yes | 2 | no |

  Slot A is flagged unbootable, so the phone has no bootable second slot as it stands. The project's fallback to a known-good slot A (CONTRIBUTING §3.1, §3.4) therefore does not exist on this phone. Why A is flagged: I19.
- **Partition sizes of slot B's boot images** [V]: `boot_b` 0x4000000 (64 MiB), `init_boot_b` 0x800000 (8 MiB), `vendor_boot_b` 0x4000000 (64 MiB), `vendor_kernel_boot_b` 0x4000000 (64 MiB), `dtbo_b` 0x1000000 (16 MiB). All are multiples of 4096, and they equal the sizes of the factory images in part 1. For the descriptor this gives `AVB_FOOTERS="boot:0x4000000 init_boot:0x800000"`, which is husky's line.
- **`userdata`** [V]: 0x371cb15000 bytes (236,704,583,680; 220.4 GiB). `userdata` has no slots.
- **More variables** [V] (a second bootloader visit, same day): `slot-count` is 2, `has-slot:boot` is `yes`, `hw-revision` is `MP1.0` (as the property in part 2). The four anti-rollback counters that husky's notes read (`ap-ar-ns`, `ap-ar-s`, `gsa-bl1-ar`, `gsa-fw-ar`) are not found on this bootloader: `getvar` fails with "variable not found", which changed nothing on the phone (I20).

## 2026-10-30: stage 0, part 2: read-only properties from the phone

Read over `adb` with USB debugging on, by exact name, on a GrapheneOS build [V] (R/).

- **Identity** [V]: `ro.product.device` is `mustang`, `ro.product.model` is `Pixel 10 Pro XL`, `ro.boot.hardware.platform` is `laguna`, `ro.soc.model` is `Tensor G5`, `ro.boot.hardware.revision` is `MP1.0`.
- **Build** [V]: Android 17, build `CP3A.261005.005`, fingerprint `google/mustang/mustang:17/CP3A.261005.005/2026102101:user/release-keys`. That is the build ID of Google's factory image in part 1. The fingerprint is GrapheneOS's build, so it does not show that the installed images are Google's.
- **Bootloader** [V]: `ro.bootloader` is `deepspace-17.4-16119390`, the version the factory image requires (`android-info.txt`). This is the running slot's bootloader.
- **Board dtbo** [V]: `ro.boot.dtbo_idx` is 30. In Google's `dtbo.img` entry 30 is `MUSTANG MP` (`board_id 0x70506`, `board_rev 0x10000`, part 1). `ro.boot.dtb_idx` is empty on this build. The index comes from GrapheneOS's build and the table from Google's: I14.
- **Boot slot** [V]: `ro.boot.slot_suffix` is `_b`. The phone is running from slot B right now. CONTRIBUTING §3.1 keeps the project's own images on slot B and the stock system on slot A, so this phone, as it is, is the reverse of that (I19).
- **Kernel the phone runs** [V]: `Linux version 6.6.144-android15-8-g92137a1ac9ec-4k`, built 2026-10-21. GrapheneOS's build, not Google's (part 1 has Google's).
- **CPUs** [V]: eight cores. By `CPU part`: five 0xd87, two 0xd80 and one 0xd82, all implementer 0x41 (Arm). The `Features` line lists SVE2, MTE and BTI. The core names behind the part numbers: I1.
- **Memory** [V]: `MemTotal` is 15,443,192 kB (I2).
- **Partitions** [V]: `/dev/block/by-name` lists, with A/B pairs for most: `abl`, `bl31`, `cap`, `cpm`, `dbc`, `dbl`, `dpm`, ten `dram_init_*`, `dram_phy`, `dram_train`, `gc`, `gdmc`, `gsa_bl1`, `gsa_fw`, `tzsw` (all slotted), and the five boot images (`boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo`), `pvmfw`, `modem` and the four `vbmeta*` (slotted). Not slotted: `bl_data`, `blenv`, `devinfo`, `efs`, `efs_backup`, `frp`, `klog`, `metadata`, `mfg_data`, `misc`, `modem_userdata`, `persist`, `pinfo`, `rdbl`, `super`, `trusty_persist`, `trusty_userdata`, `ufs_internal`, `userdata`, `userdata_exp.ai`, and the LUN nodes `sda` to `sdd`.
  - **New against husky** [V, by comparison with husky's list in its NOTES.md]: `bl_data`, `cap`, `cpm`, `dbc`, `dbl`, `dram_init_0` to `dram_init_9`, `dram_phy`, `gc`, `gdmc`, `gsa_fw`, `rdbl`, `userdata_exp.ai`. Listed on husky but not here: `bl1`, `bl2`, `pbl`, `gcf`, `gsa`, `ldfw`, `fips`. What each one is: I10.

## 2026-10-30: stage 0, part 1: Google's factory image

The package is `mustang-cp3a.261005.005-factory-099acc44.zip` (11.4 GB), which contains a bootloader image, a radio image, three small `*.ec.bin` images (I9), the flashing scripts (not run; they flash the bootloader and radio and wipe user data), and an inner `image-*.zip` with the partition images [V] (F/).

- **Bootloader and baseband it requires** [V] (`android-info.txt`): `version-bootloader=deepspace-17.4-16119390`, `version-baseband=g5400i-260604-260807-B-16035863`. The same image set accepts the boards `rango`, `deepspace`, `frankel`, `blazer` and `mustang`, so the package serves the whole Pixel 10 family (I8).
- **Image layout** [V] (`unpack_bootimg`): `boot` (header v4, kernel only, ramdisk size 0, empty command line), `init_boot` (v4, the generic ramdisk; OS version 17.0.0, patch level 2026-10), `vendor_boot` (v4, page size 0x800, a vendor command line and two vendor ramdisks, one named `16K`) and `vendor_kernel_boot` (v4, a 1.4 MB `dtb` section and one vendor ramdisk). That is the layout of cheetah and husky: `BOOT_IMAGES="boot init_boot vendor_boot vendor_kernel_boot dtbo"`. Image sizes are 64 MiB for `boot`, `vendor_boot` and `vendor_kernel_boot`, 8 MiB for `init_boot` and 16 MiB for `dtbo`, equal to slot B's partition sizes (part 3).
- **Two page sizes** [V]: the package carries `kernel_16k` and `ramdisk_16k.img` beside a 4k kernel (the `boot` kernel's version string ends in `-4k`), and `vendor_boot` has a ramdisk named `16K` (I11).
- **Kernel** [V]: `boot`'s kernel is LZ4-compressed, `Linux version 6.6.127-android15-8-g91d825611104-ab16252310-4k`, built 2026-09-03 with clang 18. It is Google's generic Android kernel; the board-specific code is in modules (I12).
- **Base DT selection: `/soc_compatible`, not `/soc_id`** [V]. `vendor_kernel_boot` holds two base DTBs and neither has a `/soc_id`. Each has one `/soc_compatible` child: `A0` ("LGA A0", `product_id 0x5`, `major 0`, `minor 0`, `pkg_mode 0`) and `B0` ("LGA B0", `product_id 0x5`, `major 1`, `minor 0`, `pkg_mode 0`). The root compatible of both is `google,lga`. Which one the phone boots: part 5.
- **Root cells** [V]: `#address-cells = <2>` and `#size-cells = <2>` at the root and in `reserved-memory`. gs201 and zuma have one size cell, so a `reg` entry is 16 bytes here, not 12; the 12-byte rule from the other Tensor phones does not apply.
- **Addresses are new** [V]: `uart0` is `/uart@3bf01000` and `serial0` is `/uart@db61000`, nothing like gs201's `0x10A00000`. No address or interrupt number is to be copied from another SoC (I4).
- **Board dtbo** [V] (`mkdtboimg`): 34 entries. Mustang's are entries 21 to 30, `board_id` `0x70502` to `0x70506` (Proto 1.0, Proto 1.1, Proto 1.1 Wingboard, EVT 1.0, EVT 1.0 Wingboard, EVT 1.1, EVT 1.1 Wingboard, DVT 1.0, PVT 1.0, MP). **MP is entry 30: `board_id 0x70506`, `board_rev 0x10000`**, which is what `ro.boot.dtbo_idx` points to (part 2). The same table holds the other boards of the family (`FRANKEL` `0x703xx`, `BLAZER` `0x704xx`, `Deepspace` `0x701xx`, two emulators) and three small debug-policy overlays (id 0, variant `eng`, target `dpm`).
- **Some compatible strings are gs101's** [V as text]: the MP overlay contains `google,gs101-gsa-gsc-v1`, `google,gs101-cp-thermal`, `samsung,exynos-cp` and `google,bitbang-spmi-controller` (I7). The maintainer expects the clocks, pin control, power domains and interrupt map to be new.
- **Verified boot** [V] (`avbtool`): `boot` and `init_boot` carry hash footers with rollback index `1791158400` and security patch `2026-10-05` (OS version 17); `vbmeta` chains `boot` (rollback index location 2) and `init_boot` (4), as on husky (I13).

## Interpretation and open questions (AI-assisted, not verified)

Everything here is a hypothesis or a gap, not a fact. Each item says what it rests on. None of it has been checked by the contributor, and none has been tested on a phone.

**What the hardware is**

- **I1. CPU core names.** Five cores report part 0xd87, two 0xd80 and one 0xd82. Mapped through Arm's part list, that would be five Cortex-A725, two Cortex-A520 and one Cortex-X4. The mapping is from Arm's list, not from the phone; the live DT also names an `arm,cortex-x4-pmu` for the single large core, which agrees.
- **I2. RAM.** `MemTotal` of about 15.4 GB suggests 16 GiB installed. Eight banks of 2 GiB would match, but the banks' sizes are not readable.
- **I3. GPU.** `img,gpu` and `rgx` register names point at an Imagination GPU, which fits the maintainer's expectation on #18. The model is unknown, and so is whether mainline's driver for that family covers it.
- **I4. UART.** `goog,goog-dw-apb-uart` names a Synopsys DesignWare APB UART, a block mainline has a driver for. Whether that driver binds to this string or a fallback is unknown. Which of `uart0` and `serial0` is the console is unknown.
- **I5. GIC.** The fourth interrupt cell (`#interrupt-cells = <4>`) has an unknown meaning.
- **I6. Clocks.** No clock-controller node was found under the usual names, so how clocks are described is unknown. It may be a different mechanism rather than a missing one.
- **I7. gs101-named strings.** `google,gs101-gsa-v1` in the base tree, and four in the MP overlay. Whether the drivers behind them carry over from gs101 is unknown.
- **I8. Other boards in the package.** Only mustang is identified. That `rango`, `deepspace`, `frankel` and `blazer` are the other Pixel 10 models is a guess; `deepspace` is also the bootloader family name.
- **I9. The three `*.ec.bin` images** (`d3m2`, `proto11`, `evt`): purpose unknown.
- **I10. The new partitions** (`bl_data`, `cap`, `cpm`, `dbc`, `dbl`, `dram_init_*`, `dram_phy`, `gc`, `gdmc`, `gsa_fw`, `rdbl`, `userdata_exp.ai`): purposes unknown. The backup set for CONTRIBUTING §3.3 would likely add `pinfo`, `trusty_persist` and `trusty_userdata`, as on husky.

**Boot and firmware behaviour**

- **I11. 16K pages.** The package ships a 16K-page kernel and ramdisk beside the 4K ones. What that means for our kernel, and which one the bootloader hands over, is unknown.
- **I12. Google's GPL kernel.** The matching branch for `6.6.127-android15-8` and for laguna is not found yet.
- **I13. AVB footers.** `vbmeta` chains `boot` and `init_boot`, as on husky, so an image of ours without footers would probably be refused by the bootloader even on an unlocked phone. That rests on the husky and cheetah notes, not on a test.
- **I14. The phone's `dtbo` table.** `ro.boot.dtbo_idx` comes from GrapheneOS's build. That the phone's own `dtbo` has the same table as Google's is assumed.
- **I15. Silicon revision.** The live node set matches B0's merged tree better than A0's, on the pair `ehld-coreinstr` and `pmu-ehld`. That the phone boots the B0 tree is an inference from node names. A kernel log line would confirm it. The descriptor can still carry both revisions.
- **I16. RAM bank sizes.** The bases of the eight banks are known from node names; the sizes need root.
- **I17. The `gsa` rewrite.** Two `reserved-memory` nodes carry a fixed address in the factory tree and appear live without one. What the bootloader does there is unknown.
- **I18. The framebuffer.** No `reserved-memory` child is named like one. It is probably described under `chosen`, which the shell user cannot list; its address and size still need root or another route.

**The phone's state**

- **I19. Slot A.** Flagged unbootable. Possible causes are boot tries used up, a failed update, or how GrapheneOS's installer leaves the inactive slot; which one applies is unknown, and so is what slot A holds and its bootloader version. I found nothing in GrapheneOS's documentation that explains it.
- **I20. Anti-rollback.** The four counters husky's notes read do not exist on this bootloader. The rollback index in the factory image's footers is not the bootloader's stored counter, so the phone's stored state is unknown.
- **I21. Unlockability.** The maintainer's reply on #18 assumes the bootloader can be unlocked. The "OEM unlocking" setting has not been checked, and unlocking would wipe the phone.

## Still needs a phone

1. **The other slot's bootloader version.** The bootloader reports only the running slot's (part 3). Slot A is flagged unbootable, so it cannot be read by booting it; how to read it without writing is open.
2. **Confirming the silicon revision** (I15): the phone's kernel log would show it.
3. **Why slot A is unbootable and what it holds** (I19).
4. **The live device tree's values, `/proc/iomem`, `dmesg`, the vendor module list**: need root (CONTRIBUTING §5.1). Not available on a locked phone.
5. **The sizes of the eight RAM banks and the framebuffer carve-out** (I16, I18): the shell user is refused them.
6. **Whether a GrapheneOS phone fits the project's safety model** (stock kept on slot A, only slot B and `userdata` written). The maintainer replied on #18 on 2026-10-30 that the phone is useful and its OS is not; whether the layout (I19) is acceptable is still open.
