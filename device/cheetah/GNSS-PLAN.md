<!-- SPDX-License-Identifier: MIT -->
# GNSS plan (cheetah / gs201): BCM4775x, stock lhd and gpsd, GeoClue

Status (2026-10-19): **works.** Google's GNSS stack runs in a chroot behind
GeoClue, on demand from the Location tile: NMEA flowing (G3d) and a first
outdoor fix (G4b, 2026-10-13: GPS and Galileo used, HDOP 0.4). GeoClue
serves clients (G5-2, partly); GNOME Maps' outdoor check with the GPS is
still to do. Results are in each stage's section.

Earlier status: **built offline, 2026-10-12. Nothing has run on the phone.** Kernel
branch `omamobile-gnss` in `~/android/mainline/wt-gnss`, build in
`~/android/mainline/out-gnss` (release
`7.3.0-rc6-omamobile-push1-00209-gec375b274d61`, logs `logs/kernel-gnss.log`,
`logs/kernel-gnss2.log`). Everything new is disabled by default: the
S2MPG13 node, USI5/SPI5 and (for NFC) the HSI1 pin controller and the NFC
node are only turned on by the overlays below. RADIOS-CAMERA-PLAN.md
section 2 has the hardware survey this builds on.

Later status: G0-G3d passed on the phone; the package (G5) is installed.
omamobile-gnss 0.2.0 (section 7, offline): constellations, assistance
(LTO timer, SUPL opt-in), time/position injection, graceful stop; its
outdoor test is G4b in 7.6.

Path abbreviations:

- `L/` = our kernel, branch `omamobile-gnss` (`~/android/mainline/wt-gnss`)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel)
- `R/` = `~/android/reference/cheetah-stock-cp2a-root` (stock live DT, logs)
- `X/` = `~/android/vendor-chroot-work/gnss` (the extract tool's output from the user's factory image; never committed)

---

## 1. Shape

```
lhd, gpsd (Broadcom, stock, unmodified)          GeoClue  gpsd (Linux)
   | /dev/ttyBCM, /dev/bbd_*, nstandby               ^        ^
   |   (vendor chroot, profile gnss)                 | sock   | pty
   v                                       omamobile-gnss-nmea
bcm4775x-gnss (kernel, SPI5)  ----NMEA FIFO----^ (/data/vendor/gps/nmea_out)
   | supplies: S2MPG13 LDO9S/10S/11S over ACPM (sec-acpm + s2mps11)
BCM4775x
```

## 2. Kernel (`omamobile-gnss`)

Based on `omamobile-int` @ `741b6ed1d`, with two merges first:
`omamobile-hsi1` (`f7a9852f1`, HSI1 pinctrl; the conflict with the HSI2
pinctrl in the aliases and `gs201-pinctrl.dtsi` is resolved here) and the
S2MPG12 commits of `omamobile-suspend` up to `93555da2a` (the S2MPG13 code
sits next to S2MPG12's in `sec-acpm.c`).

| Commit | What |
|---|---|
| `4a2cadde4` dt-bindings: firmware: google,gs101-acpm-ipc: allow the gs201 sub-PMIC | `pmic-2` = `samsung,s2mpg13-pmic` on gs201 |
| `7ef20d70e` dt-bindings: mfd: add Samsung S2MPG13 PMIC | MFD + regulator bindings (28 LDOs) |
| `3510a9c19` mfd: sec: add S2MPG13 | ACPM bus 1; common block read-only; PM block writable **only** in the LDO control registers 0x2c-0x49; INT1-4 never read; no IRQ (optional now), no meter |
| `c3937a59e` regulator: s2mps11: add S2MPG13 LDOs | from Google's `s2mpg13-regulator.c`; rails without a DT node get no constraints, so the core never switches them |
| `85664485f` dt-bindings: gnss: add Broadcom BCM4775x on SPI | `brcm,bcm4775-gnss` |
| `eb04c6c3c` misc: add a Broadcom BCM4775x GNSS driver for lhd | `L/drivers/misc/bcm4775x/`, module `bcm4775x-gnss` |
| `cad9624c0` dt-bindings: net: nfc: st,st-nci: add ST54J | `st,st54j-i2c` with `st,st21nfcc-i2c` fallback |
| `cb0505cc1` arm64: dts: exynos: google: gs201: add USI5 with its SPI | `usi5`/`spi_5` (SPI 678), pin groups; disabled |
| `bb576befa` ... gs201-cheetah: describe the GNSS receiver | `pmic-2` with LDO9S-11S (stock ranges, disabled), `gnss@0` on `spi_5` |
| `ec375b274` ... gs201-cheetah: describe the NFC controller | `nfc@8` on `hsi2c_8`, reset gph1-5; disabled |

Checks: full build exits 0; the changed C files build with `W=1` and no
warnings; `dt-doc-validate` of the five bindings passes; `dt-validate`
(dtschema 2026.9, schema from this tree) of the default DTB and of the DTB
with `gnss-pmic-test` + `gnss-test` + `nfc-test` applied reports only the
existing `soc_id` and simplefb items. `git merge-tree` against
`omamobile-int` @ `6def5bac7`: clean.

**Merge order for int:** `omamobile-gnss` alone. It carries `omamobile-hsi1`
and the S2MPG12 commits of `omamobile-suspend` (up to `93555da2a`), so
merge it before (or instead of) `omamobile-hsi1`; a later
`omamobile-suspend` merge only adds what came after `93555da2a`. Merging
`omamobile-hsi1` into int separately first gives the same aliases conflict
the branch already resolves (rerere has it): keep `pinctrl6` and `pinctrl7`,
and both `&pinctrl_hsi1` and `&pinctrl_hsi2` blocks.

### 2.1 The driver, against Google's

`bcm_gps_spi.c`, `bcm_gps_regs.c`, `bbd.c` from
`G/google-modules/gps/broadcom/bcm47765/`, same SSI framing, flow control
(PZC) and MCU wake handshake, same device nodes (`/dev/ttyBCM`,
`/dev/bbd_{sensor,control,patch,pwrstat}`, `nstandby` and `sspmcureq`
attributes). Changes:

- **Supplies on only while `/dev/ttyBCM` is open** (lhd running), chip back
  in standby and rails off on close. Stock keeps the rails always on.
  `nstandby` cannot be raised while the rails are off (`-EPERM`).
- **8-bit SPI words.** Google's switches to 32-bit words above 64 bytes,
  which relies on its controller's byte swap (`swap-mode`).
- The read command byte stays **0x70** as on stock: Google's
  `SSI_MODE == SSI_MODE_FULL_DUPLEX` test (1 vs 0x40) picks
  `SSI_READ_TRANS`, and the chip expects what stock sends.
- host_req is re-armed after resume only while `/dev/ttyBCM` is open.
- bbd: control strings matched with `strstr()` on a terminated copy
  (Google's `strcmp()` chain was inverted, so every string fell into the
  first branch and did nothing); the whole chrdev region freed; no sensor
  hub, coredump or 1 Hz statistics code. The 1 Hz timer that would wake an
  idle phone is compiled out in Google's build as well (`bbd.h:62`
  `//#define DEBUG_1HZ_STAT`), so RADIOS-CAMERA-PLAN.md 2.2 overstated it.
- debugfs `/sys/kernel/debug/spi5.0/`: `pins` (line levels, counters) and
  `probe` (G2 below).

### 2.2 Regulators: what was needed

Nothing could switch the GNSS rails before this branch: there is no S2MPG13
driver anywhere in our trees (the AoC work has a raw-ACPM bring-up module
for its own rails). This branch adds S2MPG13 to `sec-acpm` and `s2mps11`
the upstream way, deliberately narrow:

- writes reach only LDO control registers (regmap `wr_table`);
- at G1 only LDO9S-11S were in the DT (LDO12S, camera I/O, and LDO15S, the
  fingerprint sensor, came later with their own consumers), at stock's ranges (0.725-1.3 V,
  1.6-1.95 V, 1.6-1.95 V), so registering them writes nothing;
- the other 25 LDOs exist without constraints and are never touched;
- no interrupt (stock: gpa0-1), no meter, no bucks.

**One write to know about:** the regulator core turns off unused rails that
have constraints about 30 s after late init. LDO9S-11S are GNSS-only
(`L9S_GNSS_CORE`, `L10S_GNSS_RF`, `L11S_GNSS_AUX`, `R/live.dts:14072-14104`
and the ODPM rail names), so that is harmless. G1 avoids it anyway by
loading `sec_acpm` after the 30 s.

**Since #227 (2026-11-01) `sec_acpm` is built in** (`CONFIG_MFD_SEC_ACPM=y`
in the shared fragment, for the Pixel 9a's USB PHY), so on a kernel built
from it the S2MPG13 registers at boot, before the 30 s cleanup, as above
harmlessly. The G1 blacklist (`omamobile-g1.conf`) then does nothing, the
start script's `modprobe sec_acpm` succeeds without loading anything, and
`omamobile-gnss status` always finds the `vdd_gnss_core` regulator: "chip
powered" still reads the rail's state, but "not loaded yet" no longer
occurs. The 7 Pro boot of #227's config passed phone-smoke.

## 3. Userspace (omamobile repo)

All of it is the `packages/omamobile-gnss` package (default-off; it moved
there from `vendor-chroot/`). Google's files are not in it.

