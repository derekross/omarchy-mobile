<!-- SPDX-License-Identifier: MIT -->
# Xiaomi Mi 8 port state

Last updated: 2026-11-02. Older discovery notes below are historical where they
conflict with this summary.

Latest live state (2026-11-02):
- Omarchy is running; the owner confirmed the physical display is visible.
- A fresh USB SSH connection through tools/phone-ssh --fresh succeeded and
  sshd is active.
- The current Wayland output is DSI-1 (405x843). A VNC RFB 3.8 handshake
  succeeded; the viewer's rendered image and remote input remain unverified.
- SSID, LAN address, SSH aliases and key paths, credentials and private backup
  paths are intentionally omitted from this repository.
- No reboot, flash or partition write was performed during the latest
  remote-access checks. Audio playback, sensors and 3D acceleration remain
  unverified.

## Device and safety

- Xiaomi Mi 8 (`dipper`), Snapdragon 845, non-A/B OS layout. There is one `boot`
  and one `userdata`; installing Arch to `userdata` erases Android user data.
- Android was reachable over ADB; Tailscale reconnected after its app was
  opened once. A fresh backup passed all 15 device/source hash checks at
  `private off-device reference directory (path omitted)/`.
  A later RAM-rescue modem/Wi-Fi attempt ended with remoteproc `crashed` and
  recovery disabled. On 2026-10-31 the owner authorized one RAM-only boot of
  `/tmp/mi8-panel-nfs-image/images/boot.img` (SHA-256
  `9185f790896fb77bf5cedcfff745aa90a3bbf4477a4a82c424e5777caf74ac8c`). The
  phone mounted the exported scratch root; systemd eventually reached SDDM.
  SSH accepted the root key. `pam_systemd` first timed out waiting for the root
  user manager; later short commands succeeded, then SSH stopped accepting
  connections while USB remained enumerated. No partition was written.
- Mainline kernel/initramfs previously reached first light through RAM boot:
  UFS/ext4, USB NCM and rescue SSH worked; storage guard allowed only `userdata`.
  No persistent boot/rootfs install has been performed by this work.
- The owner authorized an attended Wi-Fi bring-up attempt and one clean RAM boot
  of the revised image. Do not restart the crashed modem in place and do not
  flash any partition. Do not use the shared Pixel installer for this non-A/B
  device.

## Current implementation

- Kernel source is `../../../linux` (workspace `linux/`), branch has existing
  user changes; preserve them. Current release string:
  `7.3.0-rc6-omamobile-push1-g2a318a96ae9d-dirty`.
- `CONFIG_TOUCHSCREEN_STMFTS=y`; DTS uses `st,stmfts5`. Upstream FTS5 support,
  including the controller-ready wait fix, is present and compiled in `linux/`.
  The RAM-booted kernel registered `stmfts` as `/dev/input/event1` on the
  handset. A confirmed physical tap produced an `EV_ABS` `ABS_MT_POSITION_X`
  event, so basic touch input works. Full coordinate/gesture coverage is not
  done. Firmware loading and low-power/wake touch are out of scope for this
  driver series.
- Rootfs builder now consumes `ROOTFS_DIST_PACKAGES`, stages
  `out/dipper/firmware/{qcom,ath10k}`, and fails for dipper if the proprietary
  firmware is absent. The four Qualcomm IPC packages have PKGBUILDs under
  `packages/{qrtr,pd-mapper,tqftpserv,rmtfs}` and are listed for the dipper rootfs.
- The current boot-image revision RAM-booted on 2026-10-30 and confirmed USB
  rescue SSH, visible console text and FTS5 touch input. It used Zopfli because
  the regular gzip kernel exceeds ABL's kernel limit. The current image revision
  and its untested status are recorded below.
- Rebuilt `out/dipper/images/boot.img` after adding the read-only-checked `fsc`
  link. SHA-256 is `42b51401d98ac587f04f33aebd8ab92201c5069da216c74a42aa4e23748975c4`;
  the 25,432,064-byte image fits the 64 MiB partition with 41,676,800 bytes of
  headroom. It has been RAM-booted successfully.
