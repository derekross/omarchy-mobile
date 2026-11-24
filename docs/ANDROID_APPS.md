<!-- SPDX-License-Identifier: MIT -->
# Android apps on Omamobile

Omamobile has no Android underneath. Android apps run in
[Waydroid](https://waydro.id): a LineageOS system (Android 13, arm64) in an
LXC container that shares the phone's kernel. Each Android app opens as its
own Hyprland window and starts from our launcher. It renders on the phone's
GPU, plays sound through PipeWire and reaches the network behind ufw. Android
never gets the phone's hardware: no block devices, no debugfs, no cameras,
no `/dev/snd`.

**Status: runs on the OnePlus 7T Pro (2026-11-05); on the Pixel 7 Pro the
container and the session have started (2026-11-10).** On the 7T Pro, with
the port's own build of `omamobile-waydroid` (the msm check that 0.1.6 brings
here), Android boots, renders on the Adreno, reaches the internet through ufw
and can't reach block devices or debugfs; F-Droid installs and opens from our
launcher. Apps open as a small window in the middle of the screen, not
maximized (§6). The 7T Pro's results are in section 9 of
[WAYDROID-PLAN](../device/cheetah/WAYDROID-PLAN.md); add yours there (date,
`uname -r`, device).

The design, the reasons behind each step and the gated runbook live in
[WAYDROID-PLAN](../device/cheetah/WAYDROID-PLAN.md). This page is the
how-to.

## 1. What each phone needs

| Need | Where it comes from | Pixel 7 Pro (`cheetah`) | OnePlus 7T Pro (`hotdog`) |
| --- | --- | --- | --- |
| Binder, binderfs, PSI, memfd, cgroups, namespaces | `kernel/configs/omamobile.config`, shared by every device kernel | yes | yes (all `out-hotdog*` builds) |
| Android's netd: legacy iptables, policy routing, `INET_DIAG_DESTROY` | same, the "Waydroid" block | yes | yes |
| GPU render node | the device's GPU driver | Panthor, Mali-G710 | msm, Adreno 640 |
| Android's Mesa drives that GPU | Waydroid's vendor image | no G710 row upstream: `omamobile-waydroid mesa` patches a copy into the overlay | freedreno supports the Adreno 640 as shipped; no patch needed |
| `omamobile-waydroid` accepts the phone | the package | yes | yes, from 0.1.6 |

**Other devices:** the check, which `waydroid-container.service` runs before
every start, knows two GPUs: a **Panthor** render node (Mali-G710) and an
**msm** render node with an Adreno bound. `omamobile-waydroid init` runs the
Mali-G710 Mesa patch everywhere but on msm, as before. On a phone with another GPU the check
fails and the container won't start: teach `omamobile-waydroid-check` that
device's render driver first (and whether the vendor image's Mesa needs a
patch for it). Don't work around it by masking the drop-in: the same drop-in
puts the hardening back in place before every start (§4).

Check your phone before you start (read-only, safe at any time):

```sh
omamobile-waydroid check          # on the phone, after section 2
# or from the laptop before installing anything:
tools/phone-ssh 'bash -s' < packages/omamobile-waydroid/lib/omamobile-waydroid-check
```

Every line should read `ok`. A `MISS` names what's missing and why.

## 2. Install

You need about **4 GB free** on `/var` (the images are about 1 GB, Android's
data grows from there) and Wi-Fi.

```sh
df -h /var
sudo pacman -S --needed waydroid omamobile-waydroid
omamobile-waydroid check
systemctl is-enabled waydroid-container      # disabled: nothing starts by itself
```

The pacman hook prints the hardening it applied to Waydroid's Python
("removed debugfs", "removed fb nodes" and so on). If it says
**"expected text not found"**, your Waydroid is newer than the one the
hardening knows (1.6.3). Stop there: the hardening needs updating before the
container may run.

From a checkout instead of the repository:
`tools/phone-install-package packages/omamobile-waydroid`.

## 3. Set up Android

