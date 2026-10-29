<!-- SPDX-License-Identifier: MIT -->
# OnePlus 13 (dodge)

Status (2026-10-28): native Arch Linux ARM / Omarchy Mobile on Qualcomm SM8750
(`7.3.0-rc6-dodge-gpu2` lineage). Display, GPU (Adreno 830), touch, Wi-Fi,
Bluetooth pairing, speakers/mics, sensors (autorotate), USB gadget networking
and SSH work on the phone. Modem (MPSS + IPA + ModemManager + NetworkManager
cellular) works behind an opt-in flag with a per-phone EFS restore (see
[modem/README.md](modem/README.md)); no modem blobs or EFS snapshots are in
this repository. Fingerprint, cameras and NFC are not started.

Kernel series: [linux-omarchy-mobile #115](https://github.com/derekross/linux-omarchy-mobile/pull/115)
(`dodge/pr-kernel-v1`; subsystem-split; gpu2 + IPA). Device tree:
`arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dts`. Userspace: this tree's
`device/dodge/` and `packages/omamobile-device-dodge`.

Descriptor: `BOOT_METHOD=qcom-abl`, `OMAMOBILE_SLOT=b`,
`UFS_RW="boot_b userdata"`. Omarchy runs on slot B; stock stays on slot A.
Day-2 kernel updates rewrite `boot_b`. The guarded inactive-slot installer
and firmware-match helper are deferred to a later PR; how this phone was
installed (firmware A→B copy for ARB, GPT bit-54 mark) is a record in
[BRINGUP-M1.md](BRINGUP-M1.md), not a procedure for others. Never flash xbl,
abl, vbmeta or modem from an image.

## Feature matrix (phone-verified)

| Block | Status | Notes |
| --- | --- | --- |
| Boot | testing | Omarchy on `boot_b` (2026-10-28); stock `boot_a` kept; GPT bit 54 marked by hand (kernel in review, [#115](https://github.com/derekross/linux-omarchy-mobile/pull/115)) |
| Storage | testing | UFS; guard allowlists `boot_b` and `userdata` (shared `initramfs/init`) |
| Display | testing | Samsung panel through msm/dpu; brightness and DPMS; warm-boot drop fixed (QTB read) |
| GPU | testing | Adreno 830 (gpu2); glmark2 / Freedreno on the phone; Vulkan untested |
| Touch | testing | Synaptics over SPI |
| Buttons | testing | Power and volume |
| USB net | partial | CDC NCM gadget + ACM console; SSH. Gap: gadget stuck after cable replug until reboot |
| Wi-Fi | testing | WCN7860 (peach) / ath12k; autoconnect and 5 GHz |
| Bluetooth | partial | WCN7860; pairing verified; A2DP untested (no headset yet) |
| Battery | partial | gauge reads; charging path not fully claimed |
| Speakers/mics | testing | AW882xx + UCM2 + PipeWire; speaker, earpiece and built-in mics; headset plug untested |
| Sensors | testing | SSC via hexagonrpc / libssc; accel, proximity, compass; autorotate |
| Modem | testing | MPSS + IPA + MM + NM; LTE registration and data; EFS restore every boot; opt-in flag; calls/SMS untested |
| Suspend | WIP | screen-off idle works; s2idle not yet the default |
| Fingerprint | no | |
| Cameras | no | |
| NFC | no | |
| Charging / Haptics / Torch / GNSS | no | |
| AoC | - | Tensor-only block |

## 2026-10-28: matrix evidence

Phone-verified summary for [docs/DEVICES.md](../../docs/DEVICES.md). Companion
kernel in review as
[linux-omarchy-mobile #115](https://github.com/derekross/linux-omarchy-mobile/pull/115).
Full narrative for the slot-B move is in [BRINGUP-M1.md](BRINGUP-M1.md) §5.

| Block | What was run on the phone | Status word |
| --- | --- | --- |
| Boot / storage | Firmware A→B match (27 pairs, sha256 read-back); Omarchy on `boot_b`; GPT bit 54 marked by hand; stock OTA `boot` kept on `boot_a` | testing |
| Display | msm/dpu panel up; brightness and DPMS; warm-boot drop closed (QTB read on MDSS enable; Martin verified cold start and idle/wake 2026-10-24) | testing |
| GPU | Adreno 830 via Freedreno on gpu2; Hyprland and glmark2 on the phone; Vulkan (turnip) not run | testing |
| Touch / buttons | `touchpanel` input; power and volume keys | testing |
| USB net | CDC NCM + ACM + SSH. Known gap: after a cable replug the UDC can stay stuck until a reboot | partial |
| Wi-Fi | WCN7860 / ath12k; autoconnect, DHCP, 5 GHz | testing |
| Bluetooth | hci0 up; pairing with another phone verified; A2DP / headset audio not tested | partial |
| Battery | fuel-gauge capacity reads; charging path not claimed | partial |
| Speakers/mics | Speaker and earpiece heard; built-in mic record+playback hands-on; USB-C headset plug untested | testing |
| Sensors | Accelerometer, proximity, compass through SSC; autorotate on by default after install | testing |
| Modem | With `/etc/omamobile/modem-probe.enable` and IPA (gpu2): LTE registration and data; EFS restore every boot; calls and SMS untested. Flag is opt-in in the package | testing |
| Suspend | Screen-off idle with GDSC off; `systemctl suspend` / s2idle not the default | WIP |

## Provenance

- Board DTS and driver enablement authored for Omarchy Mobile from public
  mainline SM8750 support, OnePlus 13 DT fragments, and bring-up on this phone.
- Audio codec unmute and panel sequence: see kernel commit messages and
  `Assisted-by` / `Signed-off-by` trailers.
- Missing upstream sign-offs from earlier community fragments (index986 /
  ROCKNIX / Teguh) are listed in the kernel PR description for the maintainer.

## What is not in this tree

Lab notebooks (`dev-docs/`), DIAG trials, out-of-tree splash/fastrpc experiments,
EFS snapshots, modem firmware blobs, and AGENTS/PLAN files stay on the private
bring-up branch. The modem units document how to take **read-only** `dd`
copies of the phone's own EFS partitions onto the device; those copies are
never committed.