- `out/dipper/modules-<release>.tar.zst` is staged for rootfs. All four Qualcomm
  aarch64 packages and `omamobile-device-dipper` built and were signed into the
  local repo; the device package's 12 native checks passed. The 38 published
  Omarchy Mobile packages were fetched with signature/hash verification and
  imported. The first full-rootfs attempt failed in pacstrap while checking
  three local package checksums. Their archive SHA-256 values matched the repo
  database; the retry completed successfully. The rootfs image is
  `omarchy-mobile/out/dipper/omamobile-rootfs-2026.10.29-dipper-aarch64.img.zst`
  (3.1 GiB compressed; 9,580 MiB used in a 12 GiB ext4 filesystem). Its
  checksum verifies, the manifest includes all four Qualcomm daemons, the
  dipper package and the Qualcomm/Atheros firmware packages, and all 11
  `tests/rootfs-smoke` checks passed. Firmware was copied from the private
  device extraction at build time; it is not tracked.
- No modem/Wi-Fi service is enabled automatically. Several attended modem
  starts under mainline have crashed. Use
  `device/dipper/WIFI-PLAN.md` before another attended attempt.
- The boot reached rescue SSH over USB NCM. A later NFS-root Omarchy session
  also reached Hyprland and Quickshell; see the display attempt below. The
  physical panel still did not show the desktop reliably.
- Wi-Fi driver loading was attempted, but no WLAN interface or scan appeared.
  The rescue initramfs lacks Qualcomm
  daemons, firmware and radio modules. A temporary host NFS export of a
  disposable rootfs copy was mounted read-write at `the host-side scratch mount` over USB; only
  this scratch copy was writable, not the compressed image or phone storage.
  The NFS client is currently disconnected. The host copy remains at
  `the disposable host-side NFS root`.
  Loading `qcom_q6v5_mss` first failed because the PDC reset provider was absent;
  after `reset_qcom_pdc` was loaded, remoteproc registered offline. On
  2026-10-30 `rmtfs -v -r -P -s` started the modem with all five NV links
  verified read-only. QRTR WLAN service 69 appeared. On the MCFG retry, both
  MCFG files were served and WLAN DSP firmware was fetched, but the modem
  crashed with `modem_xpu_int.c:456:XPU violation End`. Recovery was disabled.
  Timed from `wifi-20261030-mcfg-ath10k-crash-dmesg.log`, the modem came up at
  t=160.5 s and stayed healthy for 137 s; `cfg80211` loaded at t=297.53 s (the
  ath10k module insertion pulling in mac80211/cfg80211) and the XPU violation
  arrived at t=297.89 s, 0.36 s later. So the trigger is the ath10k_snoc QMI
  handshake, not modem boot or MCFG. That log contains no ath10k lines at all:
  the capture ended with the phone, so the `CONFIG_ATH10K_DEBUG` output that
  was built for this run was never obtained. Next attempt must stream the log
  off-device, or read it back from pstore, before the module is inserted. TFTP logs
  The `rmtfs` log's rejected `/boot/modem_fsg_oem_1` and `_2` requests are benign:
  dipper has no `fsg_oem*` partition and stock `/vendor/bin/rmt_storage` knows only
  `/boot/modem_fs1`, `/boot/modem_fs2`, `/boot/modem_fsc` and `/boot/modem_fsg`, so
  stock refuses them identically. Do not alias them. TFTP logs
  showed two modem MCFG files missing from staged firmware on the earlier run;
  the matching files are now in the private firmware and scratch rootfs, and
  `tools/dipper/extract-firmware` stages them for future builds. A private
  capture is at `private off-device reference directory (path omitted)`.
  Older kmsg captures show automatic recovery
  loops reaching crash counters 1–6 and 1–5; the kernel defaults recovery to
  enabled. Disable and verify recovery while remoteproc is offline before any
  future single start. Do not retry in place. `ath10k_snoc` was
  loaded on the latest attempt but no WLAN interface, scan or association
  occurred. NV partitions remained
  read-only. The `rmtfs` log showed the rescue initramfs lacks
  `/dev/disk/by-partlabel` links; the first attempt missed `modemst1`, and the
  second missed `fsc`. Every temporary target is verified read-only. A fresh
  15-partition snapshot matching the phone before RAM boot is at
  `private off-device reference directory (path omitted)/`; it does
  not include `userdata`, Android system/vendor, or the separately extracted
  firmware. A private live kernel log runs outside the repository.
  Host NFS service is disabled at boot and serves only the USB client. The
  scratch rootfs WCN3990 `board-2.bin` matches the staged corrected file
  (SHA-256 `81b0f78adcf995e93d789daf8691254ff745d53f843a4c5c7d2549cfc15f8a36`);
  the compressed rootfs image has not yet been rebuilt with it.