### 3.1 Choose the system image

Edit `/etc/omamobile/waydroid.conf` before `init`:

| `SYSTEM_TYPE` | What you get |
| --- | --- |
| `VANILLA` (default) | LineageOS without Google. Install F-Droid and other APKs yourself. For push notifications, microG can be installed as ordinary apps |
| `FOSS` | Like VANILLA, with a few open-source apps preinstalled |

Switching later needs a fresh Android data directory. Move the old one aside
(`~/.local/share/waydroid/data`) rather than deleting it.

`LCD_DENSITY=480` matches the shell's 3x scale; `MULTI_WINDOWS=true` gives
each Android app its own window.

### 3.2 Download and prepare the images

```sh
sudo omamobile-waydroid init
```

That checks the kernel, hardens Waydroid, downloads the system and vendor
images (hash-checked against Waydroid's OTA), writes the Android properties
and, on the Pixel 7 Pro, patches the Mali-G710 Mesa copy into
`/var/lib/waydroid/overlay/vendor/` (on an Adreno it says no patch is
needed). Check the result:

```sh
grep -E 'video|fb[0-9]|kernel/debug' /var/lib/waydroid/lxc/waydroid/config_nodes   # prints nothing
tail -1 /var/lib/waydroid/lxc/waydroid/config      # the lxc.include of lxc-omamobile.conf
```

### 3.3 Let Android through the firewall

ufw drops forwarded traffic by default, so Android gets an address but no
internet until you add three rules (DHCP and DNS to the bridge, and routing
out of it; nothing is opened towards Android). A firewall change can cut
your SSH session, so arm an undo first:

```sh
sudo systemd-run --unit=x-deadman --on-active=90 /usr/bin/ufw disable
sudo omamobile-waydroid firewall on
sudo ufw status
# From the laptop, over a new connection:
tools/phone-ssh --fresh 'systemctl stop x-deadman.timer'
```

If the fresh login fails, wait 90 s: ufw turns itself off and you can look
at what went wrong.

## 4. Run it

```sh
sudo systemctl start waydroid-container     # the container, no Android UI yet
waydroid session start &                    # as your user, in a terminal on the phone
```

The session start puts Android on the screen. The first boot takes one to
two minutes. Then check:

```sh
sudo waydroid shell getprop sys.boot_completed          # 1
sudo waydroid shell -- dumpsys SurfaceFlinger | grep -m2 GLES   # the GPU, not llvmpipe
sudo waydroid shell ping -c 3 example.com
```

Started over SSH instead of on the phone, the session needs your desktop's
environment:

```sh
sudo -u <user> XDG_RUNTIME_DIR=/run/user/<uid> WAYLAND_DISPLAY=wayland-1 waydroid session start &
```

To start the container at every boot: `sudo omamobile-waydroid on` (`off`
reverses it). The session still starts only when you open an Android app.

**What keeps Android away from the phone's hardware.** Waydroid's container
is privileged, so Android's root could otherwise make a node for the UFS,
clear the storage guard's read-only flag and write a partition (the IMEI,
`persist`, the bootloader). Before every container start,
`omamobile-waydroid` checks the kernel, removes Waydroid's binds of debugfs,
the camera and framebuffer nodes, appends a rule that denies every block
device, and refuses to start if any of that is missing. Keep it that way:
don't edit `/var/lib/waydroid/lxc/waydroid/config` by hand, don't bind extra
devices into the container, and don't run `iptables-legacy` on the host.

## 5. Install and use apps

```sh
waydroid app install ~/Downloads/F-Droid.apk
waydroid app list
waydroid app launch org.fdroid.fdroid
```

Check an APK before you install it. F-Droid publishes a signature next to
its APK (`F-Droid.apk.asc`): `gpg --verify F-Droid.apk.asc F-Droid.apk`
against F-Droid's key.

Every installed app with a launcher icon gets a desktop entry in
`~/.local/share/applications/waydroid.<package>.desktop`, so it shows up in
our launcher next to the phone's own apps. Tapping it starts the session if
it isn't running. Android windows have the app ID `waydroid.<package>`, so
they get a switcher card and close from the switcher like any other app.

