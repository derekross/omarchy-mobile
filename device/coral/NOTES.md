<!-- SPDX-License-Identifier: MIT -->
# Pixel 4 XL (coral) bring-up notes

Findings from real hardware (`google,coral`, Qualcomm `SM8150` / Snapdragon 855,
kernel `6.17.0-sm8150` built from
[the SM8150 kernel tree at commit `6963e3800a8e`][sm8150-kernel] (three commits
past tag [`v6.17.0-sm8150` (`379d8fe35c7c`)][sm8150-tag]) plus the two ordered
`coral` kernel patch series; the series, device trees, userspace patches and
initramfs are in [`HemangKumawat/omarchy-mobile-coral`, tag `v0.2.3`][coral-repo]
(`78f77e861cfed7cbb57aea7eedc3c539ae1c8e81`; see [`PROVENANCE.md`][coral-provenance])), newest first. Each dated
entry names the kernel build its results ran on.

[sm8150-kernel]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/commit/6963e3800a8e8059c5f01b01dd8e2a5e6a28209a
[sm8150-tag]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/tree/v6.17.0-sm8150
[coral-repo]: https://github.com/HemangKumawat/omarchy-mobile-coral/tree/v0.2.3
[coral-provenance]: https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/PROVENANCE.md

## coral (Pixel 4 XL) in detail

