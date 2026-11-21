<!-- SPDX-License-Identifier: MIT -->
# dipper (Xiaomi Mi 8) — bring-up notes

Facts only, each read off the phone. Captures remain outside the repository
because they contain device identifiers and Wi-Fi keys; this file records only
the facts needed for review.









## 2026-11-21 — packaged CPU0 idle workaround simulation

Booted the current RAM/NFS overlay with image SHA-256
`1a1f2dbf44b6353c72bf972ae86418f284a754f6c6333b7f05ce1395064c5560`.
The kernel came from source commit
`f61e96519032e385a04ca0688a068ca6dbc56d63` and reported release
`7.3.0-rc6-omamobile-push1-gf61e96519032`.
The initramfs injected the exact candidate `omamobile-dipper-cpuidle.service`
and its `multi-user.target.wants` link before firstboot so the startup order
could be observed. Firstboot completed, and the unit reached active (exited).
The local aarch64 package build passed; after checking its signature on the
phone, I removed the injected files and installed package 0.1.3 with pacman
on the overlay root. `pacman -Qo` confirmed the package owns both files.

The CPU0 cpuidle state was `cpu-sleep-0-0` (`little-rail-power-collapse`,
811 us latency, 1890 us residency): CPU0 `disable=1`, CPU1 `disable=0`. The
Hyprland/Omarchy session reached its lock screen, visible in a compositor
capture at 1080x2248. A 65-second Hyprland DPMS-off interval returned to
DPMS-on; SSH stayed available and the service remained active. This is not a
physical view of the panel or a fresh gesture test.

The read-only phone-smoke report found the DSI display, msm render node,
STMFTS device, GPIO buttons and USB gadget; all six UFS disks and 85
partitions stayed read-only. As expected, the root check failed for the
overlay instead of userdata. Kernel health reported no oops, BUG or WARN,
but six new error lines: watchdog did not stop, SquashFS ignored xattrs and
the SPMI arbiter logged a disallowed write. Those errors are not waived by
this test. No UFS partition was written. The test validates a package build,
signature check, pacman installation and service effect on this overlay; it
does not validate persistent boot, clean kernel health or the root cause of
the display wake failure.

`networkctl status usb0` reported routable/online, configured by
`20-usb-gadget.network`, with the expected gadget address and host gateway;
the device hardware address is deliberately omitted here. From this running
overlay, the packaged `/usr/bin/reboot-to bootloader` returned to fastboot.
Read-only fastboot variables identified product `dipper`, an unlocked
bootloader, a raw 64 MiB `boot` partition, and no `has-slot:boot` or
`current-slot` variable. This confirms why the existing slot-B installer
cannot install Dipper; no persistent writer was run.

## 2026-11-21 — current-main read-only phone smoke

Ran `tools/phone-smoke` from main commit `9f51bb1` against the already-running
NFS/overlay session, using the Dipper descriptor from this branch. The kernel
reported `7.3.0-rc6-omamobile-push1-gf61e96519032`; `/` was an overlay with its
lower source on NFS, not persistent userdata. All six UFS disks and all 85
partitions reported read-only. The smoke report found a 1080x2248 DSI
connector, an MSM render node, active Hyprland/SDDM/Quickshell, STMFTS touch
and GPIO buttons; firstboot completed successfully. `usb0` was routable and
online. A separate read-only sysfs check showed DSI-1 connected and the
backlight value at 511; brightness was not changed. Wi-Fi, Bluetooth, battery,
audio, sensors and camera were unavailable.
The report had no WARN rows but did report six kernel error lines, including
the watchdog-stop, ignored SquashFS xattrs and denied SPMI write findings
listed above. The physical panel was not observed in this check.

The installed `omamobile-device-dipper 0.1.4-1` came from a local volatile
overlay experiment, not this PR's package. This was a read-only inspection of
the existing session, not a new boot, persistent-userdata test or validation
of the PR package. The sanitized report and USB status summary were posted in
the PR thread; raw output and identifiers remain private.

At 2026-11-21T03:06Z, `tools/phone-smoke` from #714 head `a0f14643` was run
again over the same already-running session. The result again showed the
overlay root instead of userdata, with all six disks and 85 partitions
read-only; USB, display, render node, Hyprland/Omarchy shell, lock, STMFTS and
buttons were present, and no system or firstboot units had failed. This run
reported 0 WARN and 0 kernel error lines. Wi-Fi, Bluetooth, battery, audio,
sensors and cameras were absent. It exited 1 only because the required root
check failed. No boot, reboot or partition write was issued. This remains
overlay-session evidence, not a persistent-userdata boot.
Neither smoke capture nor the retained boot-partition audit records a boot ID
or uptime. The six-to-zero error-line difference cannot be attributed to a
reboot or log-buffer wrap from the retained evidence; capture both values
with each read in the next attended session.

## 2026-11-21 — normal Qt rendering with CPU0 idle isolation

Repeated the CPU0-only rail-collapse control without setting
`QT_QUICK_BACKEND`; Quickshell inherited no backend override. The image SHA-256
was `0257a1978e7f39160d287b5810b690802dc23baf13d6e3377e435c3d66da48f4`.
Hyprland reported Freedreno FD630; CPU0 state 1 read disabled, CPU1-7 state 1
enabled, with WFI available. Main firstboot completed and the regular
Quickshell session ran.

The locked screen blanked DSI-1 (`dpmsStatus=false`). SSH stayed responsive and
systemd's watchdog timestamp advanced during the blank interval. A scheduled
DPMS enable returned the monitor to `dpmsStatus=true`; the shell, user manager
and watchdog remained active throughout the roughly 70-second observation.
All 91 UFS read-only flags remained set. This confirms the CPU0-only control
also works without forcing QtQuick software rendering. The test root was still
a RAM overlay transported from the host; it is not an installed-userdata boot,
physical display/gesture acceptance or proof of the underlying power-state
root cause. No UFS write occurred.

## 2026-11-21 — CPU0 idle isolation and display cycle

Booted the current diagnostic overlay with the same kernel and normal shared
Mesa renderer, adding a private initramfs control that disables cpuidle
`cpu-sleep-0-0` on CPU0 only. Image SHA-256:
`82a8b87903978c04bf9f70646b849cbbfc984046f61e26739cb86c5291cfd3f4`.
Readback showed state 1 disabled on CPU0 and enabled on CPU1-7; WFI remained
enabled on every CPU. Firstboot completed, SDDM and the user manager became
active, and Hyprland plus Quickshell ran. Aquamarine again reported Freedreno
FD630 on DSI-1 at 1080x2248.

With the lock screen's ordinary display blanking, SSH and watchdog remained
available. An explicit 60-second Hyprland DPMS-off interval also completed;
SSH and watchdog stayed live, the monitor reported `dpmsStatus=false`, and
DPMS enable returned `ok` with `dpmsStatus=true`. Runtime phone-smoke found the
session, display, GPU, STMFTS and buttons; all six UFS disks and all 85
partitions stayed read-only. As expected for this diagnostic, root was overlay
rather than userdata. The kernel-health row still reports the watchdog-stop,
ignored SquashFS-xattr and disallowed-SPMI-write errors listed above. This
supports testing CPU0's rail-collapse idle state as the distinguishing factor;
it does not yet prove the specific failing PSCI/power path or an accepted
production fix. No physical-panel observation, gesture test or persistent
userdata boot is claimed. No UFS writes occurred.

## 2026-11-20 — current-stack firstboot and rendered lock screen

The handset owner explicitly authorized further RAM-only diagnostics despite
upstream's pending agreement. The stored guarded rescue remains the reset
fallback. No UFS writes were issued in these runs.

A compressed current-root image with a tmpfs overlay reached main's firstboot
0.1.6 completion, SDDM autologin, Hyprland and the Omarchy shell, on kernel
`7.3.0-rc6-omamobile-push1-gf61e96519032`. Packages included Omarchy 4.5.0-3,
omamobile-omarchy 0.1.48, shell 0.2.135, device 0.1.2 and shared Mesa
1:26.2.4-1.5. Hyprland's Aquamarine log reported vendor `freedreno`, renderer
`FD630`. The runtime smoke report found the session, DSI-1 at 1080x2248,
msm render node, STMFTS and gpio-keys; all six UFS disks and 85 partitions
were read-only. The root row failed as expected for this diagnostic overlay
rather than userdata. Kernel health found no oops, BUG or WARN, but the error
row was not clean: watchdog-not-stopped, ignored SquashFS xattrs and a
disallowed SPMI write were reported. Radio, battery, audio, sensor and camera
acceptance was not demonstrated.

The full compressed image in RAM imposed substantial memory pressure; a
second diagnostic used the same compressed lower image over read-only NFS
with a tmpfs upper. Both normal-Qt runs reset after entering the lock screen.
The observed watchdog feed stopped before the reset, but this does not
identify its cause. An automatic return to rescue supplied raw reset-reason
bytes `00 08 01 21`; their meaning is not established.

The initial full-RAM image had SHA-256
`a9f18b9f5de5058675e8e40d44aeedf03889a565974c73aa0d08f7751dfe2031`.
The compressed lower image had SHA-256
`b90ac373f6b2ba4844334942a042768e820b30537e930c17ab7d94bb65f34312`.

A subsequent control configured `QT_QUICK_BACKEND=software` for the shell,
while Hyprland still reported FD630. After recovering a failed user manager,
a downloaded 1080x2248 compositor capture showed the rendered Omarchy lock
screen and setup notifications. This is rendered-image evidence, not physical
panel observation or a successful touch gesture. That control also reset.
The diagnostic's USB-console journal forwarding and an early PAM-based
poller were additional confounders; neither is proposed as production policy.
The software-Qt control image had SHA-256
`a3063a7bbc30d9b7fb593b3b34cd2649bcd1f77426da62731ad817d27facfd10`.
A repeat without journal forwarding (image SHA-256
`d6df73551880b45edead6ea22e5694c59e4c145590603d18d804ea4b964b98ef`)
completed firstboot and again ran Hyprland and Quickshell. The live Quickshell
process environment confirmed `QT_QUICK_BACKEND=software`; the smoke report
confirmed the locked shell answered its status request. SSH was lost again
shortly afterwards and the stored rescue returned. Thus disabling Qt GPU
rendering and removing console forwarding did not resolve the reset.
No stable clean-session or persistent-install acceptance is claimed.

An off-only diagnostic override next left the shell locked but skipped
`omarchy-brightness-display off`. That image's SHA-256 was
`993498a20603cef103fe1ca5794627a82a2106fd2c741362ebc122a8be86cd31`.
It completed firstboot, kept the locked session reachable beyond the earlier
failure window, and again showed all 91 UFS flags read-only. A direct Hyprland
DPMS-disable dispatch returned `ok` at approximately 271 seconds uptime;
a separately armed five-second DPMS-enable timer did not preserve SSH access.
The next connection reached stored rescue, again with reset bytes
`00 08 01 21`. This reproduces the failure around a display-off transition;
it does not yet identify a faulty panel, DRM, idle or power-management path.
The earlier successful DPMS cycle in the rescue chroot is a distinct result
and is not evidence this full-session case works.

A further software-Qt control restored the unmodified brightness helper and
added only `cpuidle.off=1` to the diagnostic kernel command line. Image SHA-256:
`63f2c6d8369262c314600bad087d0363a0355518efe1c7fea0167d3f1ae05be9`.
After firstboot the lock blanked the display (`dpmsStatus=false`) while SSH
and watchdog feeds remained available. A subsequent explicit 60-second DPMS-off
interval also retained both, and DPMS-enable returned `ok` with status true.
This implicates an idle/power transition in the failure; it does not establish
which PSCI state or driver is faulty. This parameter is a private control,
not an accepted permanent fix or battery/suspend result.



A late-loaded PM8xxx RTC was observed setting the clock back to January 1970.
Loading the matching RTC module before setting the diagnostic initramfs clock
prevented that rollback. The contributor's public signing key was imported
and locally signed manually, following RELEASES section 10; the builder's
private keyring was not propagated. These private diagnostic adjustments are
not package fixes or release acceptance evidence.

## 2026-11-20 — serial and NFS transport diagnosis

Further RAM-only tests used the current root after the handset owner explicitly
requested continuing despite the pending upstream NFS agreement. These tests
remain bring-up diagnostics and do not satisfy the clean-session gate.

