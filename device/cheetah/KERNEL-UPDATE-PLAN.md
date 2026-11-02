<!-- SPDX-License-Identifier: MIT -->
# Kernel updates through pacman on the Pixel 7 Pro

Status (2026-11-02): **passed on the reference phone** (§4), merged as #320 ( `packages/linux-omamobile`, `packages/omamobile-boot-update`, `omamobile-device-cheetah` 0.1.38 with its boot files, `omamobile-omarchy` 0.1.28, `omamobile-shell` 0.2.76, `tools/stage-boot-files`, `bin/omamobile kernel --release`). This plan is the first attended run on the reference phone: [RELEASES](../../docs/RELEASES.md) §12 decision 10 ("install, a package-hook kernel update, a reboot into it") and checklist step 6, plus a rollback. The design is RELEASES §4, §4.1, §5.3 and §5.5; the tool's own page is [packages/omamobile-boot-update/README.md](../../packages/omamobile-boot-update/README.md).

No kernel branch: the kernel is the published release tag `kernel-2026.11.01`, built in its own worktree and output directory (`~/omamobile-kernel/wt-pkgtest`, `~/omamobile-kernel/out-pkgtest`), so nobody else's build is touched.

## 1. What is new on the phone, and what it can touch

- `linux-omamobile` puts a kernel release under `/usr/lib/modules/<release>/` (vmlinuz, modules, DTBs). Root file system only.
- `omamobile-boot-update` builds slot B's images from it on the phone and writes `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b` and `dtbo_b`, and nothing else: each found by GPT name on `sda`, on the storage guard's allowlist, `ro` 0, every image read back by sha256. Its pacman hook writes only with `/etc/omamobile/boot-update.conf` saying `AUTO_WRITE=yes`; the reference phone, a development phone, has no such file until step 6.
- Before each write it saves slot B's five partitions, whole, and the running release's modules in `/var/lib/omamobile/boot/previous/` (about 220 MB on cheetah plus one module tree); `omamobile-boot-update rollback` writes them back.
- It never reboots, never touches slot A, `vbmeta`, `devinfo` or the bootloader, never changes the storage guard.

**Recovery when slot B doesn't boot.** `omamobile-boot-success` marks slot B successful at every good boot, so ABL does **not** fall back to slot A after a bad write: the phone stops in fastboot or keeps resetting, and `previous/` on `userdata` is out of reach. So the fallback lives on the laptop: step R2 copies the set slot B holds today into `~/omamobile-kernel/known-good/2026-11-02/images/` (with its `DEVICE` file) and checks the copy against the phone, and P3 also copies `previous/` off the phone before any reboot. Never flash from `~/omamobile-kernel/out-release`: other tools build into it (`tools/release build` writes the release kernel there). Then: Power held about 30 s, then Volume Down + Power about 20 s for fastboot, and on the laptop `KERNEL_OUT=~/omamobile-kernel/known-good/2026-11-02 bin/omamobile flash`. On the recovery screen of a stock boot choose neither option (AGENTS §4); a stock boot means a fresh read-only backup of `efs`, `persist` and `modem_userdata` afterwards.

## 2. Why the running kernel can't be packaged as it is

The phone runs `7.3.0-rc6-omamobile-push1-g2219cc6cda77` from `~/omamobile-kernel/out-release`. `linux-omamobile` refuses `-push1` builds on purpose (RELEASES §4: a development kernel can never pass for a packaged one), so the package is built from the same source in release mode: the published tag `kernel-2026.11.01` with `CONFIG_LOCALVERSION="-omamobile"` (`bin/omamobile kernel --release`). Cheetah has no `device/cheetah/kernel.config`, so the release build's configuration differs from `out-release`'s only in `LOCALVERSION`; its `uname -r` is `7.3.0-rc6-omamobile-g<sha12>` and its modules live in their own directory, beside the push1 tree, which stays for the rollback.

## 3. Runbook

Read-only steps first. Each step: commands, Expect, Pass, **Stop**, Rollback, risk. Laptop steps run in this repository's checkout of the branch (`cd <repo>`); phone steps over `tools/phone-ssh` (root). Record results in §4 with the date and `uname -r`. Announce to Derek before every step marked "affects the phone" and before both reboots.

### L1. Build the release kernel from the tag (laptop, no phone; risk none)