| Path (in `packages/omamobile-gnss/`) | What |
|---|---|
| `lib/omamobile-vendor-chroot` | shared runner, `PROFILE check / start / ns / run`; grown from `fingerprint/omamobile-fp-chroot` (same tmpfs chroot, property store, shim, binderfs, supervision); profiles hold what differs |
| `profiles/gnss.conf` | binds `/dev/ttyBCM`, `/dev/bbd_*` and the `nstandby` attribute; writes lhd.conf/gps.xml from the image with the nstandby path, `/data` logs, logcat logging, `PpsEnable=false`, and the settings of section 7; refreshes the LTO file on the host; resolves `HOSTS` into the chroot's hosts file; runs `lhd`, then `gpsd`; injects time (and an optional position), then asks for positions over the control pipe; `profile_stop` ends the request before the stop signal |
| `lib/omamobile-gnss-conf` | reads `/etc/omamobile/gnss.conf` (validated keys only, never executed) |
| `lib/omamobile-gnss-lto`, `omamobile-gnss-lto.{service,timer}` | the orbit predictions download (section 7.2) |
| `etc/omamobile/gnss.conf` | the user's settings: `ASSISTANCE`, `INJECT_TIME`, `REF_POSITION`, `SUPL` (section 7.5) |
| `gnss/props.conf` | `ro.hardware` and the DNS properties |
| `bionic/` | `Makefile` and sources for the shim (from `fingerprint/shim`) and two stubs (`libcom.android.tethering.connectivity_native.so` for `libandroid_net`, `libomamobile-sitril-gps.so` preloaded in place of the SIT RIL). Built on the computer into `bionic/prebuilt/`, which is not committed |
| `lib/omamobile-gnss-start` | hang-safe start (marker file, as `omamobile-wifi-start`), `modprobe sec_acpm bcm4775x-gnss`, then the runner |
| `lib/omamobile-gnss-nmea` | reads the FIFO, serves checksummed sentences on `/run/omamobile-gnss/nmea.sock` (GeoClue; the socket comes from systemd) and a pty at `/run/omamobile-gnss/nmea-tty` (Linux gpsd); `--idle-exit 60` |
| `vendor/systemd/system/` | `omamobile-gnss-nmea.socket` (the Location switch), `omamobile-gnss-nmea.service` (BindsTo the stack), `omamobile-gnss.service` (StopWhenUnneeded), `omamobile-gnss-force.service`, `omamobile-gnss-location@.service` |
| `bin/omamobile-gnss` | `on`, `off`, `force`, `unforce`, `status [--json]` |
| `polkit/50-omamobile-gnss.rules` | the active local user may start `omamobile-gnss-location@{on,off,force,unforce}.service`, nothing else |
| `etc/geoclue/conf.d/90-omamobile-gnss.conf` | `[network-nmea] nmea-socket=/run/omamobile-gnss/nmea.sock`; Firefox, Chromium, GNOME Maps/Weather and `where-am-i` allowed as system apps (Omarchy has no GeoClue agent) |
| `vendor/modprobe.d/omamobile-gnss.conf` | `blacklist bcm4775x_gnss` (loaded only by the start script) |

Elsewhere in the repo:

| Path | What |
|---|---|
| `tools/extract-vendor-chroot` | `-p gnss`: lhd, gpsd, SensorHub.patch, configs, servicemanager, CA store and the library closure, from the user's factory image |
| `tools/gnss-capture` | on the phone: records NMEA from the socket with timestamps; `summary` gives TTFF, satellites per constellation, HDOP and fix scatter, never coordinates (G4b) |
| `device/cheetah/overlays/gnss-pmic-test.dtso`, `gnss-test.dtso` | G1, G2 |

Offline results: `tools/extract-vendor-chroot -p gnss` on
`image-cheetah-cp2a.260705.006.zip` gives 264 files, 28 MB (`X/`), closure
complete with the one stub. `make -C packages/omamobile-gnss/bionic CLANG=... BIONIC=...
CHROOT=X/root` builds both `.so` files. The generated lhd.conf/gps.xml were
diffed against stock: only the four intended changes.

**For apps:** Firefox and GNOME apps use GeoClue. GeoClue only answers apps
an agent authorizes, or ones listed with `system=true` in its config; on
Omarchy there is no agent. The package's GeoClue config lists Firefox,
Chromium, GNOME Maps, GNOME Weather and `where-am-i` as system apps; the
Location switch (`omamobile-gnss on|off`) is the user's control. A real
agent (per-app prompts) is section 6, question 4.

## 4. Runbook (staged, read-only first)

Phone in Arch over USB, from the omamobile repo. The main session merges
`omamobile-gnss` into int and builds; `ov` is the overlay helper from
AUDIO-PLAN.md (rebuild the DTB from default + overlays, then images).

### G0: pin states (read-only, current kernel)

As RADIOS-CAMERA-PLAN.md 2.6:

```sh
tools/phone-ssh 'P=/sys/kernel/debug/pinctrl; grep -hE "\((gph2-[0-5])\)" $P/*14440000*/pins;
  grep -hE "\((gpp4-3|gpp10-[0-3]|gpp15-1)\)" $P/*10840000*/pins; grep -hE "\((gpa6-4)\)" $P/*180e0000*/pins'
```

Record: gph2-3 (nstandby) and gpp4-3 (mcu_req) as ABL left them; expect
output-low or input.

**G0 result (2026-10-12, kernel `...-00214-g6def5bac7547`): passed.**

| Pin | Role | CON | DAT | PUD | Note |
|---|---|---|---|---|---|
| gph2-0 | Wi-Fi PERST# | 0x1 | 1 | 0 | ours (Wi-Fi up) |
| gph2-1 | Wi-Fi CLKREQ# | 0x2 | 0 | 3 | ours |
| gph2-2 | GNSS mcu_resp | 0 | 0 | 1 | input, pull-down (= stock pin group) |
| gph2-3 | GNSS nstandby | 0 | 0 | 1 | input, pull-down: chip held in standby |
| gph2-4 | WL_REG_ON | 0x1 | 1 | 0 | ours |
| gph2-5 | Wi-Fi dev-wake | 0 | 0 | 1 | ours |
| gpp4-3 | GNSS mcu_req | 0 | 0 | 1 | input, pull-down |
| gpp10-0..3 | SPI5 SCLK/MOSI/MISO/CS | 0 | 0 | 1 | inputs: ABL never sets up USI5/SPI5 |
| gpp15-1 | GNSS PPS | 0 | 0 | 1 | input |
| gpa6-4 | GNSS host_req | 0 | 0 | 1 | input, pull-down (not yet EINT) |

PERIC0 power-down states: CON_PDN 2, PUD_PDN 1 on the PERIC0 pins.

What this means for G1/G2:
- The GNSS chip is idle and in standby, and nothing else uses its pins.
- ABL leaves SPI5 entirely unconfigured, so the USI5 mode, clock and pins
  all come from our DT. If the G2 probe reads all 0xff with
  `mcu_resp: answered`, check the USI5 mode and the PERIC0 USI5 clock
  first.
- gph2-3 and gpp4-3 are inputs with pull-down. The driver drives them low
  as outputs at probe, which keeps the same level.
- Our host_req group takes away the pull-down (stock: none) once it
  becomes the EINT.
- int merged `omamobile-gnss` at `7af02fa41`; G1 and G2 run on the next
  push.

### G1: the sub-PMIC, read-only (int + `gnss-pmic-test`)

```sh
# 0. modules installed with the int kernel; keep sec_acpm from autoloading
#    so it registers after the regulator core's 30 s cleanup
tools/phone-ssh 'echo "blacklist sec_acpm" > /etc/modprobe.d/omamobile-g1.conf'
ov gnss-pmic-test && bin/omamobile push                        # reboots
# 1. after 60 s uptime
tools/phone-ssh 'cut -d. -f1 /proc/uptime; modprobe sec_acpm; sleep 2; dmesg | grep -iE "s2mpg13|sec-acpm|pmic-2" | tail'
#   pass: the pmic-2 device probed, no errors; three regulators registered
tools/phone-ssh 'for r in /sys/class/regulator/regulator.*; do n=$(cat $r/name); case $n in vdd_gnss*) echo "$n $(cat $r/state) $(cat $r/microvolts 2>/dev/null)";; esac; done'
#   record: on/off and voltage of each GNSS rail as ABL left them (open question 1)
tools/phone-ssh 'grep -E "^(34|35|36):" /sys/kernel/debug/regmap/*pmic-2*pmic*/registers; grep "^0b:" /sys/kernel/debug/regmap/*pmic-2*common*/registers'
#   raw L9S/L10S/L11S_CTRL (bit 7 enable, bits 5:0 selector) and CHIPID
# rollback: images without the overlay; rm /etc/modprobe.d/omamobile-g1.conf
```

The only ACPM traffic is reads on PMIC bus 1. If any read hangs the phone,
stop: the bus number or the access type is wrong (`sec-acpm.c`,
`speedy_channel = 1`, `G/.../mfd/s2mpg13-core.c:57`).

### G2: driver and link (int + `gnss-pmic-test` + `gnss-test`)

```sh
tools/phone-ssh 'install -m644 /dev/stdin /etc/modprobe.d/omamobile-gnss.conf' < packages/omamobile-gnss/vendor/modprobe.d/omamobile-gnss.conf
ov gnss-pmic-test gnss-test && bin/omamobile push              # reboots
tools/phone-ssh 'modprobe sec_acpm; modprobe bcm4775x-gnss; dmesg | grep -iE "bcm4775|spi5|10940000" | tail -5;
  ls -l /dev/ttyBCM /dev/bbd_*; cat /sys/kernel/debug/spi5.0/pins; grep ttyBCM /proc/interrupts'
#   pass: "BCM4775x GNSS on SPI, irq N; supplies off..."; five nodes; powered 0,
#   nstandby 0; the ttyBCM interrupt count 0 (it is armed only while open)
# first writes: rails on, nstandby high, MCU wake, two register reads, all off again
tools/phone-ssh 'cat /sys/kernel/debug/spi5.0/probe; cat /sys/kernel/debug/spi5.0/pins'
#   pass: "mcu_resp: answered", HSI_STATUS not 0xff, HSI_ERROR_STATUS 0x00; powered 0 after
#   "no answer": check G1's rail values and the gph2-2/3 pins (debugfs pinctrl pins);
#   all 0xff/0x00 with an answer: SPI mode or chip select (try spi-max-frequency 12 MHz)
# rollback: rmmod bcm4775x-gnss; images without the overlays
```

