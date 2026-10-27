# Pixel 7 Pro (cheetah) bring-up notes

Findings from real hardware, newest first. `BRINGUP-M1.md` is the research map written before first boot.

## 2026-10-27: the muted speakers were the open-loop coil estimate, not sleep; the static was the boost converter; the earpiece is the top speaker

- **The speaker watchdog had muted media at every boot since 10-26 22:28**
  ("Bottom: coil temperature jumped 14-27 C in this stream" at stage media
  737/10), and nothing in the UI shows a mute. Not sleep: it repeated
  2.5 min into a cold boot with no suspend, so the 10-26 note that a
  power-off cleared it was wrong. The cause is the bottom CS35L41's
  protection model with **DRE on at analog gain 10**: it over-estimates
  its output by about 20 dB on any signal above a low level (a -20 dBFS
  multitone took its coil estimate from 25 to 31 C within a second; the
  top amplifier on the same content, slots swapped, rose 0.17 C). DRE off
  restores the 10-12 numbers (bottom +0.15 C on that burst, +0.25 C on
  30 s of music at full sink volume). Stock runs DRE only at gain 17.
  But DRE is only the first trigger: the bottom's estimate jumps 10-15 C
  on **any level drop** (a volume step down during music, a 13 dB drop
  cut into the music itself with the sink untouched, the end of a stream,
  the shell's duck at unlock), while the firmware's own attenuation stays
  at full scale and the top amplifier moves by 0.1 C. At analog 10 the
  firmware does not sense the coil, so this is an open-loop estimate the
  levels do not depend on (AUDIO-PLAN section 4). omamobile-audio 0.5.3:
  the watchdog's 5 C jump rule only above the stage's analog ceiling of
  10 (stage c9); the 80 C backstop and every other rule stay; DRE stays
  on. AOC-PLAN C9j.
- **Media does not play through the wrong speaker.** The registers, the
  UCM and listening tests agree with stock: left in TDM slot 0 to the top
  amplifier, right in slot 1 to the bottom. The earpiece is the top
  speaker and carries the full left channel at the same gain as the
  bottom one; stock adds 17 dB, Waves processing and a proximity mute.
  With the sink at 60 % on top of the stage cap, media was about 30 dB
  under stock's maximum, hence "sounds like the call speaker".
- **The "static" under music is the amplifiers' boost converter at light
  load.** Measured through the phone's own mic (validated with an external
  tone): at 737/10 a 1 kHz tone distorts 44 % on the bottom speaker at
  -20 dBFS and 10 % on the top at -10 dBFS, at a fixed output per speaker
  (about 30 and 25 mA peak), at every frequency, with the DSPs bypassed,
  out of the case. With the converter off (kernel 00590 `boost_en=N`: the
  output stage from VP) the same inputs are 8-11 dB louder and clean (top
  1 %, bottom 0.5-4 % with DRE on). Stock's 817/17 never runs the
  converter in that regime. omamobile-audio 0.5.3 turns it off at analog
  10 and below. AOC-PLAN C9j has the whole elimination.
- **Streamed music is 10-15 dB under a test tone by its normalisation;** the
  package filter's limiter drive gives it back (0.5.4: flat, drive 6 dB, the
  owner's choice). 817/10 without the boost converter is not usable: the
  output stage runs out of supply near 2 V peak (bottom 82 % THD at
  -10 dBFS). AOC-PLAN C9j.
- **Routing TDM_0_TX into an EP capture crashes the AoC** (its watchdog
  fires, the AoC goes offline, every service answers -517 until a reboot).
  The amplifiers' V/I return has no host-readable copy on this card.
- Kernel 00561's S2MPG12 LDOs: 28 registered, no users, none disabled at
  the 30 s cleanup (`regulator_summary`); only `vddio_cam` is, as before.

## 2026-10-26: auto-sleep on the phone; the bottom speaker's protection broke after sleep

Kernel `7.3.0-rc6-omamobile-push1-00588-gcd72ae58ee47` (the test-bt-wifi
build), `omamobile-shell` 0.2.29 and `omamobile-device-cheetah` 0.1.34 from
the `suspend-tier1` branch. SUSPEND-PLAN P0-P5 has the step-by-step record.

- **Suspend itself held up.** 13 s2idle cycles in one boot: `systemctl
  suspend` by hand, the RTC, a WakeSystem timer (on time to 1 s), Power and
  Volume Down as wakes, and `omamobile-sleepd`'s own requests. There were
  0 failures, no `ufshcd_err_handler`, and Wi-Fi stayed connected (the D3
  ACK by control message in 13-20 ms).
- **The press that wakes the phone never reaches Hyprland.** logind logs
  it ("Power key pressed short"), but the user session is still frozen
  while the kernel takes the key, so the Power binding never ran and the
  phone woke to a dark screen. `omamobile-sleepd` now lights the PIN pad
  itself when the wake IRQ is `KEY_POWER` (`omamobile-keys wake`), and
  `omamobile-keys` ignores a late copy of that press within 1.5 s.
