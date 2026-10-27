<!-- SPDX-License-Identifier: MIT -->
# AGENTS.md: working on Omarchy Mobile as an AI coding agent

Omarchy Mobile runs native Omarchy (Arch Linux ARM, Hyprland, Omarchy's packages) on mobile devices with a mainline kernel and no Android. The reference device is the Pixel 7 Pro (`cheetah`, gs201). Read [CONTRIBUTING.md](CONTRIBUTING.md) for the project, the safety model and the bring-up order. This file holds the rules and gotchas for agents, each with the reason behind it.

**The repositories are public.** Anything you commit, push, or write into a plan, a log excerpt or a screenshot is published.

## 1. Safety rules (non-negotiable)

- **Ask the human before every reboot, flash, `push`, overlay boot or irreversible write.** That includes RPMB writes, a first `storageproxyd` run, `devinfo` and anything under `/dev/sd*`. The phone is real hardware with calibration data that can't be replaced, and a human has to be ready to recover it.
- **The phone is shared with a human. Announce anything that affects the screen or the feel of the phone before you run it**: DPMS, display modes and refresh rate, brightness, `bl_power`, haptics, the torch, the shell restarting, rotation. Otherwise they think the phone is broken, or it buzzes in their hand.
- **Only slot B and `userdata` are ours.** Write only `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b` and `dtbo_b`, and only through `bin/omamobile flash|push`. Never touch bootloader, radio, `devinfo`, `persist`, `efs*`, `modem*` or `vbmeta`, and never run an unsuffixed `fastboot flash`, with one exception: `userdata`, and only through `tools/install-phone` (serial pinned, codename typed, allowlist, dry run first). Slot A's stock Android is the way back.
- **Qualcomm A/B phones (Pixel 4 family) keep the slot flags in GPT attributes,** so slot B can only be marked bootable by writing the partition table. That write is a narrow, named exception, never automatic: by hand, once per install of slot B's boot image, and only for a device whose entry in [CONTRIBUTING](CONTRIBUTING.md) §3.1 names the LUN, the four sectors (LBAs 1, 2, last-1 and last), the attribute bit and the CRCs it rewrites. That device's plan must also record the slot flags before and after, the rollback for a corrupted GPT, and the way back: stock restored on slot A first, or the owner's explicit acceptance of buttons-only recovery. The storage guard can't block this write, so it never runs from a service or at boot.
- **Never weaken the storage guard.** Don't `blockdev --setrw` a partition or recreate `/dev/sda`. Don't mount Android partitions read-write, and don't add names to the `UFS_RW` allowlist without the human's say-so. The guard is what keeps a bad command from erasing the IMEI.
- **Check backups before radio, PMIC, AoC or Trusty work.** Run the checksum check of `efs`, `efs_backup`, `modem_userdata`, `persist` and `modem_a/b` against the off-repo backup first ([MODEM-PLAN.md](device/cheetah/MODEM-PLAN.md) M0.1). If there's no backup, stop. Find each partition by `PARTNAME` in `/sys/class/block/*/uevent`: the Arch root has no `/dev/disk/by-partlabel`. **Take a fresh read-only backup after any stock Android boot** (a slot A fallback counts): stock's modem stack writes `efs`, `persist` and `modem_userdata`, so the old checksums stop matching and the next check can't tell a change of ours from stock's.
- **Never read or write PMU registers from userspace** (no `devmem`, no `debugfs/regmap/*pmu*/registers`). PMU writes from userspace are silently ignored, and one read of a PMU G3D register crashed the phone. Use the kernel's SMC-backed `exynos-pmu` regmap.
- **`devmem` is `devmem ADDR [VALUE]`.** A second argument is written, so `devmem ADDR 32` writes 0x20. This once clobbered live DSIM timing registers.
- **Read only blocks that are known powered and clocked, one register per call on a first probe.** A read of an unpowered block aborts the SoC and kills the session.
- **Read-only steps first, then one change per boot.** New DT nodes stay `disabled` and are enabled by an overlay in [`device/cheetah/overlays/`](device/cheetah/overlays). Blacklist a module before installing a DTB that enables its node. Two new things that fail together tell you nothing.
- **Arm a safety net before every risky step:**
  - for anything that loads drivers or pokes hardware, a log stream to the laptop first and `--watchdog` (the stage tools do both);
  - for anything that can cut USB, a dead-man switch: `tools/usbc-deadman`, or `systemd-run --unit=x-deadman --on-active=90 <undo>`, then confirm over a *fresh* SSH login (`tools/phone-ssh --fresh`) and stop the timer;
  - for anything at boot, a hang marker.

  USB is the only link, so a step that can kill it must be able to undo itself.
- **When a reboot gets stuck:** systemd's `RebootWatchdogSec=1min` resets the phone a minute into a hung shutdown, so wait. It doesn't cover a hang in the kernel's `device_shutdown` (a held device lock, as after the AoC `rmmod` oops below). If it's still stuck, ask the human to force a restart: Power held about 30 s, then Power. On the Pixel 8 Pro, hold Power + Volume Up for 15-30 s; Power alone does nothing under our kernel ([BRINGUP-M1](device/husky/BRINGUP-M1.md) test 23). For fastboot by hand: Volume Down + Power held about 20 s. Don't send more commands to a phone that has stopped answering, and don't guess at its state. Ask.
- **Never commit or paste identifying data or vendor blobs.** That means MAC and Bluetooth addresses, serial numbers, IMEIs, SSIDs, account names, `getprop` dumps, `persist` or `efs` contents, partition images, Google firmware and binaries. Grep your diff before committing (`[0-9a-f]{2}(:[0-9a-f]{2}){5}`, the SSID, the serial). Use placeholders such as `<SSID>`.
- **Cite only properly licensed, citable sources** in commits, docs and code: upstream Linux, Google's GPL kernel, postmarketOS, Mesa, Omarchy and our own captures.
- **Never name or compare other mobile Linux projects or distributions in public copy** (docs, README, device notes, the website): describe a base by its parts. A source citation as above is fine ([CONTRIBUTING](CONTRIBUTING.md) §6.3).

## 2. Workflow

- **Read before you touch anything:**
  1. the subsystem's plan in `device/<codename>/*-PLAN.md`: its status line names the kernel branch, the worktree (`~/android/mainline/wt-<subsystem>`) and the output directory (`out-<subsystem>`);
  2. the newest entries in [NOTES.md](device/cheetah/NOTES.md);
  3. the gotchas below.

  Plans record what already failed and why.
- **Work offline and hand the human a runbook.** Write the code, build it, and run checkpatch, `W=1` and `dt-validate` yourself. Then add a gated runbook to the plan: the commands, Expect/Pass, a **stop condition**, a Rollback and a risk level for each step, read-only steps first. The human runs or approves each step. Record the results in the plan with the date and the kernel release (`uname -r`).
- **Build with an explicit worktree and output directory:** `KERNEL_DIR=~/android/mainline/wt-X KERNEL_OUT=~/android/mainline/out-X bin/omamobile kernel`. Other agents build in parallel, and a shared output directory mixes their builds.
- **Kernel branches:** one subsystem per branch (`omamobile-<subsystem>`). The human merges branches into the local integration branch `omamobile-int` that the phone runs. Curated, upstream-ready commits go to `omamobile`, the branch published to GitHub. Don't rebase or force-push branches someone else is merging from.
- **Commit messages:**
  - Kernel commits are upstream-style: the subsystem prefix from `git log --oneline <file>`, the why, and the evidence. AI agents never add `Signed-off-by:` (`Documentation/process/coding-assistants.rst`): the human signs off.
  - This repository uses an area prefix (`omamobile-gnss: …`, `device-cheetah 0.1.15: …`, `DISPLAY-PLAN: …`), a body that explains why, and the attribution trailer the session asks for.
- **Reviewing pull requests:** use the `omamobile-reviewer` agent (`.claude/agents/omamobile-reviewer.md`), one PR (or a few related ones) per run. It reads [docs/review/LESSONS.md](docs/review/LESSONS.md), runs `tools/pr-check` or `tools/kernel-pr-check`, and returns a verdict, a draft comment and candidate lessons. Nothing is posted until the maintainer says so; confirmed lessons (and corrections, when a review was wrong) are added to LESSONS.md in a `docs/review: …` commit, so the next review knows them.
- **Commit only your own files when others have uncommitted work**, with a temporary index:

  ```sh
  export GIT_INDEX_FILE=$(mktemp -u)      # a path git creates
  git read-tree HEAD
  git add -- path/you/changed other/path
  git commit -m "…"
  unset GIT_INDEX_FILE
  git reset -q -- path/you/changed other/path   # sync the real index with the new HEAD
  ```

  This leaves other people's staged and unstaged changes alone.
- **Moving a feature from bring-up into a package:** bump the package `version`, enable nothing that isn't hang-safe, and delete the bring-up files from `/etc/modprobe.d` on the phone (`omamobile-*-bringup.conf`, and any hand-copied package file). A file in `/etc/modprobe.d` replaces the package's `/usr/lib/modprobe.d` file of the same name, so a stale `omamobile-aoc.conf` there hid the package's new blacklist.
- **Kernel releases change with every push** (`7.3.0-rc6-omamobile-push1-NNNNN-g<sha>`). `bin/omamobile push` runs `modules-push` when the tarball's checksum differs. Without its modules a new kernel boots without its drivers, the GPU among them.

## 3. How the tools fit together

```
laptop                                              phone (172.16.42.1, root over USB)
------                                              ----------------------------------
bin/omamobile kernel   -> Image, dtbs, modules  (docker build env)
bin/omamobile modules  -> modules-<rel>.tar.zst
bin/omamobile initramfs-> Alpine + dropbear + initramfs/init
                          (storage guard, USB gadget, ssh, switch_root to Arch on userdata)
ov <overlay...>        -> DTB = default + device/cheetah/overlays/*.dtso (fdtoverlay)
bin/omamobile images   -> boot/init_boot/vendor_boot/vendor_kernel_boot/dtbo .img
bin/omamobile push     -> modules-push, dd into *_b, sha256 verify, reboot-to omamobile
bin/omamobile flash    -> the same images through fastboot (first install, recovery)
                                                    omamobile-boot-success marks slot B good
tools/phone-ssh CMD    -> run anything; stream files with  ssh 'cat > f' < f
                          (OMAMOBILE_SSH_SHARE=1: one shared connection; --fresh: never)
```

| Tool | Use |
| --- | --- |
| `bin/omamobile capture` | Stock facts over adb/fastboot (live DT, dmesg, iomem with root) into `~/android/reference` (never commit) |
| `bin/omamobile kexec` | Try a kernel without flashing (USB does not come back after kexec on cheetah) |
| `bin/omamobile fastboot` | Reach fastboot without buttons: adb, `reboot-to bootloader`, or a crash that falls back to slot A |
| `tools/wifi-w1-capture`, `acpm-stage`, `aoc-stage`, `fingerprint-capture` | Staged bring-up: kmsg streamed to `logs/` first, optional `--watchdog` feeder, `--pstore` afterwards |
| `tools/usbc-deadman` (+ `usbc-deadman-phone`) | USB-C/charger steps under a dead-man switch; `dump` is read-only |
| `tools/display-hz` | Read-only refresh-rate measurement from DECON's frame counter |
| `tools/power-ab` | On-phone A/B battery-drain test (runs detached; the cable is out) |
| `tools/bt-uart-test`, `cs35l41-id`, `ff-rumble`, `usf.py` | On-phone probes, streamed with `tools/phone-ssh python3 - < tool` |
| `tools/aoc-audio-diag` | On-phone AoC playback diagnosis (`tools/phone-ssh 'EP=6 MODES=copy bash -s' < tools/aoc-audio-diag`): plays a short tone under `timeout`, snapshots mailbox IRQs, ring counters, CS35L41 registers and DAPM. `EP=` entry point, `MODES=` copy/mmap, `AOCLOG=1` records the AoC firmware log, `SETUP2=0/1` sets `ep_setup2` |
| `tools/aoc-amp-diag` | On-phone CS35L41 check (`AMP=` top, bottom or both; `CH=` L, R or LR): a -20 dBFS tone through EP6 in stock's TDM 0 format, with both amplifiers' DAPM widgets and registers dumped mid-tone |
| `tools/extract-vendor-firmware`, `extract-vendor-chroot`, `extract-fingerprint-vendor` | Google's files from the user's own factory image, on the laptop |
| `tools/phone-mirror` | The phone's screen in a VNC viewer on the laptop with input (`omamobile-mirror on` on the phone, wayvnc on 172.16.42.1:5900 only); `--keep` leaves it on. Affects the phone's feel: announce it |
| `tools/phone-install-package packages/X` | Build a package on the phone and install it |
| `tools/pr-check [BASE]`, `tests/packages` | The pull-request gate CI runs (`.github/workflows/checks.yml`): identifiers, blobs, AI sign-offs and scripts that parse, then every package's `test/all`; run both before you push (CONTRIBUTING.md §6.5) |
| `tools/kernel-pr-check [-C KERNEL] [--build OUT] [--merge] BASE [HEAD]` | The same gate for linux-omarchy-mobile pull requests: a human Signed-off-by from the author, subsystem prefixes, `checkpatch --strict`, identifiers, and with `--build` the `W=1` builds of touched C files, device trees (new warnings only, against the base) and bindings. `--merge` builds the pull request merged onto BASE, as CI does, and reports a conflict as "rebase needed". Build it in the project container with the Android clang on `PATH` |
| `tools/phone-ssh [--fresh\|--stop] CMD` | Run a command on the phone. `OMAMOBILE_SSH_SHARE=1` shares one connection (kept 60 s), so a key that needs a touch per connection asks once rather than about 25 times in `push`. A shared connection survives what happens to new ones, so a check that SSH still works after a USB or firewall step uses `--fresh` (`tools/usbc-deadman` always does) |
| `tools/phone-smoke` | Read-only smoke test of a running phone, with a report for the pull request: boot slot, storage guard, root, kernel health, USB, session, then display, GPU, touch, radios, battery, sound, sensors and cameras as evidence. `--here` on the phone, `--json` for a machine |
| `omamobile-update` (on the phone; `omamobile-omarchy`) | What `omarchy update` runs on the phone: Omarchy's own update with the phone's stand-ins (docs/RELEASES.md §5.4). `check --json` is read-only; an update changes the phone's packages and restarts the shell, so it is the human's call |
| `omamobile-omarchy-patches status\|verify\|apply` (on the phone) | The Omarchy patch series: what is applied, already upstream or failed; `apply` re-applies it all or nothing (the pacman hook does this after every Omarchy upgrade). Log: `/var/log/omamobile/omarchy-patches.log` |
| `tools/build-packages`, `tools/build-rootfs` | aarch64 packages (signed, `out/repo`) and the root image, built on the laptop in an Arch Linux ARM container (qemu-user); no phone |
| `tools/install-phone` | The installer: fastboot checks, the owner's answers into a local image copy, then only slot B's images and `userdata`. Asks the human to type the codename; `--dry-run` first. Never run it without the human's go |
| `tools/phone-provision` | After a fresh install: Google's files from the user's factory image and the phone's own data from the backup. `--fingerprint` copies Trusty's state but never starts the service |
| `tools/build-packages`, `tools/repo-push` | Maintainer only: the signed `[omamobile]` repository, built on the laptop with no phone (needs `keys/`, never committed); the release key's layout is in [RELEASES](docs/RELEASES.md) §10 (`tools/release-key-init`, run once); `tools/repo-publish` publishes to `pkgs.omamobile.org` (development daily from `origin/main`, stable on the maintainer's go). `tools/repo-build` builds on a connected phone instead: an opt-in shortcut for Mesa, Hyprland and libcamera, never a requirement |
| `tools/publish-kernel` | Maintainer only: publish `omamobile` to GitHub on a squashed upstream base |

