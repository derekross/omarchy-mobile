<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-hotdog

The OnePlus 7T Pro's (`hotdog`, SM8150) device package for Omamobile.
It enables nothing by itself: units start from vendor wants links, and
each part is described in the plan it came from under
[`device/hotdog/`](../../device/hotdog/).

| Part | Installed as | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d/` | Keeps every partition but `userdata` read-only, by the kernel's `PARTNAME` (the initramfs removes `/dev/sda`, so udev reads no partition table), and names the radio's `oem_stanvbk`/`oem_dycnvbk` for rmtfs |
| `omamobile-rmtfs.service`, `omamobile-tqftpserv.service` | system units | The modem's file services, built from linux-msm's rmtfs and tqftpserv. rmtfs runs read-only (`-r`): the modem's NV writes stay in RAM, and its stop never stops the modem (MODEM-PLAN R9) |
| `ModemManager.service.d/omamobile-hotdog.conf`, wants link | system | ModemManager (qcom-soc over QRTR) after rmtfs and tqftpserv |
| `libexec/omamobile-hotdog-sim-select`, `omamobile-hotdog-sim-select.service` | system | Activates the first USIM's provisioning session, which this dual-SIM modem leaves "detected" (MODEM-PLAN R4) |
| `libexec/omamobile-hotdog-call-audio`, `omamobile-hotdog-call-audio.service` | user | Call audio on the ADSP's voice path, behind callaudiod's D-Bus interface, which omatel uses (MODEM-PLAN V1-V4) |
| `libexec/omamobile-hotdog-modem-recovery` | | Turns the modem's remoteproc recovery off for a stop and on again at start (MODEM-PLAN R9) |
| `gnss/qmi-loc.conf`, `geoclue/92-omamobile-hotdog.conf` | `/usr/share/omamobile/gnss/`, `/etc/geoclue/conf.d/` | omamobile-gnss's opt-in to the modem's QMI LOC engine, and GeoClue's ModemManager GPS source off (it only sees `$PQ` sentences; GNSS-PLAN) |
| `mobile-network-modemmanager`, `call-proximity` | `/usr/share/omamobile/` | omamobile-shell's opt-ins (0.2.136): the Mobile network page and data tile through ModemManager, and the screen off at the ear in calls |
| `libexec/omamobile-hotdog-sleep`, `system-sleep/omamobile-hotdog`, `sleep.conf.d/10-omamobile.conf` | | s2idle; before a sleep, waits out modem restarts, arms the modem's IPC router wakeup and takes Wi-Fi down (SUSPEND-PLAN) |
| `libexec/omamobile-hotdog-alert-slider`, its user unit, `72-omamobile-hotdog-keys.rules` | user | The alert slider sets feedbackd's profile (Silent, Vibrate, Ring) with an OSD (KEYS-PLAN) |
| `libexec/omamobile-hotdog-popup`, `omamobile-hotdog-popup.service` | system | The pop-up front camera's motor: raised while the front camera streams, lowered after, on a push and on a fall (accelerometer through `ssccli`) (CAMERA-PLAN P0-P5) |
| `libcamera/configuration.yaml`, `70-omamobile-dma-heap.rules` | `/usr/share/libcamera/`, udev | The cameras' software ISP settings and DMA heap access (CAMERA-PLAN C8) |
| `libexec/omamobile-hotdog-sensors-*`, `omamobile-hotdog-sensors.service`, `81-omamobile-hotdog-sensors.rules` | system | hexagonrpcd for the SLPI's Sensor Core, on a read-only root built from the phone's own partitions, started when the SLPI's FastRPC node appears (SENSORS-PLAN) |
| `libexec/omamobile-hotdog-sar`, `omamobile-hotdog-sar.service` | system | The SAR sensor (Semtech SX9324 through the Sensor Core, data type `sars`) as `near`/`far` in `/run/omamobile/sar/`: one QMI subscription with non-wakeup delivery, kept across SLPI restarts. While near, the modem gets QMI SAR RF state 8 (2-3 dB off LTE bands 3 and 7) and Wi-Fi a 14 dBm nl80211 SAR limit (5 dB at 5 GHz, measured); `/etc/omamobile/sar.conf` changes or turns them off (SENSORS-PLAN §6) |
| `lib/omamobile-fp-hotdog-chroot`, `omamobile-fp-hotdog.service`, `fprintd.service.d`, `modprobe.d/omamobile-fp-hotdog.conf`, `etc/pam.d/omarchy-lock-fingerprint` | system | The optical fingerprint sensor through the stock trusted app (FINGERPRINT-PLAN); the bionic programs come from `device/hotdog/fingerprint/` (`prebuilt/`, gitignored), and the owner's own files are never packaged. RPMB is off as packaged: the owner's `omamobile-fp-hotdog-chroot rpmb allow` turns the module option and the consent file on together, from the next boot (FINGERPRINT-PLAN F7) |
| `bin/omamobile-hotdog-bt-addr`, its unit | system | A stable, locally administered Bluetooth address derived from the SoC serial, which it never exposes |
| `ucm2/`, `wireplumber/51-omamobile-hotdog-mic.conf` | ALSA, WirePlumber | The speakers' and microphones' UCM profile, and the microphones' capture format (MIC-PLAN) |
| `NetworkManager/conf.d/10-omamobile-usb.conf`, `network/20-usb-gadget.network` | | USB networking to the laptop (172.16.42.1) |
| `logind.conf.d`, `system.conf.d/10-omamobile-reboot-watchdog.conf` | | The power key, and the reboot watchdog |
| `vendor/omamobile/shell-env.d/50-hotdog-gpu.conf` | `/usr/lib/omamobile/shell-env.d/` | `FD_MESA_DEBUG=sysmem` for the shell process alone: through GMEM the Adreno 640 faulted and Qt lost the shell's GL context, which froze the home screen and bar. Read by `omamobile-omarchy` 0.1.50's launcher patch 0034 (its own pull request); without it the file does nothing |
| `vendor/environment.d/40-omamobile-fp-hotdog.conf` | `/usr/lib/environment.d/` | Where the shell and onboarding find this phone's fingerprint runner and image (`OMAMOBILE_FP_RUNNER`, `OMAMOBILE_FP_IMAGE`). Without them the shell looks for the Pixels' runner, and when the bridge starts after the shell it never reads the bridge's state: no glyph and no white disc, so the optical sensor sees an unlit finger |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/` | Where pacman gets `[omamobile]`: the phone's own repository (`local`) until this port's packages are published; the published Mesa has no Adreno driver |
| `/etc/systemd/system/systemd-firstboot.service` → `/dev/null` | | systemd-firstboot would prompt on the panel console, which has no keyboard; omamobile-firstboot sets the same things |