Files: Android's shared storage is
`~/.local/share/waydroid/data/media/0/`. Copy a file there to hand it to
Android.

Stop Android when you're done; it costs battery even frozen:

```sh
waydroid session stop
sudo systemctl stop waydroid-container
```

## 6. What doesn't work yet

- **Apps open small:** Android starts each app as a freeform window at its
  default size (about half the screen), centered in the Hyprland window. To
  make one fill the screen, as root:
  `waydroid shell -- am stack list` gives its `taskId`, then
  `waydroid shell -- am task resize <taskId> 0 0 <width> <height>` with the
  size `waydroid shell -- wm size` reports (1440 2856 on the 7T Pro).
- **Back:** Android runs without its navigation bar, and the shell's back
  gesture doesn't send Android's BACK key yet. Use the app's own back
  buttons.
- **Keyboard:** our on-screen keyboard doesn't open over Android text
  fields. Android's own keyboard opens inside the app's window instead.
- **Camera, sensors, phone calls, SMS:** none inside Android. The camera
  nodes are hidden on purpose, and the window follows the shell's rotation.
- **Background apps:** the container freezes when no Android window is
  visible, and Android's alarms can't wake the phone. Notifications arrive
  only while Android runs and the phone is awake.
- **Vulkan:** Android gets OpenGL ES only. Games that need Vulkan won't run.
- **Banking and DRM apps** that check Play Integrity or the device's
  certification usually refuse a container.
- **Two Android apps side by side** can make Android's display service
  restart. Keep one Android app per workspace.

## 7. Troubleshooting

| Symptom | Look at |
| --- | --- |
| The container won't start | `systemctl status waydroid-container`: one of the three `ExecStartPre` lines failed. `omamobile-waydroid check` says which |
| The container stops a few seconds after the session starts, `Can't open /dev/null` in `/var/lib/waydroid/waydroid.log` | `omamobile-waydroid` older than 0.1.1: its device rule denied every device. Upgrade it |
| `waydroid shell` or `lxc-attach` hangs | The container is frozen (no Android window on screen): `sudo waydroid container unfreeze` first |
| Android boots to a black or blinking window, `dumpsys SurfaceFlinger` shows llvmpipe or restarts | The GPU. `sudo waydroid log \| grep -i gralloc`. On the Pixel 7 Pro, rerun `sudo omamobile-waydroid mesa` (needed after every vendor image update). To rule the GPU out: `ro.hardware.gralloc=default` and `ro.hardware.egl=swiftshader` under `[properties]` in `/var/lib/waydroid/waydroid.cfg`, then `sudo waydroid upgrade -o` and restart the session. Slow, but it tells GPU problems apart from the rest |
| No internet inside Android | `sudo ufw status` shows the three `waydroid0` rules; `sysctl net.ipv4.ip_forward` is 1 (a ufw restart can reset it); `sudo waydroid shell dumpsys connectivity \| grep 'Active default network'`. If it's `none`, restart the session |
| All Android windows close at once | Android's system_server restarted: `sudo waydroid logcat \| grep -i watchdog`. See §6, two apps side by side |
| `failed to get security context` in `dmesg` | Binder wants an LSM context our kernel can't give. Note it in WAYDROID-PLAN §9 |
| Anything in `dmesg` from the GPU driver (faults, timeouts), an oops, or the phone gets hot | Stop the session and the container, and report it with the log lines (check them for identifiers first) |

## 8. Remove

```sh
waydroid session stop
sudo omamobile-waydroid off
sudo omamobile-waydroid firewall off
sudo pacman -R omamobile-waydroid waydroid
sudo rm -rf /var/lib/waydroid                     # images and container config
rm -rf ~/.local/share/waydroid ~/.local/share/applications/waydroid.*.desktop   # Android's data and app entries
```

Nothing else on the system changed: the kernel options stay, unused.