Logs from these tools land in `logs/` (gitignored). Quote the relevant lines in the plan, not whole logs, and check them for identifiers first.

## 4. Gotchas we hit on gs201

Each entry gives the gotcha, then the reason or the fix. Details are in the linked plan.

### Boot chain and device tree

- **ABL ignores the `vendor_boot` cmdline:** put kernel arguments in `/chosen/bootargs`. ABL appends `console=null`, so a panic is invisible: use `panic=10`. [BRINGUP-M1](device/cheetah/BRINGUP-M1.md)
- **ABL leaves both cluster watchdogs running:** the phone resets at about 60 s of uptime unless `s3c2410_wdt` takes them over at probe.
- **ABL picks the base DTB by `soc_id`:** `bin/omamobile images` ships both silicon revisions. It also needs an empty `/ect` node and `/chosen/bootargs`, and applies a DPM overlay that needs label stubs (build with `-@`).
- **`reboot -f` and busybox `reboot` hang:** use `reboot-to <reason>` (`LINUX_REBOOT_CMD_RESTART2`). ABL often ignores the `bootloader` reason anyway.
- **Reserved memory on gs201 is `#address-cells = <2>`, `#size-cells = <1>`,** so each `reg`/`alloc-ranges` entry is 12 bytes. A 16-byte value is silently ignored, and the pool lands anywhere. The display pool's `alignment` must be two cells too, or `of_reserved_mem` rejects it. `/proc/device-tree` shows the raw property, so it *looks* right. [WIFI-BATTERY-PLAN](device/cheetah/WIFI-BATTERY-PLAN.md) 9.x, [NOTES](device/cheetah/NOTES.md)
- **Check every stock `reserved-memory` region against `/proc/iomem`:** five were plain System RAM in our kernel, and firmware writes into them at runtime.
- **Don't make a driver depend on device-tree node order.** The AoC sound card numbered its PCMs in DAI link order, and the PCM number is the AoC entry point ID. Rewriting the overlay's node order changed nothing on the phone (`fdtoverlay` in our tree kept the source order), so the card driver now sorts its links by link id itself. [AOC-PLAN](device/cheetah/AOC-PLAN.md) C7d-5
- **gs201 EINT numbering skips EINT19:** from EINT20 the GIC SPI is the EINT number minus one. gs201 SPIs differ from gs101's, so never copy IRQ numbers.
- **USI IPCLK gates need `CLK_SET_RATE_PARENT`:** without it, SPI ran from the undivided 400 MHz source and never shifted a byte.