- **A freeze in the middle of a fingerprint cancel wedged fprintd** ("the
  device is still busy"): the lock retried about three times a second and
  never showed the sensor. The sleep hook now try-restarts fprintd on
  every resume, and the lock re-claims it within about 0.5 s.
- **Locking with Power flashed the PIN pad.** This was an old
  `omamobile-keys` bug, unrelated to suspend: the long-press timer (0.6 s)
  fired while the lock was still being taken (0.9 s) and woke it. Fixed;
  `power-up` now forgets the press first.
- **After the sleeps, the bottom speaker's protection read a false coil
  temperature.** The first sound after 13 sleeps tripped the watchdog:
  "Bottom: coil temperature jumped 14.5 C (25.0 -> 39.5)" within 2 s.
  - It read 35 °C while silent and peaked at 40.7 °C; the top amplifier
    stayed at 25.0 °C.
  - Neither a restart of `omamobile-speaker-protection` nor a warm reboot
    cleared it. A full power-off did: both amplifiers read 25.00 °C, and
    playback at stage media works again, with the bottom amplifier moving
    more than the top.
  - So sleep left the bottom CS35L41 (or its DSP state) wrong, and that
    state survives a warm reboot, much like the LSM6DSV in AOC-PLAN C6.
  - Every earlier sleep test (S6) ran with no sound playing. This was the
    first playback after a sleep.
  - **Auto-sleep stays off** until the amplifiers' suspend and resume are
    understood: whether the driver's system-sleep ops run on gs201, and
    whether the DSP, its calibration and the TDM back end come back.
  - The speakers also hissed briefly when the amplifiers powered up during
    the cold boot; whether that is new hasn't been checked.
  - **Correction (2026-10-27):** not sleep, and a power-off did not clear it; the trip repeated 2.5 min into a cold boot. It was the watchdog's jump rule on the bottom amplifier's open-loop coil estimate; see the 2026-10-27 entry and AOC-PLAN C9j.
- **"Quiet and thin" is still the stage-media cap**, about 17 dB below
  stock, and both amplifiers report `vmon low 1` at analog gain 10. The
  owner hears it as the call speaker carrying the sound. The next speaker
  session is AOC-PLAN C9i, on the `speakers-offline` branch.

## 2026-10-23: the S2MPG12 regulator driver binds read-only (kernel #27); UFS and touch PRs boot

- **Kernel #19 + #22 (Tensor G4 UFS host and PHY, with error propagation
  in the shared gs101/gs201 paths).** One boot on top of the #27 kernel
  (7.3.0-rc6-omamobile-push1-00569-ga147e30b96e3, DTB unchanged): UFS at
  `FAST series_B G_4 L_2` as before, root mounted, no UFS/PHY error or
  timeout and no `ufshcd_err_handler` at 25, 54 and 94 s with uncached
  reads in between; the link cycled through hibern8 with clock gating.
  Host reset and resume take the same path and were not exercised.
- **Kernel #26 (synaptics-tcm: avdd before vdd, 200 ms power-on wait).**
  One boot on top of that (…-00570-g8cd00dcfc564): the supplies (dummies
  here) are taken avdd first, the controller identifies 268 ms after them
  (88 ms with the old 20 ms wait), same S3908 firmware and config, touch
  worked (808 interrupts in use).
- `ak7375_vcm_resume I2C failure: -6` (camera VCMs) and `wc-mbox … Try
  increasing MBOX_TX_QUEUE_LEN` show on every recent boot, old kernels too.

- **Kernel #27's S2MPG12 LDO driver, read-only boot.** The integration
  kernel plus #27's three driver commits
  (7.3.0-rc6-omamobile-push1-00561-g0f75358341a9); the DTB was
  byte-identical to the previous build's, and the backup checksums of the
  six radio and `persist` partitions matched beforehand. The image's
  `suspend-pmic-test` overlay enables `pmic-1`, so `s2mpg12-regulator`
  binds next to `s2mpg13-regulator`: all 28 LDOs registered with no users
  and no constraints, and none was disabled or set, at 165 s and 262 s.
  The touch rails LDO25M/LDO26M read 1.8 V/3.3 V and the display rails
  LDO27M/LDO28M 3.025 V/1.2 V, unchanged through a display off/on cycle;
  touch and display worked (touch IRQs 3 to 567), with no UFS error handler.
- **`vddio_cam: disabling` (LDO12S, S2MPG13) at about 32 s is a race, not
  new:** the 30 s unused-regulator cleanup sometimes runs before the camera
  sensors take the rail, and they enable it again later. It showed on this
  boot and on one of four earlier boots of the previous kernel.

## 2026-10-19: the guard's allowlist from the descriptor; the temperature guard on the phone

- **The storage guard's allowlist now comes from `device.conf`**
  (`/etc/omamobile-ufs-rw`, packed and checked by `bin/omamobile
  initramfs`; a missing or bad file leaves every partition read-only). Test
  boot on 7.3.0-rc6-omamobile-push1-00558-gcbd727f42785, new initramfs only:
  `ufs-ro: allowlist: boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b
  dtbo_b userdata`, no fail-closed line, the same six partitions writable as
  before, `persist`, `efs`, `efs_backup`, `modem_userdata` and `modem_a/b`
  read-only, `/dev/sda` removed, USB product still "Pixel 7 Pro (M1)".
- **Charger temperature guard (USB-C-PLAN B3g G1, G2) passed** under the
  dead-man switch; details and the Rp 3.0 A answer to the B3.3 current
  question in USB-C-PLAN section 9.
- **The charger and the guard now load at boot** (device-cheetah 0.1.33,
  USB-C-PLAN D1): 1.47 A and 4.45 V in the 20-42 C band instead of the
  bootloader's 1.93 A with no bands; the battery had reached 39.5 C at
  1.9 A without the guard.
- **The init checks the guard once more before switching to Arch** and
  stays in the initramfs if anything outside the allowlist is writable;
  test boot passed (same six writable, "switching to Arch Linux").

## 2026-10-18: a charging phone put to sleep at low battery; fingerprint stuck afterwards; the shared init boots

- **The battery read "Unknown" while charging**, so the bar showed no
  charging icon and upower counted the phone as on battery. The charger
  runs on the bootloader's settings with no driver bound (USB-C-PLAN B3),
  so nothing is described as supplying the battery, and
  `max17042_get_status()` gave up on `power_supply_am_i_supplied()`'s
  -ENODEV. At its action level (`PercentageAction=2`; the battery read
  11 % sixteen minutes later), upower's critical action (`Sleep`)
  suspended the phone while it was charging
  ("suspend requested from client … 'upowerd'"); the fuel gauge's alert
  IRQ woke it 75 s later.
- **Fix:** kernel `omamobile-battery` @ `de0aa4d4e` ("infer the status when
  no supplier is described"): with no supplier and current sense on, the
  status comes from the gauge's current (charging when positive, full at
  end of charge with no current, else discharging). Merged into
  `omamobile-int` (`cbd727f42`). On 7.3.0-rc6-omamobile-push1-00558-gcbd727f42785:
  `status` Charging at +1.9 A, upower `state: charging`, `on-battery: no`.
