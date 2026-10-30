<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a USB-C host mode: setup and runbook

Status (2026-10-29): host mode worked end to end on 2026-10-28 (NOTES, "USB-C
host mode through TCPM"). This plan is the setup that run used and the
runbook for the next one, which adds two measurements for
derekross/linux-omarchy-mobile#124: unbinding the charger with a drive
attached, and a reset without shutdown with host mode on. The device tree and
the RT9470 module are on the kernel bring-up branch
derekross/linux-omarchy-mobile#127 (`tegu-usb-host-bringup`, now at
`5ada9ab0f`, not for merge: after the `5dd15e31c` the DTB comparison below
used, `0caff021a` only changed a comment, `6c5d97e18` reworks the boost
driver and `5ada9ab0f` adds the PMIC node and the boost's lines; H2b boots
gn3 plus the overlay below, `usb-host-pmic.dtso`, not #127's DTB). The boot
helpers are in `device/tegu/usb-host/`.

## What it builds on

| Piece | Where |
| --- | --- |
| Board DT: fuel gauge, TCPC node | derekross/linux-omarchy-mobile#119 |
| `usi10`/`hsi2c10`, its pins, the RT9470 node, the TCPC as dual-role with `vbus-supply`, the graph to dwc3 | #127 (USI10 clocks: #102, merged) |
| RT9470 OTG boost module (`tegu-rt9471-boost`) | #127. Since `6c5d97e18` (the #131 follow-up) the driver keeps the RT9470's 40 s watchdog and services it from the PMIC interrupt, or from a 20 s kernel timer without it, as stock does, instead of clearing it; JEITA is off only while the boost is enabled |
| MAX77779 charger and its `chgin-otg` regulator | #92, #124 (head `4970bcdc3820`) |
| MAX77779 TCPC in `tcpci_maxim` | #97 (merged) |
| eUSB2 repeater, PHY | #118, the integration tree |
| Kernel the palmtop runs | `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` (integration tree) |

The palmtop already boots a DTB with this setup: the "gn3" build of
`zumapro-tegu.dtb`, sha256
`cde78d026e45da119fbcdcfb5eedb9900b636db5c027889a9e96fe66c2eac049` (the
`dtb_sha256` of its build record). gn3 is the ot6 round's USB-C device tree
plus the GNSS `gnss-type` change, so it isn't #127 byte for byte. The push
kit ships it with the kit's overlays applied (status flips and the GPU OPP
table), and that image's hash changes with the overlay set, so the base
build is the reference. For this run to count as #124's evidence, gn3's
`i2c@108d0000` (hsi2c6: the fuel gauge, `tcpc@25`, `charger@69` with its
`chgin-otg` regulator), `i2c@10ca0000` (hsi2c10, the boost at 0x5b) and
`usb@11210000` nodes were compared with a build of #127 at `5dd15e31c`
(both decompiled with `dtc -I dtb -O dts`; the result is below, "The three
nodes against #127"). The next run boots no new DTB until H2b. H2b pushes
gn3 plus one overlay to slot B through the normal `push` path, without a
DTB dead-man; its way back when SSH doesn't return is written into H2b.

The `tegu-dtb-deadman` used on 10-28 was a one-boot unit: if the gadget
wasn't configured 180 s into an armed boot, it wrote a known-good
`vendor_kernel_boot` image (checked against a stored sha256 first, and read
back after) into `vendor_kernel_boot_b` from the palmtop and rebooted. It is
a second path writing slot B next to `bin/omamobile push`. It stays unarmed
(H1 checks that and disables the unit), and it won't be used again unless
that's agreed first. Whether it ever fired: the laptop's logs of the 10-28
rounds show every armed boot's gadget coming up (the evening run started
with the gadget configured) and no write, but the unit's own log on the
palmtop, `/var/log/omamobile/dtb-deadman.log`, is the record. H1 reads it,
and its answer goes here.