### Registers that abort the SoC

- **PMU G3D (`0x18061e00`-`0x18062010`) from `/dev/mem`:** an immediate crash. [GPU-PLAN](device/cheetah/GPU-PLAN.md)
- **The AoC PCU (`0x19a00000`) while the AoC's A32 is in reset:** an abort. Also never read the AoC carve-out after the firmware is loaded: it is locked. [AOC-PLAN](device/cheetah/AOC-PLAN.md)
- **The modem's BAR space (0x40000000-0x405fffff) while CPIF has the link powered down:** a read hangs the SoC (watchdog reset, no pstore). From M4.1h the modem idles its link on its own, so it can go down between any check and the access. Never mmap `resource*` or `devmem` it; use CPIF's own read paths. Config space (`lspci`, `setpci`) is guarded and safe. [MODEM-PLAN](device/cheetah/MODEM-PLAN.md) section 4
- **PCIe ELBI while the PHY is isolated:** the SoC hangs. Reading HSI2 SysMMU/S2MPU register groups can hang it too: raise the probe one group per run. [MODEM-PLAN](device/cheetah/MODEM-PLAN.md), [WIFI-BATTERY-PLAN](device/cheetah/WIFI-BATTERY-PLAN.md)
- **gs101's GSA pin controller (`17940000`, `pinctrl_gsactrl`; also `17a80000`, gsacore):** it belongs to the secure world, and a read from Linux raises a synchronous external abort (`samsung_pinconf_rw`); the reader dies holding the bank's lock, which can hang the phone later. So never list `/sys/kernel/debug/pinctrl/*/pins` or `pinconf-pins` for every controller at once on gs101: read one controller you need, and reboot after an abort. Every other controller, HSI1 included, reads cleanly. [raven MODEM-PLAN](device/raven/MODEM-PLAN.md) section 3