- **The fingerprint stopped working after that sleep** (the same on
  2026-10-17 19:05). The lock screen was mid-verify when fprintd suspended
  the sensor for sleep: "Cannot run while suspended", then pam_fprintd's
  `ReleaseDevice` failed ("still busy"). After resume fprintd refused the
  lock screen ("Authorization denied … ListEnrolledFingers"), and the lock
  screen retried `omarchy-lock-fingerprint` about three times a second
  with PAM_AUTHINFO_UNAVAIL, keeping fprintd alive in that state. It only
  recovered when the lock ended and fprintd exited idle; the next lock
  matched at once. Reproduced with an RTC wake (`rtcwake -m no -s 25`, then
  `systemctl suspend`, lock screen up) and fprintd debug logging: the close
  that pam_fprintd's Release asked for was refused while libfprint had the
  device suspended, fprintd dropped its claim anyway, and every later Claim's
  open failed on the device libfprint still held open.
- **Fix:** libfprint 1.94.100-1.5: the `omamobile_udfps` driver has suspend
  and resume hooks. A verify stays open across the sleep (the HAL's capture
  is cancelled before and started again after), so the lock screen sees no
  error. Same test on the phone: suspend and resume completed without
  error, `AUTH` went out on resume, and a later Release closed the device
  and the next Claim opened it.
- **The shared initramfs init (PR #4) boots cheetah** (same kernel, new
  initramfs only): no "skipped" or "trigger failed" line, so the board
  check matched and `0x1c240030 0x3061` was written; the bring-up probe ran
  (wtcon and DPP reads as before); the guard left exactly slot B's five
  boot images and `userdata` writable.

## 2026-10-12: first sound from the built-in speaker; accelerometer at every boot

- **The top speaker plays** (AOC-PLAN C7d-6, kernel
  7.3.0-rc6-omamobile-push1-00290-g66446bf5b725): a -20 dBFS 1 kHz tone
  through AoC EP6 (PCM 5) in copy mode, heard by the human. The AoC drained
  the ring (Tx = Rx = 291840 bytes) with a PCM interrupt every 80 ms. A
  second stream in the same boot drained too.
- **Why it had been silent:** the AoC driver sends the ALSA PCM device
  number to the AoC as the entry point ID. Our card numbered its PCMs in
  device-tree link order, which differed from stock, so EP6 playback was
  PCM 47 and the AoC refused it ("Entrypoint 47 cannot be configured", in
  its own log at /dev/acd-logging; the driver ignored the rc -1 replies).
  The card driver now sorts its DAI links into the stock order (EPn
  playback = PCM n-1, EPn capture = PCM n+7), whatever order the DTB has.
- **The I3C accelerometer went missing after a warm reboot.** The sensor
  rails (S2MPG13 LDO7S 1.8 V, LDO5S 3.3 V) stay on across a reboot, so the
  LSM6DSV kept its state from the previous AoC session and didn't join the
  new one. The I2C sensors were unaffected. gs201_aoc_rails `cycle=1`
  switches both off for 150 ms before enabling them, as Google's
  reset_sensor_power() does; all four sensors now appear at boot.

## 2026-10-11: hardware buttons (gpio-keys)

