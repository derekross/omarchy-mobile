<!-- SPDX-License-Identifier: MIT -->
# Kernel updates through pacman on the Pixel 7 Pro

Status (2026-11-01): built and tested offline only (branch `kernel-update-path`: `packages/linux-omamobile`, `packages/omamobile-boot-update`, `omamobile-device-cheetah` 0.1.38 with its boot files, `omamobile-omarchy` 0.1.28, `omamobile-shell` 0.2.76, `tools/stage-boot-files`, `bin/omamobile kernel --release`). This plan is the first attended run on the reference phone: [RELEASES](../../docs/RELEASES.md) §12 decision 10 ("install, a package-hook kernel update, a reboot into it") and checklist step 6, plus a rollback. The design is RELEASES §4, §4.1, §5.3 and §5.5; the tool's own page is [packages/omamobile-boot-update/README.md](../../packages/omamobile-boot-update/README.md).

No kernel branch: the kernel is the published release tag `kernel-2026.11.01`, built in its own worktree and output directory (`~/omamobile-kernel/wt-pkgtest`, `~/omamobile-kernel/out-pkgtest`), so nobody else's build is touched.

## 1. What is new on the phone, and what it can touch

- `linux-omamobile` puts a kernel release under `/usr/lib/modules/<release>/` (vmlinuz, modules, DTBs). Root file system only.
- `omamobile-boot-update` builds slot B's images from it on the phone and writes `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b` and `dtbo_b`, and nothing else: each found by GPT name on `sda`, on the storage guard's allowlist, `ro` 0, every image read back by sha256. Its pacman hook writes only with `/etc/omamobile/boot-update.conf` saying `AUTO_WRITE=yes`; the reference phone, a development phone, has no such file until step 6.
- Before each write it saves slot B's five partitions, whole, and the running release's modules in `/var/lib/omamobile/boot/previous/` (about 220 MB on cheetah plus one module tree); `omamobile-boot-update rollback` writes them back.
- It never reboots, never touches slot A, `vbmeta`, `devinfo` or the bootloader, never changes the storage guard.

**Recovery when slot B doesn't boot.** `omamobile-boot-success` marks slot B successful at every good boot, so ABL does **not** fall back to slot A after a bad write: the phone stops in fastboot or keeps resetting. Then: Power held about 30 s, then Volume Down + Power about 20 s for fastboot, and on the laptop `KERNEL_OUT=~/omamobile-kernel/out-release bin/omamobile flash` (step R2 checks that `out-release/images` is exactly what slot B holds today). On the recovery screen of a stock boot choose neither option (AGENTS §4); a stock boot means a fresh read-only backup of `efs`, `persist` and `modem_userdata` afterwards.

## 2. Why the running kernel can't be packaged as it is

The phone runs `7.3.0-rc6-omamobile-push1-g2219cc6cda77` from `~/omamobile-kernel/out-release`. `linux-omamobile` refuses `-push1` builds on purpose (RELEASES §4: a development kernel can never pass for a packaged one), so the package is built from the same source in release mode: the published tag `kernel-2026.11.01` with `CONFIG_LOCALVERSION="-omamobile"` (`bin/omamobile kernel --release`). Cheetah has no `device/cheetah/kernel.config`, so the release build's configuration differs from `out-release`'s only in `LOCALVERSION`; its `uname -r` is `7.3.0-rc6-omamobile-g<sha12>` and its modules live in their own directory, beside the push1 tree, which stays for the rollback.

## 3. Runbook

Read-only steps first. Each step: commands, Expect, Pass, **Stop**, Rollback, risk. Laptop steps run in this repository's checkout of the branch (`cd <repo>`); phone steps over `tools/phone-ssh` (root). Record results in §4 with the date and `uname -r`. Announce to Derek before every step marked "affects the phone" and before both reboots.

### L1. Build the release kernel from the tag (laptop, no phone; risk none)

```sh
git -C ~/omamobile-kernel/linux rev-parse 'kernel-2026.11.01^{commit}'   # expect 2219cc6cda77...
git -C ~/omamobile-kernel/linux worktree add ~/omamobile-kernel/wt-pkgtest kernel-2026.11.01
export KERNEL_DIR=~/omamobile-kernel/wt-pkgtest KERNEL_OUT=~/omamobile-kernel/out-pkgtest
bin/omamobile kernel --release && bin/omamobile modules
cat $KERNEL_OUT/include/config/kernel.release
diff <(grep -v LOCALVERSION ~/omamobile-kernel/out-release/.config) <(grep -v LOCALVERSION $KERNEL_OUT/.config)
```

- Expect: the tag's commit is `2219cc6cda77` (the running kernel's); `kernel.release` is `7.3.0-rc6-omamobile-g2219cc6cda77`; the configuration diff is empty.
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
- The `--local` repository is signed with the local key only and is never published; the phone takes the files with `pacman -U` (`LocalFileSigLevel = Optional`).