### Display

- **Google's DPP format codes are named by byte order:** DRM `XRGB8888` is DPP code 4. Code 7 gives a green screen. [DISPLAY-PLAN](device/cheetah/DISPLAY-PLAN.md)
- **The panel is DSI command mode:** a frame goes out only on a TE-triggered DECON trigger. The initramfs unmasks `TRIG_CON` for simplefb from that device's `SIMPLEFB_TRIG_CON`, packed only into its initramfs. The init writes the pair only when the board's first compatible string matches the descriptor's `COMPATIBLE`. Never put another phone's address in a descriptor.
- **A CRTC check must not demand a primary plane on a CRTC being turned off,** or DPMS off and `remove_fb` fail with -EINVAL.
- **Hyprland refused DPMS commits while a flip was in flight,** and gave up after one retry. Our `packages/hyprland` patch keeps retrying. [packages/hyprland/README.md](packages/hyprland/README.md)
- **With the panel really off (gs-decon `screen_off=2`), Omarchy's key handling broke:** `key_press_enables_dpms` lit the screen on the power key's press, so its release turned it off again, and Omarchy's lock waits for a lit screen, so locking after power-off lit the PIN pad. `omamobile-shell` 0.1.20 wakes only through `omamobile-keys` (and touch), and locks behind a zero backlight before powering the panel off.
- **Hyprland 0.56 on Omarchy uses the Lua config,** so dispatchers take Lua syntax: `hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'` (or `"enable"`), not `dpms off`.