## What needs a kernel that isn't merged yet

This package configures drivers from linux-omamobile pull requests that are
still in review, and from branches of the contributor's fork
([johannSo/linux-omarchy-mobile](https://github.com/johannSo/linux-omarchy-mobile),
`omamobile-hotdog-pr/NN-*`, each on the one before) that are not pull requests
yet. On a kernel without them the part below does nothing: its unit's
condition or device node is missing, or the module it names doesn't exist.
Nothing in the package fails the boot for want of one.

| Kernel part | Where it is (2026-11-25) | What in this package is inert without it |
| --- | --- | --- |
| The board, UFS, USB, the remote processors (ADSP, CDSP, modem), the RPMh read fix | [linux-omamobile#282](https://github.com/derekross/linux-omamobile/pull/282), in review | everything: the descriptor's DTB is in no published kernel, so nothing here boots before it merges |
| QRTR's local-service announcement | [#284](https://github.com/derekross/linux-omamobile/pull/284), approved | the modem's services after a remote processor restart (MODEM-PLAN) |
| Wakeup on glink channel data | [#285](https://github.com/derekross/linux-omamobile/pull/285), in review | waking from sleep for a call or SMS: the sleep hook arms the modem's IPC router channel, whose wakeup file only this patch creates |
| `qcom_qseecom_compat` | [#283](https://github.com/derekross/linux-omamobile/pull/283), in review; to come back built only for this phone, off by default | the fingerprint: `omamobile-fp-hotdog.service`, its modprobe options, the lock screen's PAM file |
| The Samsung DSC panel driver, display and GPU | fork `03-display` | the panel's own driver and brightness; the GPU, and with it `shell-env.d/50-hotdog-gpu.conf` (the phone runs on the bootloader's framebuffer) |
| `goodix-fp` for this phone (also used by the Pixel 7 Pro and 9a; its paths stay unchanged) | fork `04-fingerprint` | the fingerprint, as above |
| The volume keys and the alert slider | fork `05-keys` | `omamobile-hotdog-alert-slider` and `72-omamobile-hotdog-keys.rules` |
| AW8695/AW8697 haptics | fork `06-haptics` | vibration (feedbackd) |
| s6sy761's ear detection | fork `07-touch` | the shell's screen off at the ear (`call-proximity`) |
| WCN399x board ID, ath10k fixes | fork `08-bluetooth`, `09-wifi` | Bluetooth (`omamobile-hotdog-bt-addr`) and Wi-Fi |
| OnePlus project info (the RF test cable state the modem reads from SMEM) | fork `12-modem` | nothing is inert, but without it the modem assumes cables in its RF test connectors (MODEM-PLAN) |
| The SLPI and a fastrpc fix | fork `13-sensors` | `omamobile-hotdog-sensors` and its udev rule, and `omamobile-hotdog-sar` |
| SM8150 CAMSS, the sensor and lens drivers (`sony-fwtable` for the IMX481 and IMX586) | fork `14-camss`, `15-camera` | the cameras (`libcamera/configuration.yaml`, the DMA heap rule) and the pop-up camera's motor (`omamobile-hotdog-popup`) |
| The PM8150B charger | fork `16-power` | charging |
| The SM8150 sound card, TFA9872, WCD9340 | fork `17-audio` | the speakers' and microphones' UCM profile and WirePlumber file |
| IPA v4.1 | fork `18-ipa` | mobile data through ModemManager |
| The q6voice series (marked "hack!") | fork `19-voice` | call audio (`omamobile-hotdog-call-audio`) |

The kernel pull requests open one at a time, each once the one before has
landed ([linux-omamobile#282](https://github.com/derekross/linux-omamobile/pull/282)
lists the order).

`build` compiles rmtfs and tqftpserv; `test/all` checks that the scripts
parse, every wants link has its unit, the modem services never run
read-write, and the staged install.