- Owner Wi-Fi credentials stay in ignored local provisioning settings; do not include their values in this public handoff. Use it without echoing values; never copy credentials into
  tracked files or logs. No Tailscale auth token was found in that file or the
  searched Claude/provision history.

## Session of 2026-10-30 (late): Tailscale fixed, Wi-Fi diagnosed

- **Tailscale now starts by itself** and is confirmed three times (two warm
  reboots and one cold power-cycle): `settings put secure always_on_vpn_app
  com.tailscale.ipn`, `always_on_vpn_lockdown 0` (deliberately off, so a
  Tailscale failure cannot cut the phone off), plus the package added to the
  doze whitelist. After the cold power-cycle the peer came up **with no USB
  attached at all**, direct to its LAN address, so it no longer needs the app
  opened by hand.
- `tools/dipper/backup-stock` gained an adb transport (`TRANSPORT=auto|adb|ssh`,
  `adb exec-out` so the `dd` pipe stays binary). It needs no SimpleSSHD or
  Tailscale now, and `adb root` already gives uid 0.
- A verified snapshot of all 15 partitions was taken before the radio runs. After
  them, everything we could have damaged -- `boot`, `recovery`, `dtbo`, `vbmeta`,
  `fsc`, `devinfo`, `misc`, `logo`, `splash`, `persistbak`, `modemst2`, `fsg` --
  was byte-identical. Only `persist`, `modemst1` and `frp` changed, which stock
  Android rewrites on every boot; our runs held all five NV partitions at `ro=1`
  before and after, so a write from our side was not possible.
- Four attended RAM boots diagnosed the Wi-Fi failure down to the SDM845 XPU
  erratum that ath10k already works around with a fixed `msleep(20)` tuned to one
  MPSS build. dipper runs a different build. `qmi.c` now takes that delay from a
  module parameter (`ath10k_snoc msa_perm_delay_ms`, default 20). Our board data
  and the WCN3990 supply map are both cleared by evidence. Full write-up, the
  cleared-suspect table and the gated next run are in `WIFI-PLAN.md`.
- The `msa_perm_delay_ms=300` run is **prepared but not yet performed**.

### Current blocker

The phone is in Android and reachable over Wi-Fi and Tailscale, but it is **not
on USB data**: `lsusb` shows no phone and `adb` lists none. SimpleSSHD answers on
port 2222 with the project key, but only as an unprivileged app
(`untrusted_app_29`), and `fastboot` cannot be driven over the network. The next
run needs the USB data connection restored -- a data-capable cable and port, not
a charge-only one.

Note the last run ended with the phone failing to return from `reboot -f` on its
own; it needed a physical power-cycle. Prefer `adb reboot` from Android, and
expect a RAM boot with a crashed modem to need the button.

## Wi-Fi works (2026-10-30)

On a RAM boot, nothing flashed, NV read-only throughout: `wlan0` associated to the
owner's AP on 2.4 GHz (`wpa_state=COMPLETED`, -59 dBm), took a DHCP lease, got a
default route and reached the internet (`ping 1.1.1.1` 3/3, 16 ms). The modem
stayed `running`. Three things were needed, all recorded in `WIFI-PLAN.md`:

1. `ath10k_snoc msa_perm_delay_ms=300` -- the upstream 20 ms XPU-settling sleep is
   tuned to a different MPSS build than dipper's.
2. Gate the ath10k load on QRTR service 69. Loading before the modem publishes it
   is what looked like flakiness; it cost the modem every time.
3. `ath user_regd=1` + `iw reg set SK` -- the calibration reports CN and ath
   applied it as a strict custom per-phy domain, so the global domain was ignored.