### Buses and drivers

- **Exynos HSI2C gave every message a fixed 100 ms timeout:** large writes (the 20 KiB CS40L26 firmware block) timed out. Fixed by scaling the timeout with the message length in `i2c-exynos5`.
- **`cs_dsp_coeff_write_ctrl()` returns 1 for "changed":** that is not an error. cs_dsp's write sequence treated it as one.
- **regmap takes `max_raw_write` from the bus, not the config, when the map has a bus:** capping it in the driver's `regmap_config` did nothing. The fix belonged in the I2C host.
- **The HSI2 SysMMU and S2MPU select by VID, and PCIe (AxID 0x0) and UFS (AxID 0x2) both arrive on VID 0:** translating VID 0 starved storage and wedged the phone. Wi-Fi ships with a restricted DMA pool instead, and the driver refuses VID 0. [WIFI-BATTERY-PLAN](device/cheetah/WIFI-BATTERY-PLAN.md) W4
- **ACPM reads its channel table from APM SRAM, and some channels are unusable** (a type-2 buffer channel with queues in DRAM): skip them rather than failing the probe. DVFS is channel 0, PMIC 2, thermal 9. Upstream supports polling only. [ACPM-PLAN](device/cheetah/ACPM-PLAN.md)
- **The regulator core turns off unused rails that have constraints about 30 s after late init:** load PMIC regulator modules after that, or make sure the rails are claimed. [GNSS-PLAN](device/cheetah/GNSS-PLAN.md)
- **The AoC starts only through Trusty** (`com.android.trusty.gsa.hwmgr.aoc`). The GSA mailbox `START` leaves the A32 held. So Trusty is a dependency of audio and sensors, not just of fingerprint, and it runs at every boot on the integration kernel.
- **Fingerprint: nothing writes `persist` or the RPMB without the human's explicit go.** The first `storageproxyd` run (FINGERPRINT-PLAN F4) is irreversible, and `omamobile-fp.service` ships disabled because its first run writes Trusty's secure storage. [FINGERPRINT-PLAN](device/cheetah/FINGERPRINT-PLAN.md)
- **Set the Bluetooth address only after powering the controller on:** set on a never-powered controller, the kernel withdrew the index for good.
- **Samsung pinctrl takes pin groups only at its own probe:** groups added later by a runtime overlay are refused ("invalid function … in map table"), so a driver's pin states belong in the base DT even when its node comes from an overlay. [tegu MODEM-PLAN](device/tegu/MODEM-PLAN.md) M2.0
- **On tegu, ABL leaves every GPA5 pin pulled down, and that hides the modem's cp2ap lines:** with the pull-down nothing rose for 10 s after power-on; with stock's pulls (wakeup up, phone-active and ps-hold floating, in the base DT) they rise within 0.5 s. Check a line's pull before blaming the device that drives it. [tegu FAR-ALIVE-PLAN](device/tegu/FAR-ALIVE-PLAN.md)
- **brcmfmac on BCM4389 needs control-ring D3 messages:** this firmware ignores the TCM mailbox, so early suspend tests ran with Wi-Fi unloaded. The D3 series on `omamobile-int` sends the D3 inform as a control message, and Wi-Fi now stays connected across s2idle (S5b-3; S5c, 31 of 31 freezes, 2026-10-19). The sleep hook (`omamobile-sleep` in device-cheetah) keeps Wi-Fi loaded when `/etc/omamobile/wifi-keep-across-sleep` exists (set on the reference phone since S5c), and otherwise unloads it; after a failed D3 handshake it falls back to unloading for the rest of the boot. Wi-Fi can't wake the phone (no host-wake consumer). [SUSPEND-PLAN](device/cheetah/SUSPEND-PLAN.md) S5

### AoC (audio and sensor DSP)

