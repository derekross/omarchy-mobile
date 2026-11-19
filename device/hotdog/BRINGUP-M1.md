<!-- SPDX-License-Identifier: MIT -->
# OnePlus 7T Pro (hotdog): first boot of Omarchy Mobile

**Status (2026-11-03):** port started. Kernel branch `omamobile-hotdog`
(worktree `~/omamobile-kernel/wt-hotdog`, output `~/omamobile-kernel/out-hotdog`),
device descriptor, device package and the userdata preparation are written
and built on the laptop; nothing has run on the phone yet. The results of
each step below are recorded under [Results](#results).

The phone ran Linux before this port: first postmarketOS's SM8150 kernel, then
the owner's own earlier port on a 7.0.0 build of that kernel with hotdog
patches (display, GPU, touch, battery, charging, Wi-Fi, Bluetooth, speakers). This port moves the
same hardware support onto linux-omarchy-mobile (7.3) and Omarchy's userspace.

## 1. How this phone differs from a Pixel

| | Pixel (cheetah) | OnePlus 7T Pro (hotdog) |
| --- | --- | --- |
| SoC | gs201 | SM8150 (Snapdragon 855+), Adreno 640 |
| Bootloader | Google ABL, header v4, vendor_boot | Qualcomm ABL, one header-v2 `boot.img` (page 4096) with the DTB appended to an `UNCOMPRESSED_IMG`-tagged Image |
| Kernel command line | DTB `/chosen/bootargs` | the boot header; ABL appends its `androidboot.*` words |
| Slots | stock on A, Omarchy on B | **Omarchy on A; no slot is ever switched** (below) |
| `dtbo` | ours, `dtbo_b` | `dtbo_a` stays **erased**: ABL applies stock's overlays to any DTB, and the result does not boot |
| UFS layout | `userdata` on `sda` | `userdata` on `sda` (4096-byte sectors); `boot_a`/`boot_b` on `sde`; modem EFS on the LUNs the guard keeps read-only |

**Slots.** The slot flags of a Qualcomm A/B phone live in GPT attributes on the
boot LUN. On this phone a slot switch once moved the UFS boot LUN onto slot B's
mismatched bootloader firmware and took a full EDL (MSM) restore. So:

- Omarchy Mobile boots from `boot_a`. Slot A is current and marked successful
  (retry count 6) and stays that way: `fastboot flash boot_a` has not changed
  the flags in any earlier capture, and nothing here marks or switches a slot.
- No `--set-active`, no `qbootctl`, no write to any GPT. The earlier Linux
  ports on this phone marked slot A at every boot with `qbootctl -m`; Omarchy
  Mobile does not (AGENTS.md §1: never from a service or at boot).
- `bin/omamobile flash`, `push` and `fastboot` refuse `BOOT_METHOD=qcom-abl-v2`.
  The boot image is written by a human with `fastboot flash boot_a`, only an
  image that has RAM-booted (`fastboot boot`), and read back.
- Before upstreaming, this model needs its own entry in CONTRIBUTING §3.1
  (a slot-A phone with no stock fallback), which only the maintainer adds.

**Storage guard.** `UFS_RW=userdata`: the shared init leaves only `userdata`
writable and removes `/dev/sda`; every other partition on every LUN is
read-only before anything mounts. Linux writes no boot partition on this phone.
In Arch, `10-omamobile-storage.rules` sets the modem's EFS partitions
(`modemst1`, `modemst2`, `fsg`, `fsc`, `oem_stanvbk`, `oem_dycnvbk`) and
`persist` read-only again whenever udev sees them, and `rmtfs -r` serves them to
the modem from RAM copies.

**No fallback slot.** The shared init's "no USB host in 45 s → panic" exists to
hand a Pixel back to stock; here it would restart the same image, so the
descriptor's `INITRAMFS_USB_RECOVERY=no` keeps the init running. (The bring-up
boots used an earlier key of this port, `USB_HOST_PANIC=0`, which also left
the log on screen; upstream's `INITRAMFS_USB_RECOVERY=no` replaced it.)

## 2. Recovery by the buttons

- **Fastboot:** with the phone off and the cable **out**, hold Volume Up +
  Volume Down + Power until the bootloader menu appears. With the cable in,
  held volume keys can enter EDL (`05c6:9008`); that is harmless and times out.
- **A hung phone:** cable out, hold Power until it is off (about 15 s), then the
  fastboot combination above.
- **Fastboot does not enumerate after a warm reboot** at times, or runs very
  slowly: unplug and replug the cable.
- **A crash dump** (`05c6:900e`, the phone stays black) is the SoC's crash
  handler: hold Power until it resets.

## 3. What was built

| Where | What |
| --- | --- |
| kernel `omamobile-hotdog` | postmarketOS SM8150 delta for this phone onto 7.3: `sm8150.dtsi`, `pm8150{,b,l}.dtsi`, `sm8150-oneplus-common.dtsi`, `sm8150-oneplus-hotdog.dts`; Samsung DSC panel driver (multi-slice DSC now through 7.3's `MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT`, so the old msm DSI patch is dropped); IPA v4.1; ath10k WCN3990 fixes (quiet mode, 5 GHz passive scan, station vdev start after the BSS peer); `qcom_smbx` SMB5 (PM8150B) charging; PM8150B fuel gauge; OnePlus project-info (RF cable state for the modem); btqca board-ID read on WCN399x; TFA9874 amplifiers; SM8150 sound card |
| `device/hotdog/kernel.config` | the SoC, UFS, USB-gadget and display path built in (the shared initramfs loads no modules); radios, sound and battery as modules |
| `device/hotdog/device.conf` | `BOOT_METHOD=qcom-abl-v2`, `UFS_RW=userdata`, `INITRAMFS_USB_RECOVERY=no`, `INITRAMFS_USERDATA_WAIT=300` |
| `bin/omamobile` | `qcom-abl-v2`: `images` packs the header-v2 `boot.img` with the pinned mkbootimg (`CMDLINE_APPEND` for test images); `flash`, `push` and `fastboot` refuse it |
| `initramfs/init` | `INITRAMFS_USB_RECOVERY=no`: no crash without a USB host; `INITRAMFS_USERDATA_WAIT` (`/etc/omamobile-userdata-wait`): wait for a late userdata |
| `packages/omamobile-device-hotdog` | storage rules, USB networking, rmtfs (read-only) and tqftpserv built from linux-msm, the Bluetooth address, the speakers' UCM profile, ModemManager masked |
| `device/hotdog/prepare-userdata` | the owner's `firstboot.conf` and the phone's firmware into a local copy of the root image |

Mesa: the published `[omamobile]` Mesa is built for Mali only. The hotdog image
leaves it out of its local repository, so Arch Linux ARM's Mesa (freedreno,
turnip) is installed, and the phone follows its own repository (`local`
channel) so an update cannot swap it back.

Firmware: none in the repository. The vendor images come from the owner's own
OxygenOS (`modem`, `bluetooth` partitions; the ath10k board file is this unit's
`bdwlan`), kept outside the repository in `~/android/reference/hotdog/`.

## 4. Runbook

Build (laptop, no phone):

```sh
export DEVICE=hotdog KERNEL_DIR=~/omamobile-kernel/wt-hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog
bin/omamobile kernel && bin/omamobile modules && bin/omamobile initramfs
CMDLINE_APPEND=omamobile.initramfs bin/omamobile images   # test image: stays in the initramfs
tools/fetch-published out/hotdog/published
rm out/hotdog/published/{mesa,vulkan-panfrost}-*            # Arch Linux ARM's Mesa instead
tools/build-packages --local hotdog --import out/hotdog/published packages/omamobile-device-hotdog
tools/build-rootfs --local hotdog --allow-missing "mesa vulkan-panfrost"
```

Every step names its risk, what passes, when to stop and how to roll back.
One step per boot; the human runs or approves each.

**H0 Read the bootloader (read-only, risk none).** `fastboot getvar all`.
Pass: `product:msmnile`, `unlocked:yes`, `current-slot:a`,
`slot-successful:a:yes`. Stop: any other slot state.

**H1 RAM boot, initramfs only (risk low: nothing is written; a power cycle
returns to whatever `boot_a` holds).** `fastboot boot $KERNEL_OUT/images/boot.img`
(the `omamobile.initramfs` test image). Pass: `ssh root@172.16.42.1`; `dmesg`
shows `ufs-ro` setting every partition read-only except `userdata`;
`cat /sys/block/sd*/sd*/ro` is 1 everywhere but `userdata`; the panel shows the
console. Stop: any other partition writable, no USB after 2 minutes.
Rollback: hold Power, the phone boots `boot_a`.

**H2 Write userdata (risk: erases the previous system on `userdata`).**
`device/hotdog/prepare-userdata ROOTFS FIRMWARE firstboot.conf userdata.img`,
then with the phone in fastboot `fastboot flash userdata userdata.img`.
Pass: `OKAY`. Rollback: the previous system's userdata image, if one was kept.

**H3 RAM boot into Arch (risk low: `boot_a` unchanged).** Build the image
without `CMDLINE_APPEND`, `fastboot boot` it. Pass: the root grows to the
partition, `omamobile-firstboot` finishes, SDDM shows Omarchy's lock screen,
SSH as the owner; `systemctl --failed` empty or explained. Stop: no SSH after
5 minutes (the initramfs shell on USB says why).

**H4 Write `boot_a` (risk medium: replaces the boot image; keep the old one).**
Only the image that passed H3: `fastboot flash boot_a boot.img`, then
`fastboot getvar slot-successful:a` and `slot-retry-count:a`. Pass: `yes`, 6.
Stop: anything else, and ask before rebooting. Then `fastboot reboot`; read
back from Linux: `head -c $(stat -c %s boot.img) /dev/<boot_a> | sha256sum`.
Rollback: `fastboot flash boot_a` with the previous image.

## Results

**2026-11-03, H0** (fastboot): `product:msmnile`, `unlocked:yes`,
`current-slot:a`, `slot-successful:a:yes`, `slot-retry-count:a:6`; slot B
retry 0, not successful. Pass.

**2026-11-03, H1, first two tries (`7.3.0-rc6-omamobile-push1-gfe9627c005bd-dirty`,
`-gf2fd674afa1e`): fail, no USB.** The console ended in
`Error sending AMC RPMH requests (-110)`; with `DETECT_HUNG_TASK` the screen
showed the cause: the rpmh-regulator probe blocked in `rpmh_rsc_send_data`
under `rpmh_read`, cpufreq's interconnect vote (`sugov`) blocked the same way,
and `dwc3_qcom_probe` waited on the interconnect mutex `sugov` held. 7.3's
new RPMh reads (rpmh-regulator reads the bootloader's voltage, enable state
and mode at probe) are never answered by this RSC; the TCS of a read is freed
only by its completion interrupt, and SM8150 has two active TCSes, so after
two reads every RPMh request waited forever. The 7.0 kernel the phone ran
before makes no reads. Fixed on `omamobile-hotdog`: `qcom,no-read-support`
on `apps_rsc` makes `rpmh_read()` refuse at once, and the regulator driver
keeps 7.0's unknown voltage and mode. Nothing was written; a held Power key
returned the phone to its old system each time (the forced reset cleared
pstore, so the log came from a photo of the screen).

Notes: `hung_task_timeout_secs=` is no longer a boot parameter on 7.3 (the
kernel passed it to init), and `hung_task_panic=1` printed the reports
without panicking; not chased yet. ABL appends `rootwait ro init=/init` and
`androidboot.mode=fastboot` (on a RAM boot) to the header's command line.

**2026-11-03, H1, third try (`7.3.0-rc6-omamobile-push1-g970d093a4160`): pass.**
`rpmh 18200000.rsc: RSC v1.7: reads disabled`; the USB gadget was up 5 s
after `fastboot boot` (`a600000.usb`, `1d6b:0104`), SSH to 172.16.42.1.
Guard: 117 partitions, only `sda22` (`userdata`) writable, `sdb`-`sdf`
read-only, `/dev/sda` removed. DSI connected, backlight 1023, `renderD128`
present; `a630_sqe.fw` missing as expected (the firmware comes with the root
image). Open: `cpu cpu7: Voltage update failed freq=2956800` (the prime core's
top OPP).

**2026-11-04, H2: pass.** Root image `omamobile-rootfs-hotdog-2026.11.04`
(all build checks ok) prepared with `prepare-userdata`, after a fix: debugfs
has no `mkdir -p`, and the image has no `linux-firmware-qcom`, so the vendor
tree's parents under `/usr/lib/firmware/qcom` were never made and the GPU
firmware check failed. `fastboot flash userdata`: 13 sparse chunks, all
`OKAY`, 301 s.

**2026-11-04, H3 (`7.3.0-rc6-omamobile-push1-g970d093a4160`): pass on the
second try.** First try: the panel showed `systemd-firstboot`'s console
prompt (locale, keymap, time zone, root password). The image's
`/etc/machine-id` is `uninitialized`, so systemd treats the boot as a first
boot, and here the console is the panel (`console=tty0`) with no keyboard;
the prompt runs before `sysinit.target`, so it held `sshd` and
`omamobile-firstboot`. Second try with `systemd.firstboot=off` appended:
SSH 11 s after `fastboot boot`, the root grown to 212.9 GB, `omamobile-firstboot`
done in about 3 minutes (Node.js deferred: no network yet), SDDM logged the
owner in to Hyprland, SSH as the owner, `systemctl --failed` empty, Wi-Fi up,
NTP synced. `omamobile-device-hotdog` 0.1.1 masks `systemd-firstboot.service`,
as dodge's package does.

Open: the modem crashed five times in the first 210 s ("fatal error without
message", recovered each time), then ran on. Each start `rmtfs` could not open
`/dev/disk/by-partlabel/oem_stanvbk` and `oem_dycnvbk` (`sda9`, `sda8`): the
initramfs removes `/dev/sda`, so udev cannot read the partition table and
names no partition on `sda` (no `ID_PART_ENTRY_NAME`, no `by-partlabel`
link). The same gap means `10-omamobile-storage.rules`' re-`setro` never
matches `sda`'s partitions; they stay read-only from the initramfs (`ro` 1).
Both rules should use the kernel's `PARTNAME`. The laptop's NetworkManager
dropped 172.16.42.2 again at each gadget start.

**2026-11-04, H4: pass, with one difference from the plan.** Before it, a
verified copy of the old `boot_a` (`sde11`, 96 MiB) went to
`~/android/reference/hotdog/`. A software `systemctl reboot` with the
`bootloader` argument ended in Qualcomm's crash dump mode (`05c6:900e`)
instead of fastboot; a held Power key and the fastboot buttons recovered it,
so reboot to fastboot by the buttons until the shutdown crash is understood.
`fastboot flash boot_a` with the image that passed H3: `OKAY`, but
`slot-successful:a` went from `yes` to `no` and `slot-retry-count:a` from 6 to
7. ABL clears the mark when `boot_a` is flashed, and nothing in our system
marks the slot again (the owner's earlier port did), so every boot now spends a try, and at zero
ABL would turn to slot B, which has no system. With the owner's yes, booted:
`androidboot.mode=normal`, slot `_a`, `boot_a` reads back as the image by
sha256, `systemctl --failed` empty. Open, the owner's decision: how slot A
gets marked again (a GPT write: `fastboot --set-active=a` in ABL or a
mark-successful from Linux), before the tries run low. Keep reboots few.

**2026-11-15: slot A marked successful again, from Linux, with the owner's
yes.** `boot_a` had been flashed with `7.3.0-rc6-omamobile-push1-gce58cc9c3759`
and booted once (tries 6). `device/hotdog/slot-a-mark`: `status` and `dump`
(read-only) first; the dump went off the phone to
`~/android/reference/hotdog/gpt/sde-before-slot-a-mark-2026-11-15.tar`
(sha256 of the touched bytes `3466da83…`, checked again on the laptop: both
entry arrays identical, `boot_a` tries 6, successful 0, active). Then
`write --sha256 3466da83…`: backup copy (LBA 1048575) then primary (LBA 1),
each written and read back, `sde` read-only again. Before → after:
`boot_a: priority 3 active 1 tries 6 successful 0 unbootable 0` →
`… successful 1 …`; `boot_b` unchanged (`priority 0 active 0 tries 0
successful 0 unbootable 0`); both CRCs valid, copies identical, new sha256
`361c9ccc…`. Every later `fastboot flash boot_a` clears the bit again
(H4 above): after the flashed kernel has booted, run `status`, `dump` and
`write` again with the owner's yes. Rollback for a broken GPT: the dump holds
both copies' header and entry bytes at their offsets; the phone still boots
to fastboot by the buttons.

**2026-11-18: `boot_a` flashed with `7.3.0-rc6-omamobile-push1-gf38b21c1fdb9`
(the sleep kernel with the ath10k MSA fix, SUSPEND-PLAN K7; cmdline
`clk_ignore_unused pd_ignore_unused panic=10 splash`), with the owner's
yes, and slot A marked again.** The old `boot_a` (96 MiB, sha256
`660f7239…`) went to `~/android/reference/hotdog/` first, checked against
the partition. A software `systemctl reboot` with the `bootloader` argument
reached fastboot in 15 s (on 11-04 it ended in the crash dump; that was most
likely K7's bug, a modem shutdown with ath10k bound). Before the flash:
`slot-successful:a` yes, tries 6; after: no, 7. Booted: slot `_a`, normal
mode, `boot_a` reads back as the image (`6688b310…`), no failed units, all
remote processors running. `slot-a-mark` `status`, `dump`
(`~/android/reference/hotdog/gpt/sde-before-slot-a-mark-2026-11-18.tar`,
`3466da83…`, the same bytes as before the 11-15 mark) and `write`: `boot_a`
successful 0 → 1, tries 6, `boot_b` unchanged, both CRCs valid, copies
identical, `361c9ccc…` (as on 11-15), `sde` read-only again.

`omarchy update` failed with "Cannot fetch updates": the `local` channel's
`[omamobile]` database is signed with this port's local key, which the build
trusted only in its own keyring, so on the phone the key was unknown. Also,
the phone has no clock across a reboot (it booted at 1970-01-04) until NTP
syncs, about 1.5 minutes in. Fixed on the phone by adding and locally signing
the key; for later images `rootfs/build-inside` ships a `local` image's key
as `/usr/share/pacman/keyrings/omamobile-local.gpg` (+ `-trusted`), which
firstboot's `pacman-key --populate` picks up. `omamobile-update check`: ok,
no blockers.