**G1 and G2 passed (2026-10-12, int `...-00238-g3393f8dee945`, DTB +
gnss-pmic-test + gnss-test + aoc-boot-test):**

- **G1** (`sec_acpm` loaded at 144 s):
  - All three rails are **off** from ABL, at stock voltages: `vdd_gnss_core`
    1.2 V, `vdd_gnss_rf` 1.8 V, `vdd_gnss_aux` 1.8 V.
  - Raw registers: L9S_CTRL 0x26 (selector 38 = 1.2 V, enable bit 7
    clear), L10S/L11S 0x2c (44 = 1.8 V), CHIPID 0x05.
  - This answers open question 1. The ACPM bus-1 reads work.
- **G2**:
  - The driver binds (`irq 119` on gpa6-4, count 0) and creates all five
    nodes.
  - `probe`: `mcu_resp: answered`, HSI_STATUS 0x00, HSI_ERROR_STATUS
    0x00, twice.
  - Afterwards the pins are back at 0 and all rails are disabled.
  - So the supplies, standby, the MCU wake handshake and the SSI debug
    frames on SPI5 all work.

### G3: lhd loads the patch

What's on the phone: the int kernel with both GNSS overlays, and
`/etc/modprobe.d/omamobile-g1.conf` (blacklists `sec_acpm`) and
`omamobile-gnss.conf` (blacklists `bcm4775x_gnss`). So after each boot
load both by hand, `sec_acpm` once uptime is past 60 s. Nothing else from
`packages/omamobile-gnss/` (then `vendor-chroot/`) is installed yet.

Laptop, from the omamobile repo:

```sh
# 1. shim + stub (already built in packages/omamobile-gnss/bionic/prebuilt; rebuilding is harmless)
make -C packages/omamobile-gnss/bionic CLANG=$HOME/android/omamobile/prebuilts/clang/host/linux-x86/clang-r596125/bin/clang \
  BIONIC=$HOME/android/omamobile/bionic/libc CHROOT=$HOME/android/vendor-chroot-work/gnss/root
# 2. the profile's Android tree (28 MB, the user's own image) and our pieces, root-owned
tar -C ~/android/vendor-chroot-work/gnss -cf - root MANIFEST SOURCE STUBS |
  tools/phone-ssh 'mkdir -p /usr/lib/omamobile-vendor/gnss && tar --no-same-owner -C /usr/lib/omamobile-vendor/gnss -xf -'
tar -C packages/omamobile-gnss -cf - profiles/gnss.conf -C lib omamobile-vendor-chroot |
  tools/phone-ssh 'tar --no-same-owner -C /usr/lib/omamobile-vendor -xf -'
tar -C packages/omamobile-gnss/bionic/prebuilt -cf - omamobile-fp-shim.so stubs |
  tools/phone-ssh 'tar --no-same-owner -C /usr/lib/omamobile-vendor -xf -'
tools/phone-ssh 'install -m644 /dev/stdin /usr/lib/omamobile-vendor/gnss/props.conf' < packages/omamobile-gnss/gnss/props.conf
tools/phone-ssh 'ls -l /usr/lib/omamobile-vendor /usr/lib/omamobile-vendor/stubs; cat /usr/lib/omamobile-vendor/gnss/SOURCE'
# 3. drivers (once uptime is past 60 s), then the preconditions check (reads only)
tools/phone-ssh 'cut -d. -f1 /proc/uptime; modprobe sec_acpm; modprobe bcm4775x-gnss;
  /usr/lib/omamobile-vendor/omamobile-vendor-chroot gnss check'
#   pass: "preconditions met"
# 4. lhd alone for 60 s: the chip is powered only while lhd holds /dev/ttyBCM open
tools/phone-ssh '(OMAMOBILE_GNSS_STAGE=lhd OMAMOBILE_VENDOR_LOGLEVEL=3 timeout 60 \
    /usr/lib/omamobile-vendor/omamobile-vendor-chroot gnss start > /tmp/g3.log 2>&1 &);
  sleep 25; echo "== during"; cat /sys/kernel/debug/spi5.0/pins;
  sleep 45; echo "== after"; cat /sys/kernel/debug/spi5.0/pins;
  for r in /sys/class/regulator/regulator.*; do case $(cat $r/name) in vdd_gnss*) echo $(cat $r/name) $(cat $r/state);; esac; done;
  echo "== log"; tail -n 80 /tmp/g3.log; dmesg | grep -iE "bcm4775|ttyBCM" | tail -5'
```

Pass:
- **During:** `powered: 1`, `nstandby: 1`, `packets` rising, `tx_fail: 0`.
- **Log:** lhd opens the nodes and downloads `SensorHub.patch` without
  errors, and keeps running.
- **After:** `powered: 0`, `nstandby: 0`, all three `vdd_gnss_*` disabled.
  The timeout kills the namespace, lhd's `/dev/ttyBCM` closes, and the
  driver powers the chip down.

Failure clues:
- `nstandby` write errors (`EPERM`): lhd raised standby before opening
  `/dev/ttyBCM`. The driver only allows it while powered. Send the log;
  the fix is a driver change (power on at the nstandby write too).
- `servicemanager` or linker errors: `run`-test a binary inside, e.g.
  `omamobile-vendor-chroot gnss ns ls /dev`, and send the log.

**G3 result (2026-10-12, runner `9163788`):**
- servicemanager starts. lhd starts, reads our lhd.conf and logs only the
  expected errors.
- **lhd never opened `/dev/ttyBCM`:** the chip stayed in standby with its
  rails off, and the stop was clean.
- **What we thought (corrected under G3c):** that lhd waits for gpsd
  before touching the chip. In fact lhd starts the chip at start-up and
  failed within a second; the 25 s sample missed it.
- **`/sys/bbd/lk_enable`:** lhd's "killer" switch. Google's GPL bbd driver
  (the one stock runs) has no such attribute either, so stock lhd logs the
  same error. No stub is needed.
- **gpsd starts a position session only when asked.** The profile now asks
  through gpsd's control pipe (`CtrlPipe`, `/data/vendor/gps/glgpsctrl`)
  with `$pglirm,req_pos,omamobile,period,1000`. The command format and its
  `$pglirm,stop,...` counterpart are strings in gpsd. The NMEA of that
  request goes to the `NmeaOutName` FIFO.
- gpsd runs as a plain daemon by default now (`OMAMOBILE_GNSS_JOB` empty).

### G3b: lhd + gpsd together, 90 s, indoors

Reinstall the profile (`packages/omamobile-gnss/profiles/gnss.conf`); the tree and
the runner are unchanged. Keep a reader on the NMEA FIFO, so gpsd never
blocks opening it.

```sh
tools/phone-ssh 'install -m644 /dev/stdin /usr/lib/omamobile-vendor/profiles/gnss.conf' < packages/omamobile-gnss/profiles/gnss.conf
tools/phone-ssh 'F=/var/lib/omamobile-vendor/gnss/data/vendor/gps/nmea_out; mkdir -p $(dirname $F); [ -p $F ] || mkfifo -m 600 $F;
  /usr/lib/omamobile-vendor/omamobile-vendor-chroot gnss check;
  (timeout 100 cat $F > /tmp/g3b-nmea.txt &);
  (OMAMOBILE_VENDOR_LOGLEVEL=2 timeout 90 /usr/lib/omamobile-vendor/omamobile-vendor-chroot gnss start > /tmp/g3b.log 2>&1 &);
  sleep 30; echo "== during"; cat /sys/kernel/debug/spi5.0/pins;
  sleep 70; echo "== after"; cat /sys/kernel/debug/spi5.0/pins;
  for r in /sys/class/regulator/regulator.*; do case $(cat $r/name) in vdd_gnss*) echo $(cat $r/name) $(cat $r/state);; esac; done;
  pgrep -a "lhd|gpsd" || echo "none left"; ls -l /var/lib/omamobile-vendor/gnss/data/vendor/gps/;
  echo "== nmea"; wc -l /tmp/g3b-nmea.txt; grep -E "GSV|RMC|GGA" /tmp/g3b-nmea.txt | tail -8;
  echo "== log"; grep -E "omamobile-vendor|\[gpsd\].* [EFW] |ESW|Broadcom" /tmp/g3b.log | head -40; tail -n 40 /tmp/g3b.log'
```

Pass:
- **During:** `powered 1`, `nstandby 1`, packets rising, `tx_fail 0`.
- **Log:** "control pipe: req_pos"; gpsd identifies the chip as a Broadcom
  BCM477x (expect "BCM4776"); no gpsd exit.
- **NMEA:** GSV sentences. Indoors there may be few or no satellites; RMC
  with status V is fine here.
- **After:** one "stopping", no lhd or gpsd left, `powered 0`, all three
  rails disabled.

If it fails:
- "a service exited" early: send `/tmp/g3b.log` (gpsd failing on binder,
  the RIL client library or the sensor service).
- "no control pipe ... after 60 s": gpsd never created `glgpsctrl`. Send
  the `ls -l` of the gps directory.
- No NMEA but lhd powered the chip: send both files.

**G3c result (2026-10-12, profile `7c281bf`):**
- The RIL stub worked (no SIT RIL failure); one sensor lookup.
- gpsd took the control-pipe request, lhd spent 220 ms on it, then gpsd
  logged `OnChipReset: GPSD exit`.
- The pins showed powered 0 at 30 s and after; no NMEA.

**Why, found offline (lhd verbose, under qemu, `LogLevel=*:V` with
`LogEnabled=true`, `Log=LOGCAT`):** lhd starts the chip on its own at
start-up. G3's "lhd waits for gpsd" was wrong; the pin sampling just
missed it. Its sequence (`BrcmGpsHalGpio::Standby/Normal`, then
`Bbd::Open`):
1. nstandby 0, then 1;
2. 20 ms ("Power enable delay");
3. open `/dev/bbd_control` and `/dev/ttyBCM`;
4. `BBD:PassThru=1`, auto-baud, patch download.

