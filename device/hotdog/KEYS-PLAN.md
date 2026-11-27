<!-- SPDX-License-Identifier: MIT -->
# Keys plan (hotdog / SM8150): volume keys and the alert slider

**Status (2026-11-15): works from a RAM boot. Volume Up, Volume Down and
the alert slider (Silent, Vibrate, Ring with its OSD) pass K1-K5;
`boot_a` still has the voice kernel (K6 open).** Kernel branch `omamobile-hotdog-keys` (worktree
`~/omamobile-kernel/wt-hotdog-keys`, output `~/omamobile-kernel/out-hotdog-keys`),
one DT commit on top of `omamobile-hotdog-voice` @ `ce58cc9c3759` (the
kernel on `boot_a`). Userspace in `packages/omamobile-device-hotdog` 0.1.11.

**Goal.** Volume Up and Volume Down change the volume (and take photos in
the Camera app) through the shell's existing bindings, and the alert
slider switches between Ring, Vibrate and Silent.

## 1. Facts

| What | Source |
| --- | --- |
| Before this plan only the power key existed (`/proc/bus/input/devices`: `pm8941_pwrkey`, fingerprint, touch, headset jack). The common dtsi gives PON RESIN `KEY_VOLUMEDOWN` but leaves it `disabled` | phone, 2026-11-15, `7.3.0-rc6-omamobile-push1-gce58cc9c3759` |
| Vendor `gpio_keys`: `vol_up` on PM8150 GPIO6, `vol_down` on PM8150 GPIO7, both active low, pull-up, `power-source` 1 | stock DTBO entry 18 (`MTP 19801 MP`), fragments 55 and 113 |
| ABL leaves PM8150 GPIO6/7 as inputs with the 30 µA pull-up at vin-1, reading high | `/sys/kernel/debug/gpio`, 2026-11-15 |
| GPIO6 read low only while Volume Up was held, GPIO7 only while Volume Down was | 60 s read-only sampling of debugfs, owner pressing, 2026-11-15 |
| Vendor `tri_state_key` (`oneplus, tri-state-key`): `gpio_key1` TLMM 27, `gpio_key2` TLMM 134, `gpio_key3` TLMM 125; pins `bias-disable`, 2 mA | stock DTBO entry 18, fragments 78 and 79 |
| Under ABL's pull-down all three read low in every slider position. A bias request through the GPIO character device does nothing here: `pinctrl-msm` has no GPIO `set_config`, so the bias can only come from the DT | sampling, 2026-11-15 |
| None of TLMM 27, 125, 134 is in `gpio-reserved-ranges` (0-3, 126-129) | `sm8150-oneplus-common.dtsi` |
| feedbackd 0.8.9 is installed; its `org.sigxcpu.feedbackd profile` (`full`, `quiet`, `silent`) is what the ringtone, notification sounds and haptics follow | phone |

The slider's polarity and order were not known before K3. The DT follows
the OnePlus 6, whose vendor node lists its lines the same way and whose
mainline DT has key1 = bottom (Ring), key3 = top (Silent), all active low:
so TLMM 125 = Silent, 134 = Vibrate, 27 = Ring. K3 confirmed it: the lines
have external pull-ups, and the selected position reads low.

## 2. What changes

- **Kernel** (`00e3900120f0`): a `gpio-keys` node "Volume keys" (PM8150
  GPIO6/7, `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN`, pull-up, wakeup source) and a
  `gpio-keys` node "Alert slider" (`EV_ABS` `ABS_SND_PROFILE`, values
  `SND_PROFILE_SILENT`/`VIBRATE`/`RING`, `bias-disable` as stock). RESIN stays
  disabled so Volume Down can't report twice.
- **device-hotdog 0.1.11**: `omamobile-hotdog-alert-slider`, a user service
  (vendor wants link) that reads the slider and sets feedbackd's profile:
  Silent → `silent`, Vibrate → `quiet`, Ring → `full`, with Omarchy's OSD on
  every move (none at start). It runs for the graphical session
  (`graphical-session.target` wants link, `PartOf`): started at login it had
  no `OMARCHY_PATH` yet, and `omarchy-osd` (through `omarchy-shell -q`)
  silently showed nothing. `ConditionUser=!@system` keeps it out of root's
  user manager, which an SSH login as root starts: two copies set and
  announced every move twice. `72-omamobile-hotdog-keys.rules` tags the
  slider's input device `uaccess` so the seat's user can read it. The
  volume keys need nothing new: `omamobile-shell`'s `hypr/phone.lua`
  already binds `XF86AudioRaiseVolume`/`XF86AudioLowerVolume`.
- The phone has no haptics driver yet (AW8697), so Vibrate is silent too
  for now.

## 3. Runbook

Every step is the owner's go. Read-only first; one change per boot.

**K0. Build (laptop).**