- **All three buttons are plain GPIOs**, so one `gpio-keys` node covers them (kernel branch `omamobile-buttons`): Volume Down `gpa10-1` (pull-up), Volume Up `gpa8-5` (FAR_ALIVE, no pull), Power `gpa10-0` (pull-up). All active low, all `wakeup-source`. They appear as `/dev/input/by-path/platform-gpio-keys-event` with KEY_VOLUMEDOWN/UP/POWER.
- **Power is `PMIC_PWRON_OD_L`** (Google's `gs201-common.dtsi`): the S2MPG12 PWRONB line is also routed to the SoC. Stock configures the pin but reports the key through `s2mpg12-keys` over ACPM instead. Upstream gs101 Pixels use the GPIO (`gpa10-1` there), so we do the same. Reading the line doesn't affect the PMIC's own long-press reset.
- **Needed the ALIVE pin controller** (`0x180d0000`, banks gpa0-5, 9, 10; alias `pinctrl0`). The driver data was already there; the DT node wasn't. Wake-up interrupts are direct, one GIC SPI per pin (gpa10 = SPI 42/43), from the stock DT.
- **Test:** `evtest --grab /dev/input/by-path/platform-gpio-keys-event`. `--grab` keeps logind and Hyprland from also acting on the key.
- **PMIC path (not needed for KEY_POWER, kept for regulators/RTC):** upstream has gs101 ACPM (`exynos-acpm*.c`, `google,gs101-acpm-ipc`) and S2MPG10/11 on top of it (`sec-acpm.c`). gs201 needs (1) a `google,gs201-acpm-ipc` match (mailbox `0x18210000`, SRAM `0x18500000`; check `initdata_base` in Google's ACPM driver), (2) S2MPG12/S2MPG13 register maps and IRQ tables in `sec-acpm.c`/`sec-irq.c`, from Google's GPL `soc/gs/drivers/mfd/s2mpg12-*.c` and `s2mpg13-*.c`, (3) regulator data. Google's `s2mpg12-key.c` only duplicates the GPIO key; upstream has no s2mpg10 key driver either.

## 2026-10-11: touchscreen (Synaptics S3908 on SPI)

- **Works with our own driver** (`drivers/input/touchscreen/synaptics_tcm.c`, kernel branch `omamobile-touch`): TouchComm v1, message CRC off, firmware `S3908GA1B0-15.0` build 4104960, 1440x3120, 10 objects. Hyprland lists it under Touch; the panel is portrait with transform 0, so no axis swap or flip.
- **Wiring:** PERIC1 USI0 SPI at 0x10d10000 (GIC SPI 690), mode 0, 10 MHz; CS on gpp20-3 as a GPIO; ATTN gpa7-0 (FAR_ALIVE, GIC SPI 52, level low); reset gpp23-2 (active low).
- **ABL holds the controller in reset** (gpp23-2 driven low) but leaves both supplies (S2MPG12 LDO25M 1.8 V, LDO26M 3.3 V) on. Releasing reset by hand with devmem made ATTN fall, which proved power before any driver existed.
- **gs201 EINT numbering skips EINT19**, so from EINT20 on the GIC SPI is the EINT number minus one (gpa7-0 = EINT53 = SPI 52; gs101 uses 53).
- **USI IPCLK gates need `CLK_SET_RATE_PARENT`.** Without it the SPI ran from the undivided 400 MHz source and never shifted a byte (TX FIFO stuck, `I/O Error ... res-(-5)`).
- **The controller answers 0xff when not ready**; reads are retried until the 0xa5 marker appears, as Synaptics' driver does.

## 2026-10-11: A/B slot metadata lives in `devinfo`

- **ABL keeps the slot state in the first 128 bytes of `devinfo`** (8 KiB, not slotted), not in `misc` and not in GPT attributes. Source: Google's boot HAL, `device/google/gs-common` `bootctrl/aidl/` (Apache-2.0, tag android-14.0.0_r75), the one that builds `android.hardware.boot-service.default-pixel`. It uses GPT attributes only if devinfo is invalid. `misc` holds only the bootloader message and, at 32 KiB, the virtual A/B merge status.
- **Layout:** magic `DEVI` (0x49564544), version u16 3 . u16 15, then 4 bytes per slot at 0x30 (a) and 0x34 (b): retry count, then flags bit0 unbootable, bit1 successful, bit2 active, bit3 fastboot-ok. No CRC. Every other header byte is ABL's own; bytes from 0x80 hold factory records (serials, IMEI).
- **The 11 October backup decodes exactly to `getvar all`:** a: active, successful, retry 2, fastboot-ok. b: successful, unbootable, retry 2.
- **`omamobile-bootctl`** (in the initramfs, not called by init yet) dumps it and can `mark-successful` / `set-active` behind `--i-understand`. On the backup, `set-active b` then `mark-successful b` changes only 0x31, 0x34 and 0x35. The HAL's `set-active` also writes the UFS `bBootLunEn` attribute, which the tool does not do.

## 2026-10-11: lost USB for an hour (our bug, not hardware)

- **Symptom:** USB enumerated, then bulk transfers stalled after a few seconds ("transmit queue timed out" on the host, then "not responding to setup address" on re-enumeration). Background jobs with `sleep` never finished.
- **Cause:** init ended with `exec setsid cttyhack sh ...`, and Alpine's busybox has no `cttyhack`. The exec failed, PID 1 exited, and the kernel panicked. The panic never showed, because ABL appends `console=null`.
- **Fix:** PID 1 never exits: it keeps the screen shell in a `while true` loop, using `setsid -c` for the controlling tty. The DTB bootargs carry `panic=10`, so any future panic reboots instead of freezing. After a few failed boots ABL falls back to stock slot A, where `adb reboot bootloader` reaches fastboot.
- **Ruled out along the way:** the gs201 clock driver, the host port, PMU state, and the HSI0 S2MPU firewall. On a non-pKVM boot, `S2MPU_HSI0` (0x11070000) reads `CTRL0` = 0, i.e. already disabled. Note for later: shipping needs real S2MPU programming for DMA protection.
- **`reboot-to bootloader` is unreliable.** syscon-reboot-mode binds to the PMU, but ABL usually ignores the reason. The one success may have coincided with the buttons being held. Open.

## 2026-10-11: M1 first light

Mainline v7.3-rc6 boots from slot B, with all 8 CPUs, 11.5 GB of RAM, USB networking and SSH at `172.16.42.1`, and a readable console on the panel.

### Boot chain

- **ABL ignores our `vendor_boot` cmdline.** The kernel cmdline is the DTB `/chosen/bootargs` plus ABL's own additions (ending with `console=null ... bootconfig`). Put kernel arguments in the DTB.
- **ABL accepted our DTB** with `soc_id = <0x09855001 0x0>` (B0 silicon), and our empty dtbo keyed `0x30306` / `0x10000`. Unsigned images boot fine on an unlocked bootloader (orange state).
- **Slot B fallback works.** Our Linux never marks the slot successful, so after its retries ABL boots stock slot A. From slot A, `adb reboot bootloader` reaches fastboot without buttons.
- **The unlocked-warning screen is not fastboot.** Pausing it doesn't expose fastboot over USB. Real fastboot is reached by holding Volume Down through the restart, until the "Fastboot Mode / Start" screen appears.
- **After a forced reset out of our Linux,** fastboot sometimes doesn't enumerate on USB.
- **Reaching fastboot by hand, as it works on this phone:** hold Power about 30 s until fully off. Then hold Volume Down, add Power, and keep both held about 20 s until the "Fastboot Mode" screen with "Start" appears. Letting go early lands on the unlocked-warning screen, which carries on booting slot B.
- **From a working Linux,** `reboot-to bootloader` (in the initramfs) reaches fastboot in about 2 s. It uses `LINUX_REBOOT_CMD_RESTART2` so syscon-reboot-mode stores 0xfc in SYSIP_DAT0 through the PMU regmap. Plain busybox `reboot` hangs.

### Display

- **ABL's framebuffer is at `0xfac00000`,** 1440x3120, stride 5760, a8r8g8b8. DPP0's RDMA base address register (`0x1c0b0000 + 0x40`) reads `0xfac00000`. simple-framebuffer at that address is correct.
- **The panel (Samsung S6E3HC4) runs in MIPI DSI command mode.** `DECON0 GLOBAL_CON` (`0x1c240020`) = `0x133`, which is command mode and running. ABL leaves `TRIG_CON` (`0x1c240030`) = `0x3070`: hardware trigger disabled, with `HW_TRIG_MASK_DECON` set. So the panel never receives a new frame after the logo.
- **Writing `TRIG_CON = 0x3061`** (unmask the trigger, enable hardware TE trigger) makes DECON send a frame on every panel TE pulse, so the framebuffer refreshes continuously. The init script does this until we have a real DECON/DSI driver. Register layout: Google GPL `google-modules/display/samsung/cal_9845/regs-decon.h` (gs201 uses cal_9855, which reuses it).
- **Console font:** `fbcon=font:TER16x32` with `CONFIG_FONT_TER16x32`. 8x16 is unreadable on this panel.

### Watchdogs

- **ABL leaves both cluster watchdogs running.** `CL0` at `0x10060000`, `CL1` at `0x10070000`, about 60 s, and the phone resets at roughly 60 s of uptime.
- **Fixed** by the upstream `s3c2410_wdt` driver with a `google,gs201-wdt` compatible (gs101 data). With `tmr_atboot=0` it stops both watchdogs at probe ("watchdog inactive, reset disabled").

### PMU and reboot

- **PMU registers are secure-only.** Google's drivers write them through `set_priv_reg` (an SMC). Plain `/dev/mem` writes (e.g. reboot reason at `0x18060810`) are silently ignored. Use the kernel's exynos-pmu regmap, which goes through SMC for gs101 data.
- **`reboot -f` hangs** (the phone stops responding but stays powered). On gs201, Google's `pixel-gs201-reboot.c` restart handler does nothing itself, so the reset is expected to come from PSCI `SYSTEM_RESET`. Root cause still open.

### kexec

- **kexec with `--reuse-cmdline` and the live DT works:** the new kernel and initramfs boot and draw to the screen.
- **USB does not come back after kexec.** The host sees the device but enumeration fails ("not responding to setup address", -71). The PHY/link is likely left powered down by the old kernel's shutdown, and can't be re-initialised with placeholder clocks. Revisit after `clk-gs201` and a proper USB PHY reset.

### Host setup

- **NetworkManager profile `omamobile-phone`** gives `172.16.42.2/24` on any `enp0s20f0u*` gadget link. Without it, NM tears the link down after DHCP fails.
- **`tools/phone-ssh`** runs commands on the phone. dropbear has no scp/sftp server, so stream files with `ssh 'cat > file' < file`.

## 2026-10-12: firewall (Omarchy's ufw)
- **Kernel:** Arch's iptables is iptables-nft, so ufw needs nf_tables plus the xtables matches its rules use through `nft_compat`: conntrack, state, owner, limit, recent, addrtype, hl, multiport, comment, LOG, REJECT (v4 and v6), and IPv6 `rt`. These are in `kernel/configs/omamobile.config`. The legacy filter tables (`iptable_filter`) are not needed.
- **Phone:** Omarchy's `install/config/firewall.sh`, plus `ufw allow in on usb0 to any port 22 proto tcp` so SSH over the USB link keeps working. ufw is on at boot (`ENABLED=yes`, `ufw.service`): incoming is denied, outgoing allowed.
- **Testing a change safely:** arm `systemd-run --unit=fw-deadman --on-active=90 /usr/bin/ufw disable` first, check that a *fresh* SSH connection opens, then stop the timer.
- **To do:** the image build should run the same steps. Should SSH-over-USB stay open on user builds? It is a developer feature.

## 2026-10-12: display rate and power baseline (read-only)
- **Refresh rate (DISPLAY-PLAN D5a, `tools/display-hz --secs 10`):** 602 frames in 10.006 s = 60.16 Hz. DSIM underrun count 0x1f09 and TE timers 0x33eb/0x3b26 are ABL's 60 Hz values; no underrun. 120 Hz is DISPLAY-PLAN D5c.
- **Power P0 (POWER-PLAN 5.1):** no `cpuidle` directory (WFI only), broadcast timer `bc_hrtimer`, no PMU SMC failures. UFS `auto_hibern8` is "Operation not supported", so step U1 is skipped. Clock gating is on with a 150 ms delay. Battery 4.33 V, -1.9 mA average on USB.

## Host changes to undo later

Made on the development laptop to give the phone internet over USB. Revert when no longer needed:

- **ufw forwarding for the phone's USB link** (added 2026-10-11): `sudo ufw route allow in on enp0s20f0u2`. Undo with `sudo ufw route delete allow in on enp0s20f0u2`.
- **NetworkManager profile `omamobile-phone`** set to `ipv4.method shared` (NAT for the phone). Undo with `nmcli con modify omamobile-phone ipv4.method manual`, or remove the profile: `nmcli con delete omamobile-phone`.

## Phone UX to-dos

- **First-run notifications are desktop-oriented.** "Learn Keybindings (Super + K…)" makes no sense on a touch phone, and "Setup Wi-Fi" needs to open the phone's Wi-Fi settings. Find how Omarchy's first run triggers them (`install/user/first-run`) and how omarchy-mac adapts them for its platform, then do the same in the Omarchy Mobile package. No local hacks.
- **Make `omarchy update` the update path on the phone.** Omarchy installs a pacman hook that blocks direct `pacman -Syu` and points to `omarchy update` (snapshots, keyrings, migrations, restarts). On the phone this needs `sudo` for the user and decisions about snapshots (no snapper/btrfs here, since the root is ext4). The `[omarchy]` repo must come **before** `[core]` in pacman.conf on aarch64, so Omarchy's own builds (quickshell 0.3.2-4, hyprland 0.56.2-5) win over Arch Linux ARM's. With ALARM's quickshell 0.3.2-1 on Qt 6.12, the shell's theme colours didn't resolve.
- **Agent choice in onboarding.** The launcher's "Ask Claude" is hardcoded. Use Omarchy's standard default-agent mechanism (`omarchy-default-agent` and its settings, which Omalauncher also follows) for the launcher's agent, and let the user pick their agent during first-run onboarding, as Omarchy does. Claude stays Derek's choice, not the default.
- **Temporary patch on the phone's Omarchy shell (2026-10-11).** Qt 6.12 (already in Arch Linux ARM) adds `QtQuick/Color`, which shadows Omarchy's `Commons.Color`, so every palette colour was undefined. Upstream fixed this in omacom/omarchy b83d3df084 (#14553, after v4.0.4) by importing `qs.Commons as Commons` and qualifying `Commons.Color`. We applied the same transformation to the installed v4.0.4 shell (54 files; original backed up at `/root/omarchy-shell-4.0.4-orig.tar.gz` on the phone). The next Omarchy release replaces those files with upstream's fix. Our phone plugins now follow the same rule.
- **Done (2026-10-11): first-run keybindings toast and agent choice.**
  - The launcher reads Omarchy's default agent (`~/.config/omarchy/defaults/agent`, set by `omarchy-default-agent`). It prompts through `omarchy-agent-prompt`, or opens Omarchy's picker (`omarchy menu summon setup.default.agent`) when none is chosen.
  - `omamobile-setup-user` marks `welcome-keybindings-not-applicable`, which the upstream change honours: submitted as omacom/omarchy#15075 (https://github.com/omacom/omarchy/pull/15075). The patch in `patches/omarchy/0001-*` is applied on the phone as a bridge until it ships.
  - The setup script will become Omarchy Mobile's `setup-user` entrypoint in Omarchy's lifecycle-dispatch contract once a release includes it.
- **Done: UTF-8 locale and timezone** via `omamobile-setup-system` (en_US.UTF-8; timezone from the host; NTP synced).
- **USB doesn't reconnect after unplugging (2026-10-11).** The USB PHY forces VBUS valid at boot (no Type-C / MAX77759 TCPC driver yet), so the gadget never sees detach or attach. After an unplug, the link stays down until the next boot. Fixed properly by the MAX77759 TCPC + dwc3 role-switch work (plan: USB-C row).
- **Done (2026-10-11): apps open off-screen.** Omarchy floats its terminal, btop and dialogs at desktop sizes (875 x 600) through a `floating-window` tag, so on a 480 px wide screen they landed mostly off-screen (seen when installing an agent). `packages/omamobile-shell/hypr/phone.lua` drops the tag and maximizes every window, Android-style; it's loaded from the user's `looknfeel.lua`.
- **Done (2026-10-11): on-screen keyboard.** squeekboard, with Omarchy's fcitx5 masked for the user and Wayland text-input selected (`20-omamobile-osk.conf`). The drawer uses on-demand focus: Hyprland routes no touch to other layers while one holds exclusive keyboard focus. Size follows the panel's real millimetres, now in the device tree.
- **Done (2026-10-11): power button menu.** Omarchy already binds XF86PowerOff to the system menu, so our extra binding toggled it twice; removed. Omarchy's menu drew its card at the top for one frame while its window still had a placeholder size (`patches/omarchy/0002-*`, applied on the phone, to send upstream). Suspend is hidden with Omarchy's `suspend-off` toggle until the kernel can suspend; later, short press = screen off + suspend, long press = menu, like Android.
- **Screensaver isn't phone-shaped.** It runs in a terminal, so focusing it pops up the on-screen keyboard. Its art (`~/.config/omarchy/branding/screensaver.txt`) is one ~80-column line of lettering, too wide for portrait. On exit it sets `cursor:invisible false`, which brings back the pointer we hide. Needs a portrait art file, no keyboard, and the phone's cursor setting kept.
- **Lock screen and PIN.** Wanted: Omarchy's lock after boot (autologin, then lock) and after the screensaver, unlocked with a PIN/password or fingerprint. Omarchy's lock (shell `lock` plugin, PAM) hides every other surface while locked, including the on-screen keyboard, so the phone needs a PIN pad inside the lock view. The PIN is the user's password, so `sudo` and the lock agree.
- **Fingerprint.** Omarchy's lock already supports fprintd. The plan (Google's HAL and Trusty TA in a minimal chroot, Trusty driver port, panel LHBM, staged runbook) is in `FINGERPRINT-RESEARCH.md`.
- **Omarchy's per-user install never fully ran on the phone (2026-10-11).** Example: no default keyring, so the first app to use the keyring (Chromium, during an agent login) popped up a desktop-sized "create a keyring password" prompt. Fixed by hand with Omarchy's own `install/user/default-keyring.sh`. The phone image must run Omarchy's user install (`install/user/all.sh`), not a hand-picked subset; audit the other steps (theme, chromium, git, xcompose, mise) too.
- **Chromium's first-run dialogs don't fit.** Its "Additional Terms of Service" page (blank text in open-source builds) put Accept off-screen and blocked an OAuth login. `omamobile-setup-user` adds `--no-first-run` to `~/.config/chromium-flags.conf`.
- **System dialogs aren't phone-shaped.** gcr-prompter (keyring), polkit and portal dialogs are GTK windows sized for desktops. Now that every window is maximized they fit the width, but they'll want a phone-friendly look.
- **Stale `/usr/local/bin/omamobile-setup-user` (fixed 2026-10-11).** An early hand-copied version shadowed the packaged `/usr/bin` one on PATH, so newly added setup steps were silently skipped when the script ran by name. Removed. Since then both packages are installed with pacman (below).
- **Shell plugin development gotchas (2026-10-11).**
  - Omarchy's live plugin reload ("Local plugin changed, reloading") can keep running the old code. After changing a plugin's QML, restart the shell (`omarchy-restart-shell`) before testing.
  - A Qt pointer handler (DragHandler, TapHandler) declared directly on a Quickshell window gets no events. Put it on an Item inside the window.
  - A plugin may only summon panels it owns (`_summon` checks `pluginOwnsTarget`). To open another plugin, run `omarchy-shell shell summon <id>`, as Omarchy's background does.
  - To debug touch, `console.log` is hard to read back (binary `log.qslog`, needs `qs log`). Appending to a file through `Quickshell.execDetached` gave a clear trace.
- **Packaged (2026-10-11).** `omamobile-shell` and `omamobile-device-cheetah` are built natively on the phone with makepkg and installed with pacman. Hand-copied files in `/etc`, `/usr/local/bin` and `/usr/share/omamobile/phone` are gone; the user's config points at `/usr/share/omamobile/shell`. The MAX77759 blacklist moved from the rootfs overlay into the device package (`/usr/lib/modprobe.d`). Still to do: a package repository so `omarchy update` (pacman -Syu) picks up new versions, instead of `pacman -U`.
- **Omarchy per-user install audit (2026-10-11).** Against `install/user/all.sh`: theme, Chromium extensions and the keyring are in place; `mise-work.sh` (`~/Work`, node) and `xcompose.sh` were run by hand. Still open: git identity (`git.sh` needs the user's name and email) and `mise.sh` (Omarchy installs about 11 agent CLIs; only Claude is installed). The image build must run Omarchy's whole user install instead.
- **Package repository (2026-10-11).** `[omamobile]` is in the phone's pacman.conf, before `[omarchy]`, through `/etc/pacman.d/omamobile-mirrorlist` (from `omamobile-device-cheetah`). Packages and the database are signed with the Omarchy Mobile key (`keys/`, never committed; public half in `omamobile-keyring`). While the project is private the repository lives on the phone at `/var/lib/omamobile/repo`: `tools/repo-build` builds (on the phone), signs and indexes it, `tools/repo-push` copies it over, and `pacman -Syu` / `omarchy update` installs new versions. Bootstrap on a new phone: `pacman-key --add` and `--lsign-key` the key once, then install `omamobile-keyring`. Our Mesa is tracked from `[omamobile]`, so Arch's can't replace it (we must keep it current with Arch's Mesa). `omarchy update` needs sudo, which asks for the PIN, so it runs in a terminal like on a computer.
- **Reserved memory audit (2026-10-11).** Firmware writing into memory the kernel thinks is free corrupts data, so every stock `reserved-memory` node was checked against `/proc/iomem`. Five were plain System RAM in our kernel: `seclog` (0xc3000000, written by the secure world at runtime), the modem's `cp_rmem`/`cp_rmem_1` (0xea400000, 0xe8000000), AoC's `xhci_dma` (0x97000000) and `ect_binary` (0x90000000). All are now `no-map` in gs201.dtsi (kernel e7cb10fe5). The regions they named, 0xd8100000 and 0xdc210000, were already inside our `dss` reservation.
- **Battery model works (2026-10-12, gate B1b).** With the gauge in POR (Status 0x0002, DesignCap 0x0bb8, TaskPeriod 0x1680, Config 0x2354 with TEx set, so Temp stuck at 22.0 °C), the new loader wrote stock's 1 kΩ-ID ModelGauge m5 model at probe ("battery model loaded (DesignCap 0x9c5, TaskPeriod 0x2d00)"). Every register then matched the expected table in WIFI-BATTERY-PLAN.md B1b; charge_full 5000 mAh (design 5002), temp 35.0 °C from the thermistor, UPower 22.25 Wh. After a reboot POR stays clear and the model is kept without reloading. Merged into the main kernel (`omamobile`).

## 2026-10-12: Wi-Fi connects (W3)

- Kernel omamobile-int `7.3.0-rc6-omamobile-push1-00131-g03266d3c4a3e` (pcie `e1c6379cf`): WPA2 association to a home AP on 5 GHz (ch 48), DHCP, 0% ping loss.
- 50 MB download over Wi-Fi: 18.97 MB/s (about 152 Mbit/s), no control timeouts, no firmware trap, no "poll: mailboxint" catches in that run.
- Fixes that got it there (WIFI-BATTERY-PLAN 9.13-9.16): host ready rung once, FLR on probe and remove, versioned join parameters (JOIN_V1), host-built 802.3/LLC TX headers (HOST_SFHLLC), and re-polling the D2H rings after each INTx.
- The interface uses the bootloader's MAC (omamobile-device-cheetah 0.1.5); NetworkManager randomises it only while scanning.
- Still a test setup: Wi-Fi stays blacklisted at boot and is loaded by hand until W4 (S2MPU confinement). No long transfers before W4.
- **W4 decision (2026-10-12): Wi-Fi ships with the restricted DMA pool only.**
  - The HSI2 System MMU (and the S2MPU) select by VID, and the negative tests showed the PCIe master (AxID 0x0) and UFS (AxID 0x2) both arrive on VID 0. Translating VID 0 starved storage and wedged the phone. So neither block can confine the chip, and the firewall driver now refuses VID 0.
  - The pool keeps every buffer the kernel gives the chip in 16 MiB below 4 GiB. That contains driver bugs and stray pointers, not hostile firmware, which appears to be no worse than stock: stock's VID-1 SysMMU maps every buffer 1:1.
  - The default DTB enables `pcie_1`, its PHY and the pool, and the SysMMU node stays disabled.
  - omamobile-device-cheetah 0.1.12 enables `omamobile-wifi.service`. The modules stay blacklisted for autoload, so only the hang-safe script loads them.
  - 6 GHz chanspecs now decode without the "Invalid chanspec 0x5001" warning; 6 GHz itself is not enabled yet.

## 2026-10-12: Bluetooth, haptics and torch bring-up (BT1.1-1.3, H1-H3, T1-T3)

Kernel omamobile-int `7.3.0-rc6-omamobile-push1-00145-ga868e7333752` with the bring-up overlays (bt-cmu-test, bt-uart-test, haptics-i2c, haptics, torch-i2c, torch).

- **BT1.1:** `dout_apm_usi1_uart` 197 MHz from `pll_alv_div2_apm` (394 MHz). UART gates 0x180020ac/0x180020b0/0x18002100 read 0x00200000: bit 21 (the gate bit the driver uses) set, manual mode off, so the clocks run.
- **BT1.2:** UART loopback passes at 115200 and 3000000 baud.
- **BT1.3:** HCI_Reset answered; HCI 10 / LMP 10 (Bluetooth 5.2), LMP subversion 0x6209, Broadcom chip id 170.
- **H1:** CS40L26 ID 0x40a260, revision 0xa1. The first I2C read NAKs while the chip wakes from hibernation; the second answers.
- **H2:** firmware 0x1800d4 rev 7.2.91 running, `cs40l26_vibra` input device. Two kernel fixes were needed:
  - i2c-exynos5 gave every message a fixed 100 ms, so the 20 KiB firmware block timed out ("tx timeout"); the timeout now scales with the message length.
  - cs_dsp's write sequence treated `cs_dsp_coeff_write_ctrl()` returning 1 ("changed") as an error.
- **H3:** buzzes at 300 ms / 40% and 600 ms / 70% felt by hand, no mailbox errors.
- **T1/T2:** LM3644TT (ID 0x04), 17 torch steps, 2550-49110 uA per channel; the camera EEPROM at 0x50 answers on the same bus.
- **T3:** brightness 1 and 9 for 2 s each, both seen, no fault flags.
- Shutdown hangs now end in a watchdog reset after a minute (`RebootWatchdogSec=1min`, omamobile-device-cheetah 0.1.6).

## 2026-10-12: everything working so far comes up at boot

Kernel omamobile-int `7.3.0-rc6-omamobile-push1-00171-g907128673cba` with the **default DTB, no test overlays**, and omamobile-device-cheetah 0.1.13. Two reboots in a row (a push, then `systemctl reboot`) gave the same result:

- **GPU:** Panthor bound with frequency scaling through ACPM (A1-A5): 151 MHz idle, capped at 572 MHz, Hyprland idle at 0% CPU.
  - ACPM A1 first failed with "Channel 3 queues outside the SRAM": a type-2 buffer channel in DRAM at 0xa8200080. The driver now skips unusable channels (14 of 15 usable; DVFS uses channel 0, PMIC 2, thermal 9).
  - A stale `/etc/modprobe.d/omamobile-acpm.conf` blacklist from A0 overrode the package's options and left the GPU unbound; remove it when moving from a bring-up stage to the package.
- **Wi-Fi:** omamobile-wifi.service (hang-safe marker), restricted DMA pool, no SysMMU (W4 decision, WIFI-BATTERY-PLAN 9.20/9.21). Autoconnects to the saved network; no "Invalid chanspec" warnings. One download measured 11 MB/s; the earlier ones were 19-21.
- **Bluetooth:** powered at boot with the bootloader's address. omamobile-bt-addr now powers the controller on before setting the address; set on a never-powered controller, the kernel withdrew the index for good.
- **Haptics and torch:** load at boot (DT default-on).
- **No failed units.**
- **On-screen keyboard:** stopped appearing once because `org.gnome.desktop.a11y.applications screen-keyboard-enabled` read false. Set back to true; what cleared it is not known yet.

## 2026-10-12: first sound, Bluetooth pairing, charging (BT3, B3.3)

- **Bluetooth pairing (BT3):** Pixel Buds Pro paired, trusted and connected from the shell's new Bluetooth panel (shell 0.1.11, `omamobile-bt-agent` as the BlueZ pairing agent).
- **First sound:** A2DP to the earbuds through PipeWire, a 440/660 Hz tone heard. The phone was missing PipeWire's BlueZ plugin (`pipewire-audio`) and `pipewire-pulse`; omamobile-shell 0.1.12 depends on them.
- **Charging (B3.3):** max77759-charger at 500 mA input, float voltage 4450 mV (stock fv-max), fast charge 1467 mA.
  - Over 10 minutes: 93 -> 96 % (the bootloader stops at 93 % with 4350 mV), 34.9 -> 35.2 °C (peak 35.5), and the gauge current fell from 1.02 to 0.62 A as it went into CV.
  - The gauge current is above what a 500 mA input allows. NO_AUTOIBUS is 0, so the chip's automatic input limit may have raised it on this laptop port (open question).
  - **Not default yet:** it needs the temperature guard (USB-C-PLAN B3) first. At boot the charger driver stays blacklisted and the bootloader's settings apply.
- Bug: `omamobile-bt-agent` doesn't exit when stdin reaches EOF, which hung a scripted `omamobile-bt-agent </dev/null`. The panel keeps stdin open, so this doesn't affect normal use.

## 2026-10-12: our own display driver at 120 Hz, by default (D4a, D5, D6)

- gs-decon (flip-only KMS on DECON0) replaces simpledrm at boot (about 4.4 s) and switches to 120 Hz at about 11 s. Hyprland runs 1440x3120@120 with a 60 Hz mode too. display-hz measured 120.01 Hz, DSIM UNDERRUN_CTRL 0x3ec, no underrun, flip_timeouts 0. Derek: scrolling is smoother, the boot animation shows with no black flash, and the brightness slider works.
- Fixes found on the way:
  - The display pool's `alignment` must be two cells (the root's #address-cells), or of_reserved_mem rejects it.
  - The DPP format for DRM XRGB8888 is code 4: Google's regs-dpp.h names formats by byte order. Code 7 gave a green screen.
- Mistake to avoid: our phone `devmem` is `devmem ADDR [VALUE]`, so `devmem ADDR 32` WRITES 0x20. It briefly clobbered DSIM 0x34/0x88; restored to 0x1f09/0x33eb3b26.
- Also today: GNSS G1/G2 passed (sub-PMIC rails read-only at stock voltages; the BCM4775x MCU answers over SPI5 with HSI status 0). The AoC loads through the GSA (command 90) and reaches "running" with RELEASE_RESET, but publishes no control block yet (AOC-PLAN).

## 2026-10-12: the AoC (audio and sensor DSP) boots under Linux; Trusty runs

On omamobile-int `7.3.0-rc6-omamobile-push1-00247-gc779a9f42a1d`, with the aoc-boot-test and fingerprint-trusty overlays:

- **Trusty** comes up from Linux: "trusty_ipc virtio0: is online", `/dev/trusty-ipc-dev0`. This is fingerprint gate F2 as well.
- **Load:** the GSA authenticates and loads Google's `aoc.bin` (mailbox command 90): state 1, loaded.
- **Start:** only works through Trusty's `com.android.trusty.gsa.hwmgr.aoc`. "AoC cmd 1 (Trusty): 2", then **"firmware up: 82 services"** 0.43 s later: control block magic 0xa0c00a0c, the same service count as stock.
  - The services include audio playback/capture/control, `com.google.usf` (sensors), `com.google.chre` and `sound_trigger`.
  - No SysMMU faults. The AoC rang doorbells: a32 mailbox INTSR1 0x401.
- **What didn't work:** mailbox command 91 START leaves the A32 held (GSA state 4). RELEASE_RESET (5) runs it, but the firmware stays silent.
- Also learned: reading the AoC PCU (0x19a00000) while the A32 is in reset aborts.
- **Next (AOC-PLAN):** an automatic start path, the AoC IPC core and character devices, a USF sensor client (auto-rotate), then aoc_alsa for the speakers and mics.

## 2026-10-12: GNSS runs Google's stack, NMEA flowing (G3d)

On omamobile-int `7.3.0-rc6-omamobile-push1-00253-g48b42df9b5c7` with the gnss-pmic-test and gnss-test overlays, plus the vendor-chroot gnss profile:

- **Daemons:** stock `servicemanager`, `lhd` and `gpsd` run in the vendor chroot.
- **Chip bring-up:** lhd powers the BCM4776 within about 1.5 s. Driver events show "nstandby <- 1", "power on", "ttyBCM opened by lhd", then the SensorHub.patch download (TX frames of 943-2834 bytes). lhd reports **ESW:READY**.
- **Traffic:** about 20k packets and 155 KB received, 0 TX failures.
- **NMEA:** gpsd answers `$pglirm,req_pos`. 3113 NMEA lines in 90 s indoors, RMC status V and 0 satellites (no fix indoors, as expected).
- **Shutdown:** the rails go off when lhd closes /dev/ttyBCM.
- **Fixes on the way:**
  - The runner used `env chroot` and had a recursive stop trap.
  - The bootstrap `linker64` was missing.
  - The SIT RIL client is stubbed (gpsd aborts without a modem).
  - lhd's absent-sensor-service lookups no longer storm.
  - The driver forced standby while lhd was starting the chip.
- **Next:** G4 outdoors for a fix, then GeoClue/gpsd for apps.