**The curated autostart** is the 9a's private bring-up startup
(`/usr/local/lib/omamobile-tegu-curated/<release>/curated-native-start.py`,
with a manifest of sha256 pins). It loads the display, GPU and touch modules
in order, refuses a pinned file that changed, and masks units the bring-up
doesn't run. It doesn't pin or load the USB-C modules: those load through
udev from their DT nodes. Re-pinning (recomputing the manifest's sha256 values
after a deliberate change) only matters when a pinned module changes. This
runbook changes none.

**The three nodes against #127 (2026-10-29).** #127 at `5dd15e31c` built on
maclab (`dtbs` only, the palmtop's config) and compared with the palmtop's
running tree (`/sys/firmware/fdt`), both decompiled with `dtc`: the
`i2c@108d0000` (gauge, TCPC with `try-power-role = "sink"`, charger with
`chgin-otg`), `usi@10ca00c0`/`i2c@10ca0000` (hsi2c10, the boost at 0x5b)
and `usb@11210000` nodes have the same properties and values; only phandle
numbers, the clock-controller phandle inside `clocks` and the order of
sub-nodes differ. So the run counts as #127's for those nodes.

**The peripheral role on warm reboots (2026-10-29).** The running
`usb@11210000` has `dr_mode = "otg"` with `usb-role-switch` and
`role-switch-default-mode`, and in four warm reboots today (09:15, 09:19,
09:55 and 10:19 local, `reboot-to omamobile` with the laptop attached) the
gadget came up as peripheral every time (`/sys/class/udc/11210000.usb/state`
`configured`, `tools/phone-smoke` "USB gadget ok, bound to 11210000.usb").
Cold boot and a replug with no host attached are still to be shown (#127's
point 7); they need a hand on the cable.

## Runbook (attended, on the charger, W4HO at the palmtop)

Forced restart if the palmtop hangs, also in a shutdown under the swap timer:
hold Power about 30 s until it is off, then press Power. Stop the run if slot
B isn't marked successful: this runbook doesn't mark it (marking is a separate
`devinfo` operation under the rules being settled on #125). The one
boot-partition write here is H2b's `omamobile push` of gn3 plus the overlay
to slot B's images, through the normal path; nothing else writes one.

**The meter rule.** Any reset while the drive is attached is a crash with
host mode on: H5's `echo b`, H4's swap timer firing, or a forced restart
with the drive in. After each one, with the inline USB-C meter between the
palmtop and the drive, expect VBUS to fall to 0 within the reboot. **Stop if
VBUS is still up two minutes after the reset.** Don't plug the laptop in
(two sources on VBUS); unplug the drive and report it.

**After any unexpected reset** (a forced restart, a crash loop; not the
timer's planned reboot), read pstore on the next boot before anything else.
Ramoops works on the 9a (round ps1): `/sys/fs/pstore/` holds
`dmesg-ramoops-*` for an oops and `console-ramoops-0` for the last console
lines, and systemd-pstore moves them to `/var/lib/systemd/pstore/` soon
after boot. Quote the lines in this plan. H5's reset leaves a console record
too; it is the evidence of what ran last.

**The detached scripts.** The steps that run with the laptop out use the
scripts in `device/tegu/usb-host/`, installed in H2 and started detached
with `systemd-run --unit=…`, so the swap doesn't kill them. Each logs to
`/var/log/omamobile/` and reads with `i2cget` only; H4's one write is the
unbind, H5's the sysrq (and the removal of the early read's marker when it
doesn't reset). Both wait for the laptop link to go and for a drive to
enumerate, and do nothing if either never happens.

**H1. Precondition (read-only, plus one unit disabled; risk none).**
`tools/phone-ssh 'uname -r; cat /proc/device-tree/__symbols__/otg_boost;
for r in /sys/class/regulator/*; do grep -H . $r/name; done | grep -E
"otg-boost|chgin-otg"; ls /dev/i2c-*; systemctl is-enabled tegu-dtb-deadman;
ls /var/lib/omamobile-tegu/dtb-deadman/armed; tail -3
/var/log/omamobile/dtb-deadman.log'`.
Expect: the release above, the `otg_boost` symbol, both regulators, the I2C
device nodes (`i2c-dev` is a module, loaded by then in a session; the early
read loads it itself, since it runs before `systemd-modules-load`), and the
DTB dead-man unarmed: its `armed` marker absent (that `ls` fails), and its
log's last armed boot ending in "gadget configured at Ns: keeping this
DTB", with no "wrote the good DTB image" line. Then `systemctl disable
tegu-dtb-deadman`, so arming it again takes a deliberate step; its files
stay on the palmtop for a DTB round under its own plan. Stop: either
regulator missing (an older DTB), or the marker present (remove it, and say
so here).

**H1 ran (2026-10-29 14:30 local, over SSH, no hands).** Release
`7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, the `otg_boost`
symbol at `/soc/usi@10ca00c0/i2c@10ca0000/regulator@5b`, both regulators
(`otg-boost`, `chgin-otg`), `/dev/i2c-19` to `-21`. The DTB dead-man: unit
`masked-runtime`, marker absent, and its log's last armed boot (10-28
13:48) ends "gadget configured at 1s: keeping this DTB", no "wrote the good
DTB image" line: it never fired on 10-28. Disabled now (`systemctl disable
tegu-dtb-deadman`; the files stay).

**H2 ran (the same session).** `omamobile-tegu-otg-bringup.conf` blacklists
the boost module; `updates/otg/` holds the #124 charger (`e5a4c78e`) and,
instead of the plan's `597a2251` boost, the reworked boost of #127 at
`6c5d97e18` (the watchdog kept and serviced; without the PMIC lines in the
running DTB it falls back to its kernel timer), the old files kept as
`*.before-h2`; `updates/gpio/` holds #139's `gpio-max77779.ko` for H2b;
`depmod -a` run; the three helpers and the unit installed and the unit
enabled, its marker absent. The modules are per release: after the next
kernel push they are reinstalled.

**H2. Modules and helpers for the run (risk low).** Blacklist the boost
module, so its node can't load it before the early read: `echo "blacklist
tegu_rt9471_boost" > /etc/modprobe.d/omamobile-tegu-otg-bringup.conf`.
Install the boost module from #127 (`597a2251…`) and the charger built from
#124's head `4970bcdc3820` (`e5a4c78e…`), both staged in
`/var/lib/omamobile-tegu/usb-host/`, over
`/usr/lib/modules/$(uname -r)/updates/otg/`, keeping the old files as
`*.before-h2`, then `depmod -a`. These live under one release's `updates/`,
so after every `push` of a new kernel they must be rebuilt and reinstalled.
Then the helpers, streamed from the laptop (`tools/phone-ssh 'cat > /usr/local/sbin/NAME'
< device/tegu/usb-host/NAME`): `tegu-rt9470-early-read`,
`tegu-usb-host-h4-unbind` and `tegu-usb-host-h5-reset` into
`/usr/local/sbin/` (`chmod 0755`), `tegu-rt9470-early-read.service` into
`/etc/systemd/system/`, then `systemctl daemon-reload; systemctl enable
tegu-rt9470-early-read`. Expect: `systemctl is-enabled tegu-rt9470-early-read`
says `enabled`, and the unit does nothing yet (its marker is absent until H5
arms it). Rollback: put the `*.before-h2` files back, `depmod -a`, and H6's
removal of the helpers.

**H2b. The PMIC block and the boost's interrupt line (risk medium: its
rollback can end in fastboot; attended, on the charger).** New since the 10-29 review: the RT9470's interrupt and chip
enable are the MAX77779's SGPIO6 and SGPIO7, and stock services the boost's
40 s watchdog from that interrupt. #127 now carries the PMIC block on the
board (`5ada9ab0f`, with its gpa8-0 line pinned as stock's `if_pmic_irq`)
and the boost reworked to keep the watchdog and kick it from the interrupt
(`6c5d97e18`); the block's driver is linux-omarchy-mobile#139 (`a6e10f2ba`).
One boot before H3, with the boost module still blacklisted from H2:

1. Modules: already done by H2, which installed #139's driver
   (`gpio-max77779.ko`) and the boost built from `6c5d97e18`
   (`tegu-rt9471-boost.ko`, W=1 clean) over `updates/gpio/` and
   `updates/otg/`; `5ada9ab0f` only changes the device tree, so nothing is
   staged for this step. After a kernel push they are rebuilt and
   reinstalled as H2 says.
2. Push gn3 plus `device/tegu/overlays/usb-host-pmic.dtso` (the PMIC node on
   hsi2c6 with gpa8-0 pinned as stock's `if_pmic_irq`, and the boost's
   `int-gpios` on SGPIO6: the PMIC node and the pin of #127 at `5ada9ab0f`,
   as an overlay, because the #127 DTB itself can't take the kit's other
   overlays; a dry pack on 10-29 applied it). The overlay does not give the
   boost its `enable-gpios`: SGPIO7 is the RT9470's charge enable (mainline's
   `richtek,rt9471.yaml`: the GPIO that turns charging on and off), and
   with the pin driven low the chip could start charging the battery at its
   power-on defaults beside the MAX77779, with nothing managing it (the
   10-29 readout had `FUNCTION` 0x41, `CHG_EN` set, with the pin undriven).
   That line stays with #127, which must clear `CHG_EN` before taking it,
   or not take it; this boot tests one thing, the PMIC block and the boost's
   interrupt. Added to the kit's `DTB_OVERLAYS` after `package-startup`,
   then `omamobile images` twice and `omamobile push`. Slot B stays marked;
   the push writes only the `_b` images.
3. Reboot with kmsg streamed. Expect: `max77779-pmic 24-0066: MAX77779 PMIC
   revision 0x02` with no "no interrupt line" message, the line in
   `/proc/interrupts` (`24-0066` on gpa8-0) at a count that stays put, the
   gadget as before, smoke 19 of 19. Then `modprobe tegu_rt9471_boost` by
   hand with kmsg streamed. Expect: `JEITA off, watchdog on (0x1)` as stock
   leaves it, `watchdog serviced from interrupt N`, and the regmap readout
   of the PMIC (`/sys/kernel/debug/regmap/24-0066/registers`) with SGPIO6
   now an input with `PU` set and `PD` clear and its DATA high, SGPIO7
   still off (CNFG7 0x00: nothing drives the enable). Then read the boost
   as the H4 script does, `i2cget -f -y <hsi2c10 bus> 0x5b 0x02`
   (`FUNCTION`) and `0x0f` (ICSTAT): expect `FUNCTION` 0x41 as on 10-29
   and ICSTAT 0xf1, VBUS ready and not charging. Stop: ICSTAT showing
   charging (anything but the not-charging value): `rmmod
   tegu_rt9471_boost`, read both again, and record them; an interrupt
   count on gpa8-0 or on the SGPIO line that climbs by more than 100 a
   second (a pull wrong; `rmmod tegu_rt9471_boost` and read the PMIC's
   `e9`/`ea`); the boost probing without the interrupt; or no SSH 3 minutes
   after the reboot. On that last one: a forced restart with the laptop
   attached (slot B is marked, so ABL boots the same DTB again). If SSH
   doesn't come back after the forced restart either, go to fastboot by the
   buttons (Volume Down + Power held about 20 s) and stop there: pushing
   the previous DTB back needs the SSH that is missing, and the way back
   from fastboot is `omamobile flash`, which unmarks slot B (#125), so ask
   Derek before any `flash`. Rollback while SSH works: the previous DTB
   pushed back (the kit restored, `omamobile images` twice, `omamobile
   push`); the modules stay as H2 left them.

Read-only before the step, for the record: the PMIC's registers as the
driver found them on 10-29 without the node (ID 0x79, revision 0x02, OTP
0x21; `INTB_MASK` 0xff; `SGPIO_PU` 0x00, `SGPIO_PD` 0x5e; CNFG0-7 `00 04
05 04 05 00 04 00`: SGPIO6 an input with the OTP pull-down, SGPIO7 off, so
nothing drives the boost's enable in the current bring-up and the chip runs
on its own default).

**H3. Boot with the boost module held back (risk low).** Reboot, with kmsg
streamed to the laptop. Expect: the gadget comes up as before (it ran before
the TCPC node existed), the charger waits for `otg-boost-supply`, and the
TCPC waits for the charger. Stop: no SSH 3 minutes after the reboot (forced
restart with the laptop attached, then H2's rollback). Then load the boost
module by hand (`modprobe tegu_rt9471_boost`) with kmsg streamed. Expect:
`otg-boost` and `chgin-otg` registered and disabled, and the TCPC probes as
a sink with the laptop attached.

**H4. Unbind the charger with the drive attached (#124; risk medium).**
Arm the swap timer first: `systemd-run --unit=x-deadman --on-active=300
systemctl reboot`. Start the script detached: `systemd-run
--unit=tegu-usb-host-h4 /usr/local/sbin/tegu-usb-host-h4-unbind`. Swap the
laptop for the drive. Expect host mode as on 10-28 (the drive enumerates).
The script then unbinds the charger 20 s after the drive enumerates (through
the device's `driver/unbind`) and logs kmsg, VBUS as the TCPC measures it
(0x70/0x71) and `CHG_CNFG_00` (0xbc) at 1, 5 and 20 s, to
`/var/log/omamobile/usb-host-h4.log`. Expect a clean kmsg, VBUS at 0 and
`CHG_CNFG_00` reading 0x05. Laptop back in. Over a fresh login
(`tools/phone-ssh --fresh`), stop the timer: `systemctl stop
x-deadman.timer`, and read the log. Stop: the laptop doesn't come back as a
sink before the timer fires, or an oops in kmsg when the drive comes out or
the laptop goes in (TCPM disabling a regulator whose driver is gone); either
goes in this plan. Rollback: the timer's reboot. If the laptop went back in
first, that boot is H3's. If the drive is still in, the meter rule applies
and the boot is in H5's position (the boost module blacklisted, no Type-C
driver on the MAX77779), so follow H5's swap text: wait for the rescue
unit, then the forced restart with the laptop attached. Reboot before H5 in
any case: after the unbind TCPM holds a stale handle on
`chgin-otg`, and a rebind gives it nothing new, so H5's host mode needs H3's
boot again, with the `modprobe`.

**H5. Reset without shutdown with host mode on (#124, #127; risk
medium-high).** From a fresh H3 boot (the boost module loaded by hand, the
laptop in as a sink). Arm the early read for the next boot (`mkdir -p
/var/lib/omamobile-tegu/rt9470-early-read; touch
/var/lib/omamobile-tegu/rt9470-early-read/armed`; H2 installed and enabled
its script and unit). With the boost module blacklisted from H2, the read
runs before any RT9470 driver. Arm the swap timer (`systemd-run
--unit=x-deadman --on-active=300 systemctl reboot`), start the script
detached (`systemd-run --unit=tegu-usb-host-h5
/usr/local/sbin/tegu-usb-host-h5-reset`), and swap to the drive. The script
refuses to reset unless the early read is armed and enabled and a drive has
enumerated; 20 s after the drive enumerates it logs the boost's state to
`/var/log/omamobile/usb-host-h5.log`, syncs, and runs `echo b >
/proc/sysrq-trigger`. On every exit without a reset (no drive in 3 minutes,
the laptop never leaving, the sysrq not taking) it removes the `armed`
marker, and it traps `TERM` to do the same, so a fallback reboot (the swap
timer firing while it still waits, which stops the unit; a `systemctl
reboot` with the charger's `.shutdown`) doesn't produce an early-read log
under the same name. **The early read counts only when `usb-host-h5.log`
ends with the "resetting now" line.** `systemctl reboot` would run the
charger's `.shutdown`, which turns the boost off, so it can't show what a
crash leaves. Then, with the inline USB-C meter between the palmtop and the
drive:
- Expect: VBUS falls to 0 within the reboot (the meter rule: stop if it is
  still up two minutes after the reset).
- The boot comes up with the drive attached and no laptop. The initramfs
  hands over to Arch without waiting for USB (its no-gadget crash is killed
  with the other helpers at the switch), and neither the root guard nor the
  curated start checks the gadget, so the early read runs (early, and at
  60 s), writes its log and removes its marker. The charger and the TCPC
  wait for the blacklisted boost module, so no Type-C driver owns the
  MAX77779 in this boot.
- Swap the drive for the laptop. Expect: no SSH is guaranteed after the
  swap. The chip opens its USB data switch when the drive comes out (AGENTS,
  "USB"), and no Type-C driver closes it. The one thing that can is
  `omamobile-tegu-usb-rescue` (started every boot by the audio-up script),
  which rewrites `USBSW_CTRL` to 0x09 once VBUS is present and the gadget
  has been unconfigured for 4 s, so the link may come back by itself. Give
  it two minutes over a fresh login (`tools/phone-ssh --fresh`). If there is
  no SSH by then: forced restart with the laptop attached (Power about 30 s,
  then Power), which boots like H3. The early-read log is on disk by then,
  so nothing is lost.
- Then read `/var/log/omamobile/rt9470-early-read.log`: the OTG bit
  (FUNCTION 0x02 bit 1) and ICSTAT before any driver, and again at 60 s. If
  the boost had survived, a read at 60 s also shows whether the regulator
  core's unused-regulator cleanup turned it off (only if the module had
  loaded by then, which H2's blacklist prevents; a second run without the
  blacklist would show it). Quote both reads, H5's log and the console
  record from pstore here.
Rollback: the forced restart with the laptop attached, then H6.

**H6. Afterwards (risk low).** Remove `omamobile-tegu-otg-bringup.conf` and
run `depmod -a`. Take the helpers out: `systemctl disable
tegu-rt9470-early-read`, then remove
`/etc/systemd/system/tegu-rt9470-early-read.service`, the three scripts from
`/usr/local/sbin/` and `/var/lib/omamobile-tegu/rt9470-early-read/` (its
marker is already gone), and `systemctl daemon-reload`. Keep the logs under
`/var/log/omamobile/` and quote them here. Then reboot. The modules stay as
installed in H2, unless H2's rollback is wanted.

## Not known yet

- What a reset without shutdown leaves with host mode on (H5).
- Why JEITA tripped. "Read hot" is an inference: the TS pin may have no
  thermistor on it.
- Whether the RT9470 charges under our kernel. Its CE comes from the
  MAX77779's sGPIO 7 (stock's `rt,ceb_gpio`). On the charger with the
  battery full, FUNCTION read 0x41 (`CHG_EN` set) and ICSTAT 0xf1 (VBUS
  ready, not charging). Since #127 turns JEITA off only while the boost is
  on, this matters only in host mode.
- ~~Where stock's source PDO (5 V, 900 mA in the run) comes from.~~ Traced
  (10-29): Google's zuma `dts/max777x9-tcpc.dtsi`, included by tegu's
  `zuma-tegu-typec.dtsi`, sets `PDO_FIXED(5000, 900, SUSPEND | USB_COMM |
  DATA_SWAP | DUAL_ROLE)` ("Extboost can only do ~1A"). The run advertised
  USB_COMM and DATA_SWAP only; the mergeable board takes stock's set.
- The RT9470's lines in stock's DT (10-29, `zumapro-buck-charge-rt9471.dtsi`
  and `zuma-tegu-charging.dtsi` in Google's tegu tree): interrupt on the
  MAX77779's sGPIO 6 (`PLC_INT_L`), chip enable on sGPIO 7, and stock's
  driver services the 40 s watchdog from that interrupt. Until 10-29 our
  kernel had no MAX77779 sGPIO driver, so the bring-up node had no
  interrupt and the boost ran with the watchdog off. Now the reworked boost
  driver on derekross/linux-omarchy-mobile#127 (`6c5d97e18`) keeps the
  RT9470's watchdog and services it from the interrupt, or from a 20 s
  timer when the node has none, as stock does, instead of clearing it
  (the follow-up Derek asked for on #131); the sGPIO driver is #139.