**DFS channels do not work.** The owner's 5 GHz AP is on channel 104, a DFS
channel. Scanning it works and the firmware returns valid noise floors, but
`vdev start` crashes the closed WLAN firmware after 52 ms, every time, with
`CONFIG_ATH10K_DFS_CERTIFIED=y` included. The same crash is reported on a
OnePlus 6T (same SoC and radio) with no upstream fix. Non-DFS and permitted here:
2.4 GHz, UNII-1 (36-48) and UNII-3 (149-165). Moving the AP's 5 GHz radio to
36-48 is the practical route to 5 GHz and is **untested**.

## Omarchy boots on the phone, from NFS (2026-10-30)

`initramfs/init` gained `boot_nfs()`, gated on `/etc/omamobile-nfsroot` existing
(the same file-presence idiom the init already uses for `omamobile-compatible`
and `omamobile-ufs-rw`), so no device changes behaviour without that file.
`tools/dipper/build` takes `DIPPER_NFSROOT=<host>:<path>` and writes it.
`CONFIG_ROOT_NFS` and `NFS_FS` are `=y`, so no module is needed. **Nothing is
written to the phone and `userdata` is untouched** -- the root filesystem is
served from the host over the USB link.

Confirmed working: `switch_root` into the Arch root, systemd as PID 1, journald,
udev, sysctl and vconsole all starting, the NFS root in active use (an
established connection from the phone to the host's port 2049), and
systemd-networkd giving `usb0` its address (the host resolves 172.16.42.1 by ARP
and pings it).

### Omarchy display attempts (2026-10-30 and 31)

Captured over USB SSH: Hyprland first failed EGL initialization because this
Mesa build had no `msm_dri.so`. The rootfs does contain Zink and Turnip, so
`MESA_LOADER_DRIVER_OVERRIDE=zink` and
`__GLX_VENDOR_LIBRARY_NAME=mesa` were added to
`/etc/environment.d/90-zink-turnip.conf` and the Zink override to
`/home/<desktop-user>/.config/uwsm/env`; SDDM was restarted. Hyprland then reported
`zink Vulkan 1.3 (Turnip Adreno 630)`, stayed up, and launched Quickshell.

The panel still failed on a later modeset: `Failed to exit sleep mode: -22`,
followed by `fb=0` on the CRTC. The EA8074 panel bridge did not request its DSI
host to pre-enable first. The kernel source now sets
`ctx->panel.prepare_prev_first = true` for this command-mode panel. The panel
object and `.ko` compile with the saved dipper config. The rebuilt `.ko` is
staged in `the disposable host-side NFS root/usr/lib/modules/<release>/.../panel-samsung-ea8074.ko`;
its vermagic matches the current
`7.3.0-rc6-omamobile-push1-g2a318a96ae9d-dirty` kernel. Its module was included
in the 2026-10-31 RAM boot, but the run did not reach a panel modeset, so this
change is not hardware-validated.

The scratch root's previous SDDM logs (19:34-19:37) show its Wayland greeter
found a socket but Mesa/Zink failed `vkEnumeratePhysicalDevices` with
`VK_ERROR_INITIALIZATION_FAILED`, then failed to choose a Vulkan device and
create a DRI2 screen. The expected Zink/Turnip overrides from the earlier
successful session were absent from this scratch root's `/etc/environment.d`
and the desktop user's UWSM environment. This is a likely userspace cause of
the black desktop in this root; the earlier panel `-22` is a separate display
issue.

This scratch root is an unprovisioned build image: `/home` is empty, there is
no non-system account in `/etc/passwd`, and `/etc/omamobile/firstboot.conf` is
absent. The firstboot unit therefore did not create the desktop account. In
the 2026-10-31 run, SDDM started at about 307 s and Hyprland created the
greeter's Wayland socket by 366 s, but no desktop-user session or Quickshell
started. This run cannot confirm a usable Omarchy login until the normal
firstboot account setup is supplied.

In the 2026-10-31 RAM boot, kernel journal recorded simpledrm `fb0`, then a
`qcom_wled` warning at about 187 s: `wled_ovp_work` called `enable_irq()` and
hit `__enable_irq`'s warning path. It was non-fatal: systemd continued and SDDM
started later; no later EA8074 modeset error is recorded. Runtime DRM exposed
only `card0` from simpledrm (`Unknown-1`), with no MSM/DPU/DSI KMS card; the
kernel also logged `aux_bridge ... failed to acquire drm_bridge`. The source
DTS enables `&mdss` and `&mdss_dsi0`, so the mismatch between the booted tree and
the absent runtime DRM device remains open.

At about 742 s SDDM's Wayland greeter logged Zink's
`vkEnumeratePhysicalDevices` failure and `failed to create dri2 screen`, then
still added a view for `Unknown-1`. This reproduces the missing Vulkan path in
the scratch root; the Zink/Turnip environment overrides are absent. Systemd
eventually reported `running`, with SDDM and sshd active. SSH root-key auth
worked once the root user manager started, but an earlier connection timed out
in `pam_systemd` while `user@0.service` was still starting. Systemd also timed
out waiting for `/dev/ttyGS0`, so the serial getty escape hatch did not start.
USB ping remains intermittent. The host log is in
`the disposable host-side NFS root/var/log/journal`.

At ~1,090 s, a root SSH command loaded the existing `msm.ko` successfully.
Sysfs then showed the MDSS, DPU and DSI platform devices bound to `msm-mdss`,
`msm_dpu` and `msm_dsi`, but `/sys/class/drm` still exposed only simpledrm.
The live device tree reports the SDM845 display nodes and EA8074 panel enabled;
the failure is therefore later in DSI component/bridge registration, not a
missing DT status or an unloaded module. Extracting the exact `Image.gz-dtb`
from the boot image independently confirmed `status = "okay"` on the MDSS,
DSI and EA8074 nodes, and the DPU-to-DSI and DSI-to-panel graph endpoints are
connected. ALSA still reported no soundcards. ADSP had booted and WCD934x
returned its chip ID; the DTS has a TAS2559 DAI link, while this kernel tree
has no TAS2559 driver or staged TAS2559 firmware.

A root-only `pam_systemd` bypass was staged in the scratch NFS root after
repeated root user-manager teardown timeouts. Later NFS-root SSH logs confirmed
root sessions opened with the bypass. Its original PAM file is backed up at
`the disposable host-side NFS root/root/system-login.pre-root-ssh-test`. The read-only NFS
control channel subsequently ran several diagnostics and a runtime SSH start;
no request marker remains. The five-second `/dev/ttyACM0` capture produced no
serial output. The stable system has since returned to its existing ext4 boot,
with USB SSH and the DSI Hyprland monitor verified.

#### Gated RAM-boot test

1. The image `/tmp/mi8-panel-nfs-image/images/boot.img` was RAM-booted on
   2026-10-31 after fastboot reported `product: dipper`, `unlocked: yes`.
   NFS mounted; no partition was written.
2. This run reached SDDM and Hyprland's Wayland socket, but had no provisioned
   desktop account. Runtime DRM exposed only simpledrm; SDDM also logged the
   Zink Vulkan failure. Manually loading `msm` bound MDSS/DPU/DSI but still did
   not register an MSM DRM card. ALSA exposed no soundcard. The `qcom_wled`
   warning at ~187 s was non-fatal; the panel change remains unverified and no
   user session was available.
3. On a separately authorized next boot, capture serial and USB logs before
   boot, confirm the exact image/hash and restricted NFS export, then check
   `dmesg` for DSI component/bridge registration, DRM state, and ALSA cards over
   SSH. Pass only when the error is absent, the panel is visible, and sound is
   audible from a working route.

Stop on a repeated `-22`, a black panel, or loss of the USB console. The test is
RAM-only; do not flash. Risk: moderate; this latest test temporarily left the
phone unresponsive and required physical recovery, but did not change its
partitions.

### What it took, and the traps

1. **The hardware watchdog must be handed over to systemd.** SDM845 leaves its
   watchdogs *running* -- `watchdog0: watchdog did not stop!` -- and the
   initramfs daemon that pets it dies with everything else at `switch_root`. The
   first boot reached "Started Journal Service" and died at
   `watchdog0: pretimeout event`, 34 s in. Fixed by a new
   `vendor/systemd/system.conf.d/10-omamobile-watchdog.conf` in the dipper
   package. `RuntimeWatchdogSec=10s` was **not enough**: systemd programs that
   as the *hardware* timeout and pings at half of it, and a first boot spends
   about 8 s inside "Applying preset policy", so the pretimeout fired again at
   17 s. 30 s was still not enough on a cold NFS boot (died at 37 s). **60 s
   works.**
2. `/etc/machine-id` shipped as `uninitialized`, which makes systemd run
   `preset-all` on first boot -- slow on NFS and the cause of trap 1's second
   failure. Writing a real id removes that stall.
3. **The image has no SSH host keys**, so `sshd` cannot start and the phone boots
   with no way in. Generated with `ssh-keygen -A -f <rootfs>`. This is why the
   first good boot was unreachable despite being healthy.
4. `systemd-pstore` consumes `/sys/fs/pstore` on boot, which eats the ramoops
   console log before it can be read. Mask it while bringing up.
5. The journal is useless for a boot that dies: systemd preallocates 8 MiB and
   flushes almost nothing, so `ramoops` remains the only record.

### Escape hatches added, because there was none

A healthy phone with no `sshd` has no channel at all -- no adb (that is Android's
daemon and goes with it), no fastboot (that is the bootloader), no console. Both
of these are now staged in the scratch rootfs:

- `serial-getty@ttyGS0` with an autologin drop-in. The initramfs already creates
  `acm.GS0` and the host sees `/dev/ttyACM0`; there was simply no getty on it,
  and root's password hash is `!*` so a plain getty would refuse anyway.
- `omamobile-nfs-trigger.timer`, polling the NFS-served root for a `/reboot-now`
  file. The root is writable from the host, so it doubles as a control channel.

Withdrawing the NFS export does **not** force a reset: systemd keeps petting the
watchdog from memory, so the phone hangs rather than rebooting.

### Still to verify on the next boot

A shell in Omarchy (host keys are now in place), then whether
`omamobile-wlan.service` brings Wi-Fi up by itself. The radio pieces are staged:
`modprobe.d` with `msa_perm_delay_ms=300`, `user_regd=1` and `ath10k_snoc`
blacklisted; the gated bring-up unit; `wireless-regdom` SK; the IPC chain
enabled; and a NetworkManager profile for the 2.4 GHz band.

Only the watchdog file has been moved into the dipper package so far. The rest
lives in the disposable scratch rootfs and still needs a proper home.

## Next steps

1. Restore a physical USB data connection and identify the phone's current
   mode before sending device commands. If Android has booted since the saved
   snapshot, capture and verify a fresh off-device read-only backup before
   radio work. Continue with RAM boot only; do not flash.
2. Verify completion and exit status of the diagnostic kernel/image build.
   Verified 2026-10-30: the build completed and debug ath10k modules exist under
   `out/dipper/modules/lib/modules/<release>/.../ath10k/`. There is **no** saved
   original `linux/.config` — `.config.old` is an unrelated kconfig artefact
   (6017 differing lines), not a pre-debug backup. The only recorded diagnostic
   change is `CONFIG_ATH10K_DEBUG=y`, so "restoring" means unsetting that one
   symbol; leave it on until the XPU violation is diagnosed. Still to do: copy
   the debug ath10k modules into the disposable NFS scratch rootfs.
3. Review private logs under
   `private off-device reference directory (path omitted)*` before deciding
   whether another attended radio attempt is justified. Do not restart a
   crashed modem in place. Keep NV links read-only, recovery disabled, and a
   private live log active.
4. The earlier NFS scratch boot exposed only simpledrm and deferred DSI on the
   IBB regulator, but the current stable boot exposes a connected 1080x2248
   DSI monitor with Hyprland and Quickshell active. Physical panel visibility
   was not directly observed. Audio is still incomplete: the current sound
   card probe defers on the missing TAS2559 DAI; do not remove the speaker link
   without a working replacement route. No flash or install to `userdata`.
5. No radio service is enabled by default. Keep `rmtfs` read-only on any later
   attempt and load one subsystem at a time.

Build script references: `device/dipper/FLASH-RUNBOOK.md`, `WIFI-PLAN.md`,
`tools/dipper/build`, `tools/build-packages`, `tools/build-rootfs`.