```sh
tools/fetch-toolchain                       # the pinned clang, mkbootimg, mkdtboimg, avbtool and test key (decision 2)
git -C ~/omamobile-kernel/linux rev-parse 'kernel-2026.11.01^{commit}'   # expect 2219cc6cda77...
git -C ~/omamobile-kernel/linux worktree add ~/omamobile-kernel/wt-pkgtest kernel-2026.11.01
export KERNEL_DIR=~/omamobile-kernel/wt-pkgtest KERNEL_OUT=~/omamobile-kernel/out-pkgtest
bin/omamobile kernel --release && bin/omamobile modules
cat $KERNEL_OUT/include/config/kernel.release
diff <(grep -v LOCALVERSION ~/omamobile-kernel/out-release/.config) <(grep -v LOCALVERSION $KERNEL_OUT/.config)
```

- Expect: the tag's commit is `2219cc6cda77` (the running kernel's); `kernel.release` is `7.3.0-rc6-omamobile-g2219cc6cda77`; the configuration diff is empty; `$KERNEL_OUT/toolchain.txt` names the pinned clang (`clang-r596125`, the compiler of every phone kernel so far).
- Pass: all three. **Stop:** another commit (then the test kernel is not the running one: ask Derek), `-dirty`, or a configuration difference beyond `LOCALVERSION`.
- Rollback: `git -C ~/omamobile-kernel/linux worktree remove ~/omamobile-kernel/wt-pkgtest`.

### L2. The device's boot files and the packages (laptop, no phone; risk none)

```sh
DEVICE=cheetah bin/omamobile initramfs --release            # into $KERNEL_OUT, no builder keys
DEVICE=cheetah tools/stage-boot-files                       # -> packages/omamobile-device-cheetah/boot-files/
packages/linux-omamobile/stage $KERNEL_OUT                  # KERNEL_DIR gives the commit count
tools/local-key-init cheetah                                # once; a local key, never the release key
tools/build-packages --local cheetah packages/omamobile-boot-update packages/linux-omamobile \
  packages/omamobile-device-cheetah packages/omamobile-omarchy packages/omamobile-shell
ls out/cheetah/repo/aarch64/
```

- Expect: `stage-boot-files` lists `device.conf`, `dtbo.img`, `initramfs.cpio.lz4` and the 15 overlays of `DTB_OVERLAYS`; `stage` prints `pkgver 7.3.0rc6.r<n>.g2219cc6cda77`; five packages built, each `test/all` passing.
- Pass: as expected. **Stop:** any refusal (keys in the initramfs, another allowlist, a test failing).
- Rollback: nothing on the phone; `rm -rf packages/*/prebuilt packages/*/boot-files out/cheetah`.
- `stage` takes only a published release tag on `omamobile` (it checks GitHub), and `tools/build-packages` builds `linux-omamobile` only when named, so the staged `prebuilt/` never reaches the daily publish. `boot-files/` does: once this branch is on `main`, `tools/repo-publish --from-main` builds `omamobile-device-cheetah` 0.1.38 from the `boot-files/` of the checkout it runs in (after `tools/stage-boot-files --check` against `main`), and refuses to build it without them. Stage them in that checkout before the first daily publish after the merge.
- The `--local` repository is signed with the local key only and is never published; the phone takes the files with `pacman -U` (`LocalFileSigLevel = Optional`).

### R1. The phone as it is (read-only; risk none)

```sh
tools/phone-ssh 'uname -r; grep slot_suffix /proc/bootconfig; cat /proc/cmdline | tr " " "\n" | grep slot_suffix; pacman -Q omamobile-device-cheetah omamobile-omarchy omamobile-shell
  ls /etc/omamobile/boot-update.conf 2>&1; test -s /root/.ssh/authorized_keys && echo root-keys-ok
  df -h /var | tail -1; cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1
  for s in /sys/block/sda/sda*; do n=$(sed -n "s/^PARTNAME=//p" $s/uevent); case $n in *_b|userdata) echo "$n ${s##*/} ro=$(cat $s/ro) $(( $(cat $s/size) * 512 ))";; esac; done'
```

