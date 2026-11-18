# USB-C and charging plan: gates B3 (charger) and B4 (Type-C) (cheetah / gs201)

Status (2026-10-19): **the charger driver and its temperature guard load
at boot (D1, device-cheetah 0.1.33); G1, G2 and D1 passed, replug
included.** Next: G3-G6 (optional, attended), then B4a. Kernel
7.3.0-rc6-omamobile-push1-00558-gcbd727f42785 (`omamobile-int` @
`cbd727f42`) has every piece B3g, B4a and B4b need; nothing has to be built
before B4b. Section 9 is the current runbook (it replaces section 6 from
B3.1 on: that one pushed the old `out-usbc` kernel, which would drop the
camera, audio and AoC), with today's results. **Next:** G3-G6 (attended),
then D1 (device-cheetah: charger and guard on by default), then B4a.

Earlier status (historical, superseded by the status above): Follows `WIFI-BATTERY-PLAN.md` sections 4-5 (MAX77759 wiring, gates B1/B1b
done, B2 pending). Written 2026-10-12, offline: nothing here has run on the
phone yet. Kernel: branch `omamobile-usbc` in `~/android/mainline/wt-usbc`,
out dir `~/android/mainline/out-usbc`.

Sources: `L/` = the worktree, `G/` = Google's GPL kernel
(`~/android/omamobile/out-kernel/google/gs-6.1/private`), `R/` = the stock
root capture (`~/android/reference/cheetah-stock-cp2a-root`).

## 1. Facts this plan rests on

| Fact | Evidence |
|---|---|
| The bootloader hands over with the charger in mode 5 (charger + buck on), which stock keeps | B1 read `0x69/0xb9 = 0x05`; `R/dmesg.txt:2408` "CHG_CNFG_00=5->5" |
| The upstream charger driver sets mode OFF at probe and turns charging on only when a power supply named `tcpm-source*` reports online **with a current limit > 0** | `L/drivers/power/supply/max77759_charger.c`, `max77759_charger_init()` and `psy_work_item()` |
| TCPM reports current 0 for a source with Type-C default power (PC ports, USB-A to C cables), because TCPCI has no `get_current_limit` | `L/drivers/usb/typec/tcpm/tcpm.c` `tcpm_get_current_limit()`; `tcpci.c` sets no `get_current_limit`. So upstream TCPM + charger does **not charge** from a default-power port at all |
| Stock's float voltage limit is 4.45 V; its step charging lowers the current at 4.3 and 4.45 V and with temperature | `R/live.dts:18205` `google,fv-max-uv = <4450000>`; `:17774-17776` cv-limits 4.2/4.3/4.45 V, temp limits 0/10/20/42/46/48/55 °C, cc-limits in % of capacity (`G/google-modules/bms/google_bms.c:195-199`) |
| The bootloader leaves a lower float voltage, so charging can stop short of 100 % | to be read in B3.0 (`CHG_CNFG_04`, expect a selector below 45 = 4.45 V) |
| The MAX77759 opens its USB2 data switch (TCPC vendor `USBSW_CTRL`, 0x93) on unplug and Linux never closes it: this is the "USB doesn't come back after a replug" bug (NOTES.md) | Google's driver writes `USBSW_CONNECT` (0x09) on **every** attach with a data role ("b/188614064 ... always enable the switches here", `G/google-modules/soc/gs/drivers/usb/typec/tcpm/google/tcpci_max77759.c:1117-1215`, register in `tcpci_max77759_vendor_reg.h:94-96`). Upstream `tcpci_maxim` writes 0x09 only when a USB PD partner says it is USB communications capable, and 0 on every port reset, including at probe |
| The USB PHY forces VBUS valid unless it is an orientation switch; with `orientation-switch` it leaves VBUS valid entirely to the Type-C driver | `L/drivers/phy/samsung/phy-exynos5-usbdrd.c`, `exynos850_usbdrd_utmi_init()` (`if (!phy_drd->sw)`) and `exynos5_usbdrd_orien_sw_set()` |
| On this board VBUS is sourced by an external boost, not the MAX77759's own reverse boost | `R/live.dts:8366,8375` `max77759,ext-otg-only`, `bst-on` = index 4 of stock's 6-line MAX77759 GPIO chip, i.e. GPIO5 (mainline line 0); `extbst-ctl` = TCPC GPIO 0, which Google's driver maps to vendor reg 0x92 `EXT_BST_EN` (`tcpci_max77759.c:750-780`). Index 5, GPIO6 (mainline line 1), is the VBUS input/OVP switch (`in-switch-gpio`, active low, `R/live.dts:8218`) |
| A panic reboots the phone; a missing USB gadget at boot crashes it after 45 s; after ABL's retries slot A (stock) boots | `initramfs/init` (self-recovery block), NOTES.md "Slot B fallback works" |
| The s3c2410 watchdog resets the phone about 15 s after its feeder stops | `tools/wifi-w1-capture --watchdog`, NOTES.md "Watchdogs" |

## 2. Order: B3 before B4, with evidence

1. **B3 (charger) never touches the USB data path.** The charger only
   programs mode, float voltage, fast-charge and input current. Its only way
   to hurt the link is to load the laptop's port past its limit, so the
   port cuts VBUS (and, today, data never comes back). The new
   `default_ilim_ua` keeps the input at 500 mA, the USB 2.0 limit every port
   must supply to a configured device.
2. **B4 changes who owns VBUS valid and the data switch**, by design costs
   one re-enumeration when TCPM takes over, and has more ways to fail.
3. **B4 needs the B3 change to charge at all** from the laptop: with TCPM,
   a default-power port reports current 0 and the upstream charger turns
   charging off. With `default_ilim_ua` it charges at 500 mA instead.
4. Without B3, B4 still leaves charging as the bootloader set it (mode 5,
   no driver), so B4 does not depend on B3 for safety. B3 first because it
   is lower risk and B4 benefits from it.

Before both: **R1**, the replug fix by itself (one I2C write, no kernel
change), and a dead-man drill.

## 3. What was built

### Kernel (`omamobile-usbc`, on `omamobile` @ `7b0f8b5d1`)