Our driver broke that order in two ways:
1. Writing nstandby=1 while `/dev/ttyBCM` was closed failed with `EPERM`
   (supplies followed the open).
2. Opening `/dev/ttyBCM` then powered the supplies and **forced nstandby
   low**.

So the chip sat in standby while lhd tried to sync with its ROM. lhd then
declares the chip crashed and resets it (`ESW:CRASHED`, gpsd
`OnChipReset`).

**Fix, kernel `omamobile-gnss` @ `7f4083e7c`:** raising nstandby now
powers the supplies itself, and drops them when nstandby falls with nobody
holding the device. The open finds the chip powered and leaves nstandby
alone. The same commit adds bring-up logging (module parameter `events`, on
by default):
- `/dev/ttyBCM` open/close and by whom;
- power on/off;
- every nstandby write with the state it found;
- wake handshake failures, rate limited;
- host requests with empty frames;
- the first 16 SSI frames of each session.

`ssi_dump=1` hex-dumps transfers from the next open. The profile now
makes lhd log verbosely (`OMAMOBILE_GNSS_LHD_LOG`, default `*:V`).

What else was checked:
- **Word size:** 8-bit vs Google's 32-bit DMA words gives the same bytes
  on the wire; Google's controller swaps bytes for 32-bit words, so its
  byte stream is the same.
- **Read command byte:** 0x70 is what stock sends.
- **host_req interrupt:** delivered as on stock (level, re-armed by the
  worker).
- **Handshake:** none of these explain a failure in the first 220 ms;
  standby does.

### G3d: lhd + gpsd with kernel events and a 200 ms pin sampler

Needs the new module: merge `omamobile-gnss` (`7f4083e7c`) into int,
build, then `bin/omamobile modules && bin/omamobile modules-push`. No
reboot is needed, since only the module changed. Reinstall the profile.

```sh
tools/phone-ssh 'install -m644 /dev/stdin /usr/lib/omamobile-vendor/profiles/gnss.conf' < packages/omamobile-gnss/profiles/gnss.conf
tools/phone-ssh 'rmmod bcm4775x_gnss 2>/dev/null; modprobe bcm4775x-gnss; cat /sys/module/bcm4775x_gnss/parameters/events'
#   expect Y
tools/phone-ssh 'P=/sys/kernel/debug/spi5.0/pins; F=/var/lib/omamobile-vendor/gnss/data/vendor/gps/nmea_out;
  mkdir -p $(dirname $F); [ -p $F ] || mkfifo -m 600 $F;
  /usr/lib/omamobile-vendor/omamobile-vendor-chroot gnss check; dmesg -C;
  (timeout 100 cat $F > /tmp/g3d-nmea.txt &);
  (OMAMOBILE_VENDOR_LOGLEVEL=2 timeout 90 /usr/lib/omamobile-vendor/omamobile-vendor-chroot gnss start > /tmp/g3d.log 2>&1 &);
  # 200 ms samples for the first 15 s (lhd starts the chip within a second or two), then every 5 s
  for i in $(seq 75); do printf "%s %s\n" "$(date +%s.%N | cut -c1-14)" "$(grep -E "^(powered|nstandby|packets|tx_fail)" $P | tr "\n" " ")"; sleep 0.2; done > /tmp/g3d-pins.txt;
  for i in $(seq 16); do printf "%s %s\n" "$(date +%s.%N | cut -c1-14)" "$(grep -E "^(powered|nstandby|packets|tx_fail)" $P | tr "\n" " ")"; sleep 5; done >> /tmp/g3d-pins.txt;
  echo "== pins (changes only)"; awk "{k=\$0; sub(/^[^ ]* /,\"\",k)} k!=last {print; last=k}" /tmp/g3d-pins.txt;
  for r in /sys/class/regulator/regulator.*; do case $(cat $r/name) in vdd_gnss*) echo $(cat $r/name) $(cat $r/state);; esac; done;
  pgrep -a "lhd|gpsd" || echo "none left";
  echo "== kernel"; dmesg | grep -iE "bcm4775|spi5|ttyBCM" | head -60;
  echo "== nmea"; wc -l /tmp/g3d-nmea.txt; grep -E "GSV|RMC|GGA" /tmp/g3d-nmea.txt | tail -8;
  echo "== lhd"; grep -E "\[lhd\]" /tmp/g3d.log | grep -vE "SetCfgValue|^\[lhd\] $" | head -120;
  echo "== rest"; grep -E "omamobile-vendor|OnChipReset|ESW|CRASH|terminat" /tmp/g3d.log | head -20'
```

Pass:
- **Kernel:** "nstandby <- 0", "nstandby <- 1 … unpowered" followed by
  "power on", "ttyBCM opened by lhd", then rx/tx frames with non-zero
  sizes.
- **Pins:** `powered 1`, `nstandby 1` while lhd runs; packets rising,
  `tx_fail 0`.
- **lhd:** the patch download finishes (`ESW:READY`), with no
  `ROM SYNC failure` and no `ESW:CRASHED`.
- **NMEA:** GSV sentences.
- **After:** one "stopping", nothing left, `powered 0`, rails disabled.

If it still fails, the kernel event lines plus lhd's verbose log show
which step: wake handshake, empty frames, or transfer errors.

### G4: a fix outdoors, unattended, rails off afterwards

Same set-up as G3b (after it passes), plus Wi-Fi in range if possible (orbit predictions and
SUPL; without them a cold start can take several minutes). Everything runs
under systemd with a hard time limit. When it ends, the namespace dies,
`/dev/ttyBCM` closes and the chip loses power, whether the run worked or
not. The phone can be unplugged and carried outside.

```sh
# before going out (USB still connected): drivers loaded as in G3 step 3, then
tools/phone-ssh 'F=/var/lib/omamobile-vendor/gnss/data/vendor/gps/nmea_out;
  mkdir -p $(dirname $F); [ -p $F ] || mkfifo -m 600 $F;
  systemd-run --unit=g4-nmea --property=RuntimeMaxSec=1000 sh -c "cat $F > /var/tmp/g4-nmea.txt";
  systemd-run --unit=g4-gnss --property=RuntimeMaxSec=900 \
    /usr/lib/omamobile-vendor/omamobile-vendor-chroot gnss start;
  sleep 20; systemctl --no-pager status g4-gnss | tail -5; cat /sys/kernel/debug/spi5.0/pins'
#   expect: g4-gnss active, powered 1. Unplug, put the phone outdoors with a clear
#   sky for 10-15 minutes, bring it back, reconnect.
tools/phone-ssh 'systemctl is-active g4-gnss g4-nmea; cat /sys/kernel/debug/spi5.0/pins;
  journalctl -u g4-gnss --no-pager | tail -60; wc -l /var/tmp/g4-nmea.txt;
  grep -E "GSV" /var/tmp/g4-nmea.txt | tail -5; grep -E "RMC" /var/tmp/g4-nmea.txt | grep ",A," | head -3'
#   pass: both units inactive (time limit), powered 0; GSV lines with satellites and
#   SNRs; RMC lines with status A (a fix).
#   empty file: no NMEA from the control-pipe request; repeat with
#   --setenv=OMAMOBILE_GNSS_JOB=omamobile (job mode) and send both journals.
# stop early at any time (rails go off the same way):
tools/phone-ssh 'systemctl stop g4-gnss g4-nmea; cat /sys/kernel/debug/spi5.0/pins'
```

### G4b: outdoors with assistance (LTO), multi-GNSS check

Superseded before it ran: the hand-installed runner is gone, and assistance,
injection and the outdoor test moved into the package (0.2.0). The runbook
is now section 7.6.

### G5: the package (Location on demand)

`packages/omamobile-gnss` replaces the hand-installed files. Nothing
starts until `omamobile-gnss on`; then GeoClue's NMEA source connecting to
`/run/omamobile-gnss/nmea.sock` starts the bridge, which pulls in the GNSS
stack. When the last client has been gone 60 s the bridge exits, the
stack stops (`StopWhenUnneeded`), `/dev/ttyBCM` closes and the rails go
off. `omamobile-gnss off` stops everything and removes the socket.

The shim and stubs are built on the laptop into `bionic/prebuilt/` (not
committed). The Android tree stays the user's own extract, as before.

```sh
# laptop: the bionic pieces, then the static checks
make -C packages/omamobile-gnss/bionic CLANG=$HOME/android/omamobile/prebuilts/clang/host/linux-x86/clang-r596125/bin/clang \
  BIONIC=$HOME/android/omamobile/bionic/libc CHROOT=$HOME/android/vendor-chroot-work/gnss/root
packages/omamobile-gnss/test/all
# phone: remove the hand-installed copies (pacman would refuse to overwrite them);
# the Android tree in /usr/lib/omamobile-vendor/gnss/{root,MANIFEST,SOURCE,STUBS} stays
tools/phone-ssh 'cd /usr/lib/omamobile-vendor && rm -f omamobile-vendor-chroot profiles/gnss.conf omamobile-fp-shim.so stubs/*.so gnss/props.conf;
  rm -f /etc/modprobe.d/omamobile-gnss.conf /etc/geoclue/conf.d/90-omamobile-gnss.conf;
  rm -f /etc/systemd/system/omamobile-gnss.service /etc/systemd/system/omamobile-gnss-nmea.service; systemctl daemon-reload'
tools/phone-install-package packages/omamobile-gnss      # or tools/repo-build packages/omamobile-gnss + repo-push
tools/phone-ssh 'pacman -S --needed --noconfirm geoclue; omamobile-gnss status'
#   expect: location off, receiver running no, chip powered no (sec_acpm/driver
#   loaded) or unknown (not loaded yet; the start script loads both)
```