*(Moved from `docs/DEVICES.md`. Status words follow its legend; qualifiers stay in parentheses while `coral`'s `CONTRIBUTING.md` §3.1 entry and guarded `tools/install-phone` support are pending.)*

| Subsystem | Status | Notes | Plan / Reference |
| --- | --- | --- | --- |
| Boot | WIP (in review) | Direct Android Bootloader (`c2f2-0.5-8906123`) header-v2 boot without U-Boot: `text_offset=0x80000`, modern LZ4 frame (`04 22 4d 18`), 12-entry board-matched `sm8150-google-coral.dtb` (`dtc -@`, `sha256: 3efe241a...`) + 12-entry no-op `dtbo.img`, `qcom-wdt` hardware watchdog petted every 5 s across `chroot`, and kernel `qcom-pon` reboot-reason latch (`PON_SOFT_RB_SPARE` `0x88f = 2` until `coral_healthy=1`). Stays up and restarts with the host's USB port switched off (cable attached); a cold boot without a cable is not yet recorded. Test handset uses `boot_a`/`dtbo_a` (historical, do not copy); slot-B installer and `CONTRIBUTING.md` §3.1 entry pending | [BRINGUP-M1](BRINGUP-M1.md) |
| Storage | testing (in review) | Two-pass `blockdev --setro` guard across all 79 UFS nodes (`sda`..`sdf`, `sda1`..`sdf6`); `findfs LABEL=omarchy-root` (`userdata`) mounted `ro,noload` under a `tmpfs` `overlayfs`; `rmtfs -r -P -s` read-only in RAM; `persist` mounted `ro,noload` (123/123 sensor registry files SHA-256 verified unchanged) | [BRINGUP-M1](BRINGUP-M1.md) |
| Display | testing (in review) | Mainline `msm_dpu` + Samsung `S6E3HC2` AMOLED (`1440x3040@60Hz`, DSC 1.1, 2 slices `720x40`), DPMS off/on, and 10-bit big-endian DCS brightness (`0..1023` on `ae94000.dsi.0`) with active DSI link clock vote (`DSI_6G_FIFO_TIMING=0x0bc`, DCS power mode `0x9c`). 90 Hz had startup FIFO underruns before OPP scaling settled and is off by default | [NOTES](#2026-10-18-wi-fi-scan-wcn3990-display-s6e3hc2-dsc-11-gpu-adreno-640-and-touch-fts) |
| GPU | testing (in review) | Qualcomm Adreno 640 (`FD640`, `2c00000.gpu` up to 698 MHz) + Mesa `freedreno` running hardware-accelerated Hyprland (`1440x3040@60`, scale `3.2`) and `omamobile-shell` | [NOTES](#2026-10-18-wi-fi-scan-wcn3990-display-s6e3hc2-dsc-11-gpu-adreno-640-and-touch-fts) |
| Touch | testing (in review) | STMicroelectronics FingerTip S (`st,fts` on `spi0.0`, `0..1439` x `0..3039`) with full flash/calibration write protection (`fts_fw_update` skips CRC/auto-reflash to `fts_init_sensing`, `fts_chip_initialization` blocked, `writeSysCmd` blocks `SYS_CMD_SAVE_FLASH` / `SPECIAL_PANEL_INIT` / `SPECIAL_FULL_PANEL_INIT` / `SPECIAL_WRITE_HOST_MEM_TO_FLASH`, `flash_unlock` blocked, `/proc/fts` & maintenance sysfs removed); double-tap wake (`KEY_WAKEUP`) works | [NOTES](#2026-10-18-wi-fi-scan-wcn3990-display-s6e3hc2-dsc-11-gpu-adreno-640-and-touch-fts) |
| Buttons | testing (in review) | Power key (`qcom-pon` `pwrkey`) and Volume Up / Down (`pm8150_resin` + `gpio-keys`) | [BRINGUP-M1](BRINGUP-M1.md) |
| USB networking | testing (in review) | ConfigFS USB gadget (`18d1:4ee3`): CDC ECM (`usb0` at `172.16.42.1/30`) + CDC ACM serial console + key-only `sshd` (note: development image keeps an unauthenticated root shell on `ttyGS0` and empty root password in RAM `/etc/shadow`) | [BRINGUP-M1](BRINGUP-M1.md) |
| Wi-Fi | testing (in review) | Qualcomm `WCN3990` (`ath10k_snoc`) + `mpss` + `pd-mapper` + `rmtfs -r -P -s` + patched `tqftpserv` + factory `bdwlan.bin` (`Google_coral`); 2.4/5 GHz scan, WPA2-PSK, DHCPv4, DNS, HTTPS, and auto-reconnect; radio sessions ran before the modem baseline | [NOTES](#2026-10-18-wi-fi-scan-wcn3990-display-s6e3hc2-dsc-11-gpu-adreno-640-and-touch-fts) |
| Bluetooth | WIP (in review) | Qualcomm `WCN3990` over `serial0-0` (`hci_qca`, `crbtfw21.tlv` + `crnv21.bin`, ROM `0x21`); `hci0` powers up and BLE/BR-EDR scan works; A2DP/HFP audio and persistent pairing across RAM-overlay reboots are still open | [NOTES](#2026-10-19-qdsp6-audio-dual-cs35l36--knowles-ia8508-slpi-sensors-bluetooth-haptics-and-batterycharger) |
| Battery | WIP (in review) | PM8150B ADC5 `VBAT_SNS` cell voltage (`4.13–4.21 V`) + GEN4 FG SRAM word 328 thermistor temperature (`31.0 °C`), surfaced in the shell via `tools/battery-status.patch`. Aftermarket pack on the test unit: no reply from the fuel gauge at `1-0036` (`-ENXIO`), so state-of-charge `%` is unavailable on this unit | [NOTES](#2026-10-19-qdsp6-audio-dual-cs35l36--knowles-ia8508-slpi-sensors-bluetooth-haptics-and-batterycharger) |
| Charging | testing (in review) | PM8150B SMB5 charger (`qcom_smbx.c`) patched with SMB5 step math (`3.60 V + N * 10 mV`, `50 mA` steps) and clamped in kernel `smb_probe()` to `FV = 0x3c` (`4.20 V`) and `FCC = 0x0a` (`500 mA`), leaving stock hardware JEITA (`0x1090 = 0xdf`, thresholds `0x1094..0x109b`) untouched | [NOTES](#2026-10-19-qdsp6-audio-dual-cs35l36--knowles-ia8508-slpi-sensors-bluetooth-haptics-and-batterycharger) |
| Haptics | testing (in review) | Cirrus Logic `CS40L25A` (`0x43` on `i2c9`) ported to Linux 6.17; wavetable click playback verified | [NOTES](#2026-10-19-qdsp6-audio-dual-cs35l36--knowles-ia8508-slpi-sensors-bluetooth-haptics-and-batterycharger) |
| Torch | testing (in review) | PM8150L flash LEDs (`yellow:flash-0`, `yellow:flash-1`): both switch `0 -> 1 -> 0` by readback from the quick-settings tile; the rear camera saw the light | [NOTES](#2026-10-19-five-camera-camss-streaming-dual-ov7251-nir-pair-lm36011-off-proof-and-torch) |
| GNSS | no | Not started (QMI PDS/LOC client not wired) | — |
| AoC | - | Hardware does not exist on SM8150 (uses QDSP6 `adsp`, `cdsp`, and `slpi`) | — |
| Speakers/mics | testing (in review) | QDSP6 (`adsp`) + `sm8150-coral` sound card (`Pixel4XL`) + dual `CS35L36` amps (`0x40`/`0x41`) + Knowles `IA8508` mic DSP (`spi11.0`); kernel enforces `-26.0 dB` digital ceiling (`608`), read-only `0 dB` analog gain, and `4.5 V` / `1600 mA` boost clamps; 23-min 48 kHz stereo soak (`0` XRUNs, `0` faults) and mic capture verified. Cold-boot ADSP GLINK readiness occasionally needs a service restart | [NOTES](#2026-10-19-qdsp6-audio-dual-cs35l36--knowles-ia8508-slpi-sensors-bluetooth-haptics-and-batterycharger) |
| Sensors | testing (in review) | `SLPI` (`slpi.mdt`) + `fastrpc` + RAM-backed `hexagonrpcd` (`openat2` confined to `/run/coral-qcom/sensors/registry`, zero writes to `persist`) + QMI SSC: accel, gyro (`LSM6DSR`), mag, light, prox, baro, Active Edge squeeze ADC (`MAX11261` at 115 Hz), and Infineon `BGT60TR13C` 60 GHz Soli radar | [NOTES](#2026-10-19-qdsp6-audio-dual-cs35l36--knowles-ia8508-slpi-sensors-bluetooth-haptics-and-batterycharger) |
| Modem | WIP (in review) | `MPSS` boots with `rmtfs -r -P -s` and patched `tqftpserv` (80 carrier MCFG files); QMI UIM detects SIM (`card present, PIN disabled`). SM8150 IPA v4.1 mobile data, WWAN netdev, SMS, and voice calls are not implemented; radio sessions ran before the modem baseline | [NOTES](#2026-10-22-boot-without-a-usb-data-link-guarded-persistence-test-wi-fi-and-sim) |
| NFC | no | Not started (ST21NFCD driver/DT not enabled) | — |
| Cameras | testing (in review) | `sm8150-camss` (CAMNOC QoS + 150 MHz floor + 3-phase C-PHY / D-PHY) streaming all 5 sensors with `0` sequence gaps: rear wide `IMX363` (12.2 MP) and rear tele `IMX481` (16 MP) together for 61 s, front `IMX520` (8 MP), and the dual front NIR `OV7251` (`5-0072` + `5-0070`, `640x480`); colour capture via `libcamera` 0.7.2 software ISP. Both `LM36011` IR laser emitters (`0x64` flood, `0x65` dot projector) remain unbound/unloaded (`ENABLE == 0x00`, strictly `OFF`) | [NOTES](#2026-10-19-five-camera-camss-streaming-dual-ov7251-nir-pair-lm36011-off-proof-and-torch) |
| Suspend | no | Screen DPMS off/on + touch wake work; system `s2idle` / deep sleep is inhibited (`nosleep`) | [NOTES](#2026-10-22-boot-without-a-usb-data-link-guarded-persistence-test-wi-fi-and-sim) |
| Fingerprint | - | Hardware does not exist on Pixel 4 XL (uses Face IR instead) | — |

## 2026-10-22: boot without a USB data link, guarded persistence test, Wi-Fi and SIM

Kernel: `#30` (installed in `boot_a`; see [BRINGUP-M1 §6](BRINGUP-M1.md#6-evidence-from-the-phone-kernel-build-provenance-and-owner-confirmation)).

- **Boot and orderly restart without a USB data link [V]:**
  - Decoupled the early-bringup USB-disconnect `reboot-bootloader` trap from
    the USB gadget helper while retaining BusyBox `watchdog -T 20 -t 5 /dev/watchdog0`
    (`qcom-wdt`, 20 s hardware timeout petted every 5 s across `chroot`) and
    the kernel `qcom-pon` Fastboot reboot-reason latch
    ([`qcom-pon-recovery.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/qcom-pon-recovery.patch)).
  - **Health loop, before and after 22 October [V]:**
    - The first rescue init (18 October, the one in `v0.1.0`) returned to
      Fastboot when its 120-second lease ran out.
    - From 18 October afternoon to 21 October, the installed init (generated
      by `tools/pack-bootimg.py`) waited a 300-second lease. After that, every
      10 seconds it required `/sys/class/udc/*/state == configured`,
      `172.16.42.1` on `usb0`, `systemd` as PID 1 and a live `sshd`, else it
      returned to Fastboot. So an unplugged phone went to Fastboot.
    - The 22 October [`initramfs/init`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/init)
      (`v0.2.1` and later) waits 120 seconds. Then, every 10 seconds, it checks
      only that PID 1 is `systemd` and that the process named in
      `/run/sshd.pid` is `sshd`, and marks `coral_healthy=1`. If the checks
      keep failing for 10 seconds, it still returns to Fastboot.
  - Verified with the build host's USB port switched off in software, cable
    still attached (whether VBUS was cut is unknown). A RAM boot and an
    installed `boot_a` boot each stayed up and set `coral_healthy=1` after
    about 170 s. The phone booted to Hyprland (`1440x3040@60Hz`), joined WPA2
    Wi-Fi by itself and answered SSH. An orderly `systemctl reboot` came back
    over Wi-Fi in about 24 s. A cold boot with the cable removed has not been
    recorded.
  - **Development image physical-access security note (`ttyGS0` root shell & empty root password in RAM) [V]:**
    - [`initramfs/init`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/init)
      spawns an unauthenticated root shell (`setsid /bin/sh </dev/ttyGS0 >/dev/ttyGS0 2>&1`)
      on the USB CDC ACM serial gadget (`ttyGS0`), and
      [`initramfs/omarchy-userspace.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/omarchy-userspace.sh)
      sets an empty password for `root` in the RAM overlay copy of `/etc/shadow`.
      Network SSH (`sshd`) is key-only (`PasswordAuthentication no`), but anyone
      with a physical USB cable connected to this development image has root.
  - **How the `qcom-pon` reboot-reason latch works (kernel SPMI `regmap`, zero userspace PMIC writes) [V]:**
    - In `drivers/power/reset/qcom-pon.c`
      ([`qcom-pon-recovery.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/qcom-pon-recovery.patch)),
      `qcom_pon_probe()` checks `of_machine_is_compatible("google,coral")` and
      immediately writes `2` (bootloader/Fastboot) to `PON_SOFT_RB_SPARE`
      (`0x88f`) via the kernel's SPMI `regmap` (`qcom_pon_reboot_mode_write()`),
      before userspace starts.
    - The driver registers a kernel reboot notifier (`coral_reboot_notify`) and
      exposes a boolean driver sysfs flag `coral_healthy` (initialized to `0`).
      Any kernel panic, `emergency_restart`, hardware watchdog bite, or reboot
      while `coral_healthy == 0` leaves `PON_SOFT_RB_SPARE` at `2` so `c2f2`
      ABL stops in Fastboot.
    - After the 120-second lease, the initramfs health loop writes `1` to
      `coral_healthy` once `systemd` is PID 1 and `sshd` is alive. Only when
      `coral_healthy == 1` does an orderly normal reboot cause the kernel's
      `coral_reboot_notify()` callback to write `0` to `PON_SOFT_RB_SPARE`.
      Userspace never touches PMIC registers directly.
  - **How `qcom-wdt` is fed after transitioning to Arch [V]:**
    - [`initramfs/init`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/init)
      starts BusyBox `watchdog -T 20 -t 5 /dev/watchdog0` in the initramfs root
      namespace, and
      [`initramfs/omarchy-userspace.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/omarchy-userspace.sh)
      transitions into Arch via
      `exec chroot /newroot /usr/lib/systemd/systemd --unit=graphical.target`
      rather than `switch_root`. Because `chroot` retains the initramfs root
      namespace, the BusyBox `watchdog` daemon stays alive under PID 1 for the
      entire Arch session and pets `/dev/watchdog0` every 5 seconds.
- **Wi-Fi association, remote access and SIM [V]:**
  - WPA2-PSK association (`<SSID>`), DHCPv4 lease, DNS and HTTPS traffic.
  - The installed image joins a saved WPA2 network by itself and can be
    reached by SSH through Tailscale (userspace networking, forwarded to an
    `sshd` on `127.0.0.1`). `sshd` listens only on `127.0.0.1` and on `usb0`
    (`172.16.42.1/30`, CDC ECM + ACM). The Wi-Fi profile, the Tailscale state
    and these two units are a private payload appended by hand to the
    installed ramdisk, and are not published.
  - QMI UIM detects the SIM (`card present, PIN disabled`).
- **Read-only UFS guard (`blockdev --setro`) and experimental persistent-overlay test [V]:**
  - In [`initramfs/omarchy-userspace.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/omarchy-userspace.sh),
    PID 1 runs a two-pass `for device in /dev/sd* /dev/vd* /dev/mmcblk*; do blockdev --setro "$device"; done`
    guard before starting `systemd` (once right after `findfs LABEL=omarchy-root`
    before mounting `/lower`, and a second time after mounting the read-only
    radio/vendor layers right before `exec chroot`), and mounts `userdata`
    (`LABEL=omarchy-root`) `ro,noload` under a RAM `overlayfs`.
  - In an experimental persistent-overlay test on 2026-10-22 (run via RAM boot,
    not installed in `boot_a`), making `/dev/sda15` writable required clearing
    the read-only flag on **both `/dev/sda15` (`userdata`) and its parent
    whole-disk node `/dev/sda`** (`sda=0, sda15=0`, while `sda1`..`sda14` and
    `sdb`..`sdf` stayed `ro=1`), because Linux's `bdev_read_only()` checks both
    the partition node and the parent `gendisk` read-only flag. Because `sda=0`
    would leave raw whole-disk `/dev/sda` LBA writes unblocked by
    `bdev_read_only()`, the installed image remains on the default RAM-only
    overlay where all 79 `sd*` nodes (`sda`..`sdf`, `sda1`..`sdf6`, including
    `sda` and `sda15`) stay `ro=1`.
  - That test wrote to `userdata`. Through a loop device we created a 42 GiB
    ext4 filesystem (`coral-persist`) at byte offset 8 GiB inside `sda15`,
    after the 7 GiB Omarchy root. The first RAM boot used it as the overlay
    upper and wrote a test file; the root superblock hash was unchanged and
    `e2fsck -fn` was clean. The second RAM boot reset to Fastboot about 12 s
    after `fastboot boot`, cause unknown. The handset has not been reachable
    since 21:28 that day (Berlin); a flat battery is suspected, not proven.

## 2026-10-19: five-camera CAMSS streaming, dual OV7251 NIR pair, LM36011 off-proof, and torch

Kernel: `#27` (five-camera kernel, installed in `boot_a` on 19 October).

- **All five camera sensors verified streaming over `sm8150-camss` [V]:**
  - Patched `sm8150-camss`
    ([`kernel/patches/camera/001..033`](https://github.com/HemangKumawat/omarchy-mobile-coral/tree/v0.2.3/kernel/patches/camera))
    with a 150 MHz `camnoc_axi` floor (`clk_set_min_rate` in `camss.c`),
    CAMNOC QoS programming (`camss-vfe-17x.c`), 3-phase C-PHY configuration
    (`camss-csiphy-3ph-1-0.c` + `camss-csiphy-sm8150-combo.h`), and 4-VC
    `csid-gen2` routing for all five sensors on `coral`
    ([`sm8150-google-coral-cameras.dtsi`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/dts/sm8150-google-coral-cameras.dtsi)):
    1. **Rear wide (`imx363`, 12.2 MP, CCI0) and rear telephoto (`imx481`,
       16 MP, CCI0):** streamed together for 61 s (`1,850` and `1,832` V4L2 raw
       frames, `0` sequence gaps); colour capture via `libcamera` 0.7.2 simple
       pipeline + CPU software ISP.
    2. **Front selfie (`imx520`, 8 MP, CCI1):** `90` frames in 3 s and
       `libcamera` software ISP capture.
    3. **Front NIR pair (`ov7251` master `5-0072` & slave `5-0070`, `640x480` Y10/Y8):**
       both sensors share CCI I2C bus 1 and `mclk4` (`24 MHz`), with separate
       resets (`GPIO 118` master, `GPIO 109` slave) and hardware frame sync
       (`FSIN` wired from master `STROBE` `0x3005=0x08` to slave `FSIN`
       `0x3006=0x00`, `0x3823=0x30`, `0x3826=0x23`). Both streamed together
       (`1,832` + `1,830` frames, `0` sequence gaps). Hardware frame sync
       between the two sensors is not proved.
- **Confirmation that nothing writes to the `LM36011` IR emitters (`0x64` flood and `0x65` dot projector) [V]:**
  - On `coral`, `i2c1` (`geniqup@8c0000/i2c@88c000`) hosts two TI `LM36011` IR
    laser/LED drivers behind a Silego/Dialog GreenPAK hardware safety state
    machine: `0x64` (`lm36011_flood`, flood illuminator) and `0x65`
    (`lm36011_dot`, dot projector).
  - **In the installed kernel and rootfs:** no `LM36011` or GreenPAK driver is
    bound or loaded (`ir_emitters: "inhibited; lm36011 unbound and unloaded"`),
    and no userspace tool ever writes to `i2c1` `0x64` or `0x65`.
  - **In the isolated RAM-boot `leds-lm3601x-coral-off.h` diagnostic**
    ([`kernel/patches/face/leds-lm3601x-coral-off.h`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/face/leds-lm3601x-coral-off.h)):
    any non-zero brightness request is unconditionally refused (`-EPERM`,
    `"coral safety gate refuses IR emitter activation"`), and the probe path
    only writes `LM3601X_ENABLE_REG (0x01) = 0x00` (Mode=00 Standby) and reads
    back `ENABLE (0x01) == 0x00`, `LED_CUR (0x03)`, and `DEV_ID (0x06) == 0x01`
    to prove both emitters remain strictly `OFF`.
- **Torch (PM8150L flash LEDs `yellow:flash-0` and `yellow:flash-1`) [V]:**
  - With fixed exposure and gain, the rear wide camera's mean (raw8) rose from
    `15.8` to `140.9` with the torch on and returned to `15.6`; the tele's rise
    was small (`15.6` to `17.3`).
  - The quick-settings Torch tile first returned `unavailable`; after the fix
    it switched both channels `0 -> 1 -> 0` by readback. The light from the
    tile was not checked by eye.

## 2026-10-19: QDSP6 audio (dual CS35L36 + Knowles IA8508), SLPI sensors, Bluetooth, haptics, and battery/charger

Kernel: `#25` (installed in `boot_a` on 19 October), with the SLPI and audio modules and DTB from the `0008`/`0009` trees.

- **Speakers and microphones (`Pixel4XL` ALSA card via QDSP6) and hardware gain ceiling [V]:**
  - Brought up `qcom_q6v5_pas` (`adsp`), `q6afe`, `q6asm`, `q6adm`, `q6routing`,
    and the `sm8150-coral` machine driver
    ([`coral-audio.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-audio.patch)
    + [`sm8150-coral.h`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/audio/sm8150-coral.h)
    + [`sm8150-google-coral-audio.dtsi`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/dts/sm8150-google-coral-audio.dtsi))
    with:
    - **Dual Cirrus Logic `CS35L36` speaker amplifiers** on `i2c@c94000` (`0x40`
      bottom speaker, `0x41` top/earpiece speaker) over Tertiary MI2S (`1.536 MHz`
      bitclk, 2-slot 16-bit TDM) + Quaternary MI2S VMON/IMON feedback slots.
    - **Knowles `IA8508` smart mic DSP** over SPI (`spi@a8c000` / `spi11.0`,
      firmware `RomeApp.bin` v`6739055.p`) feeding Primary/Secondary TDM capture
      links.
  - **Enforced kernel speaker ceiling and 23-minute soak levels [V]:**
    - Because no DSP speaker-protection algorithm is running yet, the kernel
      sound card driver (`sm8150_coral_late_probe()` in
      [`sm8150-coral.h`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/audio/sm8150-coral.h))
      enforces a hard ceiling in the kernel:
      - `Top Digital PCM Volume` and `Bottom Digital PCM Volume` have their
        kernel `platform_max` clamped to **`608` (`-26.0 dB`)**
        (`#define CORAL_DIGITAL_MAX 608 /* -26 dB; speaker-protection DSP is absent. */`),
        matching [`userspace/audio/ucm2/Pixel4XL/HiFi.conf`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/userspace/audio/ucm2/Pixel4XL/HiFi.conf).
      - `Top Analog PCM Volume` and `Bottom Analog PCM Volume` are forced to
        **`0` (`0 dB`, `CORAL_ANALOG_SAFE = 0`)** in `sm8150_coral_late_probe()`
        and have `SNDRV_CTL_ELEM_ACCESS_WRITE` stripped so userspace cannot
        raise analog gain above `0`.
      - In `sound/soc/codecs/cs35l36.c`
        ([`coral-audio.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-audio.patch))
        and [`sm8150-google-coral-audio.dtsi`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/dts/sm8150-google-coral-audio.dtsi),
        the `CS35L36` boost converter is clamped to **`4.5 V`
        (`cirrus,boost-ctl-millivolt = <4500>`)** (fixing an upstream
        `cs35l36.c` bug that overwrote `bst_vctl` with `10 V`), with peak
        inductor current clamped to **`1600 mA`
        (`cirrus,boost-peak-milliamp = <1600>`)**, hardware boost current limit
        enabled (`CS35L36_AMP_DIG_VOL_CTRL2 & 7 == 5`), and thermal warning
        threshold set to `1`.
    - The 23-minute 10-second (`1,390,234 ms`, `66,707,611` PCM frames, 48 kHz
      stereo) voice/meditation soak ran under this exact kernel ceiling
      (`digital_value = 608` / `-26.0 dB`, `analogue_value = 0`, boost `4.5 V` /
      `1600 mA`, `0` XRUNs, `0` amplifier faults), and synthetic test tones in
      `coral-phone` are additionally capped at `0.25` (`-12 dBFS`) digital peak
      (`-38 dB` combined).
  - *Known gap:* on cold boot, `qcom_q6v5_pas` (`adsp`) occasionally hits a
    GLINK/APR readiness race requiring a service restart before the ALSA card
    registers; kept at `testing` until startup ordering is race-free.
- **SLPI sensor hub (`slpi.mdt` + FastRPC + QMI/QRTR SSC) and `persist` checksum verification [V]:**
  - Enabled `remoteproc_slpi` (`5c00000.remoteproc`,
    `qcom/sm8150/google/coral/slpi.mdt`), `fastrpc`
    ([`coral-slpi.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-slpi.patch)),
    and `hexagonrpcd` patched with a RAM-backed sensor registry
    ([`hexagonrpc-ram-registry.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/userspace/hexagonrpc/hexagonrpc-ram-registry.patch)).
  - At service startup
    ([`sensor-runtime.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/userspace/services/sensor-runtime.sh)),
    `persist` is mounted `ro,noload,nodev,nosuid,noexec` at `/run/coral-persist`,
    copied into `tmpfs` at `/run/coral-qcom/sensors/registry`, and confined via
    `openat2(..., RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS)`. All 123 files in
    `/run/coral-persist/sensors/registry/registry` (`83,565` bytes) were SHA-256
    verified before and after the SLPI sensor and Soli sessions, matching 123/123
    on-flash files with zero writes to `persist`.
  - Verified all **7 hardware sensor streams** live over QMI/QRTR SSC (plus the
    Infineon `BGT60TR13C` 60 GHz Soli radar):
    1. Accelerometer (`LSM6DSR`, ~50 Hz, gravity vector `z ≈ 9.8 m/s²`)
    2. Gyroscope (`LSM6DSR`, ~50 Hz)
    3. Magnetometer (`~50 Hz`)
    4. Ambient light (`lux` updates verified)
    5. Proximity (`near/far` state transitions verified for screen blanking)
    6. Barometer (`~1013 hPa`)
    7. Active Edge squeeze ADC (`elmyra_raw` / `MAX11261` streaming 4 channels
       at `115 Hz`)
- **Bluetooth (`WCN3990` `hci_qca`) [V]:**
  - Loaded `btqca` and `hci_uart` over `serial0-0` with `qca/coral/crbtfw21.tlv`
    and `qca/coral/crnv21.bin` (`QCA Rome 0x3020100`, ROM `0201`).
  - `bluetoothctl show` confirms `hci0` `Powered: yes` and BLE/BR-EDR device
    discovery works. Audio routing (A2DP/HFP) and persistent pairing are still
    open (`WIP`).
- **Haptics (`CS40L25A`) [V]:**
  - Ported `cs40l2x` (`1-0043` on `i2c9`, reset GPIO, wavetable DSP;
    [`coral-cs40l2x-port.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-cs40l2x-port.patch))
    and verified stock click waveform playback.
- **Aftermarket battery note (`1-0036` `-ENXIO`), cell voltage/temperature telemetry, and PM8150B SMB5 charger clamp (`FV 0x3c`, `FCC 0x0a`, `JEITA 0xdf`, `DMA 0x00`) [V]:**
  - **Why `max1720x`/`max1730x` at `1-0036` returns `-ENXIO` on this handset (aftermarket replacement battery):**
    - Before the port, the owner fitted an aftermarket replacement battery.
      [I] It appears to lack the OEM Maxim `MAX1720x`/`MAX1730x` fuel gauge:
      `1-0036` on `i2c9` returns `-ENXIO`. It is not yet checked whether the
      gauge is missing, unpowered or at another address. The owner reports
      that the battery percentage also failed under stock Android.
    - Consequently, [`coral-gauge1730x.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-gauge1730x.patch)
      is expected to probe `1-0036` on an OEM pack (not tested: this unit has no
      OEM pack), while on this test unit `1-0036`
      returns `-ENXIO` (no ACK). Battery state-of-charge `%` is therefore
      unavailable on this unit (`WIP`), whereas live cell voltage (`4.13–4.21 V`
      via PM8150B `VBAT_SNS` ADC5) and thermistor temperature (`31.0 °C` via
      GEN4 FG SRAM word 328) work and are surfaced in the mobile shell by
      [`tools/battery-status.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/battery-status.patch)
      (which disables UPower's synthetic capacity warning and shows measured
      voltage and charging status from `/run/coral-phone/status.json`).
  - **What writes the charger registers:** The **kernel driver**
    `drivers/power/supply/qcom_smbx.c` (`smb_probe()` in
    [`coral-charge.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-charge.patch))
    via SPMI `regmap`, **not** userspace.
  - **Where the values come from (SMB2 vs SMB5 step math in `qcom_smbx.c`):**
    - Upstream `qcom_smbx.c` used PMI8998/SMB2 step math (`3.4875 V + N * 7.5 mV`
      float voltage, `25 mA` current steps) on PM8150B, which is an **SMB5**
      charger (`3.60 V + N * 10 mV` at `CHGR_FLOAT_VOLTAGE_CFG` `0x1070` with
      valid codes `0x00..0x77` = `3.60..4.79 V`, and `50 mA` steps at
      `CHGR_FAST_CHARGE_CURRENT_CFG` `0x1061`, per Google's stock `qpnp-smb5.c` /
      `smb5-reg.h` / `smb5-lib.c` in
      [`kernel/msm` at `82a738b32e3f`](https://android.googlesource.com/kernel/msm/+/82a738b32e3f715728b846f8908083286287cb06/drivers/power/supply/qcom/)).
    - Under the unpatched SMB2 formula, a `4.40 V` battery DT target wrote
      `(4400000 - 3487500) / 7500 + 1 = 121 + 1 = 122` (`0x7a`) to `0x1070`, exceeding
      PM8150B's maximum valid SMB5 code (`0x77` = `4.79 V`) and pushing rested
      cell voltage to `4.447 V`.
    - [`coral-charge.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-charge.patch)
      updates `qcom_smbx.c` to use SMB5 step scaling on `pm8150b` and sets
      `voltage-max-design-microvolt = <4200000>` and
      `constant-charge-current-max-microamp = <500000>` in DT. During
      `smb_probe()`, the kernel driver disables charging (`0x1042 = 0x00`),
      writes `0x1070 = 0x3c` (`60` -> `3.60 V + 60 * 10 mV = 4.20 V`) and
      `0x1061 = 0x0a` (`10` -> `10 * 50 mA = 500 mA`), and re-enables
      `0x1042 = 0x01`.
  - **`JEITA 0xdf` vs stock:** `0x1090` (`JEITA_EN_CFG_REG = 0xdf`, with
    threshold registers `0x1094..0x109b = 18 11 58 1c`) is **stock's hardware /
    bootloader register configuration left completely untouched**
    (`coral-charge.patch` never writes `0x1090..0x109b`). We only read `0x1090`
    and `0x1094..0x109b` back via debugfs regmap to verify that stock's hardware
    JEITA protection (`0xdf`) remained active.
  - **`DMA 0x00`:** In `drivers/power/supply/qcom_fg.c`
    ([`coral-fg-temp.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-fg-temp.patch)),
    GEN4 fuel-gauge SRAM temperature reads (word 328) check `MEM_INTF_DMA_STS`
    (`0x4370`) for latched DMA errors (`0x00` = clean; if an earlier transaction
    latched `0x04`, the kernel driver pulses `MEM_INTF_CTL` bit 2 to clear it,
    matching stock's FG driver).

## 2026-10-18: Wi-Fi scan (`WCN3990`), Display (`S6E3HC2` DSC 1.1), GPU (`Adreno 640`), and Touch (`FTS`)

Kernels: `#7` (touch, GPU, Wi-Fi scan) and `#8` (display), both installed in `boot_a` on 18 October.

- **Wi-Fi (`WCN3990` via `ath10k_snoc` + `mpss` + read-only `rmtfs -r`) and modem partition protection [V]:**
  - `WCN3990` on SM8150 requires `mpss` (`4080000.remoteproc`,
    `qcom/sm8150/google/coral/modem.mdt`), `pd-mapper`, `rmtfs -r -P -s`
    serving memory-backed read-only copies of `modemst1`, `modemst2`, `fsg`, and
    `fsc`, `tqftpserv`
    ([`0001-translate-serve-readonly-vendor-mbn-Pixel-MCFG-from-.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/userspace/tqftpserv/0001-translate-serve-readonly-vendor-mbn-Pixel-MCFG-from-.patch),
    mapping `/readonly/vendor/mbn/` requests to `<rproc fw dir>/mbn/`), and
    vendor board data (`bdwlan-coral` repackaged as
    `ath10k/WCN3990/hw1.0/board-2.bin` for
    `bus=snoc,qmi-board-id=ff,qmi-chip-id=30214,variant=Google_coral`).
  - *Backups and the modem baseline:* before the first flash on 12 October we
    kept Google's factory image (`TP1A.221005.002.B2`), `getprop`, the
    `/dev/block/by-name` listing and the vendor firmware. We took no raw copy
    of any partition, `persist` included; the owner approved skipping that
    backup. The read-only dump of `modemst1`, `modemst2`, `fsg`, `fsc`,
    `persist`, `modem_a` and `modem_b` in
    [BRINGUP-M1 §5 item 2](BRINGUP-M1.md#5-storage-guard-watchdog-across-chroot-qcom-pon-latch-and-security-notes)
    will be the first copy, taken after the 12–22 October sessions from a RAM
    boot that does not start `mpss`. Across those sessions: (1) `modemst1`
    (`sdf2`), `modemst2` (`sdf3`), `fsg` (`sdf4`), `fsc` (`sdf5`) and `persist`
    (`sda2`) were set `ro=1` via `blockdev --setro` in PID 1 before any service
    started; (2) `rmtfs` ran with `-r -P -s` (EFS served from RAM, nothing
    written back); and (3) all 123 files in
    `/run/coral-persist/sensors/registry/registry` (`83,565` bytes on `persist`)
    matched their SHA-256 checksums before and after the DSP sessions. With no
    earlier baseline, we cannot show that the modem partitions are unchanged.
  - Verified 2.4/5 GHz scan. WPA2, DHCP, DNS and HTTPS came on 22 October.
- **Display (`Samsung S6E3HC2` `1440x3040@60Hz` DSC 1.1) and Backlight [V]:**
  - Mainline `msm_dpu` + `panel-samsung-s6e3hc2`
    ([`0001-coral-base-dts-and-s6e3hc2-panel.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/0001-coral-base-dts-and-s6e3hc2-panel.patch))
    drives the `1440x3040` AMOLED panel over `DSI-1` with Display Stream
    Compression (DSC 1.1, 2 slices per line, slice `720x40`, 8 bpc, `vddio`
    `1.84 V`, `vci` `3.0 V` on `l4c`, reset `tlmm 67`).
  - Patched `dsi_host.c`
    ([`coral-dsi-clock.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-dsi-clock.patch)
    and [`coral-dsi-transfer-clocks.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-dsi-transfer-clocks.patch))
    to program `DSI_6G_FIFO_TIMING = 0x0bc` and keep DSI link clocks enabled
    around `msm_dsi_host_xfer_prepare()` / `unprepare()` so 10-bit big-endian
    brightness updates (`0..1023` on `/sys/class/backlight/ae94000.dsi.0`,
    [`coral-panel-brightness.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-panel-brightness.patch))
    and DPMS off/on transitions never race link power-down.
  - *Note on 90 Hz:* 60 Hz is clean (`0` DPU underruns); an experimental 90 Hz
    mode showed startup FIFO underruns before OPP/bandwidth scaling settled and
    is left disabled by default.
- **GPU (`Qualcomm Adreno 640` / `FD640`) [V]:**
  - Loaded `msm` DRM + `a630_sqe.fw` / `a640_gmu.bin` / `a640_zap.mdt` on
    `2c00000.gpu` (`698000 kHz` max OPP); Mesa `freedreno` (`FD640`) runs
    Hyprland hardware-accelerated at `1440x3040@60Hz` (scale `3.2`) with
    `omamobile-shell` and OWL widgets.
- **Touchscreen (`STMicroelectronics FingerTip S` / `fts` on `spi0.0`) and full calibration/flash write guard [V]:**
  - In [`coral-fts-readonly.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-fts-readonly.patch)
    (`drivers/input/touchscreen/fts_touch/`), when `!info->board->auto_fw_update`
    (`st,disable-auto-fw-update` in `sm8150-google-coral.dts`), **every**
    firmware flash, panel init, CX tuning, MP-flag write, and CRC-error
    auto-reflash path is blocked:
    1. **CRC-error auto-reflash & firmware update (`fts_fw_update()` in `fts.c`):**
       returns `fts_init_sensing(info)` directly *before* `"Fw Auto Update is
       starting..."`, before `fts_crc_check()`, and before `fts_fw_updater()`,
       logging `"coral fts flash-write guard: cfgAfeVer=%02X cxAfeVer=%02X mpFlag=%02X; sensing only"`.
       In `fts_chip_powercycle()` (`fts_lib/ftsCore.c`), the reset-timeout
       recovery path also skips `fts_fw_update()`.
    2. **Panel init, CX tuning & MP-flag writes (`fts_chip_initialization()` in `fts.c`):**
       returns `ERROR_OP_NOT_ALLOW` immediately (`"coral fts: calibration flash
       writes forbidden"`), blocking `fts_production_test_main()` (panel init and
       CX tuning) and `save_mp_flag()`.
    3. **Low-level system commands & flash unlock (`fts_lib/ftsCore.c` and `fts_lib/ftsFlash.c`):**
       `writeSysCmd()` returns `ERROR_OP_NOT_ALLOW` for `SYS_CMD_SAVE_FLASH`,
       `SPECIAL_PANEL_INIT`, `SPECIAL_FULL_PANEL_INIT`, and
       `SPECIAL_WRITE_HOST_MEM_TO_FLASH`; `flash_unlock()` returns
       `ERROR_OP_NOT_ALLOW` (`"coral fts: flash unlock forbidden"`).
    4. **Debug/maintenance interfaces (`fts_proc.c` and `fts.c`):**
       `fts_driver_test_init()` is stubbed out (`return OK`, no `/proc/fts`
       created), and sysfs attributes `fwupdate`, `autotune`, `stm_fts_cmd`, and
       `infoblock_getdata` are removed from `fts_attr_group`.
  - Touch coordinates (`0..1439` x `0..3039`) and double-tap wake (`KEY_WAKEUP`
    via [`coral-touch-wake.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-touch-wake.patch))
    work across screen blank/unblank cycles.