A diagnostic DTB with GPU, MDSS/DSI and touch disabled still reproduced the
reset before a usable session. Private root overrides enabled the package-owned
sshd and debug-shell units early, kept the journal in RAM and forwarded logs to
USB ACM. The serial log confirmed sshd listening, networkd startup, and a later
boot reaching basic.target, D-Bus and logind. A builtin shell snapshot completed:
PID 1 waited in do_epoll_wait and two modprobe processes waited in
rpc_wait_bit_killable. This establishes a functioning scheduler and NFS waits
at that instant, not a whole-kernel freeze.

The earlier ldconfig-running job was investigated by generating its cache on
the host and temporarily masking its boot-time rebuild. That boot progressed
further, but still reset; this is not a demonstrated ldconfig bug. A temporary
NetworkManager mask did not resolve the stop and was removed. Preserving the
static USB address and testing 64 KiB NFS transfers likewise did not establish
a stable session. None of these private diagnostic overrides is proposed as a
production change or counted as package acceptance evidence.

A private host packet capture showed final TCP payload acknowledged in both
directions. The final client tail ended only about 26 ms after the last server
RPC reply; it does not establish a server timeout. The truncated capture cannot
reassemble every RPC record. The remaining question is whether watchdog reset
truncates otherwise active NFS work or follows a transport/client stall.
No UFS write was performed. Automatic returns reached the stored RAM rescue;
full phone-smoke and clean graphics/input evidence remain outstanding.

## 2026-11-20 — current-root NFS boot attempt

Booted the current Omarchy root over NFS using the canonical Dipper initramfs,
#919's guarded init, the combined display/touch diagnostic DTB and kernel
`7.3.0-rc6-omamobile-push1-gf61e96519032`. The host exported only the private
test root to the phone's USB address. A separate read-only NFS mount first
confirmed the export contained systemd. The phone then mounted it as `/` and
started systemd; the NFS server saw the phone's root connection and the root
journal recorded systemd startup. This confirms the initramfs-to-NFS handoff.

Two attempts stopped before SSH, `tools/phone-smoke` or a visible Hyprland
session. The captured journal confirms `systemd-remount-fs` finished successfully;
it does not identify the service or kernel path responsible for the stop. For the
second attempt, `systemd-remount-fs.service` was masked in the private test
root, but the boot still stopped before SSH and session startup. The phone then
returned to the persistent guarded rescue image without an identified reset
reason. The test-only remount mask was subsequently removed because the
journal does not support that diagnosis. No userdata partition was mounted by the rescue image and all six UFS
disk flags read `ro=1`. No UFS write occurred. The phone was returned to
fastboot with the packaged helper. The cause of the second early-systemd stop
is unresolved; no clean Omarchy session or smoke report is claimed.

NFS export was removed after the tests. The private root remains available for
further diagnosis. The device PR remains draft pending a successful clean
session and phone-smoke report.

## 2026-11-20 — RAM probe builder recovery policy

CONTRIBUTING §3.1 requires a reviewed no-USB policy for single-slot phones.
The canonical Dipper builder now packs `omamobile-usb-recovery=no` and
`omamobile-root-mode=ram-rescue`, matching the locally tested rescue policy.
Previously it left those files absent: the shared no-USB panic watcher could
reset the phone, while the empty allowlist alone kept userdata read-only.
The generated policy is tested with and without an NFS request. Explicit NFS
handoff still takes precedence; a failed NFS request stays in initramfs.
The actual aarch64 initramfs build also passed with #919's exact shared init
and the matching f61 kernel modules. Inspection of the compressed newc
archive confirmed both policy files and the empty UFS allowlist. Its SHA-256
is `1f37a70f398d13543a67815561c648407d1aeb098ec04798bc88730cdaad353c`.
The source change has host regression coverage and independent review; this
rebuilt initramfs has not booted at this point in the log. Later NFS runs are
recorded below. No further phone boot is being attempted while the maintainer's
rescue and recovery questions remain open.

## 2026-11-20 — firmware backup input check

Attempted the extractor from PR #917 against local read-only copies of the
11-09 vendor, modem and Bluetooth partition backups. All three compressed
backup checksums passed first. The vendor filesystem did not expose a usable
root directory: read-only debugfs reported directory corruption and e2fsck
reported invalid extended-attribute metadata. The extractor refused the
missing vendor/build.prop; no force flag or replacement identity file was
used. This is not a successful real-backup extraction test.

The decompressed vendor image matched the earlier read-only vendor capture
from 2026-11-01 byte for byte, so this observation is not a new image-content
change from the present tests. The earlier local repaired copy contained
orphan files without a recoverable build.prop identifying Dipper. Its
identity check was not bypassed either. Full hashes and diagnostic output
remain private. Backup hash integrity therefore does not establish a usable
vendor filesystem or a complete Android restore from these images alone.
Original backups were left untouched; temporary read-only mounts were
removed and the temporary decompressed copies deleted. No phone partition
was mounted or written by this check. Previously captured named GPU firmware
remains available separately, but the full vendor-directory extractor still
needs a usable owner-provided source image or partition copy.

## 2026-11-20 — compositor-managed DPMS and captured render

Repeated the combined diagnostic RAM image `c8e9ac25…` (full hash below)
with kernel `7.3.0-rc6-omamobile-push1-gf61e96519032`. Userdata was mounted
`ro,noload` for a rescue chroot, with the exact shared Mesa archive and
complete library/DRI/GBM setup from the earlier test. A watchdog feeder,
host-side kernel log stream and timed bootloader return were armed.

Under the running Hyprland session, `hyprctl dispatch dpms off` and `on`
returned success. Monitor JSON for DSI-1 read dpmsStatus true, false, true
before, during and after the cycle. The framebuffer output resumed:
Xwayland glxinfo reported Accelerated yes / FD630, then glxgears measured
277 frames in 5 seconds (55.251 FPS) and 299 (59.790 FPS). Kernel logs before
and after DPMS plus rendering were identical: no new encoder error or other
kernel message. A subsequent grim capture contained the colored gears,
visually inspected on the host. Captures remain private outside the repo.

This supersedes the standalone modetest attempt as evidence of a controlled
compositor-managed DPMS state cycle and resumed rendering. It does not
confirm physical panel illumination or make the rescue chroot a clean boot.
All 91 UFS flags remained read-only and the explicit rescue helper returned
the phone to fastboot. No UFS write occurred.

## 2026-11-20 — persistent rescue fallback recheck

From the guarded RAM rescue, located the single boot partition by its GPT
PARTNAME and hashed its first 23,314,432 bytes, the complete rescue image
length. The result was
`06a8cc368ce86ae6ba570208d0291c642f143019283dd0a88d99ef2365d746b3`,
matching the previously installed rescue image. This was a prefix/image
comparison, not a new hash of the complete 64 MiB partition. No UFS write
was performed.

Then returned to fastboot with the explicit rescue helper and ran plain
`fastboot reboot`, rather than `fastboot boot`. USB SSH reached the stored
rescue image: its root mode was ram-rescue, root was rootfs, and all 91 UFS
disk and partition flags read 1. The explicit helper returned the device to
fastboot again. This confirms that ordinary restart currently lands in the
guarded rescue instead of the old writable userdata system. It does not
establish the cause of the earlier NFS resets or guarantee recovery from a
hard kernel hang. At this point the separate NFS handoff was paused; the later
NFS attempts are recorded below. No further phone boot is being attempted
while the maintainer's rescue and recovery questions remain open.

## 2026-11-20 — device package 0.1.2 build

The packaged descriptor omitted `DTB_OVERLAYS="fts5"` while the build
descriptor selected it. The existing descriptor-equality test caught this.
Synchronized the package copy and bumped the package to 0.1.2. The package
fixture, Dipper builder checks and PR checks passed. A real aarch64 build
through `tools/build-packages --local dipper` completed in about four minutes
with the prior shared Mesa archive imported. Package SHA-256:
`3316896998cc37f8ee279138b6b08e2f9548316b4b20e705c52cf65d99c97129`.
The archive contains the matching descriptor, reboot helper and USB,
watchdog and storage rules. This is a build result, not an on-device install
or dependency-resolved clean-system boot.

## 2026-11-20 — combined current touch DTS and panel RAM probe

Built an off-repository diagnostic base DTS from kernel PR #249 at
`7132465ea9383336eb3c89ee7130b88d160facfa`, retaining its FTS5 node and pin
states, and adding the previously probed EA8074 panel wiring. Enabled
DISPCC, MDSS, DSI0, its PHY and touchscreen in this diagnostic DTB. No
production DTS activation is proposed by this test. Kernel and rescue
ramdisk came from the prior panel/GPU image; kernel release remained
`7.3.0-rc6-omamobile-push1-gf61e96519032`.

Boot image SHA-256:
`c8e9ac25a2d6b1ec0d650a56b1326e0174e73511edf0fbfa882f153e9fc765fa`.
DTB SHA-256:
`470c63599238c663791641ced0b5a1f4ba7ae0ca7fd0258826f529a8ead4b4d6`.
DTC reported 67 diagnostic lines versus 68 for the unchanged base; this
is not a schema-validation result. The DTB contains both removed-region
reservations. Kernel boot logs confirm those regions as nomap/non-reusable;
a complete `/proc/iomem` capture was not retained for this run.

The RAM boot reached USB SSH with rootfs as root. The phone command line
contained the Dipper-specific `systemd.firstboot=off` argument. STMFTS
registered at I2C14 address 0x49 as event2; power, resin and volume-up inputs
also registered. After starting the 5-second watchdog feeder with a
30-second timeout, REFGEN, MSM and EA8074 loaded. DSI-1 reported connected
at 1080x2248; card1, renderD128 and the MSM framebuffer appeared. No SMMU
context fault appeared in the captured kernel log. All 91 UFS disk and
partition flags read back as 1. No root filesystem was mounted and no UFS
write occurred. The explicit rescue helper returned the phone to fastboot,
confirmed on the host.

This confirms simultaneous kernel enumeration of touch, display and GPU.
No gesture, visible output, compositor session or systemd firstboot execution
was tested in this run. The earlier standalone DPMS attempt read On even
after requesting Off; subsequent page-flips ran at 59.72–59.86 Hz, but this
must not be treated as a verified DPMS cycle. Physical-panel observation
and normal-system smoke remain outstanding.

## 2026-11-20 — complete Mesa overlay and KMS rendering

Package provenance: the tested archive SHA-256 is
`6122aec6efa24194c5dca9733fd8a8936d92e8c99058f9c96d7cb0eb83b8a7fc`,
the earlier scoped recipe build at `83aa88ec413644dfc2336e6d09ee0a06481edd01`.
Its effective driver list matches the restored shared recipe, but this run
must not be described as testing the separately built shared archive
`774f3b799c6e0aea91f61fea2b7991af742e0a6e4fc9511491dba1b04219872b`.

The same guarded RAM image (`022b935a…`, full hash above) and kernel
`7.3.0-rc6-omamobile-push1-gf61e96519032` were used. Userdata was mounted
`ro,noload` only to provide the installed binaries. This was a rescue chroot,
not a normal supported-system boot or a clean main-package root.

With connector 36 and CRTC 85, `modetest -M msm -s 36@85:1080x2248 -v`
ran for 15 seconds with stdin held open and reported 14 frequency samples,
59.69–60.73 Hz. Earlier attempts exited on stdin EOF; this test confirms KMS
page-flip delivery. Backlight requested and actual values both read 0 and
then 511. DPMS Off and On commands returned successfully, but a disabled
encoder IRQ error was logged; a clean DPMS cycle and physical output are
not confirmed.

Extracted the shared Mesa `1:26.2.4-1.5` package into RAM, bound its DRI and
GBM directories over the read-only root, and set `LD_LIBRARY_PATH` to the
package's library directory. Hyprland's Aquamarine and main renderer logs
both reported `freedreno` / `FD630`. The rescue lacked `/dev/shm`; mounting
a mode-1777 tmpfs there removed the failed shared-buffer setup and allowed
Xwayland to start. With the complete package library path and that tmpfs,
`eglinfo -B` reported FD630 on GBM and Wayland for core, compatibility and
GLES contexts. `glxinfo -B` under Xwayland reported:

```text
direct rendering: Yes
Vendor: freedreno (0x5143)
Device: FD630 (0xffffffff)
Accelerated: yes
OpenGL renderer string: FD630
OpenGL version string: 4.6 (Compatibility Profile) Mesa 26.2.4-arch1.1.5.omamobile5
```

`glxgears -info` ran under that session and reported 276 frames in 5 seconds
(55.129 FPS), then 299 frames in 5 seconds (59.796 FPS). The first native Wayland gears runs segfaulted after reporting EGL 1.5.
A core dump placed the crash in `wl_proxy_destroy(NULL)`. Mesa demos 9.0.0
`src/egl/eglut/eglut_wayland.c` destroys the keyboard unconditionally when
the seat has no keyboard. The rescue also lacked udev input metadata. With
a temporary RAM-only uinput keyboard, udev running, and input-only add
events processed, `es2gears_wayland` ran successfully: 299 frames in 5 seconds
(59.788 FPS), then 299 frames in 5 seconds (59.776 FPS). The synthetic keyboard
is a diagnostic aid, not a physical input pass. A native `foot` client also
ran after binding devpts into the chroot.
Two pending-page-flip messages also remain in the Hyprland log. These results
supersede the earlier software-fallback observation for this corrected test
setup, but do not prove a stable installed desktop. Physical output and the
official normal-system phone-smoke report remain unverified. Raw logs are
retained privately outside the repository.

## 2026-11-20 — repeated guarded display probe

Repeated `fastboot boot` of image
`022b935a0b49b703e964cbfb286805ca54a38cd9fb66d095dcca9e6b0e97145f`,
kernel `7.3.0-rc6-omamobile-push1-gf61e96519032`, with RAM rescue selected.
USB SSH worked. Loaded `qcom_wdt`, started the 5-second watchdog feeder
with a 30-second timeout, then loaded REFGEN, MSM and the EA8074 panel.
DRM created `card1`, `renderD128` and the MSM framebuffer. Ten SMMU context
faults for display streams `0x880` and `0xc88` occurred between MSM DRM
registration and the framebuffer console becoming available. The earlier
same-image probe had no such fault, so initialization is not consistently
fault-free. This does not establish the cause of the UI stall. The framebuffer
remained blanked at `4`; physical output, brightness and DPMS were not tested.
All 91 UFS disk and partition flags read back as `1`. No root filesystem was
mounted and no UFS write occurred. The rescue's explicit
`/usr/local/bin/reboot-to bootloader` returned the device to fastboot, confirmed
on the host. Raw logs remain private outside the repository.

## 2026-11-20 — installed Omarchy root, read-only audit

Mounted the `userdata` ext4 filesystem at `/dev/sda21` with `ro,noload` from
the guarded RAM rescue. The root identifies as Omarchy and contains Hyprland.
Its installed Mesa package is `1:26.2.4-1.4`; `/usr/lib/dri/msm_dri.so` is
absent. No changes were made to the mounted filesystem. This explains why the
installed root cannot use the Freedreno DRI module from Mesa 1.5; it does not
by itself establish the cause of the reported UI stall.

## 2026-11-20 — Hyprland renderer probe

Ran the installed Hyprland binary from the read-only userdata root with the
Mesa 1.5 package extracted into RAM and its DRI directory temporarily bound
over the installed root's DRI directory. The tested package's `.BUILDINFO`
matches the shared Freedreno PKGBUILD in PR #500. Hyprland selected DSI-1 at
1080×2248 and entered its event loop. Without a driver override, EGL reported
`llvmpipe` over GBM and Wayland; forcing `msm` reported that driver missing.
The first partial test still used the installed Mesa 1.4 GBM plugin, which
loaded the old Gallium 1.4 library and caused fallback to `llvmpipe`. After
binding the Mesa 1.5 GBM plugin from the RAM-extracted PR package over the
read-only root's plugin directory, the default GBM EGL test reported
`EGL driver name: msm` and `FD630` for both GLES and OpenGL core/compat. The
package `.BUILDINFO` matches the shared Freedreno PKGBUILD in PR #500.

During an active Hyprland test with the same Mesa 1.5 DRI and GBM directories,
Hyprland mapped only the Mesa 1.5 Gallium library and selected the DSI-1 DRM
output at 1080×2248. `hyprctl systeminfo` reported the DRM backend but left
GPU information blank. A separate Wayland EGL client still selected `swrast`
and reported `llvmpipe`. Hyprland logged pending page-flips and a failed
LinuxDMABUF `mmap`; Xwayland failed to start. The test processes were stopped
after each run. The kernel had logged a disabled DPU encoder while waiting for
its command-mode IRQ; its cause is unresolved. This identifies a working
Freedreno GBM path but does not confirm GPU composition or explain the UI
stall. The repository's read-only `tools/phone-smoke` could not execute on the
RAM rescue because it has no `bash`; this is not a valid supported-system
smoke report. `modetest -v` set the correct mode but exited without reporting
page-flip counts, so a standalone KMS page-flip test remains unverified. The
physical screen was not observed. Both temporary Mesa directory bind mounts
were removed afterward; the userdata mount remained `ro,noload`, all 91 UFS
disk/partition flags read back `ro=1`, and no UFS write was attempted.


## 2026-11-18 — NFS firstboot and matching modules

The current NFS boot ran `omamobile-firstboot` past the repeated service-enable
calls after version 0.1.8 changed them to `systemctl enable --no-reload`. The
run reached user setup, but its services/firewall step failed when UFW's
`iptables` could not create an nftables ruleset (`Could not fetch rule set
generation id: Invalid argument`). The journal records networkd and sshd
starting; a fresh phone-side smoke report and a stable SSH session were not
captured.

The booted kernel release was `7.3.0-rc6-omamobile-push1-gf61e96519032`, while
the disposable root initially contained modules only for
`7.3.0-rc6-omamobile-push1-g7062b50298ff`. I copied the module tree matching the
booted kernel from its RAM image into the disposable root and ran `depmod`;
host-side module resolution finds `nf_tables`. A subsequent RAM boot logged
all six UFS disks and 85 partitions read-only, and the NFS root handed off to
systemd. For this diagnostic boot only, UFW was disabled in the disposable
root because the preceding firstboot attempt could not install its nftables
rules. That means this run does not verify the firewall or resolve the
`iptables-nft` error.

The kernel logged simpledrm's `fb0`, then `msm-mdss` failed its deferred probe
with `-110` at 143 seconds. This does not establish what was visible on the
panel. Networkd brought `usb0` up and sshd listened, but later SSH sessions
timed out while opening the systemd login session. `omamobile-firstboot 0.1.9`
started keyring setup and had not left that step more than eleven minutes into
the boot; the device clock was in 1970 and DNS/NTP did not recover. No
`tools/phone-smoke` report, phone-side `networkctl status usb0`, visible
desktop, or GPU renderer was captured. The firstboot 0.1.9 mask change has not
completed on the phone.

Before this retry, the NFS journal had shown systemd reaching the graphical
target and SDDM reporting its autologin session started; that does not confirm
a visible frame or a working renderer.

In a separate RAM rescue, fb0 reported `blank=4`; writing `0` changed the
reported state and text was sent to tty1. The display was not visually
confirmed after that change. No phone-side smoke was captured after matching
modules were added. These tests used a disposable NFS root; no UFS partition
was flashed or explicitly written.

## 2026-11-16 — fresh current-stack NFS root

The checksum-verified Omarchy 4.5.0-3 root image (SHA-256
`75f2dc67630c2661705f3b796170621a3582d96093893ed72e6f680ec34581ce`)
was unpacked into a disposable NFS export. The first attempt read an older
export: two mounted ext4 test images had the same filesystem UUID, and NFS
served the older one despite the path naming the new image. The older root's
systemd unit and inode numbers exposed the mismatch. The new image was given
a distinct UUID while the phone was in fastboot, then exported again.

The second `fastboot boot` used RAM boot image SHA-256
`b58ab9dff9c960380563e22e3aedc41dcbe0ef58e6ec8386eb41d9251bc5710d`.
SSH on the phone confirmed kernel `7.3.0-rc6-omamobile-push1-gf61e96519032`,
an NFS root with the new image's inode and a test-only mask of the interactive
`systemd-firstboot` service. All six UFS whole-disk flags were `ro=1`. The
image's package database reported `omarchy 4.5.0-3`,
`omamobile-omarchy 0.1.45-1`, `omamobile-device-dipper 0.1.0-1`, and
`mesa 1:26.2.4-1.5`. `omamobile-firstboot` started and generated a private
pacman key, then spent several minutes importing the Arch keyring. The
disposable export was switched from `sync` to `async` during that import.

The phone later stopped answering ping and SSH while the USB gadget remained
enumerated. The firstboot log had not passed the keyring step. No raw
`tools/phone-smoke`, `networkctl status usb0`, visible desktop, or GPU renderer
was captured from this fresh root. This is a partial current-stack boot, not
the completed owner smoke gate. No flash or explicit UFS write was issued.

## 2026-11-17 — current-stack NFS phone-smoke

`tools/phone-smoke` ran on kernel `7.3.0-rc6-omamobile-push1-gf61e96519032`
with tools commit `f9b04b7`. It confirmed all 6 UFS whole disks and 85
partitions read-only, NFS as `/`, USB gadget bound, and `usb0` routable and
online at `172.16.42.1`. The display connector reported connected at
1080x2248; no failed systemd units were reported.

The required session check failed: Hyprland and the shell were not running.
GPU had no render node and no multitouch input device was present. Kernel
health had no oops, BUG or WARN, but `dmesg` had three new errors: the
watchdog did not stop, its hardware timeout was rejected, and a generated
unit failed. The boot check skipped because Dipper has no slot suffix; root
skipped as a nonpersistent NFS test root. Battery, sound, sensors, cameras,
Wi-Fi and Bluetooth were also skipped.

Firstboot was active. After importing the keyring, `gpg-agent` repeatedly
failed while locally signing trusted keys; SSH later stopped answering. The
report does not demonstrate a usable desktop or GPU. No UFS writes were made.

## 2026-11-16 — visible RAM console and NFS retry

A locally repacked RAM rescue image used the same kernel and DTB as the earlier
rescue image, with an SSH public key whose private key was available to the
test host. `fastboot boot` accepted it. SSH confirmed kernel
`7.3.0-rc6-omamobile-push1`, a `rootfs` root, all 6 UFS disks and 85
partitions read-only, and fbcon bound to the 1080x2248 framebuffer. A line
written to `/dev/tty0` was visible on the phone, as confirmed by the owner.
`/usr/local/bin/reboot-to bootloader` over SSH returned it to fastboot. The
local key and repacked image are not included in this PR.

Two RAM boots of the current NFS image then mounted the disposable Omarchy
root, but SSH in that root never became usable. The NFS connection stopped
and the phone restarted into its pre-existing ext4 `userdata` system, which
reported a writable main disk. Both times, `reboot-to bootloader` over SSH
returned it to fastboot. The second attempt used a test-only networkd rule
leaving `usb0` unmanaged and volatile journaling; neither prevented the
restart. Pstore was empty after the first restart. These attempts do not
verify a clean Omarchy boot, display session or package firstboot. No UFS
partition was flashed or explicitly written, but routine writes by the old
system cannot be ruled out.

Further diagnostic NFS boots left `usb0` unmanaged by both networkd and
NetworkManager in the disposable root. One boot reached
`omamobile-firstboot`, but pacman key population repeatedly waited on GPG
locks; removing stale lock files after the phone was back in fastboot let it
advance, not finish. A test-only initramfs clock seed and a separate boot with
`omamobile-firstboot` masked did not yield a stable NFS session. Each attempt
eventually restarted into the old writable `userdata` installation; SSH from
that installation returned the phone to fastboot. No new root image or boot
partition was flashed. The next gate is a reviewed single-slot install path,
not another claim that the old installation is the new Omarchy image.