`/etc/modprobe.d/omamobile-g1.conf` (blacklists `sec_acpm`) can stay; the
start script loads `sec_acpm` itself. Keep the 30 s rule in mind: don't
switch Location on in the first minute after boot.

```sh
# 1. on, nothing running yet
tools/phone-ssh 'omamobile-gnss on; omamobile-gnss status; ls -l /run/omamobile-gnss/'
#   expect: location on, receiver no, nmea.sock present
# 2. a GeoClue client starts it (indoors is fine for the plumbing)
tools/phone-ssh 'systemctl restart geoclue; (timeout 120 /usr/lib/geoclue-2.0/demos/where-am-i -a 8 -t 110 > /tmp/g5-wai.txt 2>&1 &);
  sleep 30; omamobile-gnss status; journalctl -u omamobile-gnss-nmea -u omamobile-gnss --no-pager -n 20'
#   expect: receiver yes, chip powered yes, "client connected (1)", "first NMEA sentence received"
# 3. idle exit: where-am-i ends at 120 s; 60 s later the stack stops
tools/phone-ssh 'sleep 150; omamobile-gnss status; cat /sys/kernel/debug/spi5.0/pins; cat /tmp/g5-wai.txt | tail -15;
  for r in /sys/class/regulator/regulator.*; do case $(cat $r/name) in vdd_gnss*) echo $(cat $r/name) $(cat $r/state);; esac; done'
#   pass: receiver no, powered 0, vdd_gnss_* disabled; where-am-i printed a location
#   if there was a fix (indoors it may only show Wi-Fi/IP sources or nothing)
# 4. the switch as the desktop user (polkit), then off
tools/phone-ssh 'su - "$(loginctl list-users --no-legend | awk "\$2 != \"root\" {print \$2; exit}")" -c "omamobile-gnss off; omamobile-gnss status --json; omamobile-gnss on; omamobile-gnss status --json"'
tools/phone-ssh 'omamobile-gnss force; sleep 30; omamobile-gnss status; omamobile-gnss unforce; sleep 80; omamobile-gnss status'
#   expect: force runs it with no client; after unforce it stops within ~65 s
tools/phone-ssh 'omamobile-gnss off; omamobile-gnss status'
# rollback: omamobile-gnss off; pacman -R omamobile-gnss
```

The `su` step: polkit allows only the active local session. Over ssh the
phone's user is not active, so the call may be refused there. If so,
try it in a terminal on the phone. Root over ssh skips polkit.

**Quick-settings tile (for the shell):**
- State: `omamobile-gnss status --json` gives
  `{"location":"on|off","running":"yes|no","forced":"yes|no","powered":"yes|no","agent":"on|off","installed":true|false}`.
- Toggle: run `omamobile-gnss on` or `omamobile-gnss off` as the user.
  This goes through `omamobile-gnss-location@.service` and polkit, with no
  password.
- Hide the tile when `installed` is false or the command is missing.
- The QML tile itself is left to the shell's owner.

**Boot:**
- `omamobile-gnss on` enables the socket (`sockets.target`), so it
  persists: after a reboot Location is still on, and nothing runs until
  GeoClue connects.
- The hang marker still protects the bring-up. A hang leaves
  `/var/lib/omamobile/gnss-bringup-started`, and later starts are skipped
  until `/usr/lib/omamobile-vendor/omamobile-gnss-start --retry`.

**G5 result (2026-10-12, int 00265, omamobile-gnss 0.1.0):**
- The package installed. `on` made the socket, and
  `/run/omamobile-gnss/nmea.sock` exists.
- `where-am-i` (as root) failed with "Failed to connect to GeoClue2
  service: Timeout was reached". GeoClue never connected to the socket.
  The driver was not loaded and no rails were touched.
- `status` printed "nono" (a bug).

**Cause (from GeoClue 2.8.2's source, Arch's version):**
- `GetClient` waits for an authorization agent registered for the
  caller's UID, with no timeout (`gclue-service-manager.c`,
  `clients_waiting_agent`, NEWS "Replace agent wait timeout with a
  queue"). With no agent, every client's first call times out after
  25 s.
- `allowed=true`/`system=true` entries skip only the agent's question,
  not the need for an agent.
