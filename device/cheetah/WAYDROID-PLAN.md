<!-- SPDX-License-Identifier: MIT -->
# Waydroid plan: Android apps in a container (cheetah / gs201)

Status: **run on hardware.** On the OnePlus 7T Pro (2026-11-05), W0-W5
pass and W6 partly (section 9): Android boots on the Adreno, reaches the
internet through ufw and can't reach block devices or debugfs, but apps open
at Android's freeform default size, not maximized. On the Pixel 7 Pro, the
container and the session started and W4 ran with `omamobile-waydroid` 0.1.1
to 0.1.3 (2026-11-09 and 11-10; recorded in those commits, not yet in
section 9). Next: launch apps maximized (W8).

Earlier status (2026-10-13): offline work done, nothing run on the phone. The
kernel options are in `kernel/configs/omamobile.config` (the "Waydroid"
block at the end) and verified with `merge_config.sh` and
`olddefconfig` on top of `omamobile-int`'s configuration: every option
resolves as written, and the only side effects are the helpers they select
(`FIB_RULES`, `NF_SOCKET_*`, `NF_TPROXY_*`, `NF_NAT_REDIRECT`,
`NETFILTER_CONNCOUNT`, `TEXTSEARCH*`). No new kernel code and no new DT
nodes are needed.

Goal: Android apps on the phone as phone apps, each in its own Hyprland
window launched from our launcher, on our mainline kernel with GPU
rendering, sound through PipeWire, and networking behind ufw. Android never
touches hardware our drivers own. Waydroid stays opt-in: a package that
installs with everything off.

## 1. What Waydroid needs, and what we already have

Waydroid (1.6.3 in Arch's `extra`, `any` architecture, so Arch Linux ARM
builds it as is) runs a LineageOS image (Android 13, arm64; VANILLA, FOSS or
GAPPS system types, MAINLINE vendor) in an LXC container. The Python
manager (`waydroid container`) runs as root from `waydroid-container.service`;
the session (`waydroid session start`) runs as the user and brings the
Wayland and PulseAudio sockets into the container.

| Need | Ours today (int @ `afb1dbd7f` config) | Notes |
| --- | --- | --- |
| Binder IPC, binderfs | `ANDROID_BINDER_IPC=y`, `ANDROID_BINDERFS=y`, C binder (Rust binder off) | Built in: Waydroid's `modprobe binder_linux` fails harmlessly, then it mounts binderfs and allocates `binder`, `vndbinder`, `hwbinder` through `binder-control` |
| ashmem | none (removed from mainline) | Android 13 uses memfd when `/dev/ashmem` is missing (`MEMFD_CREATE=y`); Waydroid's `probeAshmemDriver` fails harmlessly |
| PSI | `PSI=y`, not disabled by default | lmkd needs `/proc/pressure/memory`; without it lmkd exits and Android's init reboots the container |
| cgroups, namespaces | cgroup2 from systemd; freezer, devices, BPF, PID/NET/IPC/UTS namespaces | We `switch_root` to systemd, so no mount-namespace workaround is needed (a chroot-style boot leaves the initramfs as `/` and breaks LXC's pivot) |
| Container network | `BRIDGE`, `VETH`, `TUN` (built in), `NF_TABLES`, `NFT_NAT`, `NFT_MASQ` | Host side only. Modules autoload (`/lib/modules` comes with every `push`) |
| overlayfs, FUSE | `OVERLAY_FS=m`, `FUSE_FS=m` | Waydroid's `/var/lib/waydroid/overlay`, Android's `/sdcard` |
| **Android's netd** | **missing** | Legacy iptables and ip6tables (`NETFILTER_XTABLES_LEGACY`, filter, mangle, raw, nat), Android's xt matches and targets, policy routing (`IP_MULTIPLE_TABLES`, `IPV6_MULTIPLE_TABLES`), `INET_DIAG_DESTROY`. Without them Android gets an address but no route |
| GPU | Panthor render node, our Mesa with the G710 row | The image's own Mesa has no G710 row: section 3 |
| LSM | Landlock, Yama, BPF LSM; no SELinux or AppArmor | Section 6.3: watch binder's security-context path |
| Hardware isolation | n/a | Waydroid binds debugfs, every `/dev/video*` and `/dev/fb*`: section 5 |

### 1.1 The kernel block (W1)

In `kernel/configs/omamobile.config`, block "Waydroid (WAYDROID-PLAN.md
W1)". Built in: the routing options (they change `struct net`, so every
module is rebuilt with the kernel, as `bin/omamobile kernel` always does)
and `NETFILTER_XTABLES_LEGACY`; everything else is a module that loads on
first use. The set follows Android's own base kernel requirements for
netd, without the out-of-tree `xt_quota2` (netd falls back to `xt_quota`
for its alert rules). `NETFILTER_XT_MATCH_POLICY` was dropped: it needs
XFRM, which we don't build.