```sh
cat device/hotdog/kernel-camera.config device/hotdog/kernel-voice.config >> device/hotdog/kernel.config
DEVICE=hotdog KERNEL_DIR=~/omamobile-kernel/wt-hotdog-keys \
  KERNEL_OUT=~/omamobile-kernel/out-hotdog-keys bin/omamobile kernel
git checkout device/hotdog/kernel.config
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-keys bin/omamobile modules
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-keys bin/omamobile initramfs
# DTB_OVERLAYS="mic torch camera popup camera-main camera-af voice" in device/hotdog/device.conf for this build only
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-keys bin/omamobile images
```

Pass: `fdtget` of the image's DTB shows `/gpio-keys` and `/alert-slider`.
*2026-11-15: done. `7.3.0-rc6-omamobile-push1-g00e3900120f0`, `boot.img`
sha256 `2168e366…ed61`; the overlaid DTB has both nodes; `dt-validate`
(dtschema 2026.9): no new warning against the voice DTB; checkpatch
`--strict`: only the missing Signed-off-by (the owner's).*

**K1. Package (phone).** `tools/phone-install-package packages/omamobile-device-hotdog`
(0.1.10 → 0.1.11). On the running kernel the slider service finds no
device and exits 0. Pass: `systemctl --user status omamobile-hotdog-alert-slider`
(as the owner) shows "no alert slider input device", status 0.
Rollback: reinstall 0.1.10. Risk: low.

**K2. RAM boot (owner: fastboot by the buttons).** Stop the modem first
(AGENTS.md §2), then `DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-keys bin/omamobile modules-push`,
then `fastboot -s <serial> boot ~/omamobile-kernel/out-hotdog-keys/images/boot.img`.
Pass: Arch comes up as on `boot_a` (cameras, fingerprint, mics, modem);
`/proc/bus/input/devices` lists "Volume keys" and "Alert slider"; no
`gpio-keys` errors in `dmesg`. Stop: no SSH in 2 minutes (the known
intermittent bad RAM boots: retry once with the same image, then stop).
Rollback: a reboot (`boot_a` unchanged; a RAM boot spends no try). Risk: low.

**K3. Slider levels and values (read-only; owner moves the slider).** In
each position (top, middle, bottom, 5 s each):
`grep -E "^ gpio(27|125|134) " /sys/kernel/debug/gpio` and the slider's
current `ABS_SND_PROFILE` (the service's journal line, or `evtest --query`).
Pass: exactly one line low per position; top → 0 (Silent), middle → 1
(Vibrate), bottom → 2 (Ring). Stop: all three read the same in every
position (no external pull-ups: the DT needs `bias-pull-up`), or the order
differs (swap the lines in the DT). Fix in the DT and go back to K0.

**K4. Volume keys.** Press each key on the home screen, then hold Volume
Down with Power (screenshot), then each key in the Camera app. Pass: the
OSD shows the volume change; the screenshot is taken; the camera takes a
photo if that setting is on. Also `libinput debug-events` (root) shows
`KEY_VOLUMEUP`/`KEY_VOLUMEDOWN` once per press.

**K5. Alert slider.** Move it top → middle → bottom. Pass: the OSD shows
Silent, Vibrate, Ring; `gsettings get org.sigxcpu.feedbackd profile` (as the
owner) reads `silent`, `quiet`, `full`; an incoming call or SMS rings only in
Ring.

**K6. Flash `boot_a`** with the K2 image once K2-K5 pass, as before
(`fastboot -s <serial> flash boot_a …`, read back by sha256); this clears
slot A's successful mark, so re-run `device/hotdog/slot-a-mark`
status/dump/write with the owner's yes after it boots (BRINGUP-M1).
Rollback image: `~/omamobile-kernel/boot-voice-gce58cc9c3759-qrtr-2026-11-14.img`.

## 4. Results

All on 2026-11-15, `7.3.0-rc6-omamobile-push1-g00e3900120f0` from RAM.

- **K1** pass: 0.1.11 installed (built on the phone); on the voice kernel the
  service logged "no alert slider input device" and exited 0.
- **K2** pass: `modules-push`, then `systemctl reboot --reboot-argument=bootloader`
  (fastboot in 12 s) and `fastboot boot`; SSH 8 s later. `/proc/bus/input/devices`
  lists "Volume keys" (input1) and "Alert slider" (input2). Modem in
  ModemManager, 16 video nodes, fingerprint unit active, sound card up, no
  modem crash, no failed unit.
- **K3** pass: with `bias-disable`, slider at the top: TLMM 27 high, 134 high,
  125 low; the service read `ABS_SND_PROFILE` 0 (Silent). Moved by the owner:
  middle 1 (Vibrate), bottom 2 (Ring), middle, top 0 (Silent): one event per
  move, in order.
- **K4** pass (volume part): two presses of each key gave one down and one up
  each; the owner saw the volume OSD move up and down. The screenshot chord
  and the camera shutter are not tried yet.
- **K5** pass (profile and OSD): `gsettings get org.sigxcpu.feedbackd profile`
  followed the slider (`quiet`, `full`, `quiet`, `silent`). The OSD first
  stayed silent and two service copies ran (see §2); after both fixes the owner
  saw Vibrate, Ring and Silent. A call or SMS in each position is not tried
  yet.