- **The AoC starts at boot from `omamobile-aoc.service`** (device-cheetah 0.1.19+), and the sensor proxy with it. Start it through the unit (`systemctl start omamobile-aoc`), never by running `omamobile-aoc-start` by hand: units that `Require=` it then saw it inactive and ran the script again, which wrote `aoc.bin` to a running AoC, took it offline and left it down until a reboot. The script now exits when the AoC is online, and a marker in `/run/omamobile/` records the firmware load for the boot.
- **The AoC modules are blacklisted and the start script loads them in order,** with `aoc_channel_dev` and `aoc_alsa_dev` before `aoc_char_dev`. `aoc_char_dev` takes every free service, so a sound card loaded after it waited forever for `audio_output_control`. `aoc_alsa_dev` is blacklisted too, because autoloading from the card's DT node pulled `aoc_core`, `gsa` and Trusty in early and left `aoc_core` unbound.
- **Never `rmmod` the AoC modules on the current kernel.** Unloading them while `aoc_core` waited for deferred probe left `aoc_alsa_dev_util`'s platform drivers on the bus in freed memory: the deferred-probe worker oopsed, and its device lock hung every later shutdown in `device_shutdown`, past the reboot watchdog, until a held power key. A fix is on the `omamobile-aoc` branch; until the phone runs a kernel with it, reboot instead.
- **To learn why the AoC rejects a command, read its own log** (`/dev/acd-logging`, or `AOCLOG=1` in `tools/aoc-audio-diag`). The AoC answers a rejected command with rc -1, which the driver doesn't treat as an error, so from the kernel side everything looks accepted and nothing plays.
- **The ALSA PCM device number is the AoC entry point ID** (`entry_point_idx = pcm->device` in Google's driver). The card's PCMs must be numbered as on stock (EP1-EP8 playback 0-7, EP1-EP6 capture 8-13), or the AoC configures the wrong entry point and refuses it. The card driver now sorts its links into that order and refuses a PCM whose number doesn't match its link. Scripts and UCM still find a PCM by its `id:` (`EP6 playback`, `EP1 capture`) rather than by number. [AOC-PLAN](device/cheetah/AOC-PLAN.md) C7d
- **The I3C accelerometer went missing after a warm reboot while the I2C sensors (light, proximity, compass) came up.** The sensor rails stay powered across a warm reboot, and the LSM6DSV then keeps the previous AoC session's state, so the new AoC never finds it; the I2C sensors don't care. The AoC probes its sensors once, when the registry loads, so restarting the proxy doesn't help, and neither did waiting longer. Google's driver power-cycles these rails around an AoC restart; device-cheetah 0.1.22 does the same (`gs201_aoc_rails cycle=1`, 150 ms off), and all four sensors now appear at every boot. Keep `cycle=1` if you touch the start script. [AOC-PLAN](device/cheetah/AOC-PLAN.md) C6
- **Set the AoC's TDM 0 back end to stock's format (`TDM_0_RX`/`TDM_0_TX` Four, S32_LE, SR_48K) before playing.** At the driver default (S16_LE stereo) the amplifiers' slot width doesn't match the AoC's 32-bit slots, and the bottom CS35L41 never powered up. Stock maps left to the top speaker (slot 0) and right to the bottom (slot 1). `omamobile-audio`'s UCM profile sets this.
- **A DPCM front end with no back end routed fails at prepare,** and PipeWire opens every PCM while it probes, so the UCM verb must set the routes before PipeWire sees the card.
- **Never read a CS35L41's whole regmap `registers` file while its DSP runs.** The file continues past the amplifier registers into the DSP's memories and core registers (readable and volatile), and reading them during playback stopped the protection algorithm: the firmware still answered and audio still played, unprotected. Stop at 0x10100, as `tools/aoc-*-diag` do, or read single controls. `systemctl restart omamobile-speaker-protection` resets a frozen DSP. [AOC-PLAN](device/cheetah/AOC-PLAN.md) C9a
- **Never route `TDM_0_TX` (the amplifiers' VMON/IMON return) into an entry-point capture** (`EP5 TX Mixer TDM_0_TX` or `EP6 …` on, then a capture of PCM 12/13): the AoC's watchdog fires, the AoC goes offline and every audio service answers -517 until a reboot. The hostless PCM 15 is the only consumer of that path and delivers nothing to the host. [AOC-PLAN](device/cheetah/AOC-PLAN.md) C9j
- **The amplifiers' boost converter distorts at the everyday level.** At analog 10 and below it runs in its light-load regime, droops and distorts both speakers (10-50 % THD on a 1 kHz tone, heard as static) and takes 8-11 dB off the output; by our reading stock's 817/17 never runs it there. `omamobile-audio` 0.5.3 turns it off there through the cs35l41 `boost_en` bring-up parameter ("ASoC: cs35l41: bring-up option to run without the boost converter", on `omamobile-audio-amp`) and keeps it on at 17. [AOC-PLAN](device/cheetah/AOC-PLAN.md) C9j
- **Speakers: stay under the stage's volume ceilings.** `omamobile-audio` 0.3.0's default is stage `media`, digital 737 and analog 10 on both amplifiers: inside the no-protection limits, about 17 dB below stock. Stock's 817/17 (stage c9) needs `speaker_protection=1` and verified protection: the protection firmware only measures the coil (`vmon low` 0) at the analog gain its tuning expects (17), and at 817/10 it read a false 80 °C. Never commit the factory speaker calibration; it is unique to one phone. `omamobile-audio` blacklists the amplifier driver so that only its protection service loads it, muted until the calibration is written and read back. [AOC-PLAN](device/cheetah/AOC-PLAN.md) C7-C9

### Suspend and modem

- **On the 9a, NFC must not poll through s2idle.** A suspend with neard polling reset the palmtop (2026-10-27); with polling stopped, 35 s2idle cycles with RTC wakes that day all woke. The cause isn't known: nxp-nci has no PM callbacks, but neither does the 7 Pro's st-nci, so the controller's interrupt or the I2C bus during the freeze are the next suspects. A sleep hook on the palmtop, `omamobile-tegu-nfc` (not in the repository yet; it comes with tegu's device package), stops neard's poll loop before a systemd sleep and restarts it after; a sleep written straight to `/sys/power/state` (`rtcwake -m mem`) skips the hook, so stop polling by hand first. [tegu MODEM-PLAN](device/tegu/MODEM-PLAN.md) "Suspend with the modem on"
- **UFS must be at `spm_lvl` 5 in system suspend.** At the core default 3, UFS failed its first hibern8 exit on resume and needed a host reset (it recovered, no I/O errors); at 5 the first real s2idle freeze resumed clean. gs201 now defaults to 5 in the kernel (S3a, `a7e5e1d95`), so a suspend test only checks that `spm_lvl` reads 5; on a kernel without that commit, `echo 5` first. [SUSPEND-PLAN](device/cheetah/SUSPEND-PLAN.md) S1-S3
- **Only s2idle, never `deep`.** The firmware advertises PSCI SYSTEM_SUSPEND, so mainline offers `deep`, but Linux has no gs201 SoC sleep sequence (SYS_SLEEP), and the phone wouldn't wake. `mem_sleep_default=s2idle` in the bootargs and device-cheetah's `sleep.conf` drop-in keep it on s2idle. [SUSPEND-PLAN](device/cheetah/SUSPEND-PLAN.md) §1, §5
- **Some unattended RTC cycles wake early on the PMIC interrupt** (2 of 20 in S4, 4 of 31 in S5c, at 13-16 s instead of 30 s). Which PMIC event it is hasn't been read yet; count it, don't treat it as a failed cycle. [SUSPEND-PLAN](device/cheetah/SUSPEND-PLAN.md) S4, S5c
- **Volume Up is the one key without an internal pull** (`PUD` 0x0, as on stock), and the first freeze woke 3 s in from it with nobody touching it. It didn't recur in the 51 RTC cycles of S4 and S5c, and it isn't proven to be a false edge; if spurious wakes recur, check gpa8-5's power-down pull before blaming the wake path.
- **UFS ran its error handler around modem power changes** (PA LINERESET indications, recovered without a reset). Stock's DT shows no shared rail, clock or pin. M2.5 narrowed it down: power-on and a running link are clean, but every modem power-off is followed by one recovered UFS error-handler pass (a PA LINERESET, no I/O errors or resets). Stock powers the modem off only at shutdown, so the modem stays on once it is up (M2.6 is open), and a reboot with the modem up costs one such pass. Keep modem tests attended, don't power-cycle the modem, and check `dmesg | grep ufshcd_err_handler` after each step. [MODEM-PLAN](device/cheetah/MODEM-PLAN.md) M2, M2.5, M2.6
- **Suspend with the modem on has never run on the 7 Pro, and is unqualified on the 9a**: its one try (2026-10-27) also had NFC polling, which alone resets the 9a in s2idle, so the modem's part is unknown. CPIF's PM paths are wake-armed in code, but M6 is design only and no SIM test has happened (M4.2). Keep modem tests on the charger, so upower's critical action doesn't suspend the phone mid-test. [MODEM-PLAN](device/cheetah/MODEM-PLAN.md) 6.3, [tegu MODEM-PLAN](device/tegu/MODEM-PLAN.md) "Suspend with the modem on"
- **Never `systemctl restart omamobile-modem` (or stop and start it) to recover a crashed modem.** An in-place restart left raven's CP in BOOTING, and a bring-up that never reaches ONLINE sets a latch that makes the next boot skip the modem. Reboot instead. If a boot skipped it, remove the latch (`rm /var/lib/omamobile/modem-bringup-started`) and `systemctl start omamobile-modem`; `/usr/lib/omamobile-vendor/omamobile-modem-start --retry` also clears it, but run by hand it brings the modem up outside the unit (a stray `rfsd` in your shell's session). [raven MODEM-PLAN](device/raven/MODEM-PLAN.md) D4
- **Linux never writes the modem's NV.** The modem chroot profile (cbd, rfsd) refuses to start unless the NV partitions read `ro=1` and none is mounted, works on checksum-verified RAM copies only, and loses what the modem writes at stop. Don't give the chroot a real block device.