What the host does not use: ufw and Waydroid's own NAT keep running through
nf_tables (Arch's `iptables` is `iptables-nft`; Arch's `waydroid-net.sh`
sets `LXC_USE_NFT="true"` and writes `table inet lxc` and `table ip lxc`).
The legacy tables exist only for Android's netd inside the container's
network namespace. Never run `iptables-legacy` on the host: legacy and nft
rules in the same namespace are hard to read and ufw doesn't see the legacy
ones.

Not needed, left off: `SW_SYNC` (Waydroid binds `/dev/sw_sync` only if it
exists; the HWC uses real sync files from the GPU, `SYNC_FILE=y`),
`UHID` (Bluetooth HID from Android), `USERFAULTFD` (Android 14+ GC),
`CGROUP_NS`, Rust binder.

### 1.2 Checked on our tree, no change needed

- **Sync-file names after signal.** `SYNC_IOC_FILE_INFO` on a signaled
  `drm_sched` fence (Panthor's) read the scheduler's timeline name after the
  scheduler was freed on some earlier 7.3 release candidates and oopsed. In
  7.3-rc6 `dma_fence_driver_name()` and `dma_fence_timeline_name()` return
  fixed names once the fence is signaled, so Android's RenderThread can't hit
  it. Keep it in mind if an oops in `sized_strscpy` from an ioctl ever
  shows up with Waydroid running.
- **Binderfs device numbers** are dynamic, so the device rule in section 5
  denies block devices only and leaves character devices alone.

## 2. Images

`omamobile-waydroid init` runs `waydroid init -s $SYSTEM_TYPE`, which
downloads the system and vendor images from Waydroid's OTA channels
(`ota.waydro.id`) and checks them against the OTA's hashes. About 1 GB on
`userdata`; check `df -h /var` first. Images live in
`/var/lib/waydroid/images`; Android's data in
`~/.local/share/waydroid/data`.

- **VANILLA** (the default in `/etc/omamobile/waydroid.conf`): no Google.
  F-Droid installs as an APK (check its signature against F-Droid's key).
  For push notifications, microG can be installed as ordinary apps: the
  LineageOS-for-Waydroid VANILLA build allows signature spoofing for
  microG's own key only.
- **GAPPS:** not offered (decided 2026-11-24). The project neither ships nor
  documents Google apps: decisions put user privacy and security first.
  `omamobile-waydroid` accepts only VANILLA and FOSS; an owner who wants
  Google Play can set it up inside Waydroid on their own.
- Switching system type later means a fresh `data` directory; keep the old
  one aside rather than deleting it.

## 3. GPU

Android renders through the vendor image's Mesa: gbm gralloc and the
Gallium driver on the render node Waydroid binds (`/dev/dri/renderD128`,
Panthor). Panthor is render-only, so Waydroid's `getCardFromRender()` finds
no card node and binds none; that's fine, Android never does KMS here.

- **The image's Mesa refuses the G710.** Upstream Mesa's Panfrost model
  table has no G710 row (our `packages/mesa/0001-*` adds it; UPSTREAM.md has
  the merge request). Gralloc then can't allocate and surfaceflinger aborts
  at every start. `omamobile-waydroid-mesa` reads `libgallium_dri.so` (64-
  and 32-bit) out of `vendor.img` with `debugfs`, swaps the G610 row's
  product ID (`0xa8070000`, mask `0xff0f0000`) for the G710's
  (`0xa8020000`), and writes the copies to
  `/var/lib/waydroid/overlay/vendor/{lib64,lib}/`. The G610 and G710 are the
  same Valhall core, which is why our host patch copies the G610's numbers.
  The image is never changed; it refuses a library where the row isn't found
  exactly once. Android then reports "Mali-G610 MC7 (Panfrost)". Redo after
  every vendor image update; drop it when the image's Mesa has the row.
- **Vulkan:** Waydroid maps kernel drivers to Vulkan ICDs and has no entry
  for `panthor`, so Android gets GLES only. Fine for apps; games that need
  Vulkan won't run. Later: a one-line mapping upstream to Waydroid, once
  PanVK on the G710 is solid on the host.
- **Software fallback** (if W5 shows GPU faults): set
  `ro.hardware.gralloc=default` and `ro.hardware.egl=swiftshader` in
  `[properties]`, `waydroid upgrade -o`, restart the session. Slow, but it
  separates GPU problems from everything else.

## 4. Networking and ufw

`waydroid-net.sh` makes the bridge `waydroid0` (192.168.240.1/24), runs
`dnsmasq` on it, enables `ip_forward` and masquerades 192.168.240.0/24 out
of whatever the default route is (Wi-Fi now, `rmnet` once the modem has
data). No conflict with USB networking (172.16.42.0/24).

ufw is on with a DROP forward policy, and a packet must pass every
netfilter base chain at a hook, so Waydroid's `accept` rules don't help on
their own. `omamobile-waydroid firewall on` adds:

```
ufw allow in on waydroid0 to any port 67 proto udp   # DHCP to dnsmasq
ufw allow in on waydroid0 to any port 53             # DNS to dnsmasq
ufw route allow in on waydroid0                      # Android to the world
```

Replies come back through ufw's own `RELATED,ESTABLISHED` rule. Nothing is
opened towards Android from outside. If ufw is restarted after Waydroid,
check `sysctl net.ipv4.ip_forward` is still 1.

Inside Android, netd needs the W1 options. If the network fails later
(after Android restarted system_server, for example), `waydroid shell
dumpsys connectivity | grep 'Active default network'` says `none`; a
session restart fixes it.

## 5. Keeping Android away from the hardware

Waydroid 1.6.3 does three things that are wrong on this phone:

1. **Binds `/sys/kernel/debug` read-write** into the container. Our debugfs
   has regmap `registers` files; one read of a PMU register crashed the
   phone, and reading a CS35L41's whole regmap stopped its protection DSP
   (AGENTS.md). Android's root must not see it.
2. **Binds every `/dev/video*` and `/dev/fb*`** and `chmod -R 777`s them at
   every container start. Our `/dev/video*` are the camera's raw CSIS and
   sensor nodes (CAMERA-PLAN); world-writable camera nodes are wrong even
   without Android.
3. **The container is privileged** (no user namespace) and keeps
   `CAP_MKNOD` and `CAP_SYS_ADMIN`. Android's root could make a node for
   `/dev/sda`, clear the storage guard's read-only flag (`BLKROSET` needs
   only `CAP_SYS_ADMIN`) and write a partition: the IMEI, `persist`, the
   bootloader. The guard exists to make that impossible.

`omamobile-waydroid-harden` fixes all three, without forking Waydroid:

- `patch` (pacman hook after every `waydroid` install or upgrade) comments
  out the debugfs, video and framebuffer binds in `lxc.py` and the video,
  framebuffer and debugfs `sw_sync` entries of the chmod list in
  `container_manager.py`. Each edit matches exact text; an unknown Waydroid
  version is refused, not half-patched.
- `config` (`ExecStartPre` of `waydroid-container.service`, through our
  drop-in) drops any such lines from the generated `config_nodes` and
  appends `lxc.include = /usr/share/omamobile-waydroid/lxc-omamobile.conf`,
  which allows the character devices Android uses (`c 1:3` for `/dev/null`,
  the standard nodes, the binderfs nodes by path) and denies every block device with
  `lxc.cgroup2.devices.deny = b *:* rwm`, whoever makes the node. With LXC 7
  the filter starts in "block everything" mode and leaves deny rules out of
  the device program, so a list with only the deny rule allows nothing and
  `lxc-start` dies with `Can't open /dev/null`. Block devices are refused
  because no rule allows a `b` device, and the order of the lines does not
  matter. The deny line covers one case: an `lxc.cgroup2.devices.allow = a`
  placed before our include (a hand-edit) switches LXC to "allow everything",
  and the `b *:*` deny keeps block devices out. An `allow = a` placed after
  the include would clear every rule before it and open everything, so
  `test/all` fails if the file has one. binderfs's major is assigned at boot
  (507 on cheetah), so `binder`, `vndbinder` and `hwbinder` are allowed by
  path (`lxc.cgroup2.devices.allow = /dev/binderfs/binder rwm`): LXC reads
  each node's major and minor with `stat()` when the container starts, after
  Waydroid has mounted binderfs, and `lxc-start` fails if a node is missing.
  `binder-control` is not allowed. `omamobile-waydroid-check` wants the
  three lines, and that the Panthor render node's `major:minor` (from
  sysfs) is the one the file allows (`c 226:128`), before every start.