A controlled comparison used the earlier base DTB in place of the later
`dispcc`-enabled DTB, with the same NFS initramfs and disposable root. With
firstboot isolated, both network managers leaving `usb0` alone, and volatile
journaling, the NFS connection still stopped before root SSH answered. A
second try changed only the host's disposable NFS export from `sync` to
`async`; it reduced the observed TCP send queue but did not prevent the same
restart into the old ext4 root. Host USB logs show the Omarchy gadget
disconnecting about a minute after enumeration. Neither the DTB change nor
the export sync mode is established as the sole cause. After the test the
export was restored to `sync`, the test-only root overrides were removed, and
the phone was returned to fastboot through the old installation's SSH.

## 2026-11-16 — RAM rescue and NFS retry

RAM image `426af1000e4912f26cff210f9ffe6017753289a93db53297489525ac974d11c9`
used the kernel and DTB from `04dc54e1…`, its initramfs with the NFS export
path updated, and `omamobile.initramfs` to stay in rescue. SSH host identity
matched the image's key. `uname -r` was `7.3.0-rc6-omamobile-push1`, `/` was
`rootfs`, and `/proc/iomem` reserved `0x85fc0000–0x8a8fffff`. All 91 disk and
partition `ro` flags read `1`; `qcom_wdt` was bound and its feeder was running.
The NFS root mounted read-only and contained systemd. The initramfs helper
`/usr/local/bin/reboot-to bootloader` returned the phone to fastboot.

The matching 1818 kernel modules were copied into the disposable NFS root. A
subsequent RAM boot of `16f038cd425d4a5b0afe0da9b60df58bc79a689f50772a9c0469a5fb74b22c8c`
used the same kernel, DTB and modified initramfs without the rescue flag.
Initramfs SSH briefly opened but was gone before a shell was captured. The
phone answered ping, but NFS-root SSH and a current phone-side smoke report
were not obtained. The handoff and visible screen on this retry are unverified.
No UFS flash or explicit UFS write was issued.

The disposable root's persistent journal subsequently showed an NFS handoff
on 2026-11-16, followed by `systemd-firstboot.service` starting its interactive
Initial Setup before `sysinit.target`; the user saw a timezone prompt on the
phone. SSH in the root had not started. For a further test only, that service
was masked in the disposable NFS root; `omamobile-firstboot` and its existing
test configuration were left enabled. The next RAM boot was accepted by
fastboot, but the resulting root and SSH were not confirmed. This mask is not
a packaged change or evidence of a working first boot.

A later retry staged the draft #839 `systemd-firstboot` drop-in and verified
the test answers with `omamobile-firstboot --check`. The disposable root also
had a temporary root SSH key, a networkd override leaving `usb0` unmanaged,
and volatile journal storage. The NFS root's SSH host key was observed on
the USB link, but the connection timed out before a shell or phone-side
`phone-smoke` could be captured. This does not establish the condition result,
storage flags or a running desktop on that boot. No UFS flash or explicit UFS
write was issued.

## 2026-11-16 — isolated NFS session and smoke report

RAM image `16f038cd425d4a5b0afe0da9b60df58bc79a689f50772a9c0469a5fb74b22c8c`
reached the disposable Omarchy 4.5.0-3 NFS root with kernel
`7.3.0-rc6-omamobile-push1`; systemd reported `running`. The phone showed
`0x85fc0000–0x8a8fffff` reserved and all 6 disk and 85 partition `ro` flags
were `1`. The root used a temporary SSH key, volatile journaling, an unmanaged
USB network override and a draft #839 drop-in. `omamobile-firstboot` was masked
at boot for isolation, then the mask was removed on the host after boot. This
does not validate the normal first-boot path. `networkctl` reported `usb0`
routable and unmanaged. No UFS flash or explicit UFS write was issued.

The read-only smoke report follows. Its display result is connector detection;
after the report, the user observed the Omarchy logo and password lock screen
on the phone. Unlock was not tested. Mesa rendering was not verified: no render
node existed.

### phone-smoke: dipper

Kernel `7.3.0-rc6-omamobile-push1`, tools at `4b535d0`, 2026-11-16T08:31Z.