| Commit | What | Default state |
|---|---|---|
| `power: supply: max77759: zero the regulator and power supply configs` | fix: two stack structs were half uninitialised (masked by `INIT_STACK_ALL_ZERO`) | upstreamable fix |
| `power: supply: max77759: charge at a default input limit without a source report` | `default_ilim_ua` module parameter (max 900 mA): charge from probe without TCPM, use it for an online source with current 0, leave charging on at unbind. Logs `found:` and `probed:` lines with mode, FV, CC, ILIM | parameter 0 = upstream behaviour; module blacklisted |
| `usb: typec: tcpci: let chip drivers follow role changes` | optional `set_roles()` hook in `struct tcpci_data` | no user but tcpci_maxim |
| `usb: typec: tcpci_maxim: connect the USB data switches on attach` | writes `USBSW_CTRL = 0x09` on every TCPM attach, as Google's driver does; PD can still open it | module blacklisted |
| `phy: samsung: usbdrd: keep VBUS valid until Type-C reports a connection` | with an orientation switch, VBUS stays forced valid until the Type-C driver reports an orientation for the first time; writable `force_vbus_valid` parameter forces it again at runtime | no change without `orientation-switch` in the DT |
| `dt-bindings: phy: samsung,usb3-drd-phy: add Google gs201` | the gs201 PHY compatible was undocumented; orientation switch optional | |
| `arm64: dts: exynos: google: gs201-cheetah: charger limits and a sink-only port` | battery `constant-charge-voltage-max` 4.45 V, `constant-charge-current-max` 1.47 A (0.3 C, the lowest stock cc-limit between 10 and 46 °C at any voltage tier); `monitored-battery` on `pmic@66` (the charger cell uses the parent's node); the still disabled connector becomes sink only (no driver for the external boost, so no `vbus-supply`) | TCPC node `disabled` |

Hashes, oldest first: `1074d2178`, `49a930690`, `6cb72374d`, `80ffae6d5`,
`45e5489db`, `06e60a228`, `c86bd2db7`. Built: release
`7.3.0-rc6-omamobile-push1-00065-gc86bd2db7c72`, `kernel`/`modules`/`images`
exit 0 (`logs/kernel-usbc.log`, `modules-usbc.log`, `images-usbc.log`); the
changed C files build W=1 clean; `dt-doc-validate` passes for the PHY
binding; `dt-validate` of the base DTB, base + B4a and base + B4a + B4b
reports only the existing `soc_id` and simplefb `post-init-providers`
messages.

Not changed in the base DT on purpose: the PHY (`orientation-switch`, graph
port) and dwc3 (`dr_mode`, role switch). Those come from overlays, so the
default DTB keeps today's USB exactly.

### omamobile repo

- `device/cheetah/overlays/usbc-tcpm-test.dtso` (B4a): TCPC `okay`, connector
  port@0 <-> PHY port, PHY `orientation-switch`.
- `device/cheetah/overlays/usbc-role-test.dtso` (B4b, on top of B4a): dwc3
  `dr_mode = "otg"`, `usb-role-switch`, default peripheral, connector port@1
  <-> dwc3 port.
- `tools/usbc-deadman` (laptop) and `tools/usbc-deadman-phone` (phone): the
  dead-man switch, register dump, replug rescue.
- No change to `omamobile-max77759.conf`: `max77759`, `max77759_charger`
  and `tcpci_maxim` stay blacklisted; every step loads them by hand.

## 4. The dead-man switch (`tools/usbc-deadman`)

Every risky step runs as `tools/usbc-deadman STEP`:

1. The laptop installs `usbc-deadman-phone` in `/usr/local/bin`, streams
   `/dev/kmsg` into `logs/usbc-STEP-<time>.log` (reconnecting after drops)
   and starts the step **detached** with `systemd-run` (falls back to
   `setsid nohup`), so an SSH drop cannot stop it.
2. On the phone: the hardware watchdog is armed first (refuses to run if
   `/dev/watchdog0` cannot be opened, unless `--no-watchdog`); registers the
   step touches are saved to `/run/usbc-deadman/`; the step is applied;
   everything is logged before it happens to `/dev/kmsg` (pstore) and
   `/var/log/usbc-deadman.log`.
3. The laptop keeps trying **new** SSH logins and runs
   `usbc-deadman-phone confirm` once one works (for `replug`, only after it
   has seen the link drop and come back).
4. No confirmation within `--confirm` seconds (90; replug 120): the phone
   undoes the step (unload the module, restore the saved charger registers,
   `force_vbus_valid=1`), then runs the **rescue**: if the charger sees valid
   VBUS (`CHG_DETAILS_00` bits 6:5 = 3) it writes `USBSW_CTRL = 0x09`. Then it
   waits `--grace` seconds (60) for a confirmation again; the result is
   `reverted`.
5. Still nothing: it stops feeding the watchdog. ~15 s later the phone does a
   warm reset into slot B with all MAX77759 drivers blacklisted (known-good
   USB). If the watchdog was not armed, `sysrq c` (panic=10 reboots).

`tools/usbc-deadman undo STEP` reverts a confirmed step by hand. `--no-confirm`
deliberately lets the undo run (to test it).

### Physical recovery (also printed by the tool)

1. Wait 2 minutes (undo, then watchdog reset, then boot).
2. Unplug and replug once.
3. Hold Power ~30 s (off), press Power: slot B boots with the drivers
   blacklisted.
4. Only after an overlay DTB that kills USB at boot: the initramfs crashes
   after 45 s without a configured gadget; after ABL's retries, stock
   Android boots from slot A; `adb reboot bootloader`, then flash images
   built without the overlay. Keep that out dir (`D.default`) before any
   overlay build.
5. Fastboot by hand: Power ~30 s off, then Volume Down + Power ~20 s until
   "Fastboot Mode".

## 5. Reading the charger read-only first (B3.0)

`tools/usbc-deadman dump` runs `i2cget -f` only (bus = the `10d60000.i2c`
adapter, `i2c-0` in B1). No module needs to be loaded. Expected on the
laptop's port, with only the fuel gauge loaded:

| Reg | Name | Expected | Meaning |
|---|---|---|---|
| 0x69/0xb9 | CHG_CNFG_00 | low nibble **5** | charger + buck on (B1: 0x05) |
| 0x69/0xbd | CHG_CNFG_04 | `CHG_CV_PRM` (bits 5:0) **< 45** | float voltage 4000 + 10 x sel mV; 45 = 4.45 V (stock fv-max). **Write it down**: the bootloader's value is why charging stops short of 100 % |
| 0x69/0xbb | CHG_CNFG_02 | any, write down | fast charge: 200 + (sel - 3) x 66.67 mA (sel >= 3) |
| 0x69/0xc2 | CHG_CNFG_09 | any, write down | input limit: 100 + (sel - 3) x 25 mA; bit 7 NO_AUTOIBUS |
| 0x69/0xbf | CHG_CNFG_06 | bits 3:2: R0 read **3** | 3 = protected registers unlocked, as the bootloader leaves them; the driver's init ends with them locked (0) |
| 0x69/0xc5 | CHG_CNFG_12 | bit 5 (CHGINSEL) = **1** | USB input enabled |
| 0x69/0xcb | CHG_CNFG_18 | bit 0 (WDTEN) = **0** | no charger watchdog (if 1, charging stops 80 s after nobody kicks it; the driver clears it) |
| 0x69/0xb5 | CHG_DETAILS_00 | bits 6:5 = **3** | VBUS valid |
| 0x69/0xb6 | CHG_DETAILS_01 | CHG_DTLS (3:0) 1/2/3/4, BAT_DTLS (6:4) 3 | CC / CV / top-off / done; battery OK |
| 0x25/0x00-01 | VENDOR_ID | **0x6a 0x0b** | Maxim (0x0b6a) |
| 0x25/0x93 | USBSW_CTRL | **0x09** while the link works | data switch closed |

Stop if mode is not 5, WDTEN is 1, the vendor ID is wrong, or reads fail.

**R0 reading (2026-10-12, 93 %, on the laptop's port):** mode 5, fast charge
1933 mA, **float voltage 4350 mV** (bootloader; stock's fv-max is 4450, so
charging ends early, CHG_DTLS was 4 = done at 93 %), input limit 500 mA,
CHGPROT 3, WDTEN 0, CHGIN_DTLS 3, USBSW_CTRL 0x09. B3 therefore changes FV
4350 -> 4450 mV and CC 1933 -> 1467 mA, and keeps the input at 500 mA.

## 6. Runbook

Shorthand: `O=~/android/mainline/out-usbc`,
`D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb`. Second terminal:
`tools/phone-ssh dmesg -w`. Battery above 50 %, phone at room temperature.

### R0: dead-man drill (current kernel is fine)

```sh
tools/phone-ssh 'pacman -S --needed --noconfirm i2c-tools'
tools/usbc-deadman install
tools/usbc-deadman dump                       # section 5 table; keep the output
tools/usbc-deadman noop                       # expect: CONFIRMED within ~10 s, exit 0
tools/usbc-deadman noop --no-confirm          # expect: UNDONE after ~100 s, link up, exit 0
```

**Pass:** both results as stated, watchdog disarmed (`usbc-deadman log`),
no reset. If the phone resets during the second one, the confirm path is
broken: stop and fix the tool before any real step.

### R1: the replug fix alone (current kernel is fine)

The PHY forces VBUS valid today, so the gadget never notices an unplug; only
the data switch is open after a replug. Closing it is the whole fix until B4.

```sh
tools/phone-ssh 'systemd-run --unit=usbc-rescue-watch /usr/local/bin/usbc-deadman-phone rescue-watch'
tools/usbc-deadman replug     # unplug, wait 5 s, replug (try the other cable orientation too)
```

**Pass:** `CONFIRMED` after the replug, the phone log shows
`rescue: VBUS valid, USBSW_CTRL was 0x00` then `i2cset 0x25 reg 0x93 = 0x09`.
Even without the watcher, `replug` ends `REVERTED` (its undo runs the
rescue), which proves the same thing more slowly. Stop the watcher with
`systemctl stop usbc-rescue-watch` before B4 (TCPM owns the switch then).
Packaging the watcher as a service is a follow-up if B4 is far off.

### B3: charger

```sh
# B3.1 new kernel and modules (default DTB, no overlay); everything still blacklisted
KERNEL_DIR=~/android/mainline/wt-usbc KERNEL_OUT=$O bin/omamobile modules > logs/modules-usbc.log 2>&1
KERNEL_DIR=~/android/mainline/wt-usbc KERNEL_OUT=$O bin/omamobile images > logs/images-usbc.log 2>&1
KERNEL_OUT=$O bin/omamobile modules-push && KERNEL_OUT=$O bin/omamobile push
tools/phone-ssh 'cat /sys/module/phy_exynos5_usbdrd/parameters/force_vbus_valid'   # N
tools/usbc-deadman dump                       # same as R0 (the battery node changed, nothing else)
# B3.2 MFD core + GPIO (gate B2) under the dead-man
tools/usbc-deadman b2-core
#   pass: max77759 bound, gpiochip "max77759-gpio" with 2 lines, `grep gpa9 /proc/interrupts`
#         twice a few seconds apart: no storm. Nothing may request GPIO5/GPIO6.
# B3.3 the charger, 500 mA input
tools/usbc-deadman b3-charger --ilim 500000
```

**B3.3 pass** (the tool prints the dump and dmesg once confirmed):

- dmesg `max77759-charger ...: found: mode 0x5, float voltage <bootloader> mV,
  ...` then `probed: mode 0x5, float voltage 4450 mV, fast charge 1466730 uA,
  input limit 500000 uA`.
- dump: `CHG_CNFG_04` sel 45, `CHG_CNFG_02` sel 22, `CHG_CNFG_09` sel 19,
  mode 5, `CHG_DTLS` 1 (CC) or 2 (CV), `USBSW_CTRL` 0x09.
- `/sys/class/power_supply/max77759-charger/`: `online` 1, `status`
  Charging, `constant_charge_voltage_max` 4450 (the upstream driver reports
  mV here, not µV), `input_current_limit` 500000.
- The gauge's `current_now` is positive and at most ~550 mA.
- Watch 10 minutes: gauge `temp` rises less than 5 °C; no
  "Battery over-current" lines; link stays up.

**B3.4 (attended):** leave it on the cable until full. **Pass:** CV phase
near 4.45 V, then `CHG_DTLS` 3/4 (top-off/done), capacity 100 %. **Fail
actions:** `tools/usbc-deadman undo b3-charger` restores the bootloader's
registers.

**Not yet safe to make permanent.** Without Google's google_battery there is
no temperature policy: stock stops charging above 4.3 V below 10 °C or
between 46 and 48 °C, above 4.2 V from 48 to 55 °C, and completely outside
0-55 °C. Whether the MAX77759's
own JEITA (`CHG_DTLS` 0xc) is configured by the bootloader is unknown.
Before `options max77759_charger default_ilim_ua=500000` goes into the
device package, add a temperature guard (a small userspace or kernel policy
that sets mode OFF outside 10-45 °C from the gauge's `temp`).

### B3g: battery temperature guard (before charging is on by default)

Nothing in mainline limits charging by temperature; stock does it in
software from the `google,battery` step-charging table (`R/live.dts:17774-17776`):

| Battery | Float voltage | Charge current (% of capacity) up to 4.20 / 4.30 / 4.45 V |
|---|---|---|
| below 0 °C | no charging | |
| 0-10 °C | 4.30 V | 30 / 10 / - |
| 10-20 °C | 4.45 V | 50 / 30 / 30 |
| 20-42 °C | 4.45 V | 100 / 70 / 50 |
| 42-46 °C | 4.45 V | 80 / 50 / 50 |
| 46-48 °C | 4.30 V | 50 / 50 / - |
| 48-55 °C | 4.20 V | 30 / - / - |
| 55 °C and up | no charging | |

**Design: in the charger driver, not a userspace service.** A service can be
stopped, crash or be frozen in suspend, and the guard must hold whenever the
charger driver is bound. So the policy lives in `max77759_charger` (branch
`omamobile-chgguard` in `~/android/mainline/wt-chgguard`, commit
`37a83337c` on top of `omamobile-usbc` `c86bd2db7`; built W=1 clean into
`~/android/mainline/out-suspend/chgguard`):

- Module parameter `temp_guard` (bool, runtime-writable, **default off**).
  Every 30 s the driver reads `temp` and `voltage_now` from the power supply
  named by `guard_psy` (default `max170xx_battery`), picks the band and the
  tier, and programs the float voltage (`CHG_CNFG_04`) and fast charge
  current (`CHG_CNFG_02`), never above the battery node's limits (4.45 V,
  1.47 A; with 4926 mAh, 100 % is capped at 1.47 A anyway).
- Out of range or **no reading** means charging off: mode 4 (buck only), so the
  phone keeps running from USB and the battery rests. Mode 0 would cut the
  buck too.
- It enters a more restrictive band at once, and a less restrictive one only
  2 °C inside it (both directions), so a reading at a boundary doesn't flap.
  Tiers only rise within a band.
- Turning the parameter off restores the battery node's limits and allows
  charging again. When the module unloads while charging is inhibited, it
  stays inhibited (the safe side) until the next load.
- Backstops: the charger's own JEITA (thermistor on its THM input, status
  `CHG_DETAILS_01` CHG_DTLS 0xc). External reports say the bootloader leaves
  it on (`CHG_CNFG_08` 0xc1, bit 2). G0 reads it.

**Package:** `omamobile-device-cheetah` 0.1.14 adds `omamobile-charge-guard`
(`status`, `on`, `off`) and `/usr/lib/modprobe.d/omamobile-charger.conf`,
whose `options max77759_charger temp_guard=1` line stays commented out. The
package test fails if it is uncommented, or if the charger stops being
blacklisted, until this gate passes.

Runbook (needs the B3 kernel plus `omamobile-chgguard`; merge order:
`omamobile-usbc`, then `omamobile-chgguard`):

- **G0, read-only:** `tools/usbc-deadman dump`, plus
  `tools/phone-ssh 'i2cget -f -y 0 0x69 0xc1; i2cget -f -y 0 0x69 0xb8; i2cget -f -y 0 0x69 0xb6'`
  (CNFG_08, DETAILS_03, DETAILS_01; use the bus number B3.0 found). Record
  whether JEITA bit 2 is set. Then
  `cat /sys/class/power_supply/max170xx_battery/temp` (tenths of °C) twice,
  a minute apart, and compare with the room: it must be a plausible battery
  temperature that moves (not stuck at 22.0 °C, which would mean the
  thermistor isn't in use; B1b fixed that).
- **G1, guard on, normal temperature:** load the charger as in B3.3, then
  `omamobile-charge-guard on`, wait 35 s, `omamobile-charge-guard status`.
  Expect `temperature guard on (max170xx_battery)`, then `battery 2x.x C,
  .... mV: band 20-42 C, float 4450 mV, charge 1466730 uA` (or the 10-20 °C
  band in a cold room: 4450 mV, 50 % = 1466730 capped). Charging continues.
- **G2, simulated read failure:** with the guard on, `modprobe -r
  max17042_battery`. Within 30 s: `no reading from max170xx_battery:
  charging inhibited`, `CHG_CNFG_00` mode 4 in the dump, charger `status`
  "Not charging". `modprobe max17042_battery`: within 30 s charging resumes
  (at room temperature; within 2 °C of a band edge it waits until the
  reading is 2 °C inside the band).
- **G3, hot band (attended, cable in):** warm the phone gently (a long GPU
  load: `glmark2-es2-wayland --run-forever` with the screen at full
  brightness, or a warm room). Stop the load at once if the battery passes
  50 °C. Watch `omamobile-charge-guard status` every minute. Expect at 42 °C
  the 42-46 band (1.47 A capped -> current stays, float 4450), at 46 °C float
  4300 mV, at 48 °C 4200 mV. Cool down: the bands come back only 2 °C inside
  each one.
- **G4, cold band (optional, attended):** the phone in a fridge (not a freezer)
  for 20 min, then on the cable: below 10 °C float 4300 mV and 30 % current;
  below 0 °C inhibited.
- **G5, soak:** a full charge from below 50 % with the guard on: the same
  result as B3.4, and no guard message other than band changes.

**Pass:** G0-G2 and G5 (G3/G4 as far as can be done safely). Then uncomment the
modprobe option together with removing the charger from the blacklist, in
the same package release, so charging is never on by default without the
guard. **Rollback:** `omamobile-charge-guard off` (restores the battery
node's limits), or unload the charger (`tools/usbc-deadman undo b3-charger`).

### B4a: TCPM drives VBUS valid and the data switch (device only)

```sh
# B4a.1 DTB with the overlay; keep the default one for recovery
cp "$D" "$D.default"
$O/scripts/dtc/dtc -q -I dts -O dtb -o out/usbc-tcpm-test.dtbo device/cheetah/overlays/usbc-tcpm-test.dtso
$O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" out/usbc-tcpm-test.dtbo
KERNEL_DIR=~/android/mainline/wt-usbc KERNEL_OUT=$O bin/omamobile images > logs/images-usbc-b4a.log 2>&1
cp -r $O/images $O/images.b4a
KERNEL_OUT=$O bin/omamobile push
tools/phone-ssh 'ls /proc/device-tree/soc@0/phy@11200000/; cat /sys/module/phy_exynos5_usbdrd/parameters/force_vbus_valid;
  cat /sys/class/udc/*/state; ls /sys/bus/i2c/devices/ | grep 0025'
```

**B4a.1 pass:** boots with USB as before (the PHY keeps VBUS forced until a
Type-C driver speaks), `orientation-switch` and `port` listed, `N`,
`configured`, client `0-0025` present but unbound. **Fail** (no USB at
boot): the initramfs crash/slot A path, section 4 step 4.

```sh
# B4a.2 TCPM takes over (one re-enumeration of the link is expected)
tools/usbc-deadman b4a-tcpm
```

**B4a.2 pass:**

- dmesg: `usbdrd31 ... Type-C reported orientation 0, VBUS valid follows it
  from now on`, then the gadget reconnecting.
- `cat /sys/class/typec/port0/{power_role,data_role,power_operation_mode}`:
  `[sink]`, `host [device]`, `default` / `1.5A` / `3.0A`;
  `/sys/class/typec/port0-partner` exists.
- `/sys/class/power_supply/tcpm-source-psy-0-0025/online` 1, `current_max`
  0 (default power) or 1500000/3000000.
- `usbc-deadman-phone dump`: `USBSW_CTRL` 0x09. With the B3 charger loaded:
  mode 5 and input limit = `current_max`, or 500000 for default power.
- TCPM's own log: `cat /sys/kernel/debug/usb/tcpm-0-0025` (debugfs).

```sh
# B4a.3 the replug bug, now fixed in the kernel (rescue-watch NOT running)
tools/usbc-deadman replug       # unplug 5 s, replug; then again in the other orientation
```

**B4a.3 pass:** `CONFIRMED`; dmesg shows the detach (orientation 0, VBUS
valid dropped, gadget disconnect) and the attach (orientation 1 or 2). This
is the "USB doesn't reconnect after unplugging" fix for NOTES.md.

### B4b: dwc3 behind the role switch

```sh
$O/scripts/dtc/dtc -q -I dts -O dtb -o out/usbc-role-test.dtbo device/cheetah/overlays/usbc-role-test.dtso
$O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" out/usbc-tcpm-test.dtbo out/usbc-role-test.dtbo
KERNEL_DIR=~/android/mainline/wt-usbc KERNEL_OUT=$O bin/omamobile images > logs/images-usbc-b4b.log 2>&1
KERNEL_OUT=$O bin/omamobile push
tools/phone-ssh 'cat /sys/class/usb_role/*/role; cat /sys/class/udc/*/state'   # device, configured
tools/usbc-deadman b4b-role
tools/usbc-deadman replug
```

The UDC now appears from dwc3's role-switch work, slightly later; the
initramfs waits up to 30 s for it. **Pass:** as B4a, plus
`/sys/class/usb_role/11210000.usb-role-switch/role` = `device` after TCPM.

### After B4b: make it the default

Fold both overlays into `gs201-cheetah.dts` (that is also what upstream
wants: gs101 has the same graph), remove `tcpci_maxim` from the blacklist,
stop shipping the rescue watcher. Keep `force_vbus_valid` as the recovery
knob.

### B4c: host mode (design only)

- Needs VBUS sourcing. Stock uses the **external boost**
  (`max77759,ext-otg-only`): MAX77759 GPIO5 (`bst-on`) plus TCPC
  `EXTBST_CTRL` (0x92 bit 0), with the OVP input switch (GPIO6) toggled
  around it (`tcpci_max77759.c:754-778`, "b/309900468"). Upstream has only the
  charger's reverse boost (`chgin-otg-regulator`, mode 0xA); whether that
  path is usable on cheetah with the input switch is unknown. Candidate: a
  small regulator for the external boost in `tcpci_maxim` (EXTBST_CTRL)
  plus a `gpio` enable on MAX77759 GPIO5, as `vbus-supply`.
- Then the connector goes back to `power-role = "dual"`,
  `try-power-role = "sink"`, and the stock source PDO (5 V, 900 mA).
- Testing host mode unplugs the laptop, so the test must run detached:
  apply, wait for the keyboard/drive to enumerate, write `lsusb` to a file,
  `echo sink > /sys/class/typec/port0/port_type` after N seconds, then
  replug the laptop. Better with Wi-Fi (gate W3) as a second way in.
- USB PD (`pd-disable` off) and SuperSpeed (lane muxing by orientation,
  `maximum-speed`) are later steps.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Laptop port cuts VBUS when the charger draws more | 500 mA default (USB 2.0), capped at 900 mA in the driver; AICL in the chip; dead-man undo + rescue |
| Charging outside a safe temperature (no step charging) | attended tests only; CC 0.3 C; temperature guard before making it default |
| `tcpci_maxim` probe drops the link | sink-only port: no DRP toggling, so the laptop never sees Rp from us and the contaminant check (which runs only while toggling) never runs; the PHY keeps VBUS until TCPM reports; dead-man undo forces VBUS valid, unloads TCPM, closes the switch |
| Overlay DTB breaks USB at boot | nothing loads TCPM at boot (blacklist), PHY change keeps VBUS forced; worst case the initramfs crash -> slot A path |
| `dr_mode = "otg"` changes the boot path | separate gate (B4b), after B4a passed |
| Watchdog cannot be armed (in use) | the tool refuses; `--no-watchdog` falls back to a crash reboot |
| Something requests MAX77759 GPIO5/6 | nothing in the DT does; GPIO6 is the VBUS input switch: never drive it during bring-up |

## 9. Runbook 2026-10-19 (B3g to Type-C by default)

### Results 2026-10-19 (kernel 7.3.0-rc6-omamobile-push1-00558-gcbd727f42785)

- **P0/G0 passed** (read-only): charger mode 5, WDTEN 0, JEITA_EN 1
  (0xc1 = 0x05), no stale bring-up files in `/etc/modprobe.d`. The
  bootloader leaves fast charge at 1933 mA (sel 29), above stock's 1.47 A
  ceiling: the battery read 39.5 C at +1.9 A with no guard.
- **The B3.3 question:** TCPC `BC_STATUS1` (0x87) = 0x01, so BC1.2 says
  SDP (500 mA), while the battery took about 1.9 A. But `CC_STATUS` (0x1d)
  = 0x1c: CC2 shows Rp 3.0 A, so the source allows 3 A at 5 V under Type-C.
  Not a violation; the "SDP above 0.55 A: stop" rule below must also read
  the Rp level. K1 stays open (a port with Rp default current and SDP would
  still be over).
- **G1 passed** (dead-man `b3-charger --ilim 500000`, CONFIRMED):
  `probed: mode 0x5, float voltage 4450 mV, fast charge 1466730 uA, input
  limit 500000 uA`; guard on: `battery 29.2 C, 4401 mV: band 20-42 C, float
  4450 mV, charge 1466730 uA`; dump mode 5, CNFG_04 sel 45, CNFG_02 sel 22,
  CHG_DTLS 2.
- **G2 passed:** gauge unloaded: `no reading from max170xx_battery: charging
  inhibited`, mode 4, CHG_DTLS 8, charger `online` 1, USB unaffected; gauge
  reloaded: a band line and mode 5 within 60 s. `omamobile-charge-guard
  status` crashed without a gauge (fixed in device-cheetah 0.1.32).
- **D1 passed** (device-cheetah 0.1.33, reboot): `found: mode 0x5, float
  voltage 4350 mV, fast charge 1933420 uA`, `temperature guard on`,
  `probed: mode 0x5, float voltage 4450 mV, fast charge 1466730 uA, input
  limit 500000 uA`, then `battery 30.2 C, 4324 mV: band 20-42 C` with no
  "no reading" (the softdep works); dump mode 5, sel 45/22, CHG_DTLS 2;
  USB, SSH and `omamobile-usb-rescue` as before.
- **D1 replug passed** (2026-10-19, charger and guard loaded at boot): with
  the phone booted, unplugged for about 15 s and plugged back in,
  `omamobile-usb-rescue: VBUS valid, USBSW_CTRL 0x00: closing the data
  switch` at 48.9 s, `usb0` carrier back 0.35 s later, USBSW_CTRL 0x09,
  charger mode 5, CHG_DTLS 2, no inhibit. (A cold boot with the cable
  plugged in within the first seconds also came up normally; that one
  never needs the rescue.)

### Status as written for this runbook (2026-10-18)

Status (2026-10-18): **charging runs on the bootloader's settings; the
kernel driver and the temperature guard are built and on the phone, not yet
used.** The phone runs `omamobile-int` @ `cbd727f42`
(`7.3.0-rc6-omamobile-push1-00558-gcbd727f42785`). It contains everything
B3g, B4a and B4b need:

- `omamobile-usbc` @ `c86bd2db7` (charger `default_ilim_ua`, the tcpci_maxim
  data switch on attach, the PHY's `force_vbus_valid`, the battery limits
  and sink-only connector in the DTS);
- `omamobile-chgguard` @ `37a83337c` (`temp_guard`, default off);
- `omamobile-battery` @ `de0aa4d4e` (the gauge works out Charging from its
  current when no supplier is described: the stopgap from NOTES 2026-10-18).

All three are ancestors of `omamobile-int`. In `out-int`, `max77759_charger.ko`
has the `default_ilim_ua`, `temp_guard` and `guard_psy` parameters, the PHY
has `force_vbus_valid`, and `tcpm`, `tcpci` and `tcpci_maxim` are built as
modules (from arm64 defconfig). The B4a and B4b overlays apply cleanly with
fdtoverlay to today's `out-int/images/cheetah-overlaid.dtb` (checked
offline, in a scratch directory). **No kernel build is needed before
B4b.** Userspace: device-cheetah 0.1.31 (`omamobile-charge-guard`;
`omamobile-charger.conf` with its option commented out; `max77759`,
`max77759_charger`, `tcpci_maxim`, `gpio_max77759` and `nvmem_max77759`
blacklisted; `omamobile-usb-rescue.service` enabled), plus
`tools/usbc-deadman` and `usbc-deadman-phone` (R0 drill and R1 passed
2026-10-12).

Gates passed: R0, R1, B3.0, B3.1 (on the old `out-usbc` kernel), B3.2,
B3.3 (2026-10-12: 500 mA, 4450 mV, 93 to 96 % in 10 min). **Next:** P0,
then B3g (G0 read-only first), then D1 (charger and guard on by default),
then B4a, B4b, D2 to D4.

**Do not push `out-usbc` again.** It is a 7-day-old branch kernel without the
camera, audio, AoC, fingerprint and battery-model work. Every step below
uses the integration build (`O=~/android/mainline/out-int`), and only B4a.1
and B4b.1 change the images (DTB only, same kernel and modules).

---

### Findings this runbook rests on (new since 2026-10-12)

| Finding | Evidence |
|---|---|
| The charger's regmap is cached (`REGCACHE_FLAT`). Only 0xb0-0xb1 and 0xb4-0xb8 are volatile. sysfs `constant_charge_voltage_max`, `constant_charge_current_max` and `input_current_limit` show what the driver wrote, not what the chip holds. Verify hardware with `i2cget` (the dump) only | `drivers/mfd/max77759.c` `max77759_regmap_config_charger` |
| The guard's `CHG_CNFG_02`/`CHG_CNFG_04` writes don't unlock CHGPROT. Google's driver writes the same two registers without unlocking, so they are not protected registers. Still, G3/G4 must read the chip back to prove it | `max77759_charger.c` `set_*_limit()`; Google `max77759_charger.c:1394,1464` (`max77759_reg_update`, no `chg_prot`) |
| While the guard holds charging off (mode 4), the **charger's `status` reads Discharging**, not "Not charging". `CHG_DTLS` is 8 (off), which the driver maps to DISCHARGING. `online` stays 1 (VBUS valid, software mode CHG_BUCK_ON) | `get_status()`, `get_online()` |
| The guard's current is rounded **up** to the next charger step (`linear_range_get_selector_high_array`). It matters only below the 1.47 A cap: 0-10 °C at 4.2-4.3 V asks for 10 % = 493 mA and gets 533 mA (sel 8). That is 8 % over stock's table, in the cold band only. Follow-up: round down | `set_fast_charge_current_limit()` |
| The guard is a delayed work item, so **it doesn't run in s2idle**. A sleeping phone keeps the last float voltage and current until it wakes, then the overdue work runs at once. The backstop is the charger's own JEITA (`CHG_CNFG_08` bit 2, POR default 0x05 = on). G0 reads it | Google `max77759_A1_regs.h:1954-1963` |
| **Open question B3.3, likely answer:** the upstream driver never sets `CHG_CNFG_09.NO_AUTOIBUS`, so the chip's own charger-type detection (BC1.2) can raise the effective input limit above the 500 mA in the register (SDP 500 mA, CDP/DCP 1.5 A). Google's driver always sets NO_AUTOIBUS=1 together with the limit. A CDP laptop port (1.5 A) explains 1.02 A into the battery at 500 mA "input" (B3.3), and +1.9 A on the bootloader's 1933 mA charge current (NOTES 2026-10-18). G0 reads the detection result: TCPC vendor `BC_STATUS1` 0x87, `CHGTYP` bits 1:0 (1 SDP, 2 CDP, 3 DCP), and `CC_STATUS` 0x1d (Rp level) | Google `max77759_charger.c:1500-1525`, `bc_max77759.h:33-42` |
| **Gauge and charger are not linked.** The charger registers its power supply with no `supplied_to`, and `fuel-gauge@36` has no `power-supplies`. Loading the charger therefore changes nothing for the gauge: `power_supply_am_i_supplied()` keeps returning -ENODEV, and `de0aa4d4e`'s path (status from the current's sign) stays in use | `max77759_charger_probe()`; cheetah DTS; `power_supply_am_i_supplied()` |
| Adding `power-supplies = <&pmic66>` to the gauge would link them: the charger's power supply takes pmic@66's fwnode (`device_set_of_node_from_dev`). But `power_supply_check_supplies()` then returns **-EPROBE_DEFER until the charger has registered**, so with the charger blacklisted the battery would disappear. Add the link only with or after D1, never before | `power_supply_core.c` `power_supply_check_supplies()`, `__power_supply_register()` |
| `bin/omamobile images` applies `DTB_OVERLAYS` from `device/cheetah/device.conf` (no environment override) into `$O/images`, after `rm -rf $O/images/*`. The plan's old `cp $D $D.default` / fdtoverlay-into-the-kernel-DTB steps are obsolete | `bin/omamobile` `cmd_images()` |

---

### P0: preflight (read-only, no risk)

```sh
tools/phone-ssh 'uname -r; pacman -Q omamobile-device-cheetah; lsmod | grep -E "^(max77759|max17042|tcpci|tcpm|gpio_max77759)" ;
  systemctl is-active omamobile-usb-rescue; ls /etc/modprobe.d/; modinfo -F parm max77759_charger | cut -c1-40;
  cat /sys/module/phy_exynos5_usbdrd/parameters/force_vbus_valid'
tools/usbc-deadman install
```

**Pass:** release `...-00558-gcbd727f42785`; device-cheetah 0.1.31; only
`max17042_battery` loaded; rescue `active`; **no `omamobile-max77759.conf`,
`omamobile-charger.conf` or other hand-copied bring-up file in
`/etc/modprobe.d`** (it would shadow the package's file, AGENTS §2); three
charger parameters; `force_vbus_valid` N. **Stop** on any difference.

---

### B3g: the temperature guard

Safety net for G1 to G5: the charger is loaded with `tools/usbc-deadman b3-charger`
(watchdog, kmsg stream to `logs/`, undo unless a fresh SSH login confirms).
B3.3 proved that the charger doesn't touch the USB data path. Battery 30 to
80 %, phone at room temperature, cable in the laptop's usual port. Second
terminal: `tools/phone-ssh dmesg -w`.

### G0: read-only (risk: none)

```sh
tools/usbc-deadman dump > logs/b3g-g0-dump.txt; cat logs/b3g-g0-dump.txt
tools/phone-ssh 'B=$(for d in /sys/bus/i2c/devices/i2c-*; do readlink -f $d | grep -q 10d60000.i2c && echo ${d##*-}; done)
  for r in 0xb4 0xb5 0xb6 0xb7 0xc1 0xc2; do echo "chg $r $(i2cget -f -y $B 0x69 $r)"; done
  for r in 0x1d 0x1e 0x87 0x88; do echo "tcpc $r $(i2cget -f -y $B 0x25 $r)"; done'
tools/phone-ssh 'cd /sys/class/power_supply/max170xx_battery; cat temp current_now status; sleep 60; cat temp current_now'
```

Record:

- `0xc1` CHG_CNFG_08: **bit 2 JEITA_EN** (expect 1, POR default 0x05).
- `0xc2` CHG_CNFG_09: bit 7 NO_AUTOIBUS (B3.0: 0) and the ILIM selector.
- `tcpc 0x87` BC_STATUS1: **CHGTYP = bits 1:0** (1 SDP, 2 CDP, 3 DCP), bit 6
  CHGTYPRUN. `tcpc 0x1d` CC_STATUS: CC1 bits 1:0, CC2 bits 3:2 (as sink:
  1 default, 2 1.5 A, 3 3.0 A Rp).
- `0xb4` CHG_INT_OK: bit 7 AICL_OK, bit 2 INLIM_OK (0 = input-limited now).
- Gauge `temp` (0.1 °C): plausible and moving; `current_now` sign.

**Pass:** mode 5, WDTEN 0, JEITA_EN 1, a moving temperature. **Stop** if JEITA_EN
is 0: the guard is then the only temperature policy and blind in suspend, so
D1 needs a JEITA-on write first (a follow-up decision). **Closes the B3.3 open
question:** CHGTYP 2/3 with ILIM sel 19 means the extra current is BC1.2's
legitimate 1.5 A. CHGTYP 1 (SDP) with more than ~0.55 A into the battery
means the chip draws more than an SDP allows: **stop**, and add NO_AUTOIBUS
handling to the driver before D1 (section "To build", item K1).

### G1: guard on at normal temperature (risk: low)

```sh
tools/usbc-deadman b3-charger --ilim 500000          # B3.3 again: expect CONFIRMED
tools/phone-ssh 'omamobile-charge-guard on; sleep 35; omamobile-charge-guard status'
tools/usbc-deadman dump | grep -E 'CNFG_0[0249]|DTLS'
```

**Pass:** dmesg `found: mode 0x5, float voltage 4350 mV...` and then
`probed: mode 0x5, float voltage 4450 mV, fast charge 1466730 uA, input limit 500000 uA`;
`temperature guard on (max170xx_battery)`; then
`battery 2x.x C, 4xxx mV: band 20-42 C, float 4450 mV, charge 1466730 uA`
(10-20 band in a cold room: same numbers, capped). Dump: mode 5, CNFG_04
sel 45, CNFG_02 sel 22, CHG_DTLS 1 or 2. Gauge `status` Charging (still
the stopgap path). **Stop** on a missing band line, on mode 4 at room
temperature, or on "no reading". **Rollback:** `tools/usbc-deadman undo b3-charger`
(unloads, writes back the bootloader's 0xbb/0xbd/0xc2/0xb9).

### G2: simulated read failure (risk: low; tell the human first: the battery icon disappears for about a minute)

```sh
tools/phone-ssh 'modprobe -r max17042_battery; sleep 35; omamobile-charge-guard status'
tools/usbc-deadman dump | grep -E 'CNFG_00|DTLS'
tools/phone-ssh 'modprobe max17042_battery; sleep 65; omamobile-charge-guard status'
```

**Pass:** `no reading from max170xx_battery: charging inhibited`; dump mode
**4**, CHG_DTLS 8; charger `status` **Discharging** (not "Not charging", see
findings), `online` 1; USB unaffected. After the reload: within 60 s a
band line again, mode 5. **Stop** if the mode stays 5 while inhibited (the
guard doesn't reach the chip), or if the gauge doesn't come back (its model
loads only on POR, so a reload must just read). **Rollback:**
`modprobe max17042_battery`, `omamobile-charge-guard off`.

### G3: hot bands (attended, optional; risk: medium, the battery is warmed on purpose)

As in the plan (GPU load, full brightness, **stop the load at 50 °C**).
Every minute: `omamobile-charge-guard status` and
`tools/usbc-deadman dump | grep -E 'CNFG_0[024]|DTLS|DETAILS_00'`.
**Pass, read back from the chip:** 42-46 °C CNFG_04 sel 45 and CNFG_02 sel 22;
46-48 °C **sel 30 (4300 mV)**; 48-55 °C **sel 20 (4200 mV)**, and CNFG_02 sel 22
(30 % = 1478 mA, capped at 1467). Cooling: each band returns only 2 °C
inside it. **Stop and rollback:** `omamobile-charge-guard off` or undo
b3-charger; end the load.

### G4: cold bands (attended, optional; risk: low)

As in the plan. Pass, from the chip: below 10 °C CNFG_04 sel 30. CNFG_02 is
sel 22 below 4.2 V (30 % capped), **sel 8 (533 mA)** from 4.2 V (10 %,
rounded up, see findings). Below 0 °C: mode 4.

### G5: soak (attended; risk: low)

A full charge from below 50 % with the guard on, charger loaded as in G1.
**Pass:** CV near 4.45 V, CHG_DTLS 3/4, capacity 100 %; the only guard
messages are band and tier lines (`journalctl -k | grep max77759-charger`).
Watch the gauge `status` at the end: with no supplier link it goes Full only
when the current reads exactly 0. Otherwise it reads Discharging at 100 %
while plugged in. Note what upower and the bar show (feeds D4c).

### G6: sleep while charging (attended; risk: low; announce: the phone sleeps)

With the charger loaded and the guard on, cable in, ufw/Wi-Fi as usual:
`tools/phone-ssh 'rtcwake -m no -s 60; systemctl suspend'` (as in the NOTES
2026-10-18 reproduction; the RTC wake needs the suspend kernel's RTC). After
the wake: `omamobile-charge-guard status` shows a fresh band line within 30 s,
and the dump shows mode 5. **Pass:** no "no reading" and no stuck mode 4
after resume. **Stop:** an inhibited charger after resume, or USB not back
(`omamobile-usb-rescue` should handle it as after any replug).

**B3g pass:** G0, G1, G2, G5, G6 (and G3/G4 as far as is safe).

---

### D1: charger and guard on by default (package; one reboot; risk: medium-low)

Package change (not written yet, see "To build" P1), device-cheetah
0.1.32:

- `omamobile-max77759.conf`: drop `blacklist max77759` and
  `blacklist max77759_charger`. Keep `tcpci_maxim`, `gpio_max77759` and
  `nvmem_max77759` blacklisted.
- `omamobile-charger.conf`:
  `options max77759_charger default_ilim_ua=500000 temp_guard=1` **and**
  `softdep max77759_charger pre: max17042_battery`. Without the softdep the
  charger can probe before the gauge, and the guard's first read fails
  ("no reading", 30 s inhibited, a warning every boot). Without
  `default_ilim_ua` the upstream driver turns charging **off** at probe
  (no tcpm-source), which the old commented line alone would have done.
- `test/all`: the two B3g checks flip. Require the option line with both
  parameters whenever the charger is not blacklisted, and never one without
  the other.

```sh
tools/phone-install-package packages/omamobile-device-cheetah   # human's go
tools/phone-ssh 'ls /etc/modprobe.d/; modprobe -c | grep -E "max77759_charger|blacklist max77759"'
# reboot: human's go
tools/phone-ssh 'reboot-to omamobile'
tools/phone-ssh 'journalctl -k -b -o cat | grep -E "max77759|max1704"; omamobile-charge-guard status; systemctl is-active omamobile-usb-rescue'
tools/usbc-deadman dump
```

**Pass:** at boot `found: mode 0x5, float voltage 4350 mV` then `probed: ... 4450 mV,
1466730 uA, 500000 uA`, `temperature guard on`, a band line within 30 s;
dump mode 5, sel 45/22; USB and SSH as before; rescue still active. Also
boot once **without the cable** (Wi-Fi SSH or the screen), then plug in:
charging starts (CHG_DTLS 1/2) and USB comes up through the rescue
service. **Stop:** no USB after boot (not expected: B3.3 showed that the
charger doesn't touch data), mode 4 at room temperature, or any
`Battery over-current`. **Rollback:** `pacman -U` the 0.1.31 package (in
`/var/cache/pacman/pkg` or `out/repo`), reboot. Quick off switch without a
package: `echo 'blacklist max77759_charger' > /etc/modprobe.d/omamobile-charger-off.conf`,
reboot (remove the file afterwards: AGENTS §2). The bootloader's settings
then apply again (4350 mV, no guard).

---

### B4a: TCPM drives VBUS valid and the data switch

Wi-Fi is up at boot since W3/W4. Have a **Wi-Fi SSH session open as a
second way in** (it must not be used to confirm the dead-man: the confirm
must prove USB, so `tools/usbc-deadman` uses `tools/phone-ssh` on
172.16.42.1 only).

### B4a.1: DTB with the overlay (one reboot; risk: medium)

```sh
O=~/android/mainline/out-int
cp -a $O/images $O/images.int-good                 # the known-good images, for rollback
# local edit, do not commit yet: append usbc-tcpm-test to DTB_OVERLAYS in device/cheetah/device.conf
KERNEL_DIR=~/android/mainline/wt-int KERNEL_OUT=$O bin/omamobile images > logs/images-int-b4a.log 2>&1
cp -a $O/images $O/images.b4a
KERNEL_OUT=$O bin/omamobile push                    # human's go; same kernel, no modules push
tools/phone-ssh 'ls /proc/device-tree/soc@0/phy@11200000/; cat /sys/module/phy_exynos5_usbdrd/parameters/force_vbus_valid;
  cat /sys/class/udc/*/state; ls /sys/bus/i2c/devices/ | grep 0025; ls /sys/bus/i2c/devices/*-0025/driver 2>&1'
```

`$O/images` belongs to the integration build. Back it up as above (or ask
the human to copy out-int first). **Pass:** boots with USB as before,
`orientation-switch` and `port` present, `N`, `configured`, `0-0025` present
and unbound. **Stop/rollback (no USB at boot):** the initramfs crashes
after 45 s, then slot A boots after ABL's retries (section 4 step 4). Then
`adb reboot bootloader` and `bin/omamobile flash` with `$O/images.int-good`.
**After any slot A boot, take a fresh read-only backup of efs, persist and
modem_userdata before more radio work (AGENTS §1).**

### B4a.2: TCPM takes over (risk: high, dead-man)

```sh
tools/phone-ssh 'systemctl stop omamobile-usb-rescue'    # TCPM owns the switch now; undo runs a rescue anyway
tools/usbc-deadman b4a-tcpm
tools/phone-ssh 'cat /sys/class/typec/port0/{power_role,data_role,power_operation_mode}; ls /sys/class/typec/;
  grep -H . /sys/class/power_supply/tcpm-source-psy-0-0025/{online,current_max,usb_type} 2>/dev/null;
  cat /sys/kernel/debug/usb/tcpm-0-0025 | tail -40'
tools/usbc-deadman dump
```

**Pass:** as in the plan (`Type-C reported orientation`, `[sink]`,
`host [device]`, partner present, `USBSW_CTRL` 0x09). With D1 in place:
mode 5, ILIM = `current_max`, or 500 mA for default power, and the guard
still reporting. Note `power_operation_mode` together with G0's CC_STATUS
(they must agree). **Stop:** not CONFIRMED (the tool reverts: force VBUS,
unload TCPM, rescue). **Rollback after a confirm:** `tools/usbc-deadman undo b4a-tcpm`,
then `systemctl start omamobile-usb-rescue`.

### B4a.3: replug, both orientations (risk: high, dead-man; the human replugs)

```sh
tools/usbc-deadman replug        # unplug 5 s, replug; then again with the plug turned over
```

**Pass:** CONFIRMED both times; dmesg shows detach (VBUS valid dropped,
gadget disconnect, charger `mode` OFF from psy_work) and attach (orientation
1 or 2, charger back to mode 5, guard line unchanged). **Stop/rollback:** as
B4a.2; the replug undo forces VBUS, unloads TCPM and closes the switch.

---

### B4b: dwc3 behind the role switch

### B4b.1: DTB with both overlays (one reboot; risk: high, the boot path changes)

```sh
# device.conf: DTB_OVERLAYS ... usbc-tcpm-test usbc-role-test (local edit)
KERNEL_DIR=~/android/mainline/wt-int KERNEL_OUT=$O bin/omamobile images > logs/images-int-b4b.log 2>&1
cp -a $O/images $O/images.b4b
KERNEL_OUT=$O bin/omamobile push                    # human's go
tools/phone-ssh 'cat /sys/class/usb_role/*/role; cat /sys/class/udc/*/state; journalctl -b -o cat | grep -i -E "udc|gadget" | head'
```

**Pass:** `device`, `configured`; the initramfs found its UDC (it waits
30 s). **Stop/rollback:** same as B4a.1, with `images.b4a` or
`images.int-good`.

### B4b.2 and B4b.3 (risk: high, dead-man)

```sh
tools/phone-ssh 'systemctl stop omamobile-usb-rescue'
tools/usbc-deadman b4b-role
tools/phone-ssh 'cat /sys/class/usb_role/11210000.usb-role-switch/role'    # device
tools/usbc-deadman replug          # both orientations
```

**Pass:** as B4a, plus role `device` after TCPM, and no second UDC
re-registration loop in dmesg. Rollback as B4a.2.

---

### D2: Type-C by default, through a guarded loader (one reboot; risk: high)

Not just an un-blacklist. A TCPM that kills USB at boot has no dead-man,
and the initramfs crash path doesn't help once userspace is up. Ship the
loader the way Wi-Fi ships (`omamobile-wifi-start`). See "To build" P2:

- `tcpci_maxim` stays blacklisted. `omamobile-typec.service` (After=
  `omamobile-usb-rescue`) runs `omamobile-typec-start`. If
  `/var/lib/omamobile/typec-failed` exists, it does nothing. If VBUS is
  valid and the UDC is `configured`, it loads `tcpci_maxim` and waits 60 s
  for `configured` again (one re-enumeration is expected). Without it, it
  unloads `tcpci_maxim tcpci tcpm`, sets `force_vbus_valid=1`, writes
  `USBSW_CTRL=0x09`, records `typec-failed`, and logs to kmsg. With no VBUS
  at start (on battery), it loads TCPM and keeps watching.
- `omamobile-usb-rescue` no longer exits when a Type-C driver owns the chip.
  It becomes the watchdog for D2/D3: VBUS valid for 30 s with the UDC not
  `configured` triggers the same fallback as above.
- DTB: `usbc-tcpm-test usbc-role-test` stay in `DTB_OVERLAYS` (committed
  now, with the B4 results).

```sh
tools/phone-install-package packages/omamobile-device-cheetah    # human's go
tools/phone-ssh 'reboot-to omamobile'                              # human's go
tools/phone-ssh 'systemctl status omamobile-typec --no-pager; ls /sys/class/typec; cat /sys/class/udc/*/state'
```

**Pass:** port0 + partner, `configured`, no `typec-failed`. **Stop/rollback:**
the loader undoes itself (that is its job). By hand:
`touch /var/lib/omamobile/typec-failed`, reboot; or the previous package.

### D3: cold plug and the replug soak (risk: medium; the human plugs)

1. Boot with the cable **out** (start the reboot over Wi-Fi SSH, unplug
   while the logo shows). Plug in after the lock screen: USB comes up,
   the charger goes to mode 5.
2. Ten replugs over a day, both orientations, laptop port and a wall
   charger: USB back each time (laptop), charging each time.
   `journalctl | grep omamobile-usb-rescue` shows **no** fallback action.
3. A wall charger with Rp 1.5/3.0 A: ILIM follows `current_max` (up to
   3.0 A), and the guard still caps the battery side at 1.47 A.

### D4: retire the bring-up pieces (packages + kernel; risk: low to medium)

- (a) After D3 passes: drop the rescue service's fallback, or keep it
  as a passive logger for one release. Remove
  `blacklist tcpci_maxim` and the loader only when the loader has never
  fired in D3.
- (b) Kernel: fold both overlays into `gs201-cheetah.dts` (TCPC `okay`,
  graph to the PHY and dwc3, `dr_mode = "otg"`, role switch); remove them
  from `DTB_OVERLAYS` in the same release (one boot to check).
- (c) Optional, one boot: the gauge's supplier link
  (`power-supplies = <&pmic66>` on `fuel-gauge@36`, label on `pmic@66`).
  Only once the charger loads by default: the gauge then waits for the
  charger, and **rolling the charger back to blacklisted also needs this
  line removed**, or the battery disappears. Gain: Full at end of charge
  even with a few mA of noise, Discharging the moment the cable comes out,
  and immediate uevents on plug/unplug (the charger's IRQ propagates to the
  battery through `external_power_changed`).

---

### K1b: a NO_AUTOIBUS left set stops charging (2026-11-15, offline; no write run yet)

**The report.** A community 7 Pro on issue #169 that booted from an empty
battery read `CHG_CNFG_09` (0xc2) = `0x93`: the 500 mA limit (sel 19) with
`NO_AUTOIBUS` (bit 7) set. The battery current sat between -145 and +26 mA
on the cable; `i2cset -f -y 5 0x69 0xc2 0x13` took it to +1.41 A within a
second. A second 7 Pro on the same issue (2026-11-16) read `0x93` after a
boot from flat: -223 mA with the screen on, about +250 mA with it off, and
+1.41 A five seconds after the same write; a reboot from 88 % then read
`0x13`. A user in the community chat reports the same symptom twice ("won't
take a charge"), with no register read yet. Every read on record has the
bit clear: B3.0, the two `usbc-deadman dump`s in `logs/`, the Pixel 6 Pro's
C2, the reporter's other sessions, and the reference phone on 2026-11-15
(`7.3.0-rc6-omamobile-gda171eae4cb7`, `0x13` at 98 %). Clear is also the
power-on value (0x13 in Google's register header).

**Why.** With no Type-C driver, the charger raises its input current above
`default_ilim_ua` only by itself, following the Rp the source advertises
(#169's readings: Rp 3.0 A gives +1.42 A, Rp default about 0 net), and
`NO_AUTOIBUS` turns that off. Nothing in the driver touched the bit, so
whatever was left in the chip stayed. Who sets it isn't known. Most likely
the bootloader: both instances were boots from an empty battery, when ABL
charges before Linux. It isn't every such boot: the second phone booted flat
on 11-12 and 11-13 and took +1.41 A with no write (register not read), and
a third 7 Pro read `0x13` on flat boots on 11-15 and 11-17 (#169). Another candidate is stock: Google's driver writes
`NO_AUTOIBUS` = 1 with every input limit (it programs the limit from its
USB-PD stack, which we don't have), so a warm reboot from slot A could carry
it over if the bit survives a reboot, which K1b.4 finds out.

**The fix**, linux-omarchy-mobile#261, `omamobile-charger-autoibus` (one
commit on `github/omamobile` @ `d49d68c764d4`):
`max77759_charger_start_default()` clears `NO_AUTOIBUS` after setting the
default limit (a failure is a warning, not a failed probe), and the `found:`
and `probed:` lines end in `(NO_AUTOIBUS set)` while it is set.
`psy_work_item()` doesn't touch the bit; probe clears it on any phone with
`default_ilim_ua` set (the 7 Pro, the Pixel 6 Pro, and the Pixel 7 once
#259 lands), with or without TCPM, though no phone has both today. On a
boot with the bit already clear the regmap cache skips the write, so
nothing changes on the bus. checkpatch `--strict` and `W=1` clean,
`tools/kernel-pr-check --merge` passes all but the human sign-off.

This picks the side of K1 that every read on record has run on (bit clear,
the input following Rp); it doesn't add the SDP cap K1 describes.

**A trap for the test.** The charger regmap is `REGCACHE_FLAT` with no
`reg_defaults_raw`, filled from the hardware when the MFD probes, and 0xc2
isn't volatile. A bit set later by `i2cset` is not in the cache, so
`regmap_update_bits()` sees it clear and writes nothing: rebinding the
charger after an `i2cset` would show the fix failing. The bit has to be in
the hardware before the MFD probes, that is, across a reboot. Whether a
warm reboot keeps it (or ABL rewrites 0xc2) is not known; K1b.4 finds out.

**Setup.** The phone on the laptop's USB-C port: the dead-man tool and every
check here need the USB link (`tools/usbc-deadman` stops at "phone not
reachable at 172.16.42.1"), so a wall charger alone won't do. The source
has to advertise Rp 1.5 A or 3.0 A, or the bit makes no difference (#169:
at Rp default the current is about 0 net either way) and K1b.1 can't fail.
G0 on 2026-10-19 read Rp 3.0 A on this port; K1b.0 checks it again. If it
reads default, a USB-C PD hub between the laptop and a wall charger that
passes data is the next thing to try. The battery below 90 %, so it charges
at constant current, screen on, the modem stopped for K1b.1 to K1b.4
(`systemctl stop omamobile-modem`; with it up, a dead-man watchdog reset
would use the modem's one allowed unclean end, AGENTS.md section 2), and
before K1b.3's push `systemctl mask omamobile-modem-boot.target`, so the
test kernel's boots come up without it (unmask it at the end). The mask
goes in before the push because the 7 Pro starts the modem at boot, and
masking the target stops nothing a boot has already started.

Every write to the MAX77759 runs under the dead-man switch (section 4): the
chip also owns the USB data switch, and USB is the only link.
`tools/usbc-deadman` has two steps for this, `k1b-autoibus-on` and
`k1b-autoibus-off`. Each reads 0xc2 once, refuses (nothing written) if the
read fails, keeps that value in its own `/run/usbc-deadman/<step>.saved`,
changes only bit 7 and reads it back. It is confirmed over a fresh SSH login
(`--fresh`) or undone by the phone (its own saved value written back, the
data switch closed if VBUS is there), with the watchdog behind that.
`tools/usbc-deadman undo <step>` restores what was there before that step,
whatever ran since. `tools/usbc-deadman dump` is the read-only view (its
CNFG_09 line shows NO_AUTOIBUS; TCPC 0x1d is CC_STATUS).

**K1b.0, read-only (risk: none).**

    tools/nv-backup --check <the off-repo backup>    # AGENTS.md section 1, before PMIC work
    tools/phone-ssh 'uname -r; journalctl -k -b | grep -E "max77759-charger.*(found|probed)"'
    tools/usbc-deadman dump
    tools/phone-ssh 'for i in $(seq 10); do cat /sys/class/power_supply/max170xx_battery/current_now; sleep 1; done'

**Expect** CNFG_09 sel 19 with `NO_AUTOIBUS 0`, CNFG_00 mode 5, the battery
about +1.4 A (µA in sysfs), and CC_STATUS (0x1d) with the attached CC at 2
(Rp 1.5 A) or 3 (Rp 3.0 A): CC1 is bits 1:0, CC2 bits 3:2. **Stop** if the
NV check fails, the mode isn't 5, the battery is above 42 C, or the CC
reads 1 (Rp default): change the setup first.

**K1b.1, the symptom on the release kernel (risk: low; one charger config
bit, under the dead-man; tell the human first: charging stops for a few
minutes).** The modem stopped (Setup).

    tools/usbc-deadman k1b-autoibus-on
    tools/phone-ssh --fresh 'for i in $(seq 30); do cat /sys/class/power_supply/max170xx_battery/current_now; sleep 2; done'

**Expect** exit 0 ("CONFIRMED"), the dump's CNFG_09 line `NO_AUTOIBUS 1`.
**Pass:** the current falls to about 0 (below +300 mA) within seconds,
which reproduces the report on our phone. **Stop** if the tool exits
non-zero (3 undone, 4 no answer: follow its recovery text; 5 refused or 6
failed: nothing stayed applied), the mode isn't 5, or USB drops.
**Rollback:** K1b.2, with the dump's `NO_AUTOIBUS 0` as its check. (`undo
k1b-autoibus-on` also works after one run of the step; a second run in the
same boot saves the bit-set value, and the undo then leaves the bit set.) A
reboot may end it too (K1b.4's question).

**K1b.2, back to normal (risk: low; under the dead-man).**
`tools/usbc-deadman k1b-autoibus-off`; expect exit 0, `NO_AUTOIBUS 0`,
+1.4 A within seconds. If the phone undoes this step it writes back the
bit-set value it found: charging stays at the 500 mA limit and USB is not
affected; run the step again, or `undo k1b-autoibus-on`. **Stop** as in
K1b.1.

**K1b.3, the test kernel (risk: medium, a push and a reboot).** With
`KERNEL_DIR=~/omamobile-kernel/wt-charger-autoibus
KERNEL_OUT=~/omamobile-kernel/out-charger-autoibus` set, build the whole set
offline first: `bin/omamobile kernel`, `initramfs`, `images` (cheetah, the
default device) and `modules`. Then, on the phone, `systemctl mask
omamobile-modem-boot.target` and `systemctl stop omamobile-modem` (already
stopped since K1b.1: `systemctl is-active omamobile-modem` reads
`inactive`), and only then `bin/omamobile push`. The test kernel boots
without the modem (Setup). After boot, K1b.0 again:
`systemctl is-active omamobile-modem` reads `inactive`,
`uname -r` reads the test release, `probed:` has no `(NO_AUTOIBUS set)`,
CNFG_09 `NO_AUTOIBUS 0`, current as before, `tools/phone-smoke` passes.
**Stop** if any of those fail. **Rollback:** the same `push` with
`KERNEL_OUT=~/omamobile-kernel/out-k1115rel` (the release kernel, its set
complete).

**K1b.4, the fix itself (risk: low; the bit set under the dead-man, then a
warm reboot).** First `systemctl is-active omamobile-modem` reads
`inactive`: **stop** if it doesn't, the watchdog must not be armed with the
modem up. Then `tools/usbc-deadman k1b-autoibus-on`, check that charging
stops as in K1b.1, then `systemctl reboot`. **Stop** before the reboot if
the step didn't confirm. After boot:

    tools/phone-ssh 'journalctl -k -b | grep -E "max77759-charger.*(found|probed)"'
    tools/usbc-deadman dump

**Pass:** `found: … (NO_AUTOIBUS set)`, then `probed:` without it, CNFG_09
`NO_AUTOIBUS 0` and +1.4 A. If `found:` doesn't show it, the bit didn't
survive the warm reboot (or ABL rewrote it): record which, and the fix
stays proven only by a boot from an empty battery (K1b.5). **Stop** if
`probed:` still shows it. **Rollback:** `tools/usbc-deadman
k1b-autoibus-off` (K1b.2) puts the bit back to clear on any kernel; the
kernel itself as in K1b.3. At the end, `systemctl unmask
omamobile-modem-boot.target`.

**K1b.5, the field case (whenever a battery runs flat).** Boot from empty
on the cable and read the two probe lines: `found: … (NO_AUTOIBUS set)`
then a clean `probed:` closes it, and tells us ABL sets the bit. A flat boot
whose `found:` line has no suffix is no result: not every flat boot sets the
bit (#169).

---

### What the battery reports, and what upower sees, in each state

| State | Gauge `status` | Line power in upower | `on-battery` |
|---|---|---|---|
| Today (no charger driver; `de0aa4d4e`) | from the current: Charging if >0, Full only at exactly 0 with FullCAP≈RepCap, else Discharging | none | follows the battery state: no while Charging |
| D1 (charger bound, no link) | same as today (am_i_supplied still -ENODEV) | `max77759-charger` (type USB), `online` = VBUS valid and software mode CHG_BUCK_ON | no whenever plugged in, even while the guard holds charging off |
| Guard inhibiting (mode 4) | Discharging (current about 0 or slightly negative); charger `status` Discharging too | online 1 | no |
| B4a+ unplugged | Discharging (current <0) | `max77759-charger` 0, `tcpm-source-psy-0-0025` 0 | yes |
| D4c (link added) | Discharging at once when the charger is offline; Full when FullCAP≈RepCap while supplied; else from the current | as above | as above |

Residual risk: at a critical level with the guard inhibiting, the battery
reads Discharging, and upower's critical action could suspend a plugged-in
phone, as on 2026-10-18. That needs both a hot or cold battery and about
2 %. A later gauge change could report Not charging when supplied with no
current flowing.

---

### To build

| Item | Where | State |
|---|---|---|
| Kernel for B3g/B4a/B4b | `omamobile-int` @ `cbd727f42` | **done, running** |
| Overlays B4a/B4b | `device/cheetah/overlays/usbc-{tcpm,role}-test.dtso` | done; apply to today's overlaid DTB (checked) |
| P1: device-cheetah 0.1.32 (D1) | blacklist, options, softdep, test flip | **to write** |
| P2: `omamobile-typec-start` + unit, rescue as fallback watcher (D2) | device-cheetah | **to write** |
| K1 (only if G0 shows SDP above 500 mA): set `NO_AUTOIBUS` with the limit, as Google does | `max77759_charger.c` `set_input_current_limit()` | to write if needed; changes the charge rate on CDP ports (1.5 A to 0.5 A), so the human decides. The other half, clearing a bit the bootloader left set, is K1b above: **written, untested** |
| K2 (nice to have): round the guard's current down; charger `status` "Not charging" while inhibited | `max77759_charger.c` | not needed for safety |
| K3 (D4b/c): fold overlays into the DTS; gauge `power-supplies` | `gs201-cheetah.dts` | after B4b/D3 |
| Tool: `usbc-deadman` uses `out-usbc` nowhere; only the plan text does | `USB-C-PLAN.md` section 6 | replace with this |