- Expect: the push1 release; `androidboot.slot_suffix = "_b"` in `/proc/bootconfig` (or `_b` on the command line: the tool refuses a boot that names no slot); no `boot-update.conf`; `root-keys-ok` (the hook appends these keys to the release initramfs, so SSH into the initramfs keeps working); at least 1 GB free in `/var`; battery 30% or more, or the charger in; the five `_b` partitions and `userdata` with `ro=0`, every other `_b` partition `ro=1`.
- Pass: all of it. **Stop:** no slot named in either place (the hook would refuse; find out why first), no root keys (add Derek's key first, or the initramfs has no SSH), less space, `ro=0` anywhere else.
- Rollback: none.

### R2. Slot B today, and the laptop's known-good copy of it (read-only on the phone; risk none)

```sh
KG=~/omamobile-kernel/known-good/2026-11-02
mkdir -p $KG/images && cp ~/omamobile-kernel/out-release/images/{boot,init_boot,vendor_boot,vendor_kernel_boot,dtbo}.img ~/omamobile-kernel/out-release/images/DEVICE $KG/images/
(cd $KG/images && sha256sum *.img > SHA256SUMS)
tools/phone-ssh 'for p in boot init_boot vendor_boot vendor_kernel_boot dtbo; do s=$(for s in /sys/block/sda/sda*; do grep -qx PARTNAME=${p}_b $s/uevent && echo ${s##*/}; done); echo "$p $s"; done' > logs/kernel-update-slotb.txt
for p in boot init_boot vendor_boot vendor_kernel_boot dtbo; do
  f=$KG/images/$p.img; n=$(awk -v p=$p '$1 == p {print $2}' logs/kernel-update-slotb.txt)
  echo "$p laptop $(sha256sum < $f | cut -c1-16) phone $(tools/phone-ssh "head -c $(stat -c %s $f) /dev/$n | sha256sum" | cut -c1-16)"
done
cat $KG/images/DEVICE
```

- Expect: each pair of checksums equal: `$KG/images` is exactly slot B, the fallback for `KERNEL_OUT=$KG bin/omamobile flash`; `DEVICE` says `cheetah`. The copy stays put whatever is built into `out-release` later; every later step's fastboot route flashes from `$KG`.
- Pass: five equal pairs. **Stop:** any difference: find or rebuild the set slot B holds before going on (without it there is no known-good set to flash by fastboot).
- Rollback: none (the copy is kept as the fallback; it can be removed after P6).

### P1. Install the packages, hook off (affects the phone: root file system only; risk low)

```sh
tools/phone-ssh 'mkdir -p /var/cache/omamobile-test'
scp out/cheetah/repo/aarch64/{omamobile-boot-update,omamobile-device-cheetah,omamobile-omarchy,omamobile-shell,linux-omamobile}-*.pkg.tar.zst root@172.16.42.1:/var/cache/omamobile-test/
tools/phone-ssh 'cd /var/cache/omamobile-test && pacman -U --noconfirm omamobile-boot-update-*.pkg.tar.zst omamobile-device-cheetah-*.pkg.tar.zst omamobile-omarchy-*.pkg.tar.zst omamobile-shell-*.pkg.tar.zst'
tools/phone-ssh 'cd /var/cache/omamobile-test && pacman -U --noconfirm linux-omamobile-*.pkg.tar.zst'
tools/phone-ssh 'r=$(ls -d /usr/lib/modules/*-omamobile-g*); ls $r/vmlinuz $r/modules.dep $r/modules.dep.bin $r/dtbs/exynos/google/gs201-cheetah.dtb; ls /usr/lib/omamobile/cheetah/'
```

- Expect: both transactions end with "Slot B left alone: AUTO_WRITE is not yes"; the new release has `vmlinuz`, depmod's files and the DTB; `/usr/lib/omamobile/cheetah/` holds `dtbo.img`, `initramfs.cpio.lz4` and `overlays/`. The running shell keeps its loaded plugins until `omarchy-restart-shell` or the next login (P4's reboot).
- Pass: as expected, and R2's phone checksums unchanged (rerun R2: slot B untouched).
- **Stop:** the hook writes anything, or slot B's checksums change.
- Rollback: `pacman -R linux-omamobile omamobile-boot-update` and reinstall the previous device, omarchy and shell packages from `/var/cache/pacman/pkg`.

### P2. Read-only checks of the tool (risk none)

```sh
tools/phone-ssh 'omamobile-boot-update status; omamobile-boot-update preflight --json; sudo omamobile-boot-update write --dry-run'
```