| Check | Result | Detail |
| --- | --- | --- |
| boot (required) | skip | kernel 7.3.0-rc6-omamobile-push1, no slot in bootconfig or on the command line |
| storage guard (required) | ok | 6 whole disks read-only; 85 partitions; no writes outside the descriptor allowlist |
| root | skip | nfs test root; not persistent |
| kernel health (required) | ok | no oops or BUG; 0 WARN, 2 error lines in dmesg (0 known, 2 new) |
| new dmesg errors | not ok | watchdog: N: watchdog did not stop! x1; (generato[N]: '…' failed with exit status N x1 |
| systemd units | ok | none failed |
| USB gadget (required) | ok | bound to a600000.usb |
| display | ok | card0-Unknown-1 connected, 1080x2248 |
| GPU | not ok | no render node |
| session (required) | not ok | Hyprland runs, the shell isn't running |
| lock | ok | PAM file present (the shell didn't answer lock status) |
| touch | not ok | no multitouch input device |
| buttons | ok | gpio-keys |
| Wi-Fi | skip | no wireless interface |
| Bluetooth | skip | no controller |
| battery | skip | no battery power supply |
| sound cards | skip | none |
| sensors | skip | no sensor proxy |
| cameras | skip | no libcamera tools |
| thermal | ok | hottest zone 37 °C |

Packages: hyprland 0.57.0-3.3, libcamera 0.7.2-4.23, mesa 1:26.2.4-1.5, omacam 0.3.3-1, omamessages 0.2.2-1, omamobile-apps 0.2.3-1, omamobile-device-dipper 0.1.0-1, omamobile-firstboot 0.1.5-1, omamobile-keyring 20261026-1, omamobile-mirror 0.1.1-1, omamobile-omarchy 0.1.45-1, omamobile-owl-widgets 0.1.2-1, omamobile-settings 0.1.2-1, omamobile-shell 0.2.127-1, omamobile-voice 0.1.0-1, omaphone 0.2.3-1, omarchy 4.5.0-3, omatel-agent 0.2.4-2, quickshell 0.3.2.r7.g2b4501a-1

## 2026-11-16 — networkd reload and clean-boot retry

On the same NFS-root session, `networkctl reload` and `networkctl reconfigure
usb0` selected the packaged `/usr/lib/systemd/network/20-usb-gadget.network`;
`usb0` reported `routable (configured)` and online. A fresh SSH command
completed and the following `phone-smoke` ran. This verifies the live
reconfiguration, not that a clean boot reaches that state.

The follow-up smoke used kernel
`7.3.0-rc6-omamobile-push1-gf61e96519032`, tools at `92f8953`, and the same
RAM-only image (`4b028fb51f446647473e0a887dc5689a0c32cbedb98d8ee53ce81366a541d4f7`).
The handset clock was `1970-01-19T01:41Z`; that timestamp is not a test date.
Storage guard passed (6 disks, 85 partitions read-only), kernel health showed
no new errors, systemd had no failed units, USB and display detection passed,
and Bluetooth created `hci0` with its power state unknown. The root remained
NFS and non-persistent. The report still found no GPU render node, no shell
process, and no multitouch input device. No visual screen capture was made on
this pass.

### phone-smoke: dipper

Kernel `7.3.0-rc6-omamobile-push1-gf61e96519032`, tools at `92f8953`,
handset clock `1970-01-19T01:41Z`.

| Check | Result | Detail |
| --- | --- | --- |
| boot (required) | skip | no slot in bootconfig or on the command line |
| storage guard (required) | ok | 6 whole disks read-only; 85 partitions; no writes outside the descriptor allowlist |
| root | skip | NFS test root; not persistent |
| kernel health (required) | ok | no oops or BUG; 0 WARN, 0 error lines in dmesg |
| systemd units | ok | none failed |
| USB gadget (required) | ok | bound to a600000.usb |
| display | ok | card0-Unknown-1 connected, 1080x2248 |
| GPU | not ok | no render node |
| session (required) | not ok | Hyprland runs, the shell isn't running |
| lock | ok | PAM file present (the shell didn't answer lock status) |
| touch | not ok | no multitouch input device |
| buttons | ok | gpio-keys |
| Wi-Fi | skip | no wireless interface |
| Bluetooth | ok | hci0, powered unknown |
| battery | skip | no battery power supply |
| sound cards | skip | none |
| sensors | skip | no sensor proxy |
| cameras | skip | no libcamera tools |
| thermal | ok | hottest zone 60 °C |

After that report, `fastboot boot` accepted the same image without flashing a
partition. The kernel capture records switching to the NFS root after 4.8 s
and systemd starting. USB ping began answering after about 55 s; fresh SSH
still refused or timed out until about 110 s. The subsequent phone-smoke
report found the pre-existing dirty kernel `7.3.0-rc6-omamobile-push1-g2a318a96ae9d-dirty`
and an ext4 root on `userdata`, with the older Omarchy 4.0.6 package stack.
Its storage check found the main disk writable, so this report does not test
the NFS image. The user reported that the text console was no longer visible.
`reboot-to bootloader` over SSH then returned the phone to fastboot; product
was `dipper` and the bootloader was unlocked. No partition was flashed and no
explicit UFS write command was issued; incidental writes from the existing
system cannot be ruled out.

## Fastboot recovery (2026-11-15)

From the existing Linux system on `userdata` (not the new NFS-root image),
`DEVICE=dipper bin/omamobile fastboot` used the installed
`/usr/bin/reboot-to bootloader` and returned the phone to fastboot. The helper
reported `In fastboot`; `fastboot getvar product` returned `dipper` and
`fastboot getvar unlocked` returned `yes`. No partition was flashed. This
confirms the host-side recovery command for the installed system; it does not
verify the new NFS-root boot.

## RAM sessions (newest first)

| Date | `boot.img` SHA-256 | Source, as recorded | `/dev/sda` and UFS partitions | Checks and gaps |
| --- | --- | --- | --- | --- |
| 2026-11-15 | `04dc54e155b90e189b504df03476dc4ea086fdb6b02b2249aab54665a60ffa07` | Kernel `7.3.0-rc6-omamobile-push1`, base `da171eae4cb7b0a852b6629ff986c78ebab911c0` plus panel-driver commit `ee6f8c7139e428be8f8435e4d67503cd7b5486bc`; packed DTB SHA-256 `b5baf1c71cf85f2a0f2c16229aaa4a1a96a53ce00310f57caa68a435b631349d` | NFS root handoff confirmed. UFS guard logs say it set all 6 whole-disk nodes and all 85 partition nodes read-only; their `ro` flags were not read directly. | `fastboot boot` accepted the image. The NFS root was Omarchy 4.5.0-3 with `omamobile-omarchy 0.1.45`; its journal confirms switch to NFS, both `removed-region` reservations, the UFS guard, and the `qcom_wdt` watchdog device. The initramfs guard ran; watchdog feeder state was not read. The packed DTB was decompiled after this boot and contained both removed-region nodes. `/proc/iomem` was not captured, so the reserved-range gate is unverified. SSH was refused; `tools/phone-smoke`, phone-side `networkctl status usb0`, and the visible screen were not captured. The full kernel module bundle was added to the NFS root after this boot, so its userspace module-loading path was not tested. No flash or explicit UFS-write command was issued. |
| 2026-11-15 (retry, 60s watchdog) | `04dc54e155b90e189b504df03476dc4ea086fdb6b02b2249aab54665a60ffa07` | Same kernel, rootfs and packed DTB as the preceding row | Boot image accepted by `fastboot boot`; host enumerated CDC NCM and ACM; NFS requests confirmed root-systemd startup | NFS-root systemd journal records `RuntimeWatchdogSec=60s` rejected with `Failed to set watchdog hardware timeout to 1min: Invalid argument`; udev startup timed out and SSH/ping did not respond. No `/proc/iomem`, UFS flag readback, watchdog feeder, `phone-smoke` or visible-screen evidence from that root. No partition was flashed. |
| 2026-11-15 (retry, 20s watchdog) | `04dc54e155b90e189b504df03476dc4ea086fdb6b02b2249aab54665a60ffa07` | Same kernel, Omarchy 4.5.0-3 NFS root and packed DTB | NFS root; `/proc/iomem` showed `85fc0000-8a8fffff : reserved`; direct UFS `ro` flags were not captured | `networkctl status usb0` reported routable/configured and systemd was still `initializing`, not multi-user. The phone later returned to the existing ext4 root. `tools/phone-smoke`, watchdog feeder state, direct UFS `ro` readback and visible-screen evidence remain unavailable. The disposable test root used volatile journals and temporary early-SSH wiring, not included in the package. No partition was flashed. |
| 2026-11-14 | `d7bdde5e35b5c78a5878ebf4df28effefca35bed9a26c39098f473278d233ead` (debug image: `c86d517e5c3c5940f3099f46524968d59ddf6e0a258aac51fd00547b7acc24bb`) | Kernel `7.3.0-rc6-omamobile-push1-g7062b50298ff`, source `7062b50298ff2868e5a8a0be70483227e9c7db0b`; rootfs image SHA-256 `75f2dc67630c2661705f3b796170621a3582d96093893ed72e6f680ec34581ce` | No `/proc/iomem` or UFS `ro` flags were captured. A later SSH session reported kernel `7.3.0-rc6-omamobile-push1-g2a318a96ae9d-dirty` and root type `ext4`; `reboot-to bootloader` returned the phone to fastboot. | Omarchy 4.5.0-3 / `omamobile-omarchy 0.1.45` rootfs build and all rootfs smoke checks passed; 1818 kernel modules included `qcom-wdt`, MSM DRM and EA8074. The NFS image showed no firstboot log or created test account. A retry of this image was accepted by `fastboot boot`, but a 10-second host capture saw no SSH/RPC/NFS packets and an ARP probe got no reply. Raw `phone-smoke`, `networkctl status usb0`, `/proc/iomem`, UFS flags and display evidence remain unavailable. No flash command was issued; incidental writes by the existing ext4 system cannot be ruled out, so the earlier userdata backup may be stale. |
| 2026-11-13 | `50356521ec35b361261de571fc9f8033b55c8fd7ad0689010fb55d0cec16401c` | Corrected RAM image with NFS-root request | Exposed whole-disk and partition flags read-only during the NFS session | Booted kernel `7.3.0-rc6-omamobile-push1` with the disposable NFS root. Installed `omamobile-omarchy 0.1.44-1` locally; its hook applied 29 Omarchy 4.0.6 patches and `omamobile-omarchy-patches verify` passed. `phone-smoke` found no failed systemd units or new kernel errors; USB, DSI enumeration, GPU render node, Hyprland/session, touch, buttons, Bluetooth and thermal checks passed. Root check correctly identifies NFS as non-persistent. Lock IPC was intermittent. No flash or explicit UFS-write command was issued; see the later userdata-root observation below. |
| 2026-11-13 | `1d4ce38579a881b6d875a9a3bc025357f753cf119ce5ce16b3dbdc52f86da9f9` | Local RAM image; retained manifest has image/kernel/ramdisk hashes but no source commit; no NFS-root request was included | All exposed whole-disk and partition `ro` flags were `1` | Initramfs and USB/SSH ran on `7.3.0-rc6-omamobile-push1`. `stmfts` registered as `event2`; three touch-key and 428 absolute events arrived during three taps. Display stayed black: only simpledrm `Unknown-1` was present, with no DSI panel/backlight device. Mounted disposable NFS root without switching PID 1; chroot `pacman -Qk omamobile-device-dipper` reported 47 files, none missing. `reboot-to bootloader` used the initramfs helper because PID 1 never switched. No UFS write. |
| 2026-11-12 | `ac93a5d9f6787153cf620704f192c22da91cf2041789f16f4214111b8458d226` | Test kernel source: base `2a318a96ae9d4c87e061da1da13c05b11d305658` plus the FTS5 DTS change now proposed as kernel PR #249 commit `0d548847248512b1e8e1d40d66a85b81fe5ed471`; enabled directly for this test | `/dev/sda` absent (disk flag not applicable); `sdb`–`sdf` disk flags not read; all 85 partition flags `ro=1` | Full reserved range, kernel `7.3.0-rc6-omamobile-push1`, `stmfts` on `event2`, no Oops/BUG/panic/WARN. `qcom_wdt` and feeder state: not read. Exact touch X/Y extrema were not retained. No physical touch event captured; no UFS write. |
| 2026-11-12 | `1bf0ffd5302fff7fa75f49382567063d7e03bd52083baa81a88107a47dcbdbd2` | The booted test overlay itself defined the full touch node; its exact source was not retained. The later rebuild uses #249's disabled node plus [`device/dipper/overlays/fts5-touchscreen.dtso`](overlays/fts5-touchscreen.dtso), blob `f09381d59a110d02a8b8819f585e304efb1870a3`; both proposed sources postdate the boot. | `/dev/sda` absent (disk flag not applicable); `sdb`–`sdf` disk flags not read; all 85 partition flags `ro=1` | `0x85fc0000–0x8a8fffff` reserved; `stmfts` exposed `event2` on I2C14; physical input included contact, changing X/Y coordinates and `ABS_MT_TRACKING_ID=-1` release. `qcom_wdt` was bound; feeder state: not read. Exact touch X/Y extrema were not retained. No UFS write. |
| 2026-11-12 (superseded) | `e37196952fca14d5a9152871927039b2ac1d311ec500710f8611f9ac6eff8072` | The booted test overlay itself defined the full touch node; its exact source was not retained. The later rebuild uses #249's disabled node plus [`device/dipper/overlays/fts5-touchscreen.dtso`](overlays/fts5-touchscreen.dtso), blob `f09381d59a110d02a8b8819f585e304efb1870a3`; both proposed sources postdate the boot. The exact source commit for the stale `base-panel.dtb` was not retained. | `/dev/sda` absent (disk flag not applicable); `sdb`–`sdf` disk flags not read; all 85 partition flags `ro=1` | Touch events worked, but the DTB omitted `removed-region@86200000` and `removed-region@89100000`; `/proc/iomem` exposed those areas as System RAM. This was noticed when reviewing `/proc/iomem` after the boot's touch test. Replaced by the corrected image above. No UFS write. |
| 2026-11-11 | `665fcbd682cd8e64b3ffec1ff7f4ab9ca33a26b9b47b11073be7a3c267abf2b1` | #505 `2d67708e07728b13b5d2a9eda299ace8a1608163`; kernel/DTS #220 `26aa77c317cd029d16e58890c532562ca275c9f0` | Node absent, disk `ro=0`; all 85 partitions `ro=1`; `sdb`–`sdf` `ro=1` | `uname -r` `7.3.0-rc6-omamobile-push1`; `qcom_wdt` bound and feeder running; simpledrm fb0, USB/SSH and reserved `0x85fc0000–0x8a8fffff` passed. Physical screen, keys, touch, GPU and Wi-Fi not tested. RAM boot only; no UFS write. |
| 2026-11-10 | `540b5d31ea73a31ade9a8d8cb5152cf701dc3c2ad8256734790b0ef2db6dbdd0` | Combined #503/#505; kernel/DTS #220 `055a4019998f22cc0e2a8afef7650274a6ce0657` | Node absent, disk `ro=0`; all 85 partitions `ro=1`; `sdb`–`sdf` `ro=1` | Watchdog/feeder, simpledrm, USB/SSH, reserved TZ range, pinned host key and `reboot-to bootloader` passed; physical keys not captured. |
| 2026-11-10 | `a2d435a7430e7e4c145c61cdb9866d16929731859d91c7105e6bfcaf9e3e9dd7` | Rebased #503 NFS image with #220 `055a4019998f22cc0e2a8afef7650274a6ce0657` | `/dev/sda` present, set `ro=1`; six disks and all 85 partitions read back `ro=1` | `uname`, NFS root, multi-user systemd, watchdog and SSH passed; generic Arch test root only; link-loss recovery and Omarchy desktop untested. |
| 2026-11-10 | `0ee4f11d1973085c434e741a2e9dd73af5a9cd157296c25801ed5a92a6b9e9d9` | #505 `994944d7ecbacd69444221e6951153cb329a374e`; kernel/DTS #220 `055a4019998f22cc0e2a8afef7650274a6ce0657` | Node absent, disk `ro=0`; all 85 partitions `ro=1`; `sdb`–`sdf` `ro=1` | Watchdog/feeder, framebuffer, USB/SSH, reserved TZ range and `reboot-to` passed; physical keys not captured. |
| 2026-11-10 | `e2cdb765de21a5869a1db314c19f1fddb668219a51d3c9ce81a1a083536d711e` | Older rescue image; exact source commit unknown; its init differs from the shared init | Node present, disk `ro=0`; all 85 partition flags recorded `ro=1`, including `sda21` | Kernel `7.3.0-rc6-omamobile-push1`, initramfs root; no `logdump` or whole-disk removal in init, so not the October diagnostic init. SSH host key verified but key was not authorized. No UFS write. |
| 2026-11-09 | `e2cdb765de21a5869a1db314c19f1fddb668219a51d3c9ce81a1a083536d711e` | Image was reported booted; exact build/init source unknown | `/dev/sda` reported present with `ro=0`; partition details for this session unknown | The retained 08:53 capture is a dirty-kernel writable-root observation; whether it came from this exact image is unknown. |
| 2026-11-09 | `0f0ec9d62ebe57bef9ae8a4804bb23728f624daab824a0bf7dee18f63c2a3d59` | `linux-omarchy-mobile` panel test tree with EA8074 from #218; exact combined revision unknown | `/dev/sda` absent; all 85 partitions `ro=1`; `sdb`–`sdf` present, `ro=1` | Panel/DRM, backlight 0→511, DPMS off/on passed; `vdda` used a dummy regulator, GPU rendering and touch untested. |
| 2026-11-09 | Same boot as panel test, `0f0ec9d6…` | Same as panel test | Same as panel test | Full backup of 84 non-`userdata`, non-`super` GPT partitions was read from this guarded boot and every source hash/size verified; separate userdata archive was file-level and non-atomic. |
| 2026-11-09 | Unknown; exact image hash not retained | Omarchy Mobile RAM kernel; exact build unknown | Disk and partition flags not recorded | Power-only 10-second restart passed from Android and RAM kernel; no UFS write was attempted. |
| 2026-11-09 | `2244d74aea472b0c595b2056ad8618f614e6a9161b5b264c7f898939e626f318` | Initial NFS-root image reused the earlier #505 kernel and DTB | `/dev/sda` present and set `ro=1`; all six disks and 85 partitions logged `ro=1` | NFS root and SSH worked; systemd reported `RuntimeWatchdogUSec=20s`. Direct `uname`/sysfs reads were not captured. |
| 2026-11-09 | `f2f5cb2e3da8fe992d366dba36e059c0d9106cf14a7d1c8872c61ee144a4474b` | Earlier #505 image after `qcom-pon` was built in; exact kernel/DTS heads unknown | `/dev/sda` absent, disk `ro=0`; all 85 partitions and other disks `ro=1` | PMIC keys registered and Volume Down produced `KEY_VOLUMEDOWN`; watchdog/feeder, framebuffer and USB/SSH worked. |
| 2026-11-09 | `93484a91103c294f6c73799ae6cb7161019129b9f89ab331222ae04f10ecf3e1` | First #505 image before `qcom-pon` was built in; exact kernel/DTS heads unknown | `/dev/sda` absent, disk `ro=0`; all 85 partitions and other disks `ro=1` | Console, framebuffer, USB/SSH and watchdog/feeder worked; no physical key event was captured. |

On 2026-11-13, all 84 entries in the off-device partition checksum manifest
were revalidated. The separate 7.1 GB compressed userdata archive passed its
SHA-256 and zstd integrity checks; it remains a file-level, non-atomic archive,
not a raw partition image.

The 2026-11-13 NFS-root run used Omarchy 4.0.6 and
`omamobile-omarchy 0.1.44-1`; it does not satisfy the owner's requested
Omarchy 4.5.0-3/`omamobile-omarchy 0.1.45` run. The full
`tools/phone-smoke` output and `networkctl status usb0` were not retained.
The corrected image was booted again, but its USB gadget did not provide ping,
SSH or NFS connectivity, so the refreshed run and those captures remain pending.

The corrected NFS-root image above was booted with `fastboot boot`; it was not
flashed. The NFS test root's configured stable repository key was unknown to
the root's local pacman keyring, so it was not imported or trusted. The package
was built from the PR source on the phone and installed from the local archive
with a local-only pacman configuration. The pacman commands had no
`--nodeps`; all declared runtime dependencies were present in the root's local
package database. The normal `tools/phone-install-package`
repository path therefore remains unverified. During cleanup, the stale
`omamobile-wlan.service` was disabled in the disposable root because it waited
for unavailable modem/QMI services; Wi-Fi and modem remain unverified.

After the NFS session, USB SSH became unavailable and later returned. The
device reported `/dev/sda21` (`PARTNAME=userdata`) as the ext4 root, mounted
read-write, with no NFS-root request. The owner confirmed this was the
pre-existing Linux installation on userdata, not an installation made by this
test. No flash or explicit UFS-write command was issued. The existing system
may perform routine writes while running; the separately verified userdata
backup is file-level and non-atomic. The phone was then placed in fastboot,
where the bootloader reported product `dipper`. The corrected NFS image was
RAM-booted again; its USB gadget enumerated, but ping and SSH did not respond
and no NFS connection reached the host at the time of this note.

The old 4.0.6 test root also contained unowned files in
`/etc/systemd/system`: `omamobile-wlan.service`,
`omamobile-dipper-display.service` and `omamobile-nfs-trigger.service`.
The WLAN unit is a one-shot WCN3990/QMI startup calling
`/usr/local/bin/omamobile-wlan-up`; neither it nor that helper appears in a
package manifest or this repository. The display unit refers to a dirty local
kernel module release. The NFS trigger calls an unowned local helper. The old
root's package database does not identify who staged these files or when.
WLAN was disabled because modem/QMI is unverified; the other two are not
evidence of package-owned services. A new NFS root must omit all three.

That root also had unowned files in
`/usr/lib/firmware/qcom/sdm845/dipper/`. The local porting record says
`a630_zap.mbn` and the Dipper DSP images were extracted from this phone's own
vendor firmware and reassembled outside this repository; the old root's
package database confirms they were not package-owned. `a630_sqe.fw` came
from `linux-firmware-qcom 20260916-1`. The exact per-file source hashes used
by the render run were not retained. No vendor firmware blob is committed.

On 2026-11-13, the Mesa 1.5 package was extracted to tmpfs in the phone's
pre-existing userdata Linux root and tested from a console login with
`eglinfo -p gbm`. OpenGL core, compatibility and ES reported
`freedreno` / `FD630`; `LD_DEBUG=libs` confirmed this package's
`libgallium` and `dri_gbm.so` were loaded. This was not a Hyprland test and
the package was not installed to the root. The archive SHA-256 was
`6122aec6efa24194c5dca9733fd8a8936d92e8c99058f9c96d7cb0eb83b8a7fc`.

The test root had `a630_sqe.fw` owned by `linux-firmware-qcom
20260916-1`; `a630_zap.mbn` was extracted and reassembled from this phone's
own vendor firmware, as described above. The exact kernel release, boot-image
hash and kernel source revision for this console session were not retained.
The raw `eglinfo` and `tools/phone-smoke --json` output were not retained. The
contemporaneous summary says the GPU render node and display passed, while the
session check reported Hyprland and the shell were not running. Retained build
metadata ties the package PKGBUILD checksum to Mesa commit
`83aa88ec413644dfc2336e6d09ee0a06481edd01`. The boot image SHA-256 and exact
kernel source revision for this console session were not retained, so this
renderer result cannot be correlated with a particular kernel image. Do not
describe this as a Hyprland renderer test.

The missing Omarchy Hyprland files were copied from the test root's standard
user skeleton without overwriting existing files. `omamobile-setup-user` then
completed in the disposable test account; the monitor config contains scale 3,
and the earlier minimal config was kept as a recovery copy. Restarting SDDM
started Hyprland and the Omarchy shell automatically. A subsequent
`phone-smoke` confirmed the display, GPU, session, touch, buttons, Bluetooth
and thermal checks, with no failed units or new kernel errors. The root check
remains expectedly non-persistent, and lock IPC stayed intermittent. A
`phone-demo shot --wake` attempt did not complete, so visible desktop content
was not confirmed. No UFS write.

The original 10-29 count of 92 `/dev/block/by-name/` entries was not saved as a
name list. The retained backup and kernel records cover 84 non-userdata GPT
partitions plus `userdata`; the other seven names cannot be identified from the
retained artifacts and remain unknown.

## 2026-11-12 — corrected FTS5 RAM image

The first active-low FTS5 image (`e37196952fca14d5a9152871927039b2ac1d311ec500710f8611f9ac6eff8072`)
bound `st,stmfts5` on I2C14 and physical taps produced touch, multitouch X/Y
and release events inside the 1080×2248 panel. Its `base-panel.dtb` was stale:
the merged DTB omitted `removed-region@86200000` and
`removed-region@89100000`, exposing both ranges as System RAM in `/proc/iomem`.
The base DTB was reused from an earlier local build output; its exact source
commit was not retained. The missing reservation was noticed when reviewing
`/proc/iomem` after the boot's touch test, not before boot. The image is
superseded even though all 85 UFS partition flags were read-only.

Rebuilt the base DTB from the current preprocessed Dipper DTS, then reapplied
the same FTS5 overlay. The corrected RAM image
`1bf0ffd5302fff7fa75f49382567063d7e03bd52083baa81a88107a47dcbdbd2` booted on
kernel `7.3.0-rc6-omamobile-push1`. `/proc/iomem` showed
`0x85fc0000–0x8a8fffff` reserved; all 85 UFS partition flags were `ro=1`,
`/dev/sda` was absent, and `stmfts` plus `qcom_wdt` bound. The kernel reported
no Oops, BUG, panic or WARN. Physical touch on `/dev/input/event2` produced
`ABS_MT_TRACKING_ID`, changing `ABS_MT_POSITION_X/Y` values, and a release
event (`ABS_MT_TRACKING_ID=-1`). No UFS partition was written. The node is now
proposed disabled in kernel PR #249 at
`0d548847248512b1e8e1d40d66a85b81fe5ed471`; enabling it with the repository
overlay [`device/dipper/overlays/fts5-touchscreen.dtso`](overlays/fts5-touchscreen.dtso),
blob `f09381d59a110d02a8b8819f585e304efb1870a3`, is meant to rebuild the tested node; the boot image was not retained for comparison.
Both proposed sources postdate the historical boots.

Then booted a RAM image with the same FTS5 node enabled directly in the kernel
DTS. Image SHA-256:
`ac93a5d9f6787153cf620704f192c22da91cf2041789f16f4214111b8458d226`.
`stmfts` registered on `event2`; all 85 UFS partitions remained read-only,
`/dev/sda` was absent, and `/proc/iomem` retained the complete
`0x85fc0000–0x8a8fffff` reserved range. No Oops, BUG, panic or WARN appeared.
A physical touch event was not captured during this direct-DTS boot; the
preceding overlay boot with identical node properties captured contact,
changing X/Y and release. No UFS partition was written.

## 2026-11-11 — rebuilt #505 RAM image

Built and booted `boot.img` SHA-256
`665fcbd682cd8e64b3ffec1ff7f4ab9ca33a26b9b47b11073be7a3c267abf2b1` with
`fastboot boot` from #505 `2d67708e07728b13b5d2a9eda299ace8a1608163` and
kernel/DTS #220 `26aa77c317cd029d16e58890c532562ca275c9f0`. `uname -r` was
`7.3.0-rc6-omamobile-push1`. The `/dev/sda` whole-disk node was absent; its
sysfs flag remained `ro=0`. Nodes `/dev/sdb`–`/dev/sdf` were present with
`ro=1`; all 85 partition flags were `ro=1`, and `ufs-ro` logged the guard for
each. `qcom_wdt` was bound and the watchdog feeder was running. simpledrm
registered `fb0`; authenticated USB SSH worked. `/proc/iomem` reserved
`0x85fc0000–0x8a8fffff`, including the former TZ range. The physical screen,
keys, touch, GPU rendering and Wi-Fi were not tested in this run. Only
`fastboot boot` was used; no UFS partition was written.

## 2026-11-10 — final PR #505 RAM image

Booted image SHA-256 `0ee4f11d1973085c434e741a2e9dd73af5a9cd157296c25801ed5a92a6b9e9d9` with `fastboot boot`; it was built from PR #505 head `994944d7ecbacd69444221e6951153cb329a374e` and kernel/DTS PR #220 head `055a4019998f22cc0e2a8afef7650274a6ce0657` (touch PR #219 is merged). `uname -r` was `7.3.0-rc6-omamobile-push1`; `/` was the initramfs (`rootfs`). The guard reported the UFS devices read-only. Sysfs showed six disks: `sda` had `ro=0` but its whole-disk `/dev/sda` node was absent; `sdb`–`sdf` each had `ro=1` and present nodes. All 85 partitions had `ro=1`. This matches PR #505's intended missing-node case for `sda`; no UFS write was attempted.

`qcom_wdt` loaded and `/usr/bin/watchdog -t 5 -T 30 /dev/watchdog0` was running. simpledrm registered `fb0`; USB gadget and authenticated SSH worked. `/proc/iomem` marked `0x85fc0000–0x8a8fffff` reserved, covering the former TZ range. The final image's physical button events were not captured, so the earlier Volume Down/Up observations are not evidence for this kernel. The image's `reboot-to bootloader` helper successfully returned the phone to fastboot; fastboot reported product `dipper` and unlocked `yes`. The only boot operation was `fastboot boot`; no UFS partition was written.


## 2026-11-10 — rebased #503 and combined #505 RAM runs

The rebased PR #503 init was RAM-booted with PR #505's Dipper builder and
kernel/DTS PR #220 at `055a4019998f22cc0e2a8afef7650274a6ce0657`. NFS image
SHA-256: `a2d435a7430e7e4c145c61cdb9866d16929731859d91c7105e6bfcaf9e3e9dd7`;
`uname -r` was `7.3.0-rc6-omamobile-push1`, and `/` was NFS. The initramfs
used BusyBox `mount`; the export was a generic Arch Linux ARM test root, not an
Omarchy rootfs. Direct sysfs reads returned `ro=1` for all six UFS disks and
all 85 partitions. The guard logged each read-back, including `/dev/sda` set
read-only for NFS. Systemd reached the multi-user target with
`RuntimeWatchdogUSec=1min`; SSH remained available. `reboot-to bootloader`
returned the phone to fastboot. No UFS write was attempted. The NFS link was
not deliberately dropped, so hard-mount link-loss recovery remains untested.

The combined #503/#505 non-NFS RAM image was also booted. SHA-256:
`540b5d31ea73a31ade9a8d8cb5152cf701dc3c2ad8256734790b0ef2db6dbdd0`.
`uname -r` was `7.3.0-rc6-omamobile-push1`; `/` was the initramfs (`rootfs`).
Direct sysfs reads returned `ro=1` for all 85 partitions and disks `sdb`–`sdf`;
`sda` remained `ro=0`, while the guard removed `/dev/sda`. The `qcom_wdt`
module and feeder ran, simpledrm registered `fb0`, USB/SSH worked, and the
former TZ range was reserved in `/proc/iomem`. The rescue SSH host key matched
the build output, and `reboot-to` returned the phone to fastboot. No UFS write
was attempted. Physical input events were not captured on this exact image.

## 2026-11-09/10 — recovery and historical RAM observations

The current `recovery` partition matches the `recovery.img` in the
checksum-verified 15-partition backup of the installed system captured on
2026-10-29 at 19:01;
both have SHA-256
`7691a33e8b65d1ffcbf67b16fd4dc5c4c421420230f230db312512c73abc2221`. Its
Android boot header contains a gzip-compressed kernel that identifies as
`Linux version 4.9.337-perf-g0b3e38ef6c40`, not the 7.3 diagnostic kernel. This
confirms the current partition holds the installed ROM's recovery image. The order of the
snapshot and the two diagnostic writes remains unknown. `logdump` is not in the
15-partition backup. A separate live, file-level userdata archive was
verified off-device; it is not a raw partition image or an atomic snapshot,
and the filesystem remained mounted during the copy.

The recovery image hash is recorded from the backup, but the backup's `boot.img`
was not present among the accessible artifacts for this review. Its kernel
string and whether it matches the recovery build remain unknown.

Before entering fastboot, the handset answered over USB SSH; no restart was
needed to restore SSH. Holding Power alone for 10 seconds restarted the phone
back into Android both from the installed system and under the Omarchy Mobile
RAM kernel. Volume Down + Power then entered fastboot. Read-only fastboot
variables reported product `dipper` and an unlocked bootloader.

A separate NFS-root attempt used a RAM-only image with SHA-256
`2244d74aea472b0c595b2056ad8618f614e6a9161b5b264c7f898939e626f318`, reusing
the earlier #505 kernel and DTB and repacking its initramfs with
`OMAMOBILE_NFSROOT`. The persistent NFS-root journal recorded NFS mode and
read-only confirmations for all 85 unique UFS partitions and all six UFS
disks; the guard reads each `ro` value back as `1` before logging success. SSH
confirmed `/` was NFS, PID 1 was systemd, and the system was running with
`RuntimeWatchdogUSec=20s`. The exported root was a generic Arch Linux ARM base,
not an Omarchy rootfs. No UFS write was attempted. Direct `uname -r` and
sysfs `ro` output were not captured, and this pre-#484 image does not verify
the post-#484 whole-disk-node absence check.

An earlier read-only SSH observation, reported on 2026-11-09 at 08:53 UTC,
was on the dirty kernel
`7.3.0-rc6-omamobile-push1-g2a318a96ae9d-dirty`. It reported `/dev/sda21`
mounted as the root filesystem read-write, with `/sys/block/sda/ro=0` and
`/sys/block/sda/sda21/ro=0`; the other partition `ro` values were `1`. Thus
`/dev/sda` existed and the whole main LUN was writable. The surviving record
does not say how that image was started, the device uptime at the check, or
whether its diagnostic init's `logdump` mirror was running. Do not boot that
old image again. Systemd reported failure to set the `qcom_wdt` timeout to one
minute, but the exact journal line was not retained and the feeder was not
checked. This old-kernel observation is not evidence for PR #505's image.

The image with SHA-256
`e2cdb765de21a5869a1db314c19f1fddb668219a51d3c9ce81a1a083536d711e` was
previously described here as PR #505's RAM image. On 2026-11-10, I booted that
exact file again with `fastboot boot` and read it over the USB serial shell.
It reported `7.3.0-rc6-omamobile-push1`, but `/dev/sda` existed with
`/sys/block/sda/ro=0`; `/sys/block/sda/sda21/ro=1`. Its initramfs root was
`rootfs`; no UFS write was attempted. Offline extraction found init SHA-256
`ab6db476f5cd26cb84a8346e18da5b2137530091be504c47a23b0a21934277c5`, different
from the checked-in shared init. It contains neither the October `logdump`
mirror nor whole-disk-node removal, so it is not the October diagnostic init
and does not verify PR #505's guard. Do not treat it as #505's image or boot it
again. SSH host-key verification succeeded, but the configured key was not
authorized. The separate rescue image still provides authenticated SSH
and `reboot-to bootloader` returned the phone to fastboot without writing UFS.

`pm8941_pwrkey` and `pm8941_resin` registered. On the earlier final image, a
physical Volume Down press produced `KEY_VOLUMEDOWN` (code 114, value 1), and
Volume Up produced `KEY_VOLUMEUP` (code 115, value 1). The current kernel
image's button events have not yet been rechecked. The owner reported seeing
the console during the first boot.

The table above records `/dev/sda` absent on the earlier `93484a91…` and
`f2f5cb2e…` boots. Those results are separate from the `e2cdb765…` artifact
checked above, where `/dev/sda` was present and writable. The final #505 image
and its successful disk-node check are recorded below. The `e2cdb765…` boot did
report all 85 UFS partition flags read-only; no UFS writes were made.
`/proc/iomem` reports `0x86200000–0x88efffff` as System RAM and
`0x88f00000–0x890fffff` as reserved, so the TZ range is not reserved in this
RAM boot's map. A separate EA8074 panel test used a RAM-only overlay on
2026-11-09 with kernel `7.3.0-rc6-omamobile-push1` and boot image SHA-256
`0f0ec9d62ebe57bef9ae8a4804bb23728f624daab824a0bf7dee18f63c2a3d59`. The panel
driver bound to `ae94000.dsi.0`, DRM reported `connected` at `1080x2248`, and
the owner confirmed the console was visible on the lit panel. All 85 partition
flags were `ro=1`; `/dev/sda` was absent, while `/dev/sdb` through `/dev/sdf`
remained present and had `ro=1` on this pre-#484 image. Backlight value 0 was
accepted and restored to 511 (maximum 1023). Framebuffer blanking changed
DRM `dpms` from `On` to `Off` and back to `On`. FTS5 contact, coordinate
changes and release were later captured on 2026-11-12; see above. Hyprland
delivery remains untested. The panel log included a missing DSI `vdda`
supply (dummy regulator) and missing `a630_sqe.fw`; the display initialized,
but GPU rendering was not tested. The RAM image had no Arch root, and the probe
did not write UFS. The installed-system backup checksums were verified before
boot.
After this session, a read-only backup of all 84 non-`userdata`, non-`super` GPT
partitions was captured from this guarded RAM boot. Each partition's source
SHA-256 and byte count were checked against the decompressed local copy, and
the compressed archive checksums were rechecked. The separate live userdata
archive remains file-level, non-atomic, and is not a raw partition backup.
The backup is stored outside the repository; it must not be published. After
the last Android boot and before any future flash, the on-device partition
checksums must be taken again and compared with the off-device backup because
Android can rewrite modem partitions. A reviewed button-by-button restore
procedure and supported single-slot writer are still required before a flash.

## 2026-10-29 — installed-system facts, read-only over SSH with the owner's Magisk root

- **SoC** SDM845. Live DT root: `model = "Xiaomi Technologies, Inc. Dipper new MP v2.1"`,
  `compatible = "qcom,sdm845-mtp", "qcom,sdm845", "qcom,mtp"`,
  `qcom,msm-id = <0x141 0x20001>`, `qcom,board-id = <0x37 0x00>`.
  6 GB RAM. `androidboot.cert=M1803E1A` (Mi 8 Global), `hwversion=3.13.0`.
- **The installed system** is a custom Android 14 (SDK 34) ROM with Magisk 30.7, not MIUI;
  its build fingerprint is a spoofed MIUI 8.1 string, and `ro.boot.verifiedbootstate=green`
  with `flash.locked=1` contradict the owner's unlocked bootloader. **No boot-state claim
  may be made from Android on this phone; read it in fastboot.** Running kernel 4.9.337.
- **Not A/B for the OS.** 92 entries under `/dev/block/by-name/`: a single `boot` (64 MiB),
  `recovery` (64 MiB), `dtbo` (8 MiB), `system`, `vendor`, `cache` and `userdata`
  (113 GiB). Only the bootloader chain is slotted: `xbl`, `xbl_config`, `abl`, `tz`, `hyp`,
  `aop`, `cmnlib`, `cmnlib64`, `devcfg`, `keymaster`, `qupfw`, `storsec`.
  **There is therefore no known-good OS slot to fall back to**, which the shared Pixel
  safety model assumes. A full backup of the installed system is a precondition, not a nicety.
- **Boot image** uses Android header v1, page size 4096, `second_size = 0`, and the kernel
  blob ends with **two concatenated FDTs of ~480 KB each** (`d00dfeed`, version 17): the
  base DTB is appended to the kernel and ABL selects one by msm-id/board-id.
- **Display** Samsung **EA8074**, 1080x2248, command mode, 60 Hz, notch; physical
  68 x 142 mm. Confirmed twice: `msm_drm.dsi_display0=dsi_ss_ea8074_notch_fhd_cmd_display`
  on the kernel command line, and the live DT node `qcom,mdss_dsi_ss_notch_fhd_ea8074_cmd`
  (`qcom,mdss-dsi-panel-width = <0x438>`, `height = <0x8c8>`, `framerate = <0x3c>`).
- **Touch is STMicroelectronics, not FocalTech.** Live DT, on `i2c@a98000` (mainline
  `i2c14`): `fts@49 { compatible = "st,fts"; fts,irq-gpio = <&tlmm 31 ...>;
  fts,reset-gpio = <&tlmm 32 ...>; fts,default-fw-name = "st_fts_e1.ftb"; }`, with
  `fts,tp-vendor = <0x48>`. The running kernel's input device is `N: Name="fts"`.
  An `atmel,mxt-ts@4a` node exists as the alternate vendor and is not the active one.
  Mainline's ST driver is `st,stmfts` (`drivers/input/touchscreen/stmfts.c`),
  a different driver from Xiaomi's downstream `st_fts`; tested on Dipper
  2026-11-12, see above. No sibling board helps —
  polaris uses `syna,rmi4-i2c@20`, beryllium a FocalTech/Novatek part.
- **Audio** `sdm845-tavil-snd-card` (WCD9340). **Fingerprint** Goodix, capacitive
  (`fingerprint_goodix`, `uinput-goodix`); no mainline driver, out of scope.
  **Buttons** `qpnp_pon` plus `gpio-keys`.
- **UFS** host at `1d84000.ufshc`. The installed Android `system` is dm-verity over the
  `system` partition.

## 2026-10-29 — first light, and what the hardware said

**The phone reached a shell on an unpublished kernel tree.** `fastboot boot` of
the image used kernel release
`7.3.0-rc6-omamobile-push1-g2a318a96ae9d-dirty` with its matching DTB: UFS up
(all six LUNs, ext4 mounts), USB NCM gadget, dropbear, gpio-keys, 8 CPUs and
5.7 GB RAM. This records the historical first-light tree; kernel PRs [#218](https://github.com/derekross/linux-omarchy-mobile/pull/218),
[#219](https://github.com/derekross/linux-omarchy-mobile/pull/219) and
[#220](https://github.com/derekross/linux-omarchy-mobile/pull/220) are later
successor changes and are not the code tested in that boot; FTS5 PR #219 is now
merged into linux-omarchy-mobile. The diagnostic image's guard allowed `userdata` and `logdump`
writes. A temporary init widened the allowlist to include `logdump` and used
`dd` to copy the kernel log there every two seconds during the 2026-10-29
diagnostic boot. The 2026-11-09 read-only check was on this dirty October
kernel; it found `/dev/sda21` as the read-write root and therefore `/dev/sda`
present and writable. The saved record does not establish whether the mirror
process was still running during that later check, nor the device uptime then.
Two diagnostic-image writes to the `recovery` partition from rooted Android were also
made on 2026-10-29. The existing 15-partition backup did not include `logdump`;
an unverified `logdump.img` file is not evidence of a checked phone backup.
The current recovery SHA matches the verified 2026-10-29 19:01 backup
described above; the order of that backup and the two writes is unknown. The
image previously attributed to PR #505 was `e2cdb765…`; its `/dev/sda` node was
present and writable, so it does not verify #505's guard. The final #505 image
and its successful check are recorded above. The mount options and whether
`persist` was mounted during first light are not recorded here.

The recorded 15-partition backup of the installed system before the radio runs
was checksum-verified.

The 2026-10-30 comparison found `boot`, `recovery`, `dtbo`, `vbmeta`,
`fsc`, `devinfo`, `misc`, `logo`, `splash`, `persistbak`, `modemst2`
and `fsg` byte-identical; only `persist`, `modemst1` and `frp` changed.
All five NV partitions were read-only before and after the recorded runs. The
cause of the three differences is not established. Other recorded activity:
NFS-root Omarchy sessions on 2026-10-30, 2026-10-31 and 2026-11-02; modem
starts under `rmtfs -r`, followed by an XPU violation crash and remoteproc
recovery loops. The sequence of boots between the two backups (date, installed
Android or RAM image, and actions) has not been reconstructed, so the later
backup is not a baseline and the changes are not attributed to Android or
Omarchy. The installed ROM's current recovery image matches the 10-29 19:01
backup and its kernel identifies as `4.9.337-perf-g0b3e38ef6c40`; the backup's order
relative to the two diagnostic writes remains unknown. The 10-29 first-light
boot is recorded as `fastboot boot` from RAM, not a recovery boot. The separate
08:53 old-kernel observation's launch method remains unknown; the surviving
record does not establish its source.

### What had to be fixed before any of that
Six defects in the recovered [sdm845-mainline MR !71](https://gitlab.com/sdm845-mainline/linux/-/merge_requests/71)
work, three of them fatal:

1. **`qcom,board-id = <69 0>` (0x45) is polaris's.** dipper reports `0x37`. ABL matches on
   it and silently refuses the whole boot image otherwise — no kernel output,
   no panic, just a reboot. Two blind diagnostic-image attempts were written to
   the `recovery` partition from rooted Android before this mismatch was
   corrected.
2. `drm_panel_init()` no longer exists; the panel probe needed the refcounted
   `devm_drm_panel_alloc()`.
3. `panel-samsung-ea8074.ko` had no `MODULE_LICENSE()`, so modpost refused to link.
4. The touch node named `focaltech,ea8074` at `0x38`; the chip is ST at `0x49`.
5. Its Kconfig entry was copied from an SPI panel (`depends on SPI`, `select DRM_MIPI_DBI`)
   for what is a `mipi_dsi_driver`.
6. `ts_int_default` carried `bias-pull-down` from beryllium; dipper's vendor tree says
   `ts_active { pins = "gpio31", "gpio32"; drive-strength = <16>; bias-pull-up; }`.

### And two kernel-config lessons, both found on the hardware
Devices probe once, early. A driver that only appears later as a module never gets a
second chance — the device is left unbound and is not even on the deferred list. Proven
twice: the Qualcomm PHYs (so no USB and no storage: `dwc3: failed to initialize core`,
`sync_state() pending due to 88e8000.phy`), then i2c (`modprobe i2c-qcom-geni` bound to
nothing, and a hand-written `bind` failed). That is why every driver needed for first
light was built in (`=y`).

### Touch: first failed probe (historical)

The original FTS4-only driver bound and timed out. These observations describe that
kernel revision; they are not results from the current FTS5 driver. The current
driver and Dipper node were tested on 2026-11-12; see the corrected FTS5 RAM image
above:

- `i2c-14` and `i2c-5` come up; the touch device **exists as `14-0049`**, so the bus and
  address in the DTS are right.
- Both supplies are enabled and in use: `ldo28` at 2.856 V, `vreg_tp_vddio` at 1.8 V,
  one user each.
- `stmfts` binds and fails with **`-110`** from `wait_for_completion_timeout` — it sends
  its first command and never sees the reply interrupt.
- The interrupt pin bias was corrected to pull-up per the vendor tree. **No change.**
- `i2cdetect` output is incoherent: in `-r` mode every even address reads as present and
  every register as `0x00`; in quick-write mode `0x49` is not detected at all, while
  `stmfts`'s own `i2c_smbus_write_byte` to `0x49` returns success.
- On i2c5 the driver logs **`geni_i2c_gpi_xfer:I2C timeout` / `GPI transfer failed: -110`**,
  so the GPI DMA path is not reliable here.
- GPI DMA cannot simply be turned off: this kernel's `geni_i2c` requires the channels and
  defers forever without them (`geni_i2c: Failed to get tx DMA ch`). There is no FIFO
  fallback to fall back to.

At the time, it was unknown whether GENI/GPI or the FTS5 protocol caused the timeout.

### FTS5: historical tap and published driver series

The live controller is FTS5. A separate historical RAM boot on 2026-10-30, using
the unpublished kernel release above, registered `stmfts` and a physical tap
produced `ABS_MT_POSITION_X`. That observation is not a test of the current
kernel PRs. The current driver and Dipper node were tested on 2026-11-12; see
the corrected FTS5 RAM image above. The public successor series and its binding are in
[kernel PR #219](https://github.com/derekross/linux-omarchy-mobile/pull/219).
The upstream v8 cover letter states it was tested on Xiaomi Mi 8:
[FTS5 v8 cover letter](https://lists.openwall.net/linux-kernel/2026/09/25/2211),
[FTS5 driver patch](https://lists.openwall.net/linux-kernel/2026/09/25/2213),
[controller-ready fix](https://lists.openwall.net/linux-kernel/2026/09/25/2214),
[binding update](https://lists.openwall.net/linux-kernel/2026/09/25/2212).
Firmware loading, low-power touch and wake-on-touch/AP-SLPI handoff are not implemented.
# 2026-11-19 — Dipper boot argument for systemd's firstboot prompt

The default RAM-only boot image command line now includes
`systemd.firstboot=off`, following the owner's review of #839. This is
Dipper-specific and leaves the shared firstboot package unchanged. The
argument is present in the generated boot manifest, but it has not yet been
verified on the phone. The firstboot prompt and the Omarchy firstboot service
still need a clean on-device run after the NFS reset/fallback path is resolved.

## 2026-11-19 — guarded on-device backup comparison

Booted the rescue image `5e0370e4933232f2e56440ab19e0950981a99bb96113619313d462df1c64cd70`
with `fastboot boot` (RAM only). Its `omamobile.initramfs` argument held PID 1
in the initramfs, and its empty UFS allowlist left every partition read-only.
Before hashing, the phone reported `ro=1` for all six UFS disks and all 84
backed-up partitions; partition names, nodes and sizes matched the 11-09
manifest. SHA-256 was calculated from each phone partition and compared with
the raw-source hashes captured with the 11-09 compressed backup: **83 of 84
matched**. Only `logfs` differed. No partition was mounted or written during
this comparison. The full hashes and comparison table remain off-repository.

Between the 11-09 capture and this check, the phone ran Android, the older
installed Linux system and multiple RAM/NFS boot attempts. The 11-13 check
only re-hashed backup files; it did not compare the phone. The NFS attempts
between 11-13 and 11-16 also fell back into the older writable install at
least eight times, as counted in the owner's review. The exact boot sequence
and cause of the `logfs` change are not established. The other 83 backed-up
partitions, including `persist`, `modemst1` and `modemst2`, matched byte for
byte at this check.

The rescue boot exposed `/chosen/pureason` as big-endian `0x000800a1`, with
an empty pstore. This boot followed a manual entry to fastboot, so the value
does not establish the cause of the earlier NFS resets. The roughly one-minute
reset cause remains unknown; the fallback path is recorded below.
The rescue image lacked `reboot-to`; a previously built static AArch64 helper
was copied into `/run` (RAM) and `reboot-to bootloader` returned the phone to
fastboot. The bootloader again identified the product as `dipper`. No UFS
partition was flashed during this comparison.

## 2026-11-19 — RAM-rescue fallback image preflight

An initial RAM-rescue image without an NFS request exposed a storage-guard
defect: all 85 partition flags were `ro=1`, but the `sda` disk flag was `0`
and its whole-disk node was removed. It was never flashed. The shared init
fix is proposed separately in omarchy-mobile#919; with no writable allowlist,
it marks the whole disk read-only and checks it at hand-over.

A second RAM-only image, SHA-256
`06a8cc368ce86ae6ba570208d0291c642f143019283dd0a88d99ef2365d746b3`,
included #919's exact `initramfs/init`, `ram-rescue` mode, no NFS request,
disabled automatic USB-failure panic, and a static `reboot-to` in RAM.
`fastboot boot` reached an SSH shell on kernel `7.3.0-rc6-omamobile-push1`;
`/` remained rootfs, all six UFS disk flags and all 85 partition flags read
`ro=1`, and the built-in `reboot-to bootloader` returned to fastboot. After
verifying the existing boot partition matched the 11-09 backup, flashed this
image to the single `boot` partition. `reboot-to bootloader` and then a plain
`fastboot reboot` returned to this persistent rescue image; all six disks and
85 partitions again reported `ro=1`. No userdata or other partition was
written. The 11-09 raw boot image remains available as the restore source;
its raw SHA-256 is `e9ef7bff84d181e09de286a95b9487ec5fcb5c0cc53db3ae780d6a64ceb4fbe8`.
The persistent rescue fallback now works. The cause of the earlier NFS reset
is still unknown; the next NFS test can collect its reset evidence without
falling into the older writable userdata system.

### Persistent boot write record and recovery

The exact host command used for the 11-19 write and whether it included
`fastboot -s <serial>` were not retained. The post-write check read only the
first 23,314,432 bytes of the 64 MiB `boot` partition and compared that prefix
with the image; a full-partition hash was not captured then. On 2026-11-21 a
read-only audit confirmed the current partition is still 64 MiB and `ro=1`,
and calculated the whole-partition SHA-256 as
`2453231cb158f8cea115fc998a9e3c8075e564c33182b2e234e6bbabe6c3cf88`. No
boot-partition write is recorded after 11-19, but this is a current hash, not
a hash captured immediately after the write. A search of retained text logs
and shell histories found no matching `fastboot flash boot` command, so its
exact arguments and serial pinning remain unknown. Quatrix One owns the
handset and operated the test.

The recorded 11-09 raw boot image is the recovery source
(`e9ef7bff84d181e09de286a95b9487ec5fcb5c0cc53db3ae780d6a64ceb4fbe8`). A
restore has not been run. It would put back the image associated with the
pre-existing ext4 `userdata` system that earlier fallbacks entered with a
writable main disk. That outcome is inferred from those fallbacks, not verified
by restoring this exact image; it is not a safe read-only rescue path. After
verifying that file against this hash and
confirming the target is the unlocked Dipper, the documented recovery command
would be `fastboot -s "$FASTBOOT_SERIAL" flash boot "$BOOT_11_09_IMAGE"`,
followed by `fastboot -s "$FASTBOOT_SERIAL" reboot`. Do not run it until the
maintainer confirms the recovery plan; no further phone writes are authorized
while that review question is open.

## 2026-11-20 — current rootfs and canonical initramfs preflight

Built a fresh aarch64 root with Omarchy 4.5.0-3, omamobile-omarchy
0.1.48-1, shell 0.2.135-1, main firstboot 0.1.6-1, device-dipper
0.1.2-1 and the exact shared Mesa 1:26.2.4-1.5. Its modules match
`7.3.0-rc6-omamobile-push1-gf61e96519032`. All 17 rootfs-smoke checks,
e2fsck and compressed-stream comparison passed. The pristine compressed
image SHA-256 is
`8f420324dbc65cb18a18a283cf7d069216c60b6250c90c0f7e6e2e6ed599b616`.
An offline ownership audit covered 394 system/user service definitions and
found none unowned. A private provisioned copy passed the packaged firstboot
configuration check; no personal account or Wi-Fi configuration was included.
This is build/offline evidence, not a successful full-system phone boot.

The canonical Dipper initramfs builder, using #919's closed whole-disk guard,
produced a matching watchdog/reboot-capable candidate. A diagnostic DTB keeps
the previously tested display/GPU/touch wiring and disables untested ADSP,
Bluetooth UART and Wi-Fi. Its rescue-preflight boot image SHA-256 is
`17b2d97bfef8a11a9ee1044f54dc723a0c0fad4627cd8a93945113d91353990a`.
Two RAM boots with explicit `omamobile.initramfs` stopped before NFS handoff:
root stayed rootfs, the automatic 30-second watchdog feeder was active, and
all six UFS disks plus 85 partitions were read-only. The captured iomem
contains `85fc0000-8a8fffff : reserved`; dmesg records both removed-memory
regions as nomap. Strict pinned-key SSH and the built-in `reboot-to bootloader`
worked. No UFS write occurred.

The separate NFS-handoff image remained unbooted at this preflight; subsequent
NFS attempts are recorded in the 2026-11-20 current-stack entry above. They did
not establish a clean persistent-userdata boot. The maintainer has asked that no
further phone writes be made until he replies on the boot and NFS questions.
Clean-session phone-smoke, network status and physical-session evidence remain
required before this device PR leaves draft.

## 2026-11-20 — firmware extractor with a valid factory source

After the archived phone vendor filesystem failed the earlier check, tested
#917 against a locally downloaded official Xiaomi Global Dipper
V12.0.3.0.QEAMIXM factory archive. The archive SHA-256 was
`06f138e00ad47bbb17ea5a03f4d703498b80d9d99a6d5f58ca3033f853658d21`.
Only vendor, modem and Bluetooth images were extracted on the host; no flash
script ran. Sparse vendor was converted locally, and all three filesystems
were mounted read-only. The actual vendor build.prop identified `dipper`.
The unchanged extractor passed without force, staged 73 firmware files at
the DTS-requested destinations and passed all 73 output checksum checks.
The proprietary archive, firmware and source paths remain private. This
validates real source layout and extraction, not firmware operation on the
phone or usability of the damaged historical vendor backup.