- `verify` (`ExecStartPre` too) refuses to start the container unless all
  of it is in place. `waydroid upgrade` regenerates the config, so this runs
  before every container service start (Waydroid's own `lxc-start` comes later,
  when a session starts, and rewrites `config_session` just before it). It also
  refuses a hand-opened config: any uncommented `lxc.cgroup2.devices.allow`
  (or the older `lxc.cgroup.devices.allow`) line in Waydroid's generated
  `config`, `config_nodes` or `config_session` fails it (`FAIL
  <file>:<line>: a device allow rule, which Waydroid never writes`), so such an
  edit fails closed instead of relying on where it sits relative to our
  include. Waydroid writes no allow line there itself, and our own binder and
  render-node paths live in our include, which `verify` does not scan. It
  refuses every allow rather than a list of open forms (`a`, a `b` device,
  `c *:*`, an absolute path, which LXC 7 `stat()`s and allows as whatever type
  it finds), because LXC's own parser accepts more than a list can name, such
  as a value in quotes.

Sound reaches Android only through PipeWire's PulseAudio socket (no
`/dev/snd` is bound), so the speaker stages and protection in
`omamobile-audio` stay in the path. Sensors are stubbed (Arch ships no
`waydroid-sensord`): Android gets no accelerometer, which is fine, since
the window follows the shell's rotation.