### R1. The phone as it is (read-only; risk none)

```sh
tools/phone-ssh 'uname -r; cat /proc/cmdline | tr " " "\n" | grep slot_suffix; pacman -Q omamobile-device-cheetah omamobile-omarchy omamobile-shell
  ls /etc/omamobile/boot-update.conf 2>&1; test -s /root/.ssh/authorized_keys && echo root-keys-ok
  df -h /var | tail -1; cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1
  for s in /sys/block/sda/sda*; do n=$(sed -n "s/^PARTNAME=//p" $s/uevent); case $n in *_b|userdata) echo "$n ${s##*/} ro=$(cat $s/ro) $(( $(cat $s/size) * 512 ))";; esac; done'
```

- Expect: the push1 release; slot `_b` (or no slot suffix line); no `boot-update.conf`; `root-keys-ok` (the hook appends these keys to the release initramfs, so SSH into the initramfs keeps working); at least 1 GB free in `/var`; battery 30% or more, or the charger in; the five `_b` partitions and `userdata` with `ro=0`, every other `_b` partition `ro=1`.
- Pass: all of it. **Stop:** no root keys (add Derek's key first, or the initramfs has no SSH), less space, `ro=0` anywhere else.
- Rollback: none.

### R2. Slot B today, and the laptop's copy of it (read-only; risk none)

```sh
tools/phone-ssh 'for p in boot init_boot vendor_boot vendor_kernel_boot dtbo; do s=$(for s in /sys/block/sda/sda*; do grep -qx PARTNAME=${p}_b $s/uevent && echo ${s##*/}; done); echo "$p $s"; done' > logs/kernel-update-slotb.txt
for p in boot init_boot vendor_boot vendor_kernel_boot dtbo; do
  f=~/omamobile-kernel/out-release/images/$p.img; n=$(awk -v p=$p '$1 == p {print $2}' logs/kernel-update-slotb.txt)
  echo "$p laptop $(sha256sum < $f | cut -c1-16) phone $(tools/phone-ssh "head -c $(stat -c %s $f) /dev/$n | sha256sum" | cut -c1-16)"
done
```

- Expect: each pair of checksums equal: `out-release/images` is exactly slot B, the fallback for `bin/omamobile flash`.
- Pass: five equal pairs. **Stop:** any difference: find or rebuild the set slot B holds before going on (without it there is no known-good set to flash by fastboot).
- Rollback: none.

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
```

- Expect: the reinstall runs the hook: plan, "Saving slot B (7.3.0-rc6-omamobile-push1-g2219cc6cda77)", `boot_b` and `vendor_kernel_boot_b` "written and verified", "Restart the phone to boot it"; `previous/` holds five images, `RELEASE` the push1 release, `BOOTED` yes and its modules; the result is `written`.
- Pass: as expected, and the partitions' leading bytes match `current/SHA256SUMS` (the tool checked; re-check with `head -c | sha256sum` for `boot_b`).
- **Stop:** any error. Do **not** reboot; `sudo omamobile-boot-update rollback --dry-run`, then `rollback`, then R2 again (slot B must equal `out-release` before any reboot).
- Rollback: `sudo omamobile-boot-update rollback` (P5), or R2's set by fastboot.

### P4. Reboot into the packaged kernel (affects the phone: reboot; risk medium)

```sh
tools/phone-ssh 'systemctl reboot'
# about a minute later
tools/phone-ssh 'uname -r; systemctl --failed --no-legend | head; ls /dev/dri; nmcli -t -f STATE general'
tools/phone-smoke
```

- Expect: `7.3.0-rc6-omamobile-g2219cc6cda77`; the lock screen as usual; GPU (`/dev/dri/renderD128`), Wi-Fi, touch, audio and sensors as before (`tools/phone-smoke`); no new failed units. SSH into the initramfs (if it ever stays there) answers with Derek's key and a new host key.
- Pass: as expected. **Stop:** no SSH after 3 minutes: ask Derek to look at the screen; fastboot by the buttons and R2's set with `KERNEL_OUT=~/omamobile-kernel/out-release bin/omamobile flash`.
- Rollback: P5.

### P5. Roll back (affects slot B; risk medium)

```sh
tools/phone-ssh 'rm /etc/omamobile/boot-update.conf; sudo omamobile-boot-update rollback --dry-run'
tools/phone-ssh 'sudo omamobile-boot-update rollback --yes'
```

- Expect: the dry run plans `boot_b` and `vendor_kernel_boot_b` (and nothing else) back to the saved set; the rollback writes and verifies them, finds the push1 modules still in `/usr/lib/modules` (kernel-modules-hook kept them) or restores them, and prints the `IgnorePkg` line. R2 afterwards: slot B equals `out-release/images` again.
- Pass: R2's five equal pairs. **Stop:** any error or difference: no reboot; fastboot route if slot B can't be made equal to `out-release`.
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

(Date, `uname -r`, each step's outcome and the lines that show it.)
