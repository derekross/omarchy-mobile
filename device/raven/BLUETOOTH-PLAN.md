<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): Bluetooth

Status (2026-10-27): **Bluetooth works**, at every boot since kernel #6 v2's
CMU_APM mux fix (POWER-PLAN R4b, `g1de37d2bef30` and later; linux #6, merged).
The B3 outage below followed kernels whose `assigned-clock-parents` override
set a reserved bit in the always-on CMU_APM; GrapheneOS's Bluetooth came up
clean after warm and cold boots once that kernel had run (B3 follow-ups).

Earlier status (2026-10-21): **broken again since a forced restart (B3)**: the
chip answers no command, and no reset tried so far brings it back.
Before that (2026-10-20): **fixed: the BCM4389 starts cleanly at every warm
reboot** (B2: 15 of 15, not one lost command) with hci_bcm pulsing BT_REG_ON
low 30 ms before power-on, as Google's driver does (`omamobile-gs101-
bluetooth` d9b209a81). What left it silent until a forced restart was
powering it down at shutdown (B1). Earlier status (2026-10-15): **Bluetooth works and is on at boot** (kernel
`g014e0672a241`, omamobile-device-raven 0.1.1). The patched BCM4389C1
(`ES1PX_GG_R4`, build 0203) loads at every boot, bluetoothd runs, the
controller is powered, and a scan found 18 devices. Next: set the phone's
own Bluetooth address (as cheetah's `omamobile-bt-addr` does: power on
first, then set it), then pair and play audio.

**2026-10-15: the address is set at boot** (omamobile-device-raven 0.1.5):
raven's bootloader writes `/chosen/config/bt_addr` as cheetah's does, so the
package ships cheetah's `omamobile-bt-addr`, its udev rule
(`DRIVERS=="hci_uart_bcm"`) and service. After a reboot the controller's
address equals the bootloader's (not the `43:89:00:00:..` placeholder),
powered, with the AoC and speaker protection up. On the split kernel one
boot of several lost the controller (baudrate and patchram timeouts,
AUDIO-PLAN R2.0); not seen since.

**2026-10-16: a rebind brought it back; boots are now checked.** The
journal of the last 40 boots shows the failure on every kernel since
2026-10-15 (g38dc6b9, gb3dd66e, g8998692 and the cpif kernels), some boots of
each fine: no kernel change caused it. Today the first `0xfc18` timed out at
about 6.5 s on five boots in a row, a power-off among them. Unbinding and
rebinding `hci_uart_bcm` (on 7.3.0-rc6-omamobile-push1-g6efb2b9205c1) brought
the controller up with its patch at once, unlike on 2026-10-15.
- device-raven 0.1.12: `omamobile-bt-addr` rebinds the driver itself when
  the setup fails (up to 3 times a boot, counted in `/run/omamobile/bt-rebinds`),
  and `omamobile-boot-check` (a timer two minutes after boot) records every
  part, Bluetooth with its power-cycle count, in
  `/var/log/omamobile/boot-check.log`. Those lines tell whether the rebind
  is enough or the stuck case of 2026-10-15 comes back.

**2026-10-15 (later): the controller can get stuck until a cold restart.**
In about 30 boots the BCM4389 never answered twice, each time for a run of
boots: `0xfc18` (update baud rate) and the reset time out, and the UART
counts `tx:28 rx:0`, so the chip sends nothing at all. The UART clock (196.6
MHz), the four `uart16` pins and BT_REG_ON/device-wake were all as on good
boots. Unbinding `hci_uart_bcm` (BT_REG_ON low a full second) and a normal
reboot did not help; a forced restart (Power held, a PMIC reset) did, as the
watchdog resets had before. Likely the combo chip's shared power stays up
while WL_REG_ON is high, so BT_REG_ON alone doesn't reset its Bluetooth
core. What puts it there is not known yet.
- device-raven 0.1.6: `omamobile-bt-addr` and `omamobile-wait-bluetooth` stop
  waiting once this boot's kernel log shows the setup failed (the dead chip
  cost about 30 s and 16 s of boot).
- Tried 2026-10-16 (g38dc6b965ee4, stuck after several warm reboots):
  `hci_uart_bcm` unbound, then the PCIe controller unbound, which released
  `wlan-reg-on` (regulator `disabled`, gpp14-2 `out lo`), both REG_ONs low
  for 2 s, PCIe then BT rebound. Wi-Fi came back and associated; BT still
  timed out on `0xfc18` and the reset. So the chip-side power theory is
  wrong: with both REG_ONs low the BCM4389 should be in full reset.
- Next suspect: the host side. USI1 is in the APM (alive) block, which a
  warm reboot keeps and a PMIC reset clears, matching every recovery so
  far. On the next stuck boot: read APM USI1's USI_CON/USI_OPTION and the
  UART's ULCON/UCON/UFCON/UFSTAT/UMCON (read-only, block known clocked
  since the driver is bound), compare with a good boot, then try a USI
  software reset (USI_CON reset bit) before rebinding.
- Read the same boot, still stuck (driver bound, `gout_apm_apm_usi1_uart_pclk`
  enabled; URXH and UERSTAT skipped as read-side-effect): ULCON 0x3, UCON
  0xf3c5, UFCON 0x131, UMCON 0x11 (AFC, RTS), UTRSTAT 0x1000e (TX empty),
  UFSTAT 0, UMSTAT 0x11 (CTS asserted), UBRDIV 0x69 + UFRACVAL 0xa (115200 on
  196.6 MHz), UINTM 0xe, USI_CON 0, USI_OPTION 0x3. The host UART is sane
  and transmits, so the host-side theory is out too. Left: something only a
  PMIC reset cuts, likely the chip's VBAT/VDDIO rails (dummy regulators in
  our DT, so Linux never drops them). Find which PMIC rails feed the BCM4389
  in Google's raviole DT/schematic names and whether one can be cycled.
- After the forced restart (same kernel) BT failed differently, and a
  driver rebind with Wi-Fi idle failed identically, so it is not a race with
  brcmfmac's firmware load: power on (100 ms wait in `bcm_gpio_set_power`),
  `0xfc18` (3 Mbaud) unanswered, then chip id/version answer at 115200 2 s
  later, the patch downloads at 115200 and Launch RAM (`0xfc4e`) hits the
  2 s command timer. The chip is alive; its first command after power-on is
  lost, and hci_bcm only retries the baud switch after the patch. Good-boot
  UART registers equal the stuck boot's (UTRSTAT 0x2000e). Candidate fix in
  hci_bcm/btbcm: retry `0xfc18` after a successful HCI_Reset, before the
  download (or a longer power-on wait; Android's BigHammerBtRegOnDelay is
  100 ms too).
- **Fixed (2026-10-16, gb3dd66ee748d):** hci_bcm now answers a `0xfc18`
  timeout with HCI_Reset and one retry (`b3dd66ee7` on merge-test, to move
  to `omamobile-gs101-bluetooth`). First boot: the retry fired at 6.4 s,
  the patch loaded at 3 Mbaud (build 0203 at 13.2 s), hci0 powered; Wi-Fi,
  AoC and speaker protection unaffected, DTB byte-identical to the previous
  push. The earlier fully silent state (no answer to anything) is not
  covered by this; if it recurs, a forced restart is still the way out.

**2026-10-20: the silent chip again, and two fixes to test (B1).** On
`g8bc6e0e857f3` the chip answered nothing at 6.7 s (the 0xfc18 retry fired
and timed out, HCI_Reset too, through omamobile-bt-addr's 3 rebinds);
of 7 boots that day (all warm) one silent, two that needed rebinds.
Google's nitrous driver (google-modules/bluetooth/broadcom, nitrous.c,
`nitrous_rfkill_set_power`) drives REG_ON low, waits 30 ms, then REG_ON
and DEV_WAKE high; hci_bcm only drove it high, so after a warm reboot the
chip may never see a reset. Its `toggle_dbo_ff` needs `bt-ble-dbo-le`,
which raven's DT doesn't have. Two changes:
- kernel `omamobile-gs101-bluetooth` d9b209a81 (int 084198625,
  `g08419862513c`): hci_bcm pulses BT_REG_ON low 30 ms before power-on;
- device-raven 0.1.19: `omamobile-bt-off.service` unbinds hci_uart_bcm at
  shutdown, so the chip goes into each reboot with BT_REG_ON low.

**B1 runbook (asks the human: push, then a series of reboots; risk: low).**
Push `out-gs101-int` (`g08419862513c`; rollback `images-g8bc6e0e857f3`),
then about ten warm reboots (`reboot-to omamobile`), reading
`/var/log/omamobile/boot-check.log` and this boot's
`journalctl -k | grep -c "0xfc18 tx timeout"` after each. Pass: Bluetooth
ok on every boot, no 0xfc18 timeouts beyond the first retry. Stop: any
boot with Bluetooth down records the kernel log; a forced restart
(Power about 30 s) recovers it.

**B1 result (2026-10-20, `g08419862513c`, device-raven 0.1.19): failed.**
The first boot on the new kernel came up from the silent chip (one
0xfc18 timeout, the retry, the patch, powered). Then nine warm reboots in
a row (`reboot-to omamobile`, about 2.5 min apart): Bluetooth down on all
nine, 8-10 `0xfc18 tx timeout` each, omamobile-bt-addr's three rebinds
did not help; boot 6 also lost the accelerometer. So once silent the chip
stays silent across warm reboots, as before, and neither the 30 ms
REG_ON pulse nor powering it down at shutdown prevents that; the
shutdown power-off ran before the first failing boot, so it may even
trigger it. Recovery is still a forced restart (Power about 30 s).
Next: take omamobile-bt-off out (device-raven) and find what only a
PMIC reset clears; one experiment per series, each started from a forced
restart.

**B2 result (2026-10-20, same kernel, omamobile-bt-off masked, from a
forced restart): passed.** Six warm reboots in a row: Bluetooth up on all
six, `0xfc18 tx timeout` 0 on every boot (before the pulse a good boot
usually lost its first command and needed the retry), and every boot
check `ok`. So the silent state came from omamobile-bt-off's power-down
at shutdown (gone in device-raven 0.1.21), and the reset pulse makes the
first command land. The 2026-10-15 silent boots, before any power-down at
shutdown, show it isn't the only way in; watch the boot check.
Nine more warm reboots on device-raven 0.1.21 (the power-off removed, not
masked): Bluetooth up on all nine, 0 timeouts each: **15 of 15**. One of
them lost the accelerometer (the AoC sensor flake, AOC-PLAN), not
Bluetooth. The hci_bcm patch is a candidate for upstream.

## 1. Facts

From Google's raviole DT: `gs101-common-bluetooth.dtsi`,
`gs101-raven-bluetooth.dtsi` and `gs101-usi.dtsi`.

| Item | raven (gs101) | cheetah (gs201) |
| --- | --- | --- |
| UART | APM USI1 at `0x175b0000`, SPI 69, FIFO 256, pins `uart16_bus` (gpa3-0..3, func 2) | `0x181b0000`, SPI 69 |
| USI mode | `sysreg_apm` + `0x4e4` (Google: sysreg `0x174204e0`, usi-offset 4) | the same offset |
| BT_REG_ON | gpp16-2 | gpp16-2 |
| Device wake | **gpp14-3** | gpp16-3 |
| Host wake | gpa6-6 | gpa6-6 |
| Timesync | gpp11-1 (raven only, not used) | - |
| UART clock | `mout_apm_func` on the 24.576 MHz oscillator, `dout_apm_usi1_uart` 12.288 MHz | 197 MHz from `mout_apm_funcsrc` (PLL_ALV/2) |

Upstream already has: `brcm,bcm4389-bt` in hci_bcm and its binding, gs101
CMU_APM with the USI1 UART gates, and `uart16_bus`.

## 2. Results

**BT1 (2026-10-15, `g0133ca8741af`):**
- The UART probes as ttySAC1 and serdev creates `serial0-0`.
- `modprobe hci_uart`: hci0 appears; BT_REG_ON and device wake are driven
  high (gpio debugfs).
- Both `0xfc18` (update baud rate) and `HCI_Reset` time out: no Command
  Complete. The UART interrupt fired twice, and nothing was received.
- No hang. hci_uart was unloaded again.

**BT1.1 (same day, read only):**
- CMU_APM in hardware: `MUX_APM_FUNC` 1 (FUNCSRC), `MUX_APM_FUNCSRC` 0
  (PLL_ALV/2), `DIV_USI1_UART` 1 (/2), so the UART runs at **197 MHz**. The
  gates `0x2038`, `0x203c` and `0x20a4` read `0x00200000`.
- Linux's clock tree had cached `mout_apm_func` on the oscillator (24.576 MHz,
  so the UART at 12.288 MHz): the mux must have been 0 when cmu_apm
  registered, then changed. The serial driver then programmed a baud divisor
  16x too small.
- A module calling `clk_set_parent(mout_apm_func, mout_apm_funcsrc)`, which
  rewrites the value the hardware already held, fixed the tree (UART
  196608000).
- With that, UBRDIV `0x69` and UFRACVAL `0xa` give 115200 baud; TX drains
  (UTRSTAT `0x6`), RX stays empty, and hci0 still times out on `0xfc18` and
  HCI_Reset. So the clock was one bug, not the only one.
- Listing `/sys/kernel/debug/pinctrl/*/pins` aborted the SoC (AGENTS.md
  gotcha); rebooted.

- Pins, from a single read of the alive pinctrl bank (powered): gpa3 CON
  `0x2222`, so all four UART pins are in function 2.
- So the UART side (registers, pins, clock once fixed) is right, and the
  silence is on the chip's side: power-up sequence, wake lines or rails.

## 3. Next (gated, with the human there)

1. **Read only:** CMU_APM's mux, divider and the UART gate registers
   (cheetah BT1.1 decoding: bit 28 auto-gating, bit 20 manual, bit 21
   value), through the clock driver's debugfs or raw reads of a block now
   proven readable. Confirm that the UART's IPCLK runs.
2. **Loopback** (cheetah BT1.2, `tools/bt-uart-test`): the UART node
   without the bluetooth child, TX looped to RX, at 115200 and 3000000.
   This separates the UART from the chip.
3. The chip's power-up. Google's `nitrous.c` (GPL, google-modules/bluetooth/
   broadcom, raviole android14) on rfkill unblock does:
   - REG_ON low, 30 ms, REG_ON high;
   - DEV_WAKE high;
   - timesync on;
   - 10-20 ms wait.

   Timesync (gpp11-1, raven only) is an input IRQ from the chip, so it is
   not needed for power-up. **Test first:** a clean REG_ON low-high cycle
   before hci_uart opens: the GPIO read high before hci_bcm took it, so the
   chip may have been left on in some state. Then check the host-wake
   (gpa6-6) and device-wake polarities.
4. Make the clock fix permanent: re-parent `mout_apm_func` to
   `mout_apm_funcsrc` (197 MHz, as on cheetah), or have the clock driver
   re-read the mux. **Risk: boot hang.** The
   mux also clocks the alive pinctrl and the APM mailbox, so the first try
   must be by hand (a module), never a DTB that every boot uses.

**BT2 passes (2026-10-15):**
- `tools/bt-uart-test hci --tty /dev/ttySAC1 --wake gpp14:3` (DT child
  disabled for one boot): HCI_Reset passes, HCI 10, LMP subversion `0x6209`,
  chip id 170.
- `patch` (new): the 3038 Write RAM records stream with no answer to any
  of them; Launch RAM is answered and the version reads `0x20cb` after it.
  At 115200 that takes 41.5 s, at 3 Mbaud 1.7 s.
- Through the kernel: btattach loads the patch at 115200 and the HCI core's
  2 s command timer fires on Launch RAM, so it cannot work. The serdev
  path sets 3 Mbaud before the download and, with
  `btbcm.patchram_nowait=1` (cheetah's option, now `4a245b278`), loads the
  patch.
- The clock fix is permanent as `assigned-clock-parents` on usi_apm1
  (`014e0672a`). After a cold boot, `dout_apm_usi1_uart` reads 196608000
  and Bluetooth comes up by itself.
- Android's `bt_vendor.conf` has `FastDownloadDisable = false` and
  `BigHammerBtRegOnDelay = 100`. The vendor image also has `BTFW_B.hcd` and
  `BTFW_D.hcd`; `BCM.hcd` is the one in use.
- **The shell's tile (same day):** after boot the tile read Off while the
  adapter was powered. Omarchy's shell started before the adapter appeared
  (about 11 s into boot, once the patch loaded) and never picked it up; a
  shell restart fixed it. omamobile-device-raven 0.1.2: an sddm drop-in
  waits up to 15 s for a powered hci0 (`omamobile-wait-bluetooth`). On the
  next boot sddm waited about 7 s and the tile is right.

## B3: silent after a forced restart (2026-10-21, `g472317126aea`)

The human force-restarted the phone (Power held) at 08:22 while the
touchscreen was down. That boot and the next one, a normal warm reboot
from `bin/omamobile push`, both found the chip silent: the 0xfc18 baud
rate change timed out, the HCI_Reset after it timed out (`BCM: Reset
failed (-110)`), and a second probe at 59 s failed the same way, so no
controller reached bluetoothd. The boot before the forced restart, on the
same kernel, came up normally.

So the reset pulse covers warm reboots (B2) but not a chip left in this
state: a forced restart cuts the SoC mid-run, and the chip's supply comes
straight from the battery (`vbat` and `vddio` are dummy regulators here),
so nothing cycles its power. In B1 a forced restart recovered it; this
time it caused it, so what a forced restart does depends on the chip's
state at the moment it hits.

What did not bring it back (same day, kernels `g472317126aea` and
`g0422abf64c05`, each a fresh boot unless noted):

| Reset | Result |
| --- | --- |
| warm reboot (`bin/omamobile push`) | silent |
| `systemctl poweroff` with USB in (ABL started the phone again) | silent |
| forced restart, twice | silent |
| hci_uart_bcm unbound about 4 s (BT_REG_ON low), then bound | silent |
| also brcmfmac and pcie_gs201 unloaded (WL_REG_ON low too: the whole BCM4389 off) for 3 s, then all back | silent; Wi-Fi came back and connected |

The host side looks right: `dout_apm_usi1_uart` runs at 196608000 from
`pll_alv_div2_apm`, as after the clock fix. The same kernel brought the
controller up at 08:17, before the forced restart. So this is no longer a
chip state that a reset clears, and B2's warm-reboot result (and PR #6's
claim) is not what changed.

**Under GrapheneOS (same day, after flashing it):** Bluetooth works. The
chip is not damaged, and stock's start sequence brings it back where every
reset above failed. What stock does differently is the lead: its HAL's
"big hammer" (`BigHammerBtRegOnDelay = 100` in `bt_vendor.conf`), the
order of BT_REG_ON, BT_DEV_WAKE and the UART lines, the firmware download
path. Still open: does Bluetooth work on Omarchy again after this
GrapheneOS boot (then stock's sequence clears the state and is worth
copying), or does it fail again?

Next (left for another day):

1. Answered: the chip works under GrapheneOS (above).
2. After the next Omarchy install, check Bluetooth at the first boot. If
   it fails, the bt-uart-test overlay (UART as a plain tty, no hci_bcm),
   then `tools/bt-uart-test hci` at 115200 and 3000000, with the device
   wake line both ways; and compare the UART pin and BT GPIO states
   (`/sys/kernel/debug/pinctrl`, read only the gpp14/gpp16/gpa6 banks,
   never the whole `pins` file) with a working boot's.

Also on this boot: the controller sat soft-blocked by rfkill, restored by
systemd-rfkill from a previous boot; the boot check reports that as
"bluetooth" failing too, which mixes a switched-off adapter with a dead
chip.

**B3, the user's GrapheneOS observation (2026-10-26):** under GrapheneOS
the BT stack now reports a crash at boot, and comes up after a few presses
of the Bluetooth tile (each one a full power cycle and firmware download);
once up it stays up (an Oura ring stays connected). Before the Omarchy work
GrapheneOS booted Bluetooth cleanly. So the chip's start-up has become
flaky under Google's stack too: Android hides it by retrying.

What Omarchy could have changed that GrapheneOS sees:

- storage: no (the guard allows only slot B's boot images and userdata;
  efs, persist, modem and devinfo were only read);
- the chip: no known path (no flash; everything sent was HCI into RAM,
  including `bt-uart-test patch`; no OTP vendor commands);
- state across a warm reboot: possible. The chip shares power with Wi-Fi,
  and our DT wrote a reserved bit in CMU_APM (always-on block; Derek's
  finding on PR #6, fixed in v2);
- unrelated: GrapheneOS was reinstalled fresh on 10-21 (new version, new
  BT config), and the trouble began with the 10-21 forced restart.

**Next time GrapheneOS is on the phone, before reinstalling Omarchy:** boot
it, power it off (not restart) for 30 s, power on, watch Bluetooth.
Clean the first time: the bad state was carried over a warm reboot from
Omarchy (look at our shutdown path and the CMU_APM write). Still crashing:
not carried state (GrapheneOS's own change, or hardware). Missed on
2026-10-26: Omarchy was already reinstalled.

On Omarchy, do what Android does: a boot-time retry that power-cycles the
controller up to about 10 times, a few seconds apart, logging each attempt
(first try or random; after a warm or a cold boot). If it works, move the
retry into hci_bcm's setup for upstream.

**B3 follow-up (2026-10-26, GrapheneOS 2026102100):** Bluetooth came up
cleanly at the first GrapheneOS boot after reinstalling it, where that
morning GrapheneOS's stack had crashed at boot and needed retries. The
difference: the last Omarchy kernel before this GrapheneOS boot was the
review kernel (`g1de37d2bef30`/`gb3d6253b0d61`), whose CMU_APM mux fix
(PR #6 v2) never writes the reserved bit that the old
`assigned-clock-parents` override set in the always-on CMU_APM; the
morning's crash followed kernels with the override. That fits state
carried over a warm reboot. One boot each way: not proven. Next GrapheneOS
boots, and the cold-boot test above, would confirm it.

**B3 cold boot (2026-10-27, GrapheneOS 2026102100):** GrapheneOS's own
Power off from the menu, then Power: Bluetooth came up on its own, with no
crash and no tile presses. The second clean GrapheneOS boot in a row since
the last Omarchy kernel without the `assigned-clock-parents` override, and
the first after a cold boot, so state left by the override over a warm
reboot remains the best explanation for the 10-26 morning crash. (How long
the phone stayed off wasn't timed.)

**B3 on the fixed kernel (2026-10-27, `gb3d6253b0d61`, Omarchy):** the
override isn't the whole story. This kernel has the CMU_APM fix (#6 v2),
and Bluetooth came up on three boots of it that day (09:59, 10:05, 10:54),
but the warm reboot from `bin/omamobile push` at 11:32 found the chip
silent again: `0xfc18` timed out, the HCI_Reset after it too (`BCM: Reset
failed (-110)`), twice, as in B3. Then a real cold boot, the first on
Omarchy in this state: `systemctl poweroff` with the cable out, about 30 s
off, Power with no cable. The first `0xfc18` timed out, the driver's
retry after a reset answered (`BCM4389C1`, chip id 170), the patch loaded,
and the controller powered up. So a warm reset can carry the chip's silent
state on any kernel, and only cutting its power clears it; a forced
restart, the REG_ON lines and every warm path did not (table above). That
points at the reset sequence rather than at one bad register: next, hold
BT_REG_ON low longer before power-up (hci_bcm's `power_on_delay_ms` is
30 ms for the BCM4389; stock's "big hammer" is 100 ms), and a boot-time
retry that power-cycles the controller as Android does.