- Expect: `preflight` `{"auto_write": "no", "ok": true, ...}`; the dry run builds the images for `7.3.0-rc6-omamobile-g2219cc6cda77` and plans `boot.img` and `vendor_kernel_boot.img` as "write" (new kernel, new initramfs), `init_boot.img`, `vendor_boot.img` and `dtbo.img` as "already there" (the same bytes as `bin/omamobile images` made: the parity test's claim, now on the phone), then "Dry run: nothing written".
- Pass: as expected, and no `/var/lib/omamobile/boot` or `/run/omamobile/boot-update.json` afterwards.
- **Stop:** any refusal (note it; fix offline), or `init_boot`/`vendor_boot`/`dtbo` planned as "write" (the phone builds other bytes than the laptop: find out why before writing).
- Rollback: none.

### P3. The package-hook write (affects slot B; risk medium)

Battery 30% or more, or the charger in. R2's fallback set confirmed.

```sh
tools/phone-ssh 'printf "AUTO_WRITE=yes\n" > /etc/omamobile/boot-update.conf
  pacman -U --noconfirm /var/cache/omamobile-test/linux-omamobile-*.pkg.tar.zst'
tools/phone-ssh 'omamobile-boot-update status; cat /var/lib/omamobile/boot/current/SHA256SUMS; ls /var/lib/omamobile/boot/previous; cat /run/omamobile/boot-update.json'
scp -r root@172.16.42.1:/var/lib/omamobile/boot/previous ~/omamobile-kernel/known-good/2026-11-02/previous
(cd ~/omamobile-kernel/known-good/2026-11-02/previous && sha256sum -c SHA256SUMS)
```

- Expect: the reinstall runs the hook: plan, "Saving slot B (7.3.0-rc6-omamobile-push1-g2219cc6cda77)", `boot_b` and `vendor_kernel_boot_b` "written and verified", "Restart the phone to boot it"; `previous/` holds five images, `RELEASE` the push1 release, `BOOTED` yes and its modules; the result is `written`.
- Pass: as expected, the partitions' leading bytes match `current/SHA256SUMS` (the tool checked; re-check with `head -c | sha256sum` for `boot_b`), and the laptop's copy of `previous/` passes its checksums (its images are R2's set, now also on the laptop; `previous/` on the phone is out of reach if the phone doesn't boot).
- **Stop:** any error. Do **not** reboot; `sudo omamobile-boot-update rollback --dry-run`, then `rollback`, then R2's comparison again (slot B must equal `known-good/2026-11-02/images` before any reboot).
- Rollback: `sudo omamobile-boot-update rollback` (P5), or R2's set by fastboot (`KERNEL_OUT=~/omamobile-kernel/known-good/2026-11-02 bin/omamobile flash`).

### P4. Reboot into the packaged kernel (affects the phone: reboot; risk medium)

```sh
tools/phone-ssh 'systemctl reboot'
# about a minute later
tools/phone-ssh 'uname -r; systemctl --failed --no-legend | head; ls /dev/dri; nmcli -t -f STATE general'
tools/phone-smoke
```

- Expect: `7.3.0-rc6-omamobile-g2219cc6cda77`; the lock screen as usual; GPU (`/dev/dri/renderD128`), Wi-Fi, touch, audio and sensors as before (`tools/phone-smoke`); no new failed units. SSH into the initramfs (if it ever stays there) answers with Derek's key and a new host key.
- Pass: as expected. **Stop:** no SSH after 3 minutes: ask Derek to look at the screen; fastboot by the buttons and R2's set with `KERNEL_OUT=~/omamobile-kernel/known-good/2026-11-02 bin/omamobile flash`.
- Rollback: P5.

### P5. Roll back (affects slot B; risk medium)

```sh
tools/phone-ssh 'rm /etc/omamobile/boot-update.conf; sudo omamobile-boot-update rollback --dry-run'
tools/phone-ssh 'sudo omamobile-boot-update rollback --yes'
```

- Expect: the dry run plans `boot_b` and `vendor_kernel_boot_b` (and nothing else) back to the saved set; the rollback writes and verifies them, finds the push1 modules still in `/usr/lib/modules` (kernel-modules-hook kept them) or restores them, and prints the `IgnorePkg` line. R2's comparison afterwards: slot B equals `known-good/2026-11-02/images` again.
- Pass: R2's five equal pairs. **Stop:** any error or difference: no reboot; fastboot route (`KERNEL_OUT=~/omamobile-kernel/known-good/2026-11-02 bin/omamobile flash`) if slot B can't be made equal to R2's set.
- Rollback: write P3 again (`pacman -U` with `AUTO_WRITE=yes`) if the packaged kernel is wanted back.

### P6. Reboot into the push1 kernel, and tidy up (affects the phone: reboot; risk low)

```sh
tools/phone-ssh 'systemctl reboot'
tools/phone-ssh 'uname -r'; tools/phone-smoke
tools/phone-ssh 'pacman -R --noconfirm linux-omamobile; omamobile-boot-update status'
```

- Expect: `7.3.0-rc6-omamobile-push1-g2219cc6cda77`, everything as in R1; removing `linux-omamobile` runs no hook (removal) and takes only its own module tree. `omamobile-boot-update` and the new device package stay: without `boot-update.conf` the hook leaves slot B to `bin/omamobile push`.
- Pass: as expected. **Stop/Rollback:** as P4.

## 4. Results

**2026-11-02, the reference 7 Pro, attended by Derek. Passed: decision 10 is met.** Release kernel `7.3.0-rc6-omamobile-g2219cc6cda77` from tag `kernel-2026.11.01`. Before and after: `7.3.0-rc6-omamobile-push1-g2219cc6cda77`. Packages from main at `048f9fb3`, built `--local` on the laptop: linux-omamobile `7.3.0rc6.r635.g2219cc6cda77-1`, omamobile-boot-update 0.1.0, device-cheetah 0.1.38, omarchy 0.1.28, shell 0.2.76.

- **L1:** the tag peels to `2219cc6cda77`. `kernel.release` is `7.3.0-rc6-omamobile-g2219cc6cda77`. `toolchain.txt` names `clang-r596125`, pinned. The configuration diff without `LOCALVERSION` is empty.
- **L2:** `stage-boot-files` staged `device.conf`, `dtbo.img`, the initramfs and 15 overlays. `stage` printed pkgver `7.3.0rc6.r635.g2219cc6cda77` (1815 modules, 8 DTBs). Five packages built, each `test/all` passing. Two `error: command failed to execute correctly` lines in the build log are pacman hooks inside the build container; the builds went on.
- **R1:** slot `_b`, no `boot-update.conf`, root keys present, 89 GB free, battery 99%. Only the five slot B boot partitions and `userdata` are `ro=0`.
- **R2:** slot B had changed since this plan was written: the morning's push of the reproducible-initramfs boot test (see #320's phone boot). So the fallback is `~/omamobile-kernel/known-good/2026-11-02b/images`, a copy of that push's set. All five checksums matched the phone.
- **P1:** both `pacman -U` transactions ended with "Slot B left alone: AUTO_WRITE is not yes". The release has `vmlinuz`, depmod's files and `gs201-cheetah.dtb`. `/usr/share/omamobile/linux/kernel.release` names it. Slot B still matched R2 on all five images.
- **P2:** `preflight` returned `{"auto_write": "no", "ok": true}`. The dry run planned `boot` and `vendor_kernel_boot` as write. `init_boot`, `vendor_boot` and `dtbo` were "already there": the phone builds the same bytes as `bin/omamobile images` on the laptop. Nothing was written. `/run/omamobile/boot-update.json` held only P1's "skipped" result.
- **P3:** "Saving slot B (…push1-g2219cc6cda77)", then `boot_b` and `vendor_kernel_boot_b` "written and verified". The write counters (field 7) afterwards were sda20 131072 and sda23 13768, and 0 on the other three. `previous/` holds the push1 set, `BOOTED=yes`, and its modules. The laptop copy in `known-good/2026-11-02b/previous` passes `sha256sum -c`.
  - The first copy of `dtbo.img` came back 32 KiB short over SSH and failed the check. Copying it again in 4 MiB pieces passed. This is the same USB NCM stream drop as nv-backup's (REINSTALL-RUNBOOK §4a).
  - The saved images are whole partitions. Their leading bytes equal R2's set.
- **P4:** booted `7.3.0-rc6-omamobile-g2219cc6cda77`, slot `_b`, no failed units, `renderD128` present. The slot B write counters read 0 after the reboot. phone-smoke: every required row ok, and display, GPU, touch, buttons, Wi-Fi, Bluetooth, battery, sound card, sensors and thermal ok. Two rows were not ok:
  - `audio_playback0: ASoC: no backend DAIs` ×1, which is on every boot (#336);
  - cameras at 22 s. libcamera listed all 4 at 41 s.
- **P5:** with `boot-update.conf` removed, the dry run planned `boot` and `vendor_kernel_boot` only. `rollback --yes` wrote them and printed the `IgnorePkg` advice. The push1 modules were still in `/usr/lib/modules`. Slot B matched `known-good/2026-11-02b/images` on all five images.
- **P6:** booted `7.3.0-rc6-omamobile-push1-g2219cc6cda77`, slot `_b`, no failed units. phone-smoke matched P4 (cameras: 4 at 43 s). `pacman -R linux-omamobile` ran only `depmod` and removed only its own module tree. `status` reads auto write no, slot B and previous both push1 (booted: yes). omamobile-boot-update 0.1.0 and device-cheetah 0.1.38 stay installed.
