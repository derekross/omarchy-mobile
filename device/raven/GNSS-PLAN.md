<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): GNSS (location)

Status (2026-10-15): **GNSS works on raven: a real satellite fix outdoors (HDOP 0.6)**. Indoors it tracks little or nothing; GeoClue also has network sources, so check a fix by its HDOP or accuracy, not by a position alone. Kernel branch
`omamobile-gs101-gnss` (`ba1b90401` driver, `44f0af683` DT), merged in
`omamobile-gs101-merge-test` (`38dc6b965`, kernel `g38dc6b965ee4`); overlay
`overlays/gnss-test.dtso` (in `DTB_OVERLAYS`); vendor chroot from
`tools/extract-vendor-chroot -d raven -p gnss` (private, in
`~/android/vendor-chroot-raven-gnss`). The port of cheetah's GNSS
([device/cheetah/GNSS-PLAN.md](../cheetah/GNSS-PLAN.md)): same chip, same
daemons.

## 1. Facts

From stock raven's device tree (factory dtbo, CP3A.261005.002.A1) and its
vendor partition.

| Item | raven (gs101) | cheetah (gs201) |
| --- | --- | --- |
| Chip | Broadcom BCM4775x (`ssp-spi,bcm4775`) | the same |
| Bus | PERIC0 USI5 SPI (`spi@10940000`), 26 MHz, mode 3 (CPOL, CPHA), DMA | the same bus |
| Chip select | gpp10-3 (stock: the SPI's own CS, `spi5_cs_func`); a GPIO here, as on cheetah | gpp10-3 as GPIO |
| host-req (IRQ from the chip) | gpa6-4, EINT | gpa6-4 |
| mcu-req (AP to chip) | gpp1-1, output | gpp4-3 |
| mcu-resp (chip to AP) | gpp0-0, input, pull-down | gph2-2 |
| nstandby | gpp0-2, output | gph2-3 |
| Supplies | S2MPG11 LDO9S (`L9S_GNSS_CORE`), LDO10S (`L10S_GNSS_RF`), LDO11S (`L11S_GNSS_AUX`), always-on on stock | S2MPG13 LDO9S-LDO11S |
| Daemons | `/vendor/bin/hw/lhd`, `/vendor/bin/hw/gpsd`, `firmware/SensorHub.patch`, `etc/gnss/{lhd.conf,gps.xml,gps.cer}` | the same files and paths |
| Device node | `LheBbdPacket=/dev/ttyBCM`, `PortName="/dev/ttyBCM"`, `NmeaOutName="/data/vendor/gps/nmea_out"` | the same |

Mainline already describes the three LDOs (`vdd_gnss`, `vdd_gnss_rf`,
`vdd_gnss_aux`, not always-on): the driver claims them, so the regulator
core's late cleanup leaves them alone.

## 2. Port

- Kernel: cheetah's `drivers/misc/bcm4775x` (lhd interface, `/dev/ttyBCM`,
  `/dev/bbd_*`) and its binding, imported unchanged (NOT FOR MERGE); raven's
  DT node with the pins and supplies above, disabled until `gnss-test`.
- Userspace: `omamobile-gnss` unchanged (its start script checks the same
  `usi@109400c0/spi@10940000` path and loads `sec_acpm`, which raven has);
  the vendor chroot from raven's own factory image.

## 3. Runbook (gated, read-only first)

| Step | What | Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| G0 | push `g38dc6b965ee4` with `gnss-test` | boots; SPI 5 `okay`; nothing GNSS autoloaded | no boot | old images to slot B | low |
| G1 | install omamobile-gnss and the chroot (`/usr/lib/omamobile-vendor/gnss`) | files in place | | remove | none |
| G2 | `omamobile-gnss-start` (marker, then `bcm4775x-gnss`) | `/dev/ttyBCM`; lhd loads `SensorHub.patch` | hang (marker keeps the next boot clean) | reboot | medium: first SPI traffic to the chip |
| G3 | gpsd running, NMEA in `nmea_out` | `$GPGSV` with satellites; outdoors a `$GPGGA` fix | no NMEA after 5 min outdoors | stop the service | low |
| G4 | GeoClue (`omamobile-gnss` agent) | `where-am-i` gives a position | | | low |

## 4. Results

**2026-10-15, kernel `g38dc6b965ee4`:**
- G0: boots with `gnss-test`; SPI 5 `okay`, the chip's SPI device present,
  the driver not autoloaded; the AoC, speakers, sensors and Bluetooth up;
  taint 0.
- G1: `omamobile-gnss` 0.2.1 (unchanged; its bionic shims built on the laptop
  with AOSP's clang, bionic's headers from AOSP and raven's chroot libc) and
  the raven chroot (239 files, 28 MB) in `/usr/lib/omamobile-vendor/gnss`.
- G2: `omamobile-gnss.service` has `StopWhenUnneeded=yes` (it starts when a
  client opens the NMEA socket), so started by hand it stopped at once and
  left its marker; run as a transient unit with `--retry`:
  `bcm4775x-gnss spi0.0: BCM4775x GNSS on SPI, irq 156`, power on when lhd
  opens `/dev/ttyBCM`, SSI frames both ways; lhd loads `SensorHub.patch`;
  gpsd reports `MCU_PWR: HwVersion 0x35000011`. Taint 0.
- G3 (indoors, cold start): NMEA once a second (`$GPGGA`, `$GPRMC`, GSA for
  GPS, Galileo and combined), no fix yet.
- The shell's location tile was grey: the chroot was copied with the
  laptop's private modes (`drwxrwx---`), so `omamobile-gnss status` (run as
  the user) found no `/usr/lib/omamobile-vendor/gnss/root`. Fixed with
  `chmod -R go+rX`; `phone-provision -d raven` now pushes the chroot with those
  modes and enables `omamobile-gnss-nmea.socket` and `omamobile-gnss-lto.timer`.
- With the tile on, GeoClue gave a position, but from its network sources:
  `geoclue.conf` enables ip, wifi, 3g, cdma, modem-gps, network-nmea,
  compass and static. Forced on (`omamobile-gnss force`) for 45 s indoors:
  every `$GPGGA` fix 0, 0 satellites, HDOP 999.9, and **no `GSV` sentence at
  all**: nothing tracked. Indoors some weak satellites are normal, so this
  may be the RF path (antenna, LDO10S RF supply) or just the building.
- **G3 outdoors (detached logger, `omamobile-gnss-sky-log`, no coordinates in
  its log):** within 4 minutes outside, GPS satellites came into view (5,
  C/N0 up to 38 dB-Hz) with no fix yet (a cold start, no assistance); a
  longer run gave the owner a GNSS fix with **HDOP 0.6**, matching their
  position (seen on the phone; the GPX track stays on it). G3 and G4 pass.