- The rest of the setup was right:
  - `/etc/geoclue/conf.d/*.conf` is read on top of
    `/etc/geoclue/geoclue.conf`, and same-name app sections merge.
  - `nmea-socket=` connects directly to the Unix socket. Avahi is only
    linked (Arch's geoclue depends on it); avahi-daemon need not run.
  - `geoclue.service` (Type=dbus, User=geoclue, `/usr/lib/geoclue`) can
    be restarted, and D-Bus starts it again on the next call.
- A second mistake: the demo identifies itself as `geoclue-where-am-i`,
  not `where-am-i`.

**Fix (0.1.1):**
- `omamobile-geoclue-agent.service` (user unit) runs GeoClue's demo
  agent (`/usr/lib/geoclue-2.0/demos/agent`, desktop id
  `geoclue-demo-agent`, already in geoclue.conf's agent whitelist).
  - `omamobile-gnss on` enables it for every user
    (`systemctl --global`), and `off` disables it.
  - Run as the user (the tile), `on`/`off` also start/stop it in the
    current session.
- The package now depends on geoclue and libnotify (the agent's
  notifications for apps not in the list).
- The config section is now `[geoclue-where-am-i]`.
- `status` reads the GNSS rails from `/sys/class/regulator`, which is
  readable without root (no regulator means `sec_acpm` is not loaded,
  so "no"). It also shows the agent; JSON gains `"agent"`.

### G5-2

```sh
# laptop (the bionic prebuilt/ from G5 is still there; test/all checks it)
packages/omamobile-gnss/test/all && tools/phone-install-package packages/omamobile-gnss
tools/phone-ssh 'omamobile-gnss off; omamobile-gnss on; omamobile-gnss status; ls -l /etc/systemd/user/graphical-session.target.wants/;
  pgrep -a -f geoclue-2.0/demos/agent; systemctl restart geoclue'
#   expect: location on, receiver no, chip powered no, GeoClue agent on, the agent link;
#   pgrep may already show an agent if the session runs XDG autostart (geoclue's own
#   /etc/xdg/autostart entry); a second copy then just exits
# 1. as root, with an agent for root in a throwaway session bus (the demo agent is a
#    GApplication and needs a session bus; root over ssh has none)
tools/phone-ssh '(dbus-run-session -- sh -c "/usr/lib/geoclue-2.0/demos/agent & sleep 2;
    timeout 120 /usr/lib/geoclue-2.0/demos/where-am-i -a 8 -t 110; kill \$!" > /tmp/g5-wai.txt 2>&1 &);
  sleep 40; omamobile-gnss status; journalctl -u geoclue -u omamobile-gnss-nmea -u omamobile-gnss --no-pager -n 30 -o cat'
#   expect: receiver yes, chip powered yes; "listening on the socket systemd passed",
#   "client connected (1)", "first NMEA sentence received"; lhd/gpsd lines
# 2. idle exit: where-am-i ends at ~112 s, the bridge 60 s later, then the stack
tools/phone-ssh 'sleep 150; omamobile-gnss status; cat /tmp/g5-wai.txt | tail -20'
#   pass: receiver no, chip powered no. where-am-i shows a location only with a fix (or
#   from GeoClue's Wi-Fi/IP sources); indoors "no location" is fine here.
# 3. the desktop user's session: the agent there, the polkit switch, where-am-i as the user
tools/phone-ssh 'u=$(loginctl list-users --no-legend | awk "\$2 != \"root\" {print \$2; exit}"); id=$(id -u $u); e="XDG_RUNTIME_DIR=/run/user/$id DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$id/bus";
  su $u -c "env $e systemctl --user start omamobile-geoclue-agent; env $e systemctl --user --no-pager status omamobile-geoclue-agent | head -5";
  su $u -c "env $e omamobile-gnss off; omamobile-gnss status --json; env $e omamobile-gnss on; omamobile-gnss status --json";
  su $u -c "env $e timeout 60 /usr/lib/geoclue-2.0/demos/where-am-i -a 8 -t 50" > /tmp/g5-user.txt 2>&1;
  tail -5 /tmp/g5-user.txt; omamobile-gnss status'
#   expect: the agent active; off/on succeed (if polkit refuses over su, repeat those two
#   in a terminal on the phone); where-am-i connects (no timeout)
# 4. force/unforce, then leave it off
tools/phone-ssh 'omamobile-gnss force; sleep 30; omamobile-gnss status; omamobile-gnss unforce; sleep 80; omamobile-gnss status; omamobile-gnss off'
#   expect: running yes (forced), then no within ~65 s of unforce; powered no at the end
# rollback: omamobile-gnss off; pacman -R omamobile-gnss
```

If step 1 still times out, run GeoClue in the foreground with debug
output. Its config dump and the agent/NMEA steps then show where it stops:

```sh
tools/phone-ssh 'systemctl stop geoclue; (timeout 150 runuser -u geoclue -- env G_MESSAGES_DEBUG=all /usr/lib/geoclue > /tmp/geoclue-debug.txt 2>&1 &);
  sleep 2; (dbus-run-session -- sh -c "/usr/lib/geoclue-2.0/demos/agent & sleep 2;
    timeout 60 /usr/lib/geoclue-2.0/demos/where-am-i -a 8 -t 50; kill \$!" > /tmp/g5-wai.txt 2>&1 &);
  sleep 70; grep -iE "nmea|agent|socket|config|Network source|error|warn" /tmp/geoclue-debug.txt | head -60; tail -5 /tmp/g5-wai.txt'
```

Suspend: with lhd open the host_req line is a wake source; measure the
drain with GNSS running and idle (POWER-PLAN.md) before enabling at boot.

## 5. Risks

- **ACPM bus 1.** First traffic to the sub-PMIC from Linux. Reads only in
  G1; the regmap can't write anything but LDO control registers.
- **Rails.** Only GNSS-only rails are described, at stock's ranges.
- **gph2 is shared with Wi-Fi** (pins 0, 1, 4, 5); the GNSS node claims only
  2 and 3.
- **host_req has no pull** (stock); an interrupt storm would show in
  `/proc/interrupts` in G3.
- **Proprietary blobs** stay on the phone, from the user's image.

## 6. Open questions

1. ~~ABL's LDO9S-11S state~~: off, at stock voltages (G1).
2. Does gpsd's job mode produce NMEA on `nmea_out` (G4)? If not, the bridge
   must speak the HAL's control pipe.
3. ~~Does bionic's resolver work without netd?~~ No (qemu, checkpoint): the
   runner writes the few hosts gpsd needs into the chroot's hosts file.
4. GeoClue authorization on Omarchy: GeoClue needs an agent per user
   (G5). The package runs GeoClue's demo agent and lets a few apps through
   without asking; others get a notification, whose Allow/Deny actions
   depend on the notification daemon (mako: its action menu). An agent in
   the shell with proper prompts would replace it.
5. PPS: mainline `pps-gpio` on gpp15-1 for time sync, later.
6. Move the fingerprint profile onto the shared runner once it has run on
   the phone (it needs its RPMB, panel and Trusty hooks as profile functions).

## Checkpoint 2026-10-12

**Done (on the phone):**
- G0-G3d passed. lhd powers the chip in about 1.5 s, the patch loads
  (`ESW:READY`), there are no transfer errors, gpsd runs a session
  (control-pipe `req_pos`), NMEA reaches the FIFO, and the rails go off
  cleanly at close.
- G4 (windowsill, unplugged, about 8 min): 17834 NMEA lines, at most 2 GPS
  satellites in view, RMC always V, no fix. Only GP talkers.

**Done (offline, not yet run on the phone):**
- Runner + gnss profile: the chroot gets a hosts file, and HOSTS are
  resolved on the host at start (`gllto2.glpals.com`, `gllto.glpals.com`,
  `supl.google.com`).
  - bionic can't resolve names without netd. This was tested under qemu:
    `getaddrinfo` fails in both resolver modes, and works with
    `/system/etc/hosts`.
  - The LTO file is reachable over plain HTTP from the laptop: 121603
    bytes from `http://gllto2.glpals.com/4day/v5/latest/lto2.dat`.
- gps.xml facts for multi-GNSS:
  - `<hal>` rejects unknown keys and asserts (`EnableGlonass` there kills
    gpsd);
  - `<gll>` silently ignores unknown keys, so a key placed there proves
    nothing;
  - gpsd knows `EnableGlonass`, `EnableGalileo`, `EnableBeidou` and
    `EnableNmeaV411`, but which section they belong to is not known yet.
  - Nothing is changed for constellations yet. The GP-only output may
    simply be the poor sky view: GSV lists tracked satellites only on a
    cold start without assistance.

**Half done:**
- **G5 design** (not written):
  - a systemd socket unit for `/run/omamobile-gnss/nmea.sock`;
  - the bridge started by GeoClue connecting, exiting after an idle period
    with no clients;
  - `omamobile-gnss.service` with `StopWhenUnneeded=yes`, so the stack and
    the rails run only while GeoClue has a client;
  - an `omamobile-gnss on|off|status` command;
  - a new `packages/omamobile-gnss` package, default-off, with the small
    bionic `.so` files (shim, stubs) prebuilt from `packages/omamobile-gnss/bionic/Makefile`.
- **Multi-GNSS:** find the section for the Enable* keys, e.g. by trying
  each one in `<gll_features>` under qemu and watching gpsd's parser.

**Next steps:**
1. On the phone: reinstall the runner and profile (commit `2873e27`, commands below) and
   repeat G4 with Wi-Fi in range. Expect assistance downloads in gpsd's
   log (LTO/SUPL) and a faster fix.
2. Compare talker IDs with a clear sky view before changing constellation
   settings.
3. G5 as designed above.

**Ready to run on the phone** (after `git pull`; the tree, shim and stubs
are unchanged):

```sh
tools/phone-ssh 'install -m755 /dev/stdin /usr/lib/omamobile-vendor/omamobile-vendor-chroot' < packages/omamobile-gnss/lib/omamobile-vendor-chroot
tools/phone-ssh 'install -m644 /dev/stdin /usr/lib/omamobile-vendor/profiles/gnss.conf' < packages/omamobile-gnss/profiles/gnss.conf
# then the G3d command (section 4); check that the log has no "cannot resolve" lines and
# look for LTO/SUPL activity in the gpsd lines, then G4 as before (with Wi-Fi in range)
```

After any unplug/replug, reboot or use the USB rescue watcher (USB-C-PLAN
R1).

## Update 2026-10-12, after the checkpoint (offline)

- **Assistance in G3d:** the G3d log has no gpsd lines at all. gpsd's own
  log was off (stock `LogEnabled="false"`, `Log="JAVA"`), so it can't show
  whether LTO/SUPL were tried. There were no "cannot resolve" lines.
  - Since `cf392de`, gpsd logs to logcat (journal), and the profile fetches
    `lto2.dat` on the host before gpsd starts.
  - G4b checks both.
- **Multi-GNSS:** stock's gps.xml sets no constellation keys, so the
  engine runs on its built-in defaults. Those are what stock ships, and
  nothing is changed.
  - GP-only NMEA may be how gpsd's NMEA output reports satellites. On
    Android the framework's satellite list comes from the HAL callbacks,
    not from this NMEA.
  - `OMAMOBILE_GNSS_NMEA411=1` is an optional G4b run (`EnableNmeaV411`
    in `<gll>`).
- **G5 package:** `packages/omamobile-gnss` (section 3), default-off.
  `vendor-chroot/` moved into it. The runbooks are G4b and G5 in
  section 4.

## 7. Fast first fix and power (omamobile-gnss 0.2.0, offline 2026-10-12)

Goal: the first outdoor fix as fast and reliable as the hardware allows,
with nothing privacy-relevant on by default, and the chip fully off when no
one asks for a position. Nothing in this section has run on the phone yet;
G4b (7.6) tests it. Sources: the stock `gps.xml` and `lhd.conf` from the
user's extract (`X/`) and static analysis of stock gpsd (its strings, its
symbol table from `.gnu_debugdata`, and the config and control-pipe parsers
read with llvm-objdump). No Google code or config is in the repository; the
profile edits the user's own copy at start, as before.

### 7.1 Constellations and dual frequency

- gpsd reads constellation switches in two places:
  - `<hal>` accepts `EnableBeidou`, `EnableGalileo` and `EnableNavic`
    (not `EnableGlonass`: that is why it asserted there, checkpoint);
  - `<gll_features>` takes the full set: `EnableGlonass`, `EnableGalileo`,
    `EnableBeidou`, `EnableNavic`, `BestGnssMix` and the `Enable*AutoSwitch`
    keys. Both write the same engine settings.
- Each setting has three states: on, off, and "not set" (the engine
  default). gpsd's built-in defaults have GLONASS, Galileo and BeiDou **on**
  and NavIC off; stock `gps.xml` turns NavIC on and sets
  `EnableQzsAutoSwitch=false` and `EnableGloAutoSwitch=false` (QZSS and
  GLONASS tracked always, not switched by region), `EnableNicAutoSwitch=true`
  (NavIC only where it is useful).
- So stock already runs GPS + GLONASS + Galileo + BeiDou + QZSS (+ NavIC).
  The G4 output with only `GP` talkers was the windowsill (two GPS
  satellites in view), not a disabled constellation.
- Dual frequency is stock's too: `<gll>` `MultiCarrRFMode=..._L1_L5`,
  `MultiCarrLnaMask=L1_EXT_ON|L5_EXT_ON`, separate L5 RF path losses and an
  L5 bias, and a per-PRN GPS carrier table. That is L1/E1/B1I plus L5/E5a.
  BeiDou B1C stays off (`EnableB1C=false`), as on stock.
- **Change (0.2.0):** the profile names `EnableGlonass`, `EnableGalileo`
  and `EnableBeidou` = true in `<gll_features>`. This equals the defaults;
  it makes the intent visible in our config and fails loudly at start
  (`die`) if a future image has no `<gll_features>` line to extend. Stock's
  keys stay as they are.

### 7.2 Assistance: orbit predictions (LTO), RTO/RTI, SUPL

How stock gets the LTO file:
- `gps.xml` `<hal>`: `LtoDir=/data/vendor/gps/`, `LtoFileName=lto2.dat`,
  `LtoSyncThresholdDays=1`, `HttpSyncLto=true`.
- `HttpSyncLto` (alias `SyncLto`) means: when the file is older than the
  threshold, gpsd asks the **Android framework** to download it, through
  the HAL's PSDS (formerly XTRA) download request; the framework fetches it
  and hands the data back. `HttpDirectSyncLto` would make gpsd download it
  itself; stock leaves that off.
- The address gpsd knows for it (its `LtoConfig` default):
  `gllto2.glpals.com/4day/v5/latest/lto2.dat` (Broadcom's server; about
  120 KB of orbit predictions for four days).
- gpsd reads `lto2.dat` from `LtoDir` when its engine starts. The
  control pipe also has an `lto` command (reload), unused here.
- Separately, with `RtoEnable`/`RtiEnable` (both true on stock) gpsd
  downloads short-term orbits and satellite health itself, over plain HTTP:
  `gllto.glpals.com:80/rto.dat` and `/rtistatus5.dat` (its built-in
  defaults).
- gpsd's HTTP requests are `GET <path> HTTP/1.0` with a `Host:` header,
  nothing else: no account, no identifier.

Ours (0.2.0):
- `omamobile-gnss-lto` downloads `lto2.dat` on the host with curl into the
  chroot's `/data/vendor/gps/`, keeping the server's modification time
  (`-R`), with `If-Modified-Since`, when:
  - `ASSISTANCE=1` (default);
  - the file is older than `LTO_MAX_AGE_HOURS` (20);
  - there is a default route that is not cellular (`LTO_CELLULAR=0`).
  It rejects anything under 20 KB or starting with `<` (an error page) and
  replaces the file atomically.
- `omamobile-gnss-lto.timer` checks every 4 h (`Persistent`, 20 min random
  delay; no `WakeSystem`, so it never wakes a suspended phone). It is
  enabled and disabled with the Location switch. The profile runs the same
  script before gpsd starts (20 s limit, quiet when offline).
- gpsd keeps doing RTO/RTI itself; the chroot's hosts file now lists only
  `gllto.glpals.com` for that. `ASSISTANCE=0` turns RTO, RTI and the LTO
  sync request off and downloads nothing.
- Tested on the laptop: 122363 bytes, then "0 h old", then a 304 from the
  server with the age limit at 0.
- Privacy: Broadcom's server sees the phone's IP address and when it
  downloads, as for any HTTP fetch. That is what stock does too, so it is
  on by default and switchable.

SUPL (`acSuplServer=supl.google.com`, port 7275, TLS, `SuplEnable=true` on
stock):
- What a SUPL session carries: the device's IP address to the server; a
  SET ID (on Android the SIM's IMSI or MSISDN, which gpsd asks from the
  framework); the serving cell (stock already sends dummy cell info,
  `SuplDummyCellInfo=true`; with no modem there is none anyway); and in
  MS-assisted mode measurements from which the **server computes the
  position**. With no framework and no SIM, what gpsd sends as SET ID is
  untested (it has a default test IMSI for automatic SLP configuration and
  fixed-SET-ID options).
- What it would add here: ephemeris and a coarse reference position from
  cell IDs. With no cell IDs and LTO/RTO present, the gain is small.
- **Change (0.2.0):** SUPL is **off by default** (`SuplEnable=false`, and
  the server is not in the chroot's hosts file, so even a stray attempt
  cannot resolve it). The profile refuses to start if the generated
  `gps.xml` does not say `SuplEnable="false"` while `SUPL=0`. `SUPL=1`
  restores stock behaviour with `SUPL_SERVER` (default
  `supl.google.com:7275`); other public SUPL servers can be set there.
  Experimental: whether gpsd's SUPL works without the framework's data
  connection callbacks is unknown.

### 7.3 Time and position injection

How stock does it: Android's location service injects NTP time
(`IGnss.injectTime`) and the network location (`injectLocation`,
`injectBestLocation`) through the HAL that gpsd implements. On the Pixel,
`gps.xml` sets `IgnoreInjectedSystemTime=true`, so gpsd ignores the
framework's time and keeps its own; injected locations are used.

Without the framework, gpsd's **control pipe** (`CtrlPipe`, the one we
already use for `req_pos`) has the same aiding. Its command table:
`req_pos`, `req_pos_single`, `stop`, `clear`, `set_aid`, `ref_time`,
`startup`, `lto`, `rto`, `rti`, `req_aid`, and test commands. Parameters
come as name,value pairs after the command:
- `$pglirm,ref_time,utc,<ms since 1970 UTC>,unc_ms,<ms>` (also
  `week`/`tow` in GPS time). gpsd logs `IRMSetRefTime:: ulUtcOffsetMs = ...`.
  This path is the engine's own reference-time input, not the HAL's
  `injectTime`, so `IgnoreInjectedSystemTime` does not apply.