### USB

- **The MAX77759 opens the USB2 data switch on unplug, and nothing closes it until a Type-C driver owns the chip:** the phone stays off the bus after a replug. `omamobile-usb-rescue` closes it while VBUS is valid. Tegu's MAX77779 does the same (`USBSW_CTRL` 0x09 to 0x00 on unplug, reported on kernel #40), so expect it on every Tensor phone until its Type-C driver lands. Tests that need the cable out (`power-ab`) must run detached and must not assume USB comes back. [USB-C-PLAN](device/cheetah/USB-C-PLAN.md)
- **USB doesn't come back after `kexec`.**
- **PID 1 must never exit:** a missing busybox applet once made init exit, and the resulting panic looked like a USB fault because of `console=null`.

### Userspace

- **`grep -q` under `set -o pipefail`:** `grep -q` exits early, SIGPIPEs the writer, and the pipeline fails on large input. Use `grep -c … >/dev/null`.
- **Omarchy's Chromium launcher splits each line of `chromium-flags.conf` on spaces:** quote a flag whose value has spaces (`"--user-agent=…"`).
- **Chromium needs `--force-device-scale-factor` on the phone,** even with the mobile user agent: its window layout won't go below about 500 px and the panel is 480 px wide in logical pixels, so without it the window runs off the right edge. Sites get phone layouts from the user agent.
- **The screensaver runs in a terminal, so focusing it pops up the on-screen keyboard:** `patches/omarchy/0006-*` turns `org.gnome.desktop.a11y.applications screen-keyboard-enabled` off for the screensaver and back on afterwards (from an EXIT trap in the launcher, since omamobile-omarchy 0.1.9), and `omamobile-osk-guard` (omamobile-shell 0.2.19) turns it back on whenever it is off with no screensaver running. If the keyboard stops appearing, check that key first.
- **Vendor chroots:** bootstrap binaries such as `servicemanager` use `/system/bin/bootstrap/linker64` as their interpreter. `extract-vendor-chroot` links it to the runtime APEX linker. Run the chroot by path, without `env chroot`.
- **Quickshell plugins:**
  - live reload can keep the old code, so run `omarchy-restart-shell`;
  - pointer handlers declared directly on a window get no events, so put them on an Item inside it;
  - Qt 6.12's `QtQuick/Color` shadows Omarchy's `Commons.Color`, so import `qs.Commons as Commons`.