## 6. Phone integration

### 6.1 Windows, launcher, touch

- **Multi-window mode** (`persist.waydroid.multi_windows=true`, set by
  `omamobile-waydroid props`): each Android activity is its own Wayland
  window with app ID `waydroid.<package>`, so it gets a switcher card,
  maximizes under `phone.lua` like our own apps and closes from the
  switcher. No Android home screen or navigation bar.
- **Launcher:** Waydroid writes `~/.local/share/applications/waydroid.<package>.desktop`
  for every app with a launcher activity, with category `X-WayDroid-App`
  and `NoDisplay=true` for Android's own system apps. Our launcher uses
  Omarchy's AppLibrary entries, so Android apps appear next to ours.
  To check in W6: AppLibrary honours `NoDisplay` (else Android's Settings,
  Clock, Contacts duplicate ours) and the icon path (a PNG under
  `~/.local/share/waydroid/data/icons`). Tapping one runs
  `waydroid app launch <package>`, which starts the session if it isn't.
- **Back:** Android has no navigation bar in this mode. The shell's back
  gesture must send `KEY_BACK` to a `waydroid.*` window (Android maps evdev
  158 to BACK); hold it about 80 ms, since a press and release sent together
  can be dropped.
- **Hotplug storms.** Waydroid's hwcomposer re-reports Android's display on
  every `configure` of any Android window, and Android's display manager can
  deadlock on a stream of them (system_server watchdog, all Android windows
  close). Rules for the shell: never tile two Android windows on one
  workspace (give each its own), and don't resize Android windows for the
  on-screen keyboard. If W6 still shows watchdog restarts, a small patch to
  the vendor hwcomposer that reports a hotplug only when the size really
  changes is the known fix (an overlay binary like Mesa's; W6b).
- **Rotation:** the shell rotates the whole output, the Android window gets
  a new size, and Android relayouts. That is one more hotplug; test it in
  W6 and lock Android windows to portrait if it destabilizes Android.
- **Density:** `ro.sf.lcd_density=480` (the shell's 3x scale).

### 6.2 Keyboard

Waydroid doesn't speak Wayland's text-input protocol, so squeekboard never
opens over an Android text field; Android's own keyboard (LatinIME) opens
inside the app's window instead. That works by touch from day one and is
the W6 baseline. Later (W8): an Android input method that shows an empty
view of our keyboard's height and asks the shell to show squeekboard, so
typing looks the same everywhere; Android then receives keys as a hardware
keyboard through Waydroid's Wayland seat. It needs a US layout set in
Android, or Android posts "Configure physical keyboard".

### 6.3 Watch items

- **Binder security contexts.** With no LSM that implements
  `secid_to_secctx` (our list: landlock, lockdown, yama, integrity, bpf),
  binder fails transactions to a node that asked for the sender's security
  context (`-EOPNOTSUPP`, "failed to get security context" in dmesg).
  LineageOS-for-Waydroid images are known to boot on kernels without SELinux
  or AppArmor, so their service manager evidently doesn't depend on it. If
  W5 shows that message, this is why; the fix would be a kernel-side
  fallback (an empty context), upstream material.
- **Freezing.** Waydroid freezes the container when no Android window is
  visible (`suspend_action=freeze`), so background Android apps get no
  messages. Keep the default for now (battery); W7 measures both.
- **Android and phone sleep.** Android's alarms can't wake the phone from
  the container. Once s2idle is on by default (SUSPEND-PLAN S8), Android
  apps sync only when the phone is awake. Push through microG holds one
  connection; making it survive sleep is later work with the modem.
- **Camera:** none for now (the nodes are hidden on purpose). Later through
  PipeWire and a v4l2loopback bridge, MJPEG, if Android apps really need it.

## 7. The package (`packages/omamobile-waydroid`, 0.1.0 draft)

| File | Installed as | What |
| --- | --- | --- |
| `bin/omamobile-waydroid` | `/usr/bin` | `check`, `init`, `mesa`, `props`, `firewall on\|off`, `on\|off`, `status` |
| `lib/omamobile-waydroid-check` | `/usr/lib/omamobile-waydroid` | Read-only: kernel options (`/proc/config.gz` or `CONFIG_FILE=`), binderfs, PSI, the Panthor render node, cgroup2 |
| `lib/omamobile-waydroid-harden` | same | Section 5 |
| `lib/omamobile-waydroid-mesa` | same | Section 3 |
| `lib/lxc-omamobile.conf` | `/usr/share/omamobile-waydroid` | The device rules: allow list, then the block-device deny |
| `systemd/waydroid-container-omamobile.conf` | `waydroid-container.service.d/omamobile.conf` | `ExecStartPre`: check, harden config, harden verify |
| `libalpm/90-omamobile-waydroid.hook` | `/usr/share/libalpm/hooks` | `harden patch` after `waydroid` installs or upgrades |
| `etc/omamobile/waydroid.conf` | `/etc/omamobile` (backup) | `SYSTEM_TYPE`, `LCD_DENSITY`, `MULTI_WINDOWS` |
| `test/all` | n/a | Syntax, staging, the check against good and bad configs (`KCONFIG=` for a real one), the hardening against synthetic copies of Waydroid's lines (idempotent, refuses unknown versions) |

Depends on `waydroid lxc nftables dnsmasq e2fsprogs`; ufw optional.
Installs with the service disabled and no images. The hardening was also
run by hand against Arch's `waydroid` 1.6.3-1 files: all six edits apply,
the result parses, a second run changes nothing.

## 8. Runbook

Everything below is for the human to run or approve. Before every step:
`tools/phone-ssh 'uname -r'` and record it. Record results in section 9.

### W0: what the current kernel lacks (read-only, risk none)

```sh
tools/phone-ssh 'bash -s' < packages/omamobile-waydroid/lib/omamobile-waydroid-check
```

- **Expect:** `ok` for binder, binderfs, PSI, cgroups, bridge, veth, nft
  and the Panthor render node; `MISS` for `NETFILTER_XTABLES_LEGACY`, the
  `IP_NF_*`/`IP6_NF_*` tables, `IP_MULTIPLE_TABLES`,
  `IPV6_MULTIPLE_TABLES`, `INET_DIAG_DESTROY` and most `NETFILTER_XT_*`.
- **Pass:** exactly the W1 block is missing. **Stop:** binder, PSI or the
  render node missing (a different kernel than expected).

### W1: a kernel with the Waydroid block (push, ask the human; risk low)

Build `omamobile-int` with the fragment
(`KERNEL_DIR=~/android/mainline/wt-int KERNEL_OUT=~/android/mainline/out-int bin/omamobile kernel`),
then modules, images and `bin/omamobile push` as usual.

- **Expect:** a normal boot; the check from W0 passes with no `MISS`;
  `ufw status` unchanged and active; SSH, Wi-Fi, sound, sensors as before;
  `lsmod | grep -c ip_tables` is 0 (nothing loads the legacy tables yet).
- **Stop:** a boot that doesn't come back (wait out `RebootWatchdogSec`,
  then ask for the button reset), ufw failing to load its rules, any oops.
- **Rollback:** push the previous release's images (slot B), or the human
  boots slot A.

### W2: install (risk low)

```sh
tools/phone-ssh 'pacman -S --needed waydroid'      # from Arch Linux ARM's extra
tools/phone-install-package packages/omamobile-waydroid
tools/phone-ssh 'omamobile-waydroid check; systemctl is-enabled waydroid-container'
```

- **Expect:** the hook prints "removed fb nodes ... removed debugfs";
  `check` passes its kernel part and says Waydroid isn't initialized;
  the service is `disabled`. Arch's `waydroid` enables nothing by itself;
  if it did, `systemctl disable --now waydroid-container`.
- **Stop:** the hook says "expected text not found" (a Waydroid newer than
  1.6.3: update `omamobile-waydroid-harden` before going on).
- **Rollback:** `pacman -R omamobile-waydroid waydroid`.

### W3: images and hardening (risk low; about 1 GB download over Wi-Fi)

```sh
tools/phone-ssh 'df -h /var; omamobile-waydroid init'
tools/phone-ssh 'grep -E "video|fb[0-9]|kernel/debug" /var/lib/waydroid/lxc/waydroid/config_nodes; \
  tail -1 /var/lib/waydroid/lxc/waydroid/config; ls -l /var/lib/waydroid/overlay/vendor/lib*/'
```

- **Expect:** the images verify; the grep prints nothing; the config's last
  line is the `lxc.include` of `lxc-omamobile.conf`; both patched
  `libgallium_dri.so` files exist (the tool prints their row offset and
  SHA-256: record them).
- **Stop:** less than 4 GB free; the Mesa tool refuses the library (record
  its message: the image's Mesa may already know the G710).
- **Rollback:** `rm -rf /var/lib/waydroid` (images and config only; nothing
  else on the system changed).

Firewall, under a dead-man switch (AGENTS.md):

```sh
tools/phone-ssh 'systemd-run --unit=x-deadman --on-active=90 /usr/bin/ufw disable && omamobile-waydroid firewall on && ufw status'
tools/phone-ssh --fresh 'systemctl stop x-deadman.timer'   # a fresh SSH login
```

### W4: the container, no Android UI yet (risk medium)

Nothing changes on the screen. CPU load rises for about a minute.
Stream the kernel log first: `tools/phone-ssh 'dmesg -w' | tee logs/waydroid-w4.log &`.

```sh
tools/phone-ssh 'systemctl start waydroid-container; sleep 5; systemctl --no-pager status waydroid-container | head -5; \
  ls -l /dev/binderfs; waydroid status'
# Block devices must be unreachable from inside (loop0 is harmless to read):
# lxc-attach gives Android's shell no PATH: without the export every command
# is "inaccessible or not found" (rc=127), which looks like a refusal.
tools/phone-ssh 'lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /system/bin/sh -c \
  "export PATH=/system/bin:\$PATH; toybox mknod /dev/omtest b 7 0; echo mknod_rc=\$?; toybox head -c 1 /dev/omtest > /dev/null; echo head_rc=\$?; toybox rm -f /dev/omtest"'
# The character side: major 1, minor 1 is /dev/mem (toybox takes MAJOR MINOR as two words; `c 1:1` is a usage error, not a refusal), which no allow line lists. mknod only,
# never read or open the node: if the rule ever failed, reading /dev/mem could
# crash the phone.
tools/phone-ssh 'lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /system/bin/sh -c \
  "export PATH=/system/bin:\$PATH; toybox mknod /dev/omtest2 c 1 1; echo mknod2_rc=\$?; toybox rm -f /dev/omtest2"'
tools/phone-ssh 'lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /system/bin/sh -c \
  "export PATH=/system/bin:\$PATH; toybox ls /sys/kernel/debug /dev | toybox head"'
```

The `lxc-attach` lines need a running container; if the container only
starts with a session, run them after W5's session start instead.

- **Expect:** the service is active (its three `ExecStartPre` lines passed);
  `binder`, `vndbinder`, `hwbinder` in `/dev/binderfs`; `toybox mknod`
  prints `mknod: /dev/omtest: Operation not permitted` (that line is the pass
  condition, not a nonzero rc: a missing command also gives one), and so
  does `toybox mknod /dev/omtest2 c 1 1` (`mknod: /dev/omtest2: Operation not
  permitted`);
  `/sys/kernel/debug` empty or
  missing inside; no `video*` or `fb*` in the container's `/dev`.
- **Stop:** the block read succeeds, or `mknod /dev/omtest2 c 1 1` succeeds
  (stop the container at once and fix the device rule before anything else;
  never read `/omtest2`); any oops; any
  `ufshcd_err_handler`; binder errors repeating in dmesg.
- **Rollback:** `systemctl stop waydroid-container`.

### W5: Android boots, GPU and network (risk medium)

**Announce:** the Android UI appears on the phone's screen in a window.
As the user, in the desktop session:

```sh
tools/phone-ssh 'sudo -u <user> XDG_RUNTIME_DIR=/run/user/<uid> WAYLAND_DISPLAY=wayland-1 waydroid session start &'
tools/phone-ssh 'sleep 90; waydroid shell getprop sys.boot_completed; \
  waydroid shell dumpsys SurfaceFlinger | grep -m2 -E "GLES|Panfrost|llvmpipe"; \
  waydroid shell ping -c 3 1.1.1.1; waydroid shell ping -c 1 example.com; \
  dmesg | grep -iE "panthor.*(fault|timeout)|binder.*security context|Oops" | tail'
```

- **Expect:** `sys.boot_completed` 1 within about two minutes; GLES
  "Mali-G610 MC7 (Panfrost)"; both pings answer; nothing in the dmesg grep.
- **Pass:** all four. **Llvmpipe or a surfaceflinger restart loop:** the
  Mesa overlay didn't apply; check `waydroid log` for gralloc errors, and
  try section 3's software fallback to separate the two.
- **Stop:** Panthor faults or timeouts repeating, an oops, the phone hot to
  the touch, or the shell unresponsive.
- **Rollback:** `waydroid session stop`; `systemctl stop waydroid-container`.

### W6: apps as phone apps (risk low; the human holds the phone)

Install F-Droid (check the APK's signature) with `waydroid app install`.
Then by hand: it appears in our launcher with its icon, opens maximized in
its own window, scrolls and taps correctly, closes from the switcher; the
back gesture (once the shell sends `KEY_BACK`); Android's keyboard in a
text field; a short sound from an Android app at low volume (announce it;
it goes through PipeWire under `omamobile-audio`'s stage); rotate the
phone with an Android app open. Watch for system_server watchdog restarts
(`waydroid logcat | grep -i watchdog`).

- **Stop:** Android restarting more than once in ten minutes: go to W6b
  (the hwcomposer hotplug fix) before more UX work.

### W7: power (cable out; risk low)

`tools/power-ab` with three cases: no Waydroid, container running with a
frozen session, session running with no window. Record drain and the
container's CPU time. Then decide whether `suspend_action` stays `freeze`.

### W8: integration work (offline first)

The shell's back gesture for `waydroid.*` windows; each Android window on
its own workspace; the keyboard bridge (6.2); Android notifications in our
shade (Waydroid's notification bridge already posts them as desktop
notifications with app ID `waydroid.<package>`: check them in W6); an
Android-apps switch in quick settings that starts and stops the container.

## 9. Results

### 2026-11-05, OnePlus 7T Pro (`hotdog`), `7.3.0-rc6-omamobile-push1-gb743280ab222`

The first run recorded here, on the 7T Pro (Adreno 640, msm) rather than the
Pixel, with the port's own builds of `omamobile-waydroid` (numbered 0.1.1 and
0.1.2 in the port's tree, not this repository's 0.1.1 and 0.1.2; their msm
check is what 0.1.6 brings here). Waydroid 1.6.3-1 and lxc 7.0.0 from Arch
Linux ARM's `extra`; images `lineage-20.0-20260927-VANILLA` (system) and
`lineage-20.0-20261022-MAINLINE` (vendor).

- **W0:** every kernel option `ok` (the W1 block is in every `out-hotdog*`
  build). The only `MISS` was the GPU: the check accepted Panthor only. The
  port's build also accepts an msm render node when an Adreno is bound (msm's
  render node sits on `msm_dpu`), and runs the Mali-G710 Mesa patch only on
  Panthor. Waydroid itself maps `msm_dpu` to freedreno and binds only the
  render node, no card node.
- **W2:** the hook commented out all six lines (five in `lxc.py`, three tagged
  lines in `container_manager.py`); the service stayed disabled.
- **W3:** both images downloaded and verified in about 2.5 minutes; the
  Mesa step said no patch is needed; `config_nodes` binds `renderD128` and no
  video, framebuffer or debugfs node. Firewall rules under the dead-man
  switch: a fresh SSH login worked, ufw stayed active.
- **W4, first try: the container stopped about 19 s after start**
  (`lxc-start: open_devnull: Operation not permitted - Can't open
  /dev/null`): `lxc-omamobile.conf` held only the block-device deny, and LXC
  7's cgroup2 filter then allows nothing. This repository's 0.1.1 fixed the
  same fault with an allow list (#493); the port's build put
  `lxc.cgroup2.devices.allow = a` before the deny instead, which is not what
  ships here.
- **W4 with that fix:** the container runs. Inside, `mknod` of a block device
  (7:0 and 8:0) is refused with "Operation not permitted";
  `/sys/kernel/debug` is empty; `/dev` has no `video*`, `fb*` or `sd*`;
  `/dev/dri` holds only `renderD128`. The container starts with the session
  (Waydroid 1.6), not with the service.
- **W5: pass.** `sys.boot_completed` 1 within about a minute;
  `GLES: freedreno, FD640, OpenGL ES 3.2 Mesa 26.0.8` (`ro.hardware.vulkan`
  freedreno); ping to 1.1.1.1 and to a name both answer. No oops, no
  `ufshcd_err_handler`, no "failed to get security context". The Adreno
  `gpu fault ... source=CCU` lines and one `hangcheck recover` in the log come
  from a host GPU context that faulted from 16:52, before Waydroid ran: the
  7T Pro's existing host fault, not Android's.
- **W6, partly:** F-Droid (signature checked against F-Droid's key)
  installed with `waydroid app install`; its desktop entry has no
  `NoDisplay`, Android's own twelve system apps all do. `waydroid app
  launch` opens it as its own window, app ID `waydroid.org.fdroid.fdroid`,
  focused, and Hyprland gives it the full 480x952. **But Android opens the app
  as a freeform task at its default size** (751x1440 px of the 1440x2856
  display, `sw250dp`), so the app is a small card in the middle of the
  window with the shell showing around it. `am task resize <task> 0 0 1440
  2856` inside Android made it fill the screen at once (`sw480dp`). Waydroid
  1.6.3 has no setting for this: `launchApp` goes to Android's platform
  service. Next: launch maximized (W8).
- **Freeze:** with no Android window on screen the container froze within
  about a minute, and an `lxc-attach` into a frozen container hangs; `waydroid
  container unfreeze` first.