- `$pglirm,set_aid,pos,Lat,<deg>,Lon,<deg>,Alt,<m>,HorAcc,<m>,VerAcc,<m>,AgeSec,<s>`
  (gpsd's defaults: 50 m altitude, 10 km / 3 km uncertainty). Values are
  parsed as single-precision floats.

Ours (0.2.0), sent before `req_pos`, each with its own bounded open:
- `INJECT_TIME=1` (default): the system time, only when the clock is
  NTP-synchronized (`timedatectl` NTPSynchronized, or timesyncd's
  `/run/systemd/timesync/synchronized`), with 1 s uncertainty. No network
  traffic of its own. Why it should help: with the rails off between
  sessions the chip keeps no time, and on a cold start the time
  uncertainty decides how much code phase must be searched. G4b checks
  that the value gpsd logs matches the phone's clock; if it is wrong,
  `INJECT_TIME=0`.
- `REF_POSITION=lat,lon[,accuracy_m]` (opt-in, empty by default): a
  coarse position the user chooses (a city is enough; 30 km default
  uncertainty). It never leaves the phone.
- Not done: GeoClue's Wi-Fi position. GeoClue would have to be asked as a
  client (from a root service, with its agent rules), and on Arch its Wi-Fi
  source sends nearby access points to an online service, which is a
  privacy decision of its own. gpsd also keeps its last fix in its own
  storage, which covers the common case of starting where the last session
  ended.
- **Keeping that state (0.2.0):** gpsd's state file (`gldata.sto` in
  `/data/vendor/gps`, persistent under `/var/lib/omamobile-vendor/gnss`)
  only helps if gpsd gets to write it. Until now the stop killed the
  namespace at once. `omamobile-gnss.service` now has
  `ExecStop=omamobile-vendor-chroot gnss stop`, which runs the profile's
  `profile_stop` on the host before systemd signals anything: it sends
  `$pglirm,stop,omamobile` and waits 2 s, with a reader on the NMEA FIFO
  meanwhile (the bridge may already have left). G4b checks the file's
  time stamp.

### 7.4 Power: when the chip is on

| State | What runs | Chip |
|---|---|---|
| Location off | nothing (socket and LTO timer disabled) | rails off, nstandby low |
| Location on, no client | the socket (systemd), the LTO timer | rails off; after the first use `sec_acpm` and `bcm4775x-gnss` stay loaded, but the supplies follow nstandby and `/dev/ttyBCM` (2.1), and host_req is armed only while open |
| A GeoClue client wants exact positions | bridge, lhd, gpsd | on: lhd raises nstandby, which powers the three rails; 1 Hz session |
| Last client gone | bridge counts 60 s (checked every 5 s), exits; the stack stops (`StopWhenUnneeded`): `ExecStop` ends the request (up to 4 s), SIGTERM, the namespace dies, `/dev/ttyBCM` closes | rails off within about 70 s of the last client |
| `omamobile-gnss force` | as with a client, until `unforce` | on |

- G3d measured the off path: `powered 0`, nstandby 0 and all three
  `vdd_gnss_*` disabled after the stop, every time.
- What keeps the chip on, by design: any GeoClue client asking for exact
  accuracy (GeoClue starts its NMEA source only for those), a `force`, and
  `gnss-capture record` (it is a socket client). Linux gpsd on the pty is
  not a client: it needs `force`.
- The LTO timer costs one short HTTP request every 4 h, and a download
  about once a day, only while Location is on.
- To verify on the phone (7.6): that GeoClue drops its socket connection
  when its last client stops (the bridge logs "client gone (0)"), and the
  rails' state 70 s later.
- Running cost: no rail-level meter here. gpsd prints its own estimate in
  `$PGLOR,...,PWR,mA,...` sentences when they are enabled; `gnss-capture
  summary` reports the last one. A battery A/B (`tools/power-ab`, running
  vs. idle) belongs in POWER-PLAN.md before Location is used for long
  sessions.

### 7.5 Settings (`/etc/omamobile/gnss.conf`)

| Key | Default | Effect |
|---|---|---|
| `ASSISTANCE` | 1 | LTO download (timer + at start), gpsd's RTO/RTI; 0 = none of it |
| `LTO_URL` | `http://gllto2.glpals.com/4day/v5/latest/lto2.dat` | |
| `LTO_MAX_AGE_HOURS` | 20 | |
| `LTO_CELLULAR` | 0 | 1 = also over a modem link |
| `INJECT_TIME` | 1 | system time to gpsd when NTP-synchronized |
| `REF_POSITION` | empty | opt-in `lat,lon[,accuracy_m]` |
| `SUPL` | 0 | opt-in; `SUPL_SERVER` (`supl.google.com:7275`) |

- The file is parsed, never sourced: only these keys, each checked against
  a pattern (bad values are logged and ignored). `OMAMOBILE_GNSS_<KEY>` in
  the environment overrides it (tests, `systemd-run --setenv`).
- Changes apply at the receiver's next start.
- `pacman` keeps local edits (`backup=`). An upgrade from 0.1.x enables the
  LTO timer if Location is on.
- `test/all` checks the parser (defaults, quoting, comments, refused
  values, the environment), the shipped file's defaults, and, when the
  user's extract is on the machine, the generated `gps.xml` (SUPL off by
  default, RTO kept, the three constellation keys in `<gll_features>`,
  stock's L1+L5 mode unchanged, well-formed; SUPL on with a custom server;
  `ASSISTANCE=0`). The generated file differs from stock only in the
  intended lines (diffed).

### 7.6 G4b: first fix outdoors with assistance (package 0.2.0)

Preconditions: the int kernel with both GNSS overlays (as since G3); G5's
package installed. G5-2 (GeoClue) need not have passed: this test talks to
the socket directly. Uptime over a minute (the regulator rule, 2.2). Risk:
low. The chip path is G4's; new are the control-pipe `ref_time` before
`req_pos`, `stop` at `ExecStop`, `SuplEnable=false`, and three
`<gll_features>` keys equal to the defaults. Every run is time-limited and
ends with the rails off whether it worked or not.

Logs: the NMEA file holds positions. Keep it on the phone or in `logs/`
(gitignored), never commit or paste it; paste only `gnss-capture summary`
output and journal lines checked for identifiers.

**Step 0 (laptop, read-only on the phone): install.**

