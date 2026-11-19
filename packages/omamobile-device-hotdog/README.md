<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-hotdog

The OnePlus 7T Pro's (`hotdog`, SM8150) device package for Omarchy Mobile.
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
| `libexec/omamobile-hotdog-popup`, `omamobile-hotdog-popup.service` | system | The pop-up front camera's motor (CAMERA-PLAN P0-P5) |
| `libcamera/configuration.yaml`, `70-omamobile-dma-heap.rules` | `/usr/share/libcamera/`, udev | The cameras' software ISP settings and DMA heap access (CAMERA-PLAN C8) |
| `libexec/omamobile-hotdog-sensors-*`, `omamobile-hotdog-sensors.service`, `81-omamobile-hotdog-sensors.rules` | system | hexagonrpcd for the SLPI's Sensor Core, on a read-only root built from the phone's own partitions, started when the SLPI's FastRPC node appears (SENSORS-PLAN) |
| `lib/omamobile-fp-hotdog-chroot`, `omamobile-fp-hotdog.service`, `fprintd.service.d`, `modprobe.d/omamobile-fp-hotdog.conf`, `etc/pam.d/omarchy-lock-fingerprint` | system | The optical fingerprint sensor through the stock trusted app (FINGERPRINT-PLAN); the bionic programs come from `device/hotdog/fingerprint/` (`prebuilt/`, gitignored), and the owner's own files are never packaged |
| `bin/omamobile-hotdog-bt-addr`, its unit | system | A stable, locally administered Bluetooth address derived from the SoC serial, which it never exposes |
| `ucm2/`, `wireplumber/51-omamobile-hotdog-mic.conf` | ALSA, WirePlumber | The speakers' and microphones' UCM profile, and the microphones' capture format (MIC-PLAN) |
| `NetworkManager/conf.d/10-omamobile-usb.conf`, `network/20-usb-gadget.network` | | USB networking to the laptop (172.16.42.1) |
| `logind.conf.d`, `system.conf.d/10-omamobile-reboot-watchdog.conf` | | The power key, and the reboot watchdog |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/` | Where pacman gets `[omamobile]`: the phone's own repository (`local`) until this port's packages are published; the published Mesa has no Adreno driver |
| `/etc/systemd/system/systemd-firstboot.service` → `/dev/null` | | systemd-firstboot would prompt on the panel console, which has no keyboard; omamobile-firstboot sets the same things |

`build` compiles rmtfs and tqftpserv; `test/all` checks that the scripts
parse, every wants link has its unit, the modem services never run
read-write, and the staged install.