- **pacman.conf order on aarch64:** `[omamobile]`, then `[omarchy]`, then Arch Linux ARM's repositories, so our Mesa and Omarchy's builds win. Use `omarchy update`, not `pacman -Syu`: on the phone it hands over to `omamobile-update` (patch 0012), which refuses a wrong order, low battery or a kernel/bootloader package, skips Snapper, the AUR and gum prompts, and holds boot-related migrations ([RELEASES](docs/RELEASES.md) §5.4).
- **Omarchy upgrades overwrite our Omarchy patches;** `omamobile-omarchy`'s pacman hook puts them back (all or nothing, from Omarchy's own files). Edit the series in `packages/omamobile-omarchy/patches` (`patches/omarchy` links there), bump that package's version, and make every patch apply with `--fuzz=0` on the Omarchy the phone runs: `packages/omamobile-omarchy/test/all` applies it to the real aarch64 package. A patch Omarchy has absorbed is reported as upstream: drop it.
- **`environment.d` can't unset a variable:** `VAR=` with an empty value is a syntax error, and the generator skips the line silently, so the old value stays. Set an explicit value instead (`omamobile-shell` uses `none`).
- **GeoClue answers no client until an authorization agent is registered for the caller's user,** and queues the call with no timeout, so every client just times out. `omamobile-gnss` runs GeoClue's demo agent as a user unit; app allow-list entries skip only the agent's question, not the agent.
- **Firewall changes** (ufw is on): arm `systemd-run --on-active=90 /usr/bin/ufw disable` first, then check with a fresh SSH connection (`tools/phone-ssh --fresh`).

## 5. Where things are

| Path | What |
| --- | --- |
| `device/cheetah/NOTES.md` | Findings from real hardware, newest first |
| `device/cheetah/*-PLAN.md`, `*-RESEARCH.md` | One plan per subsystem: facts, design, gated runbook, results |
| `device/cheetah/overlays/*.dtso` | Bring-up overlays that turn on disabled nodes |
| `initramfs/init` | Storage guard, USB gadget, SSH, switch to Arch |
| `kernel/configs/omamobile.config` | Config fragment on top of arm64 `defconfig`, commented by plan |
| `packages/omamobile-device-cheetah` | Boot-success marker, Wi-Fi and AoC start scripts, udev, modprobe and systemd policy |
| `packages/omamobile-shell`, `-sensors`, `-gnss`, `-audio`, `-fingerprint`, `-modem` (chroot profile), `libfprint`, `neard`, `mesa`, `hyprland`, `omamobile-keyring` | Userspace packages |
| `packages/omamobile-omarchy/patches/` (`patches/omarchy/` links there) | Omarchy changes waiting to land upstream, re-applied after every Omarchy upgrade |
| `docs/DEVICES.md` | Supported-devices matrix |
| `~/android/mainline/wt-*`, `out-*` | Kernel worktrees and build outputs (outside the repo) |
| `~/android/reference/` | Stock captures and partition backups: private, never committed |