```sh
make -C packages/omamobile-gnss/bionic CLANG=$HOME/android/omamobile/prebuilts/clang/host/linux-x86/clang-r596125/bin/clang \
  BIONIC=$HOME/android/omamobile/bionic/libc CHROOT=$HOME/android/vendor-chroot-work/gnss/root   # if prebuilt/ is gone
packages/omamobile-gnss/test/all && tools/phone-install-package packages/omamobile-gnss
tools/phone-ssh 'cat > /var/tmp/gnss-capture && chmod 755 /var/tmp/gnss-capture' < tools/gnss-capture
tools/phone-ssh 'pacman -Q omamobile-gnss; cut -d. -f1 /proc/uptime; grep -vE "^#|^$" /etc/omamobile/gnss.conf;
  timedatectl show -p NTPSynchronized; ip -o route get 1.1.1.1; omamobile-gnss status'
```

- Expect: `omamobile-gnss 0.2.0`; uptime over 60; `ASSISTANCE=1`,
  `INJECT_TIME=1`, `REF_POSITION=`, `SUPL=0`; `NTPSynchronized=yes`;
  a route (Wi-Fi or USB); location on or off, receiver no, chip powered no.
- `NTPSynchronized=no`: the run still works, without time injection. Note
  it in the result.
- Stop if the package does not install or `status` shows the chip
  powered with no receiver running.
- Rollback: `pacman -U` the 0.1.1 package from the pacman cache.

**Step 1 (indoors, USB connected, about 3 min): plumbing, injection, stop.**

```sh
tools/phone-ssh 'omamobile-gnss on; systemctl start omamobile-gnss-lto.service;
  journalctl -u omamobile-gnss-lto -n 3 --no-pager -o cat; omamobile-gnss status | grep -i orbit'
#   expect: "downloaded N bytes via <wlan or usb>" (N ~120000) or "... h old"; status "orbit predictions (LTO): <20 h old"
tools/phone-ssh 'T=$(date +%s); echo "start $T"; /var/tmp/gnss-capture record --out /var/tmp/g4b-0.nmea --seconds 60; sleep 80;
  omamobile-gnss status; cat /sys/kernel/debug/spi5.0/pins | grep -E "^(powered|nstandby)";
  journalctl -u omamobile-gnss -u omamobile-gnss-nmea --since @$T --no-pager -o cat |
    grep -E "omamobile-vendor\[gnss\]|omamobile-gnss|IRMSetRefTime|IrmSetAid|LTO|lto2|Rto|Rti|OnChipReset|CRASH" | head -60;
  ls -l --time-style=+%T /var/lib/omamobile-vendor/gnss/data/vendor/gps/;
  /var/tmp/gnss-capture summary /var/tmp/g4b-0.nmea'
```

Pass:
- The journal shows, in order: "LTO: ..."/the lto script's line, "time:
  injected the system time", gpsd's `IRMSetRefTime:: ulUtcOffsetMs = V`
  with V within a few thousand of `T*1000` (printed as "start T"),
  "control pipe: req_pos", the bridge's "client connected (1)" and "first
  NMEA sentence received", then "client gone (0)", "no client for 60 s",
  "control pipe: stop; 2 s for gpsd to finish", "stopping".
- gpsd mentions the LTO file being opened/read (an `LTO file [...]` or
  `LTO age` line).
- After: receiver no, chip powered no, `powered: 0`, `nstandby: 0`.
- `gldata.sto` (or whatever gpsd's state file is) has a time stamp from
  the stop. If no such file exists, record the directory listing:
  gpsd may keep its state elsewhere.
- The summary shows sentences (indoors, no fix is fine).

Stop conditions and what they mean:
- `IRMSetRefTime` value far from `T*1000` (seconds instead of
  milliseconds, or a leap-second-sized offset): set `INJECT_TIME=0` in
  `/etc/omamobile/gnss.conf` and report the line.
- gpsd exits right after start (`OnChipReset`, "a service exited"): retry
  once with `INJECT_TIME=0`; if it still exits, roll back to 0.1.1 (the
  `<gll_features>` lines are then suspect) and send the journal.
- Chip still powered 80 s after the capture ended: `omamobile-gnss off`,
  check the rails, send the journal; do not go outdoors.


**Step 0-1 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00345-g606b84c7a9fd,
omamobile-gnss 0.2.0): passed.** Step 0: all four settings as expected,
`NTPSynchronized=yes`, route via USB, LTO 3 h old (no download needed).
Step 1, indoors: "time: injected" → gpsd `IRMSetRefTime:: ulUtcOffsetMs =
1791849457760 UNC_MS=1000`, 6.8 s after the "start" stamp in ms (the
injection happens at stack start, before the capture: correct, ms since
1970). `control pipe: req_pos`; gpsd opened `/data/vendor/gps/lto2.dat` and
reported LTO ages GPS 0.2 d, GLONASS 0.3 d, QZSS 0.3 d, BeiDou 0.2 d; the
bridge's "client connected (1)" and "first NMEA sentence received" (+7.7 s).
After: receiver no, chip powered no, `powered: 0`, `nstandby: 0`. gpsd left
no state file in `data/vendor/gps/` (only chip.info, lto2.dat and the pipes):
it doesn't save one there. No fix indoors (expected); gpsd's own power
estimate 38.5 mA. G4b step 2 (outdoors) is next.

**Step 2 (outdoors, unplugged, 15 min): the first fix.**

```sh
tools/phone-ssh 'systemctl start omamobile-gnss-lto.service; date +%s > /var/tmp/g4b-1.start;
  systemd-run --unit=g4b-1 --property=RuntimeMaxSec=960 /var/tmp/gnss-capture record --out /var/tmp/g4b-1.nmea --seconds 900;
  sleep 20; omamobile-gnss status'
#   expect: receiver running yes, chip powered yes
```

Unplug. Put the phone outdoors with a clear view of the sky, screen up,
not moving (the scatter figure assumes it), for 15 minutes. Bring it back
and reconnect (USB-C-PLAN R1: replug rescue).

**Step 3 (collect; read-only).**

```sh
tools/phone-ssh 'S=$(cat /var/tmp/g4b-1.start); systemctl is-active g4b-1; omamobile-gnss status;
  /var/tmp/gnss-capture summary /var/tmp/g4b-1.nmea --start $S;
  echo "== talkers"; cut -d" " -f2 /var/tmp/g4b-1.nmea | cut -c2-6 | sort | uniq -c | sort -rn | head -20;
  echo "== engine"; journalctl -u omamobile-gnss --since @$S --no-pager -o cat |
    grep -iE "time:|position:|IRMSetRefTime|lto|rto|rti|supl|OnChipReset|CRASH|stop" | head -40'
tools/phone-ssh 'cat /var/tmp/g4b-1.nmea' > logs/g4b-1.nmea      # private: positions
tools/phone-ssh 'journalctl -u omamobile-gnss -u omamobile-gnss-nmea --since @$(cat /var/tmp/g4b-1.start) --no-pager' > logs/g4b-1.journal
```

Record in this plan (date, `uname -r`, package version, sky, Wi-Fi or USB
for the LTO download):
- **TTFF**: "first fix: N s after start". Expect well under a minute with
  fresh LTO, injected time and an open sky; a few minutes means the
  assistance did not take (check the engine lines).
- **Satellites per constellation**: in view, strong (C/N0 >= 30) and used.
  Expect GPS, GLONASS, Galileo and BeiDou, QZSS if in view. Signal IDs
  appear only with NMEA 4.11 (below).
- **Accuracy**: HDOP median, and the scatter of the settled fixes
  (median and 95 %, in metres).
- gpsd's power estimate if a `$PGLOR PWR` line came out.
- Pass: `g4b-1` inactive, receiver no, chip powered no; a fix; at least
  two constellations used.

**Steps 2-3 result (2026-10-13, 7.3.0-rc6-omamobile-push1-00375-gc73a652bd07a,
omamobile-gnss 0.2.0): passed.** Daylight, outdoors, still; the LTO file
was current (downloaded over Wi-Fi) and the system time injected. The
capture started indoors and the phone was carried out, so the TTFF is an
upper bound.
- **First fix:** 148.5 s after start (GGA quality 1).
- **In view (strong ≥ 30 dB-Hz):** BeiDou 13 (9), GLONASS 9 (6), GPS 10
  (7), Galileo 10 (7); max C/N0 42-47 dB-Hz.
- **Used (max per epoch):** GPS 15, Galileo 6, a multi-constellation
  solution of 12. BeiDou and QZSS showed none used.
- **Accuracy:** HDOP median 0.4 (best 0.3, 56 fixes). The last 28 fixes
  scattered 3.9 m median and 6.2 m at 95 % around their mean.
- **Power:** gpsd's estimate is 39.0 mA.

**G5-2 (GeoClue), partly (same day):** `where-am-i` run as the desktop
user (not root: GeoClue waits for the caller's agent) connected to the
bridge ("client connected (1)"). Indoors it reported only a 25 km fallback
position. GNOME Maps (installed from Arch Linux ARM) showed a position
indoors, but the GNSS receiver was not running at the time, so that was
GeoClue's coarse source, not the GPS. Next: GNOME Maps outdoors with
`omamobile-gnss status` showing the receiver running. Chromium's web
geolocation doesn't use GeoClue on Linux, so web maps can't locate; use
GNOME Maps.

**Step 4 (optional, each a separate run of steps 2-3, 3-5 min):**
- **Hot start:** right after step 2, again outdoors. Expect a fix within
  seconds if gpsd kept its state (7.3).
- **NMEA 4.11** (system and signal IDs, so L5/E5a show as their own
  signals): `systemctl set-environment OMAMOBILE_GNSS_NMEA411=1` before the
  run, `systemctl unset-environment OMAMOBILE_GNSS_NMEA411` after.
- **Without time injection**, if TTFF looked slow: `INJECT_TIME=0` in
  `/etc/omamobile/gnss.conf`, then back.
- **SUPL** only with the human's explicit go (it contacts the SUPL server,
  7.2): `SUPL=1`, then back to `SUPL=0`.

Rollback for any step: `omamobile-gnss off` (stops everything and disables
the socket and timer); `pacman -U` the 0.1.1 package.
