<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) suspend: s2idle, on the Pixel 7 Pro's path

Status (2026-11-16): Z1, Z3, Z4 and P7 passed; Z2 found its cause. The screen comes back after s2idle (DISPLAY-PLAN D5, to come with the 90 Hz pull request), the RTC alarm wakes the phone ([linux-omarchy-mobile#201](https://github.com/derekross/linux-omarchy-mobile/pull/201), merged), and Power and Volume Down wake it too. Wi-Fi's hang after a resume is the firmware trapping on the freeze path (Z2g to Z2k); on `systemctl suspend` it hasn't trapped in 256 resumes. So device-panther unloads Wi-Fi around sleep by default (#475), and a check that reloads it when it is kept loaded (Z2l, Z2m) and two brcmfmac patches are pull requests to come. Z6 has standby numbers (Z6b to Z6k): asleep with Wi-Fi kept, about 284-296 mA with the memory bus at 2028 MHz (Z6c, Z6j) and 248-251 mA at 1014 MHz (Z6j, Z6k; the 1014 MHz floor is a kernel pull request to come); at 1014 MHz with Wi-Fi unloaded, 184-200 mA (Z6k). Power off powers off on a kernel with [linux-omarchy-mobile#233](https://github.com/derekross/linux-omarchy-mobile/pull/233) (P7); the kernel releases since `kernel-2026.11.13` carry it, so the upower drop-in waits only for off-mode charging (#788). Z5 hasn't run.

The Pixel 7 Pro (cheetah, the same gs201) has done this work:
`device/cheetah/SUSPEND-PLAN.md` explains s2idle on gs201, the wake
sources, the Wi-Fi D3 handshake and the userspace policy. This plan only
takes its stages to panther, in the order the Pixel 7's state allows,
and says what differs. Tier 1, as on the Pixel 7 Pro: screen off and
locked means s2idle, Power wakes it to the PIN pad, Wi-Fi stays
associated, alarms wake it on time. SYS_SLEEP (deep) is for later, after
the Pixel 7 Pro has it.

[V] is verified on this phone or in the source; [I] is inferred.

## What is known

**Kernel [V].** The daily kernel (`7.3.0-rc6-omamobile-push1-g1ba78e119cc8`,
DISPLAY-PLAN D5, to come with the 90 Hz pull request) has, from
`omamobile`:
- `mem_sleep_default=s2idle` in panther's bootargs, so `mem_sleep` reads
  `[s2idle] deep` (gs201 never wakes from `deep`);
- the S2MPG12 PMIC and its RTC as `rtc0`, with `alarmtimer`;
- cpuidle `state1` (C2), and `mct-comp` as the broadcast timer;
- UFS `spm_lvl` 5 by default;
- the brcmfmac D3 series (`d2197079e`, `41d8350ea`) that let the Pixel
  7 Pro keep Wi-Fi up across s2idle (its S5c, 31 of 31);
- `CONFIG_PM_DEBUG`, `PM_SLEEP_DEBUG` (`pm_test`, `pm_wakeup_irq`) and
  `BRCMDBG`.

**Results so far [V]:**
- DISPLAY-PLAN D5: four sleeps through `rtcwake -m freeze -s 30`, plus
  three `pm_test` runs, all `rc=0`.
- Each real sleep woke on the RTC alarm, through IRQ 101 (`s2mpg12-pmic`).
- USB came back by itself after each wake.
- The panel woke through its cold init, or kept running at 90 Hz.
- Each resume printed one UFS `dme-set: attr-id 0x4021` line, as the Pixel
  9a's clean resumes do (`device/tegu/SLEEP-PLAN.md`), and no UFS
  errors.

**Wake-enabled devices [V]:**
- the Bluetooth serdev;
- the MAX77759 charger and the fuel gauge;
- the Wi-Fi function (`0000:01:00.0`);
- the PMIC and its RTC;
- gpio-keys.

The charger's wake is new compared with the Pixel 7 Pro's list (its S0):
plugging or unplugging the cable may wake the phone.

**Userspace [V], as of 2026-11-05:**

| Piece | Pixel 7 Pro | This phone |
|---|---|---|
| `sleep.conf.d` (`MemorySleepMode=s2idle`, no hibernation) | yes | yes, device-panther |
| Sleep hook (`omamobile-sleep`: Wi-Fi unload or keep, wake reason) | device-cheetah | **no** |
| `omamobile-keys` (Power locks and darkens) | yes | yes, omamobile-shell 0.2.28 |
| `omamobile-sleepd` (sleep when dark and locked; the toggle) | omamobile-shell 0.2.29+ | **no** (0.2.28) |
| Patch 0021 (the sleep lock darkens the screen) | omamobile-omarchy 0.1.13+ | **no** (0.1.12) |
| Omarchy's `suspend-off` toggle | set until tier 1 ships | set |
| upower critical action | 6.6's decision | `CriticalPowerAction=Auto` at 2 % |

The shell and Omarchy packages here are far behind `main`'s (0.2.100,
0.1.32). They come from the published channel. The phone's
`[omamobile]` still points at a local, contributor-signed repo (NOTES, to come with the 90 Hz pull
request), so
**Z5 waits for that repository change**.

**Power off reboots the phone** (NOTES 2026-10-28), spending a slot B
retry. Until that is fixed, upower's critical action must not be
`PowerOff` here. With `Auto` and no hibernation it [I] picks power off,
so Z6 decides it before tier 1 is left on.

## Rules

As in DISPLAY-PLAN D5, and the Pixel 7 Pro's section 8:
- Stage tests write `/sys/power/state` directly or use `rtcwake`, so no
  hooks run; the stages through logind say so.
- Every sleep drops the USB link. Run each one detached with `systemd-run`,
  log to `/var/lib/omamobile/suspend`, and read the log after the link is
  back.
- Wake with the RTC unless the step tests a key.
- After every wake: `dmesg | grep -E "ufshcd_err_handler|hibern8|I/O error"`
  must be empty, and `suspend_stats/fail` must not grow.
- Announce every step that sleeps the phone or changes the screen.
- Slot B: keep at least 2 retries before a step that sleeps. A flash of
  the same images refills it to 3.
- Never query pacman on the phone while `[omamobile]` is the local repo:
  read `/var/lib/pacman/local` instead. Answer `n` to any key import.

**Recovery.** It is the Pixel 7 Pro's, with panther's keys:
- **No wake after 60 s:** hold Power about 30 s. The next boot is slot B,
  and costs one retry.
- **Awake, but no USB after 2 minutes:** hold Power and Volume Down for
  fastboot (no retry spent), boot slot B again, and read the log.
- **Any UFS error:** reboot, `fsck` if the journal asks, stop and report.
- **Wi-Fi dead after a wake:** `systemctl restart omamobile-wifi`. If it
  stays dead, reboot.

## Stages

### Z1. C2 in s2idle, then a loop (low risk; no flash)

The Pixel 7 Pro's S4. Wi-Fi unloaded.

1. One 60 s sleep with the C2 counters read before and after:
   `usage`, `rejected`, `s2idle/usage` and `s2idle/time` of every CPU's
   `cpuidle/state1`.
2. Then 20 cycles of 30 s asleep and 15 s awake, detached, logging each
   cycle's `rc`, wake IRQ and time. The loop stops by itself on a failure
   or a UFS error.

**Pass:**
- `s2idle/usage` grows by one or two on every CPU, and `rejected` stays a
  small fraction of `usage`. `s2idle/time` doesn't measure the sleep:
  timekeeping is suspended once the last CPU is in, so it grows by under
  a millisecond (the Pixel 7 Pro's S4 expected about 60 s, but never ran
  that part);
- 20 lines, all `rc=0`, each woken by IRQ 101 (`s2mpg12-pmic`);
- no UFS error.

A gpio-keys, charger or fuel gauge wake with nobody touching the phone is
a spurious wake: record which (the Pixel 7 Pro's 3.1 and 6.3).

**Stop:**
- a failed cycle;
- `rejected` close to `usage`;
- an RCU stall;
- a wake that needs the 30 s reset.

### Z2. Wi-Fi across sleep (medium risk; no flash)

The Pixel 7 Pro's S5b and S5c, with the D3 series already in this kernel.

1. Wi-Fi connected. Turn on brcmfmac's PCIe debug messages (`echo
   0x80000 > /sys/module/brcmfmac/parameters/debug`), then one 30 s
   sleep, then turn them off again.
2. On a pass, a 20-cycle loop as in Z1, with Wi-Fi loaded, and a `ping`
   to the gateway after every wake.

**Pass:**
- `rc=0`;
- "D2H_MB_DATA: D3 ACK" in the debug output, with no "Timeout on response
  for entering D3 substate" and no "Failed to send D3 inform";
- "Hot resume", not a re-probe;
- Wi-Fi associated again within about 10 s, and the gateway answers;
- in the loop, no "Failed to reserve space in commonring".

**Stop:**
- `rc` non-zero with `last_failed_dev` `0000:01:00.0`: the D3 ACK never
  came. Record the debug output and stop.
- Wi-Fi dead after a wake.

**Then:** on a pass, Z3's hook keeps Wi-Fi loaded
(`/etc/omamobile/wifi-keep-across-sleep`). On a failure, it unloads Wi-Fi
before every sleep, as the Pixel 7 Pro did until its S5c.

### Z3. The sleep hook in device-panther (low risk; package)

The package gets the Pixel 7 Pro's hook:
- `bin/omamobile-sleep`, linked as `/usr/lib/systemd/system-sleep/omamobile`.
  Its `pre` unloads Wi-Fi, unless the keep flag is present and no D3
  failure was seen this boot. Its `post` reloads Wi-Fi through the
  hang-safe service, logs the wake IRQ by name, and falls back to
  unloading after a Wi-Fi suspend failure.
- The fprintd restart stays: it does nothing without fprintd.
- A `test/all` case, as device-cheetah's.

It is installed as a local build (device-panther 0.1.7.2), with
`tools/phone-install-package` and the temporary pacman config (NOTES, to come with the 90 Hz
pull request).
Then the Pixel 7 Pro's P1:
1. `rtcwake -m no -s 40`, then `systemctl suspend`, through logind and the
   hook.
2. **Pass:**
   - the hook's lines in the journal ("Wi-Fi stays up across sleep", or
     "Wi-Fi unloaded for sleep" and then "Wi-Fi reload queued");
   - "woken by IRQ 101: … s2mpg12-pmic";
   - Wi-Fi connected afterwards, and no UFS line.

The screen must be off before this step. Without patch 0021, a
`systemctl suspend` with the screen lit sleeps lit (DISPLAY-PLAN D5c).

### Z4. Power as the wake (low risk; attended)

The Pixel 7 Pro's P2, with this phone's `omamobile-keys`:
1. The human locks the phone with Power, and the screen goes off.
2. `systemctl suspend` after 5 s, detached, then no SSH.
3. About 20 s later, the human presses Power once.
4. Then the same with Volume Down as the wake.

**Pass:**
- After Power, the PIN pad lights within about 1 s, and the wake IRQ is
  gpio-keys. The lock holds: no session is shown without the PIN.
- After Volume Down, the screen stays dark.

**Stop:**
- a dark phone after Power: press again, and record a lost key report;
- at once on any lock bypass.

0.2.28's `omamobile-keys` predates the Pixel 7 Pro's lock-flash fix
(0.2.29), so a short PIN pad flash when locking is expected until Z5.

**Before Z4 (2026-11-05, read-only).**
- The keys are `gpio-keys` (`event0`, `power/wakeup` enabled), and the
  board file marks all three as `wakeup-source`: Power on `gpa10-0`
  (IRQ 104), Volume Down on `gpa10-1` (IRQ 102), Volume Up on `gpa8-5`
  (IRQ 103). Power is the PMIC's PWRONB line, also wired to the SoC.
- `omamobile-keys` isn't a service: Hyprland's binds in
  `/usr/share/omamobile/shell/hypr/phone.lua` call it per key.
- The hook and the keep flag are in place from Z3.

**A backup alarm.** Each sleep also arms the RTC 90 s ahead
(`rtcwake -m no -s 90`). If the key doesn't wake the phone, the RTC does,
instead of the long-press PMIC reset, which reboots and spends a slot-B
retry. `/sys/power/pm_wakeup_irq` (and the hook's line) tells them apart:
104 or 102 is the key, 101 is the backup alarm, and a 101 counts as a
failed Z4.

```sh
tools/phone-ssh 'systemd-run --collect --unit=z4 sh -c "sleep 5; sync; rtcwake -m no -s 90 >/dev/null; systemctl suspend"'
# the human presses the key about 20 s after the screen went off
tools/phone-ssh 'journalctl -b -o cat | grep omamobile-sleep | tail -3; cat /sys/power/pm_wakeup_irq'
```

### Z5. Tier 1 userspace (medium-low risk; needs the published channel)

**Blocked until `[omamobile]` points at the published channel**, so the
phone can take current omamobile-shell (`omamobile-sleepd`, the keys fix)
and omamobile-omarchy (patch 0021).

Then the Pixel 7 Pro's P3 and P5:
- **P3:** an alarm wakes the phone on time (`tools/alarm-wake-test`).
- **P5:** turn the `omamobile-sleep` toggle on, which makes the phone sleep
  30 s after the screen goes off behind a secure lock. Check that media,
  an SSH session and charging inhibit it as the Pixel 7 Pro's table
  says.
- Clear Omarchy's `suspend-off` toggle only once those pass.

### Z6. upower's critical action, and standby numbers (low risk)

- **upower's critical action.** Decide it before the toggle stays on: power
  off reboots this phone, so `Suspend` or `Ignore` (the Pixel 7 Pro's 6.6)
  until power off is fixed.
- **Standby numbers.** Then the Pixel 7 Pro's S7 and P8: `current_now` and
  the capacity over an hour asleep, unplugged, against an hour awake with
  the screen off.

**Before Z6 (2026-11-05, read-only).**
- upower 1.91.5 with Arch's `UPower.conf`: `PercentageAction=2`,
  `CriticalPowerAction=Auto`, which it resolves to `Sleep`
  (`GetCriticalAction`). It reads `/etc/UPower/UPower.conf.d/`, empty
  apart from its README. On the cable, `OnBattery` is false: upower takes
  `max77759-charger` (`online=1`) as the line, although the battery reads
  `Discharging` at about -12 mA at 99 %.
- The gauge (`max170xx_battery`) reports `charge_counter` (µAh, negative
  here, so only differences count), `current_now` and
  `charge_full` 4144000 µAh.

**Z6a, upower's critical action: no drop-in for now**, as the Pixel 7
Pro's 6.6 decided:
- `PowerOff` reboots this phone (NOTES, 2026-10-27 and -28). With 2 % left,
  that is a boot on a flat battery, which may count against slot B.
- The default `Sleep` at 2 % (about 83 mAh, under 20 minutes of s2idle at
  Z6b's rate, to be measured) ends in a brown-out asleep. That is no worse
  than a phone left asleep, and nothing on this phone suspends by itself
  until Z5.
- So the default stays until a power off that really powers off exists;
  then the drop-in would be `CriticalPowerAction=PowerOff` with
  `PercentageAction=3`.

**Z6b, the Pixel 7 Pro's S7 (the human unplugs; about 65 minutes).**
Screen off, Wi-Fi connected and kept across sleep (Z3's keep flag, the
wake off), the cable out. `tools/power-ab` runs on the phone, detached:

```sh
tools/phone-ssh 'cat > /root/power-ab && chmod +x /root/power-ab' < tools/power-ab
tools/phone-ssh '/root/power-ab --detach --unplug 60 --phase 600 --settle 30 --rounds 3 s2idle'
# within 60 s: the human pulls the cable, then presses Power (lock, screen off)
# about 65 minutes later, the cable back in (omamobile-usb-rescue brings USB back)
tools/phone-ssh 'cat $(ls -t /var/lib/omamobile/power/*-s2idle.txt | head -1)'
```

- A = awake with the screen off, B = s2idle (`rtcwake -m freeze` for the
  whole phase, frozen again after an early wake). Both from the charge
  counter, A also sampled once a second.
- **Pass:** every B phase frozen for its whole 10 minutes; no suspend
  failure, Wi-Fi hang or UFS error; Wi-Fi connected at the end.
- **Compare:** the Pixel 7 Pro's 434 mA awake and 312 mA in s2idle
  (4986 mAh, about 16 hours). Stock's SYS_SLEEP is 32-50 mA.
- **Stop:** USB not back after the replug: `omamobile-usb-rescue`, or
  Power and Volume Down.

## Results

### 2026-11-05: Z1

Kernel `7.3.0-rc6-omamobile-push1-g1ba78e119cc8`, Wi-Fi unloaded, the
screen off, nobody touching the phone, on the USB cable.

**C2 in s2idle: passed.**
- A 60 s `rtcwake` sleep woke after 60.7 s on IRQ 101.
- `s2idle/usage` grew by one or two on every CPU, and `rejected` grew by
  4 to 30 a CPU, from the time awake.
- `s2idle/time` grew by under a millisecond: timekeeping is suspended
  while the CPUs are in, so it doesn't measure the sleep. The pass
  criterion above was corrected.

**The loop: 20 of 20 `rc=0`, but the alarm landed at the wrong time five
times.**
- Every wake was IRQ 101, and `rtc-alarm0` counted one per suspend: each
  wake was the RTC alarm, none was spurious. No UFS error, and
  `suspend_stats` ended at 24 successes and 0 failures.
- 15 cycles slept 31 s as set. Four slept 16 s (cycles 6, 10, 12 and 20),
  and the first slept 67 s.
- The kernel log of the first cycles was lost: `pm_print_times`, left on
  since D5, filled the buffer. It is off now.

**The cause: a stale RTC read.**
- `rtc-s5m` waits for the PMIC's read update (clear RUDR, wait, set it,
  wait 1 ms) only on the S2MPG10, since `210e28ff7` (the Pixel 6 Pro's
  stale reads and early or late alarms). The S2MPG12 uses the
  S2MPG10's registers, but reads at once.
- Awake, 40 reads half a second apart, and 20 more each right after an
  alarm write, were all within a second of the system clock.
- Six more `rtcwake` cycles, each with a read of `since_epoch` just
  before `rtcwake`: that read was 45 s ahead once and 15 s behind once.
  `rtcwake`'s own read a moment later was right, and all six slept 31 s.
  So the first read after a while returns old registers, and a second
  read gets the copy.
- `rtcwake` sets its alarm from its read. A read 15 s behind wakes after
  about 16 s, and one about 37 s ahead after 67 s.

**The fix**, local kernel branch `omamobile-s2mpg12-rtc-rudr`
(`8cd4ca54c`, on `omamobile`): take the S2MPG10's path on the S2MPG12
too. The Pixel 7 Pro's 13 s wakes in its S4 loop look like the same
thing [I]. Next: build it on the daily kernel, flash, and run the loop
again with no read before `rtcwake`.

**Z1 again, on the fix (2026-11-05).** Kernel
`7.3.0-rc6-omamobile-push1-g85f0c4ecf93c`: the same daily kernel with
`8cd4ca54c` cherry-picked, the same config, flashed after its modules.
The same loop, with no read before `rtcwake`:
- 20 of 20 `rc=0`, and **every cycle slept 31 s**;
- every wake IRQ 101, with `rtc-alarm0` at 20 for the 20 suspends;
- `suspend_stats` 20 and 0, and no UFS error.

Z1 passed.

### 2026-11-05: Z2

Kernel `…-g85f0c4ecf93c` (Z1's, with the RTC fix), Wi-Fi connected, the
screen off, on the USB cable.

**One sleep with PCIe debug messages (`debug=0x80000`): passed.**
- `rc=0` after 31 s, woken by the RTC, and `last_failed_dev` was empty.
- `brcmf_pcie_pm_enter_D3` sent the D3 inform, and "D3 ACK by control
  message after 13857 us" came back (the Pixel 7 Pro's P1 was 13.6 ms).
- On resume: "Hot resume, continue....", not a re-probe.
- Wi-Fi stayed `connected` with no reload, and the gateway answered 3 of
  3 pings.
- The debug messages are so chatty that they pushed the sleep out of
  `dmesg`; the journal (`journalctl -k`) kept it.

**The loop, with Wi-Fi loaded: stopped at cycle 12.**
- **Cycles 1 to 10:** each slept 31 s, with the D3 ACK in 13.3 to 13.9 ms
  and a hot resume; Wi-Fi stayed connected and the gateway answered.
- **Cycle 11:** the same D3 ACK and hot resume, then `pcieport
  0000:00:00.0: PME: Spurious native interrupt!`. From then on every
  firmware command timed out ("Timeout on response for query command").
  NetworkManager still showed `connected`, but no ping came back.
- **Cycle 12:** "Timeout on response for entering D3 substate (1999 ms,
  mailboxint 0x00000000)". The suspend failed in `0000:01:00.0` (`rc=1`),
  and the loop stopped.
- No UFS error. `suspend_stats` showed 32 successes and 1 failure for the
  boot.

**What differs in the failing cycle.** Most cycles, the good ones too,
logged "Country code iovar returned err = -5" from the regulatory
notifier, with "bus is down", during D3 entry: harmless. Only cycle 11
had the spurious PME on the root port after the hot resume.

**Recovery:**
- `systemctl restart omamobile-wifi` did nothing: the modules were still
  loaded, so the start script found nothing to do.
- `modprobe -r brcmfmac_wcc brcmfmac pcie_gs201` returned 0, then
  `systemctl restart omamobile-wifi` brought the chip back (`phy2`),
  connected, with 3 of 3 pings and only the usual start-up lines.

**Where this leaves Z2.**
- The D3 series works on this phone, but not every time: 1 hang in 11
  resumes, against the Pixel 7 Pro's 31 of 31 (S5c).
- This kernel's PCIe GEN4A_1 description comes from
  linux-omarchy-mobile#195, the Pixel 7 Pro's from its own board file.
  Comparing the two (the root port's PME and wake set-up, ASPM, the
  `pcie-gs201` link state across s2idle) is the next step, along with
  more loops to get a rate.
- The resume that hangs leaves Wi-Fi dead without a failed suspend. Only
  the next suspend fails. So the hook's fallback (unload after a D3
  failure, 6.2) catches it one sleep late.
- Until this is understood, Z3's hook ships in unload mode: no
  `/etc/omamobile/wifi-keep-across-sleep`.

### 2026-11-05: Z2, the hang against the Pixel 7 Pro (no phone)

**The board description is not the difference.** The compiled
`gs201-panther.dtb` and `gs201-cheetah.dtb` (`out-ptest-e`, decompiled
with `dtc -s`) have the same `pcie@14520000` with its `pcie@0,0` bridge
and `wifi@0,0`, the same PHY, SysMMU and `wifi-dma-pool`, and the same
regulator and pins. Only phandle numbers and `brcm,board-type` differ;
the board type picks the NVRAM and CLM files.

**The driver is the one S5c passed on.** This kernel has the whole D3
series that cheetah's S5c ran: mailbox data as control messages
(`c01308a83`), the ACK in shared memory and the missed-ACK path
(`d2197079e`), the ring stop before a bus reset (`fc68ae420`) and
`synchronize_irq()` before the D3 mask (`41d8350ea`). Every ACK on this
phone came in 13.3 to 13.9 ms, as on the Pixel 7 Pro. `pcie-gs201` has no
PM ops on either phone: the link stays up and the endpoint goes to D3hot.

**What the spurious PME means.** `pcie_pme_handle_request()`
(`drivers/pci/pcie/pme.c`) prints "Spurious native interrupt!" when the
root port did receive a PME message, but no device below it still has
PME status set. brcmfmac calls `device_wakeup_enable()` on the function at
attach, so the PCI core arms PME before D3hot. So in cycle 11 the firmware
asked to wake the host while the host was already resuming: by the time
the PME work ran, the function was back in D0 and its status was clear.
The firmware stopped answering right after. On the hot resume brcmfmac
sends no D0 inform with mailbox data as control messages; the host-ready
doorbell resumes the device (`brcmf_pcie_pm_leave_D3()`). How Google's
bcmdhd orders this is not checked (no copy here).

**Working hypothesis: the trigger is traffic to the phone during the
sleep, not the board.**
- The external reports in cheetah's plan (S5c) saw about 2 hangs in 20
  resumes on this chip with mainline brcmfmac, close to 1 in 11 here.
- At 1 hang in 11, 31 clean cycles in a row happen about 5 % of the time,
  so S5c's 31 of 31 doesn't rule out the same rate on the Pixel 7 Pro.

**Next (each on the human's go):**
1. Read-only: the journal times of cycle 11 (PME, hot resume, first
   timeout) and `power/wakeup` of `0000:01:00.0` and the root port.
2. Z2b: 10 cycles with the laptop pinging the phone through each sleep.
   Frequent hangs make incoming traffic the trigger.
3. Z2c: the same with `power/wakeup` disabled on `0000:01:00.0`
   (runtime, gone on reboot). If it holds, Z3's hook can keep Wi-Fi loaded
   with its wake off. Wi-Fi can't usefully wake the phone today anyway:
   every Z1 and Z2 wake was the RTC.

**Step 1, read-only (2026-11-05, same boot as Z2): done.**
- `0000:01:00.0` `power/wakeup` is `enabled` (wakeup_count 0); the root
  port's is `disabled`. So `pcie_pme_suspend()` finds a wake-enabled device
  below the port and arms IRQ 140 as a wake interrupt.
- IRQ 140 (`gs201-pcie-intx`) is **one INTx line shared** by the root
  port's PME, AER and bwctrl services and by `brcmf_pcie_intr`.
- Cycle 11 in the kernel log (printk time; it doesn't advance across the
  sleep itself, cheetah S5b):
  - the D3 inform got "D3 ACK by control message after 13599 us", as in
    the good cycles;
  - "hot resume" came 9.5 ms of printk time later;
  - "PME: Spurious native interrupt!" came 0.6 ms after the hot resume,
    before tasks restarted. No good cycle logged a PME;
  - the first firmware command after the resume timed out 2 s later, and
    every one after it did too. So the firmware was dead from the resume
    on, not hung later by traffic.
- After every good resume the firmware sent four "Received unexpected
  monitor pkt" about 2.6 s later. After cycle 11 it sent none.

**What this changes.** The PME is the firmware asking for a wake while
the host has just told it to resume. It looks as if the firmware never saw
the resume: with mailbox data as control messages brcmfmac sends no D0
inform and relies on the host-ready doorbell (`brcmf_pcie_pm_leave_D3()`).
If that doorbell is lost or comes too early, the firmware stays in its D3
state and asks for a wake with a PME that nobody answers. This is still a
hypothesis. To check it:
- how Google's bcmdhd resumes this chip with mailbox data as control
  messages (a D0 inform message or not, and in which order with host
  ready). Its source isn't on this laptop;
- Z2b (traffic during the sleep) still tells whether a firmware wake
  request is what opens the race;
- Z2c (`power/wakeup` off on `0000:01:00.0`, so no PME is armed in D3hot)
  tells whether taking away the firmware's PME avoids the hang or only the
  message.

### 2026-11-05: Z2c, Wi-Fi's wake off

Same kernel and boot as Z2, Wi-Fi connected, the screen off, on the cable.
`echo disabled > /sys/bus/pci/devices/0000:01:00.0/power/wakeup` before
the loop, `enabled` again after it. Z2's loop, with three changes: it
reads only kernel messages logged since it started (`journalctl -k
--since`, so Z2's old errors don't count), logs the D3 ACK time and any
"Spurious native" line per cycle, and stops if the gateway ping fails
(cycle 11's silent hang).

**20 of 20 passed.**
- Every cycle `rc=0`, woken by the RTC (IRQ 101) after 31 s.
- Every D3 inform ACKed by control message, in 13.2 to 14.0 ms (8.1 ms in
  cycle 1). Every resume was a hot resume.
- No PME line, no firmware timeout, no UFS error.
- Wi-Fi stayed `connected`, and the gateway answered 2 of 2 pings after
  every cycle.
- 80 "Received unexpected monitor pkt", four per resume: the healthy
  pattern from step 1.
- `suspend_stats` went from 32/1 to 52/1. `last_failed_dev` still names
  `0000:01:00.0` from Z2's cycle 12; it keeps the last failure.

**What it shows, and what it doesn't.**
- With no PME armed, the firmware didn't hang in 20 resumes, and no wake
  request reached the root port.
- But at Z2's rate (1 in 11), 20 clean cycles in a row still happen about
  15 % of the time. One loop is not enough to say the wake caused it.
- Next, to tell them apart: more cycles with the wake off, and a control
  loop with the wake on, at the same time of day. With a hang rate near
  1 in 11 with the wake on and none in 40 or more with it off, the result
  would be clear (both on the human's go).
- If it holds, Z3's hook keeps Wi-Fi loaded and turns
  `power/wakeup` off on the Wi-Fi function before sleep (or a udev rule
  does it once). Nothing is lost: Wi-Fi can't usefully wake the phone
  today, and wake-on-WLAN would need its own kernel work (cheetah 6.5).

### 2026-11-05: Z2d, the control loop (Wi-Fi's wake on)

Right after Z2c, the same boot and script, with `power/wakeup` back to
`enabled`. **Stopped at cycle 1.**
- `rc=0`, woken by the RTC after 31 s, "D3 ACK by control message after
  13515 us", "hot resume".
- "PME: Spurious native interrupt!" 0.6 ms after the hot resume, as in
  Z2's cycle 11.
- The first firmware command after the resume timed out 2 s later, and
  so did every one after it. Wi-Fi showed `connected`, but the gateway
  ping got nothing back.
- Recovered as before (`modprobe -r brcmfmac_wcc brcmfmac pcie_gs201`,
  then `systemctl restart omamobile-wifi`): `phy3`, connected, 3 of 3
  pings. No UFS error.
- **brcmfmac turns the wake back on at every load** (`device_wakeup_enable()`
  in `brcmf_pcie_attach()`): after the reload `power/wakeup` read
  `enabled` again.

**Z2 so far.**

| Wi-Fi's wake | Resumes | Hangs | Cycles with a PME |
|---|---|---|---|
| on (Z2, Z2d) | 13 | 2 | 2, both the hangs |
| off (Z2c) | 20 | 0 | 0 |

- Each hang came with the PME right after the hot resume, and no clean
  resume had one.
- At the wake-on rate (2 in 13), 20 clean cycles in a row with it off
  would happen about 3 % of the time by chance.
- **So the wake is the trigger:** with PME armed in D3hot, the firmware
  sometimes sends a wake request just as the host resumes it, and after
  that it stops answering. Why the firmware wedges (the missing D0 inform,
  or the host-ready doorbell coming too early) is a driver question, for
  later and for the Pixel 7 Pro too.

**For Z3.** The hook keeps Wi-Fi loaded with `power/wakeup` off on the
Wi-Fi function. brcmfmac turns it back on at every load (boot, and the
hook's own reloads), so it has to be set after each load: a udev rule on
the function (`ACTION=="add|bind"`, `14e4:4441`) or the hook's `pre`
step before every sleep. The fallback (unload after a D3 failure, 6.2)
stays. More cycles with the wake off would firm up the 0 in 20, and can
run as part of Z3's own loop.

### 2026-11-05: Z3, the hook in device-panther 0.1.7.2

Kernel `…-g85f0c4ecf93c`. device-panther 0.1.7.2 (`006f5cc`), built on the
phone with `makepkg -d` (no pacman queries) and installed with `pacman -U`
and the temporary config without `[omamobile]`; the contributor key stayed
out of the keyring. The package adds `omamobile-sleep` (the Pixel 7 Pro's
hook, plus turning the Wi-Fi wake off before a sleep that keeps Wi-Fi) and
`80-omamobile-wifi-wake.rules`.

**The rule: passed.** `power/wakeup` read `enabled` (brcmfmac's, after
Z2d's reload). After a full-stack reload it read `disabled` with nothing
else done, and Wi-Fi came back connected (`phy4`, 3 of 3 pings).

**Unload mode (no keep flag), the screen off: passed.** `rtcwake -m no -s
40`, then `systemctl suspend`:
- "omamobile-sleep: Wi-Fi unloaded for sleep", then s2idle;
- the wake about 38 s later, when the alarm was due: "woken by IRQ 101:
  … s2mpg12-pmic";
- "Wi-Fi reload queued", and `omamobile-wifi` finished 2.2 s after the
  wake; Wi-Fi connected, and the wake `disabled` again from the rule.

**Keep mode (`/etc/omamobile/wifi-keep-across-sleep`): passed.** The same
steps:
- "Wi-Fi stays up across sleep". There was no "wake turned off" line,
  because the rule had already turned it off;
- "D3 ACK by control message after 13686 us", "hot resume", no PME line;
- woken by IRQ 101 after about 40 s;
- Wi-Fi connected with no reload (`phy5`), and 3 of 3 pings.

No UFS error. `suspend_stats` 55 successes, 1 failure (Z2's cycle 12). The
keep flag stays set on the phone. The fallback (unload after a D3 failure)
covers what is left. Z2c's 0 hangs in 20 grows with every keep-mode sleep;
the first hang in keep mode means removing the flag and going back to the
driver.

Next: Z4 (Power as the wake).

### 2026-11-05: Z4, the keys as the wake

Kernel `…-g85f0c4ecf93c`, device-panther 0.1.7.2 with the keep flag,
omamobile-shell 0.2.28. Each sleep was `systemctl suspend` 5 s after the
human locked the phone with Power, with the backup alarm 90 s ahead.

**Power: passed.**
- "woken by IRQ 104: … gpa10 0 Edge KEY_POWER" about 43 s after the
  sleep began, before the backup alarm.
- The PIN pad lit at once (the human); the lock held.
- Wi-Fi stayed loaded: "D3 ACK by control message after 7205 us", "hot
  resume", no PME, connected afterwards.
- The PMIC's own interrupt (101) also counted two, from the PWRONB press;
  the wake IRQ was the GPIO.

**Volume Down: passed.**
- "woken by IRQ 102: … gpa10 1 Edge KEY_VOLUMEDOWN" about 43 s after the
  sleep began.
- The screen stayed dark (`panel_asleep 1`, and the human).
- D3 ACK after 13483 us, hot resume, no PME, Wi-Fi connected.

No UFS error, no lost key press. `suspend_stats` 57 successes, 1 failure
(Z2's). Sleeps with Wi-Fi loaded and its wake off, all without a hang: 23
(Z2c's 20, Z3's keep-mode one, and these two).

Without tier 1 userspace nothing puts the phone back to sleep after a
wake: a Volume Down wake leaves it awake with the screen off until the
next `systemctl suspend`. That is Z5's watcher.

Next: Z5, blocked until `[omamobile]` points at the published channel
(omamobile-shell 0.2.28 has no `omamobile-sleepd`, omamobile-omarchy
0.1.12 no patch 0021). Z6 (upower, standby numbers) can come first.

### 2026-11-05: Z6b, standby numbers

**Passed.** `power-ab --detach --unplug 60 --phase 600 --settle 30 --rounds 3
s2idle`, cable out, screen off, Wi-Fi connected with the keep flag and its
wake off, battery from 99 % down to 88 %:

| Phase | Charge counter | Reported charge | Sampled (A only) |
| --- | --- | --- | --- |
| A, screen off and awake | 164 mAh over 1707 s: **346 mA** | 422 mA | 342 mA, 1.47 W |
| B, screen off in s2idle | 144 mAh over 1803 s: **288 mA** | 367 mA | (frozen) |

- All three B phases froze for the whole 10 minutes, with no early wake.
  `suspend_stats` went from 57 to 60 successes and still has 1 failure
  (Z2's). There was no PME, no brcmfmac error and no UFS error since the
  start, and Wi-Fi answered a ping after the replug. Sleeps with Wi-Fi
  loaded and its wake off, all without a hang: now 26.
- s2idle saves about 17 % over awake. The Pixel 7 Pro measured 434 mA and
  312 mA (about 28 %); this phone draws less awake, so s2idle saves less.
  The reported charge reads about 20 % higher than the charge counter in
  both phases; the counter is the figure compared, as on the Pixel 7 Pro.
- With 4144 mAh (`charge_full`), 288 mA is about **14.4 hours** of standby
  (the Pixel 7 Pro's estimate is about 16). Stock's SYS_SLEEP is 32-50 mA, so
  as on the Pixel 7 Pro, battery life now depends on deep sleep, not on
  more s2idle work.
- Z6a's estimate holds: the 2 % left at `PercentageAction` (about 83 mAh)
  lasts about 17 minutes at this rate.

### 2026-11-05: Z2e, the firmware hang in the driver (no phone, then read-only)

Read in brcmfmac (`pcie.c`, `cfg80211.c`, `usb.c`) on the daily kernel:

- **The wake is armed for nothing.** `brcmf_pcie_attach()` calls
  `device_wakeup_enable()` at every load, so the PCI core arms PME at every
  suspend. But this firmware has no WoWLAN (`iw phy phy5 wowlan show`:
  "Operation not supported"), so `brcmf_cfg80211_suspend()` always takes the
  `wowl == NULL` branch. That branch disassociates from the AP, waits
  500 ms and turns MPC on. `brcmf_pcie_wowl_config()` stores
  `wowl_enabled` and nothing reads it. The USB bus does it the other way:
  it enables the wake only for the suspend.
- **Wi-Fi is not connected while asleep.** Z6b's journal shows one
  `CTRL-EVENT-DISCONNECTED reason=3 locally_generated=1` at each of the
  three sleeps, logged at the wake because userspace is frozen, and
  `CTRL-EVENT-CONNECTED` 2 s later. "Wi-Fi stays up across sleep" (Z3)
  means the driver stays loaded and the phone rejoins in 2 s. Z6b's 288 mA
  is with the radio idle and disassociated, as on the Pixel 7 Pro (same
  code).
- **Where it hangs.** The firmware learned about D3 from the D3 inform
  and acknowledged it. On a hot resume it gets no D0 inform: with
  mailbox data as control messages, `brcmf_pcie_pm_leave_D3()` only rings
  host ready, as bcmdhd does for this shared-memory version. In every
  hang (Z2, Z2d) the firmware had raised a PME during that sleep. The
  likely reading: once it has asked for a wake, it waits for a resume that
  host ready alone doesn't complete. That can't be proven without the
  firmware's console.
- **Android never takes this path.** On the Pixel, bcmdhd turns the link
  off for suspend (exynos-pcie L2) and the chip wakes the host out of band
  (WL_HOST_WAKE GPIO), so an in-band PME from D3hot with the link up is
  never exercised there.

So the fix belongs in the driver: **arm the wake only for WoWLAN**, as
USB does. Kernel commit `5eda66d72` on branch
`omamobile-brcmfmac-pcie-wake` (worktree `linux-brcmf-wake`, on
`origin/omamobile`, unsigned):
- it drops `device_wakeup_enable()` from `brcmf_pcie_attach()`;
- `brcmf_pcie_wowl_config()` calls `device_set_wakeup_enable(dev, enabled)`.

The test kernel is `ptest-daily4` (`ptest-daily3` plus that commit), release
`g0e7e40d706f8`, footer images in `out-ptest-e`, and it builds with no
warning. 80-omamobile-wifi-wake.rules and the hook's check stay in
device-panther until the patch is merged and running.

**Z2f, the patch on the phone (one boot: asks for approval, spends a slot B
retry).**
1. Mask the rule so the patch is tested alone:
   `ln -s /dev/null /etc/udev/rules.d/80-omamobile-wifi-wake.rules`.
2. Run `modules-push` and then `push` `ptest-daily4`
   (`DEVICE=panther KERNEL_OUT=~/android/mainline/out-ptest-e`).
3. After boot: the release is `g0e7e40d706f8`, and `power/wakeup` of
   `0000:01:00.0` reads `disabled` with the rule masked.
4. Override check: `echo enabled` into it, run one `systemctl suspend`
   with a 30 s alarm, and expect `disabled` after the wake
   (`wowl_config(false)` at suspend).
5. Run Z2c's loop with 20 cycles, keep mode. Pass: 20/20 without a hang,
   `pme=0`, Wi-Fi connected after each wake.
6. Remove the mask. Rollback: `ptest-daily3`'s images in
   `out-ptest-e/prev`.

### 2026-11-05: Z2f, the patch on the phone: the hang without a PME

`ptest-daily4` (`g0e7e40d706f8`), 80-omamobile-wifi-wake.rules masked,
keep flag on:

- **Steps 3 and 4 pass.** The wake reads `disabled` at boot with the rule
  masked. Set to `enabled` by hand, it reads `disabled` after the wake from
  one suspend written straight to `/sys/power/state`, which bypasses the
  hook, so the driver turned it off. (A first try with `systemctl suspend`
  showed nothing: the hook turned it off first.)
- **Step 5 fails: a hang in cycle 14,** the 16th resume of the boot. The
  D3 ACK came by control message after 13.5 ms and the hot resume looked
  normal. There was **no PME** (`pme=0`, no "Spurious native interrupt")
  and the wake read `disabled`. Then every query timed out from 2 s after
  the resume (`brcmf_msgbuf_query_dcmd: Timeout on response`; 38 of them
  before the reload). Nothing came back from the chip: the four
  "unexpected monitor pkt" lines that follow every other resume (cycles
  1-13) are missing.
- Recovered with the usual reload. Wi-Fi rejoined, ping 2/2, and the mask
  is removed. `suspend_stats`: 16 successes, 0 failures.

**So Z2e's reading is wrong:** the PME is not needed for the hang. With the
wake off there is 1 hang in 42 resumes (Z2c 20, Z3 1, Z4 2, Z6b 3, Z2f 16);
with it on, 2 in 13. The difference may be real (fewer hangs without
PME) or chance; samples this small can't tell. The hook and the rule stay,
because they cost nothing. `5eda66d72` is still right as a cleanup (no
WoWLAN means nothing to wake for), but its message must not claim it
fixes the hang; reword it before any PR. The open problem is
the same as Z2's: after some hot resumes the firmware answers nothing, and
the hook only finds out one sleep later.

**Z2g, next: the firmware's own console at the hang (no reboot).**
The kernel has `CONFIG_BRCMDBG=y`, so `BRCMF_FWCON_VAL` (0x00100000) in
`/sys/module/brcmfmac/parameters/debug` turns on the 1 s timer that copies
the firmware's console buffer from TCM into dmesg (`brcmf_pcie_fwcon_timer`,
restarted on each hot resume).
1. `echo 0x00100000 > /sys/module/brcmfmac/parameters/debug`, the wake
   left off, keep flag on.
2. Z2f's loop for 40 cycles. It stops at the first hang. Save the firmware
   console lines from the last resume into `/var/lib/omamobile/suspend/`
   (never committed: firmware output, which may carry MACs).
3. Read for a trap (`TRAP`, `_hnd_die`, PC/LR), a "deep sleep" or "D3"
   message, or silence (TCM unreadable means the chip lost power or the
   link is gone).
4. Turn the flag back off and reload Wi-Fi.

### 2026-11-05: Z2g, the firmware console at the hang: a trap at the resume

`ptest-daily4`, wake off, keep flag on, `debug=0x00100000` (firmware console
into dmesg once a second). **Cycle 19 of 40 hung**, again with no PME
(`suspend_stats` 35 successes, 0 failures). The console was saved on the
phone (`z2g-fw-131457.log`, not committed). Unlike Z2f, the firmware said
why:

```
THREADX TRAP INFO:
Thread: main_thread(ID:0x54485244) run cnt:4747
TRAP 4(326d68): pc 27489a, lr 27488d, sp 326fc0, cpsr 60000193, spsr 60000033
  dfsr 80f, dfar 0
  r0 0, r1 0, ... r3 0
FWID 01-68777be5
```

- **What it is.** Trap 4 is a data abort, and `dfar 0` with r0, r1 and r3 at
  0 points to a NULL dereference in the firmware's main thread. It is a
  firmware bug, not a lost interrupt or a hung link. TCM still reads fine:
  the driver copied the console out after the trap.
- **When it happens.** At the resume, not during the sleep. On the
  firmware's clock the D3 inform came at 17506.48 s (its "EL: 38 aafc 0"
  line, as in every cycle) and the trap at 17536.94 s, 30.5 s later. That
  is the length of the sleep, and the console line was the first one after
  the hot resume. In a good cycle the first line after the wake comes
  30.7 s after the D3 inform. So whatever the host does to wake the chip
  (the D3 to D0 write to its power-state register, then the host-ready
  doorbell) sometimes sends the firmware down a path that dereferences
  NULL.
- **What the driver sees.** Nothing, until the first query times out
  2 s later. The firmware sent no FW halt over the mailbox. bcmdhd looks at
  the trap flag in the shared area when a query times out; brcmfmac doesn't.
- This was the only trap in the run. Cycle 8's 327 console lines were the
  same lines as other cycles, repeated (the buffer wrapping), with no trap.
- Recovered with the usual reload. The flag is back to 0, the wake is off,
  Wi-Fi rejoined.

The tally with the wake off is now 2 hangs in 61 resumes (about 3 %),
against 2 in 13 with it on.

**What it means.** The firmware can't be fixed here (no symbols, no
source). That leaves three ways to live with it:
1. **Find it at the wake, not one sleep later.** Shortly after each
   resume, ask the firmware something that reaches it
   (`iw dev wlp1s0 info` does: channel and tx power are firmware queries).
   If the kernel then logs "Timeout on response", reload the stack right
   away, through `omamobile-wifi`, from a unit that the post hook starts
   with `--no-block`. The hang becomes a 10-15 s gap at each wake about
   3 % of the time.
2. **The driver reports it.** After a hot resume, or at the first query
   timeout, read the trap flag in the shared area and the trap record
   (bcmdhd's `dhdpcie_checkdied()`), log the trap and call
   `brcmf_fw_crashed()`. That's a kernel PR with a clear cause, but
   brcmfmac's own reset doesn't bring this chip back (D3 series), so the
   reload stays in userspace.
3. **Compare the resume order with bcmdhd's** for this shared-area version
   (PMCSR, host-ready doorbell, device-wake). If bcmdhd does something
   brcmfmac doesn't, that could be the real fix, but Android takes the link
   down for suspend, so it may have no D3hot resume at all to compare with.

1 is the one that helps users now; 2 is worth sending upstream; 3 is a
read of Google's source (no phone).

**Z2h, option 1 in device-panther 0.1.7.3 (no reboot).**
- New `bin/omamobile-wifi-check` and `omamobile-wifi-check.service`. The
  post hook starts the service with `--no-block` after a resume with Wi-Fi
  kept loaded, never after an unload. The check waits for a fresh second,
  runs `iw dev <if> info` (a tx power query to the firmware) and reads the
  kernel log from that second. On "Timeout on response for query command"
  or "device unresponsive after D3 inform" it unloads and reloads the stack
  as the hook does, under `systemd-inhibit --what=sleep`.
- `test/all` stubs the tools and covers four cases: post queues the check
  after a kept Wi-Fi; post reloads without the check after an unload; the
  check leaves a Wi-Fi that answers alone; and a query timeout makes it
  reload under the inhibitor.
- On the phone: install it the usual way (no pacman queries, without
  `[omamobile]`), then run Z2g's loop with `systemctl suspend` and a 30 s
  `rtcwake -m no` alarm instead of `rtcwake -m freeze`, so the hook runs.
  The loop stops only on a failed ping that the check didn't fix within 30 s.
- **Pass:** every wake logs "the Wi-Fi firmware answers". On a trap, if one
  comes (about 1 in 30), "reloading the Wi-Fi stack" follows, Wi-Fi is back
  within about 15 s, and the loop goes on.

### 2026-11-05: Z2h, 0.1.7.3 on the phone: 40 of 40, the reload not reached

device-panther 0.1.7.3 installed as usual (no pacman queries; the
contributor key stayed out of the keyring). `omamobile-wifi-check` by hand:
"the Wi-Fi firmware answers". Then 40 cycles of `rtcwake -m no -s 30` and
`systemctl suspend`, so the hook ran each time, with the firmware console
on:

- every cycle woke on the alarm (IRQ 101), the check ran and logged "the
  Wi-Fi firmware answers", and the ping passed at the first try;
- no trap, no query timeout, no PME, no UFS error; `suspend_stats` 76
  successes, 0 failures.
- A first launch stopped after cycle 1 on a false "UFS-ERROR": the loop
  read the whole journal, and systemd logs the unit's own command line,
  which contains the patterns. The relaunch reads only the kernel log and
  the check's own lines.

So the check costs nothing on a healthy wake, but the reload path has
only run against stubs, because no trap came. The tally with the wake off:
2 hangs in 102 resumes. Next, to run the reload on the phone without
waiting for a trap: write a fake "Timeout on response for query command"
line into `/dev/kmsg` while the service runs. The check should then unload
and reload the stack under the inhibitor, and Wi-Fi should come back.

**Z2h, the reload on the phone: passed.** `omamobile-wifi-check.service`
started by hand, and 2.5 s later a fake "brcmf_msgbuf_query_dcmd: Timeout on
response for query command (Z2h injected)" line written to `/dev/kmsg`
(at 14:27:14.86). The check:
- logged "stopped answering ... reloading the Wi-Fi stack" at 15.47;
- unloaded the stack and restarted `omamobile-wifi` ("up: wlp1s0" at
  18.52), logged "Wi-Fi reloaded" at 18.64, and the service ended with
  `Result=success`;
- Wi-Fi rejoined at 23.67 (phy2 to phy3), the wake read `disabled` from the
  rule, and the ping got 2 of 2 replies.

About 9 s from the detection to Wi-Fi back. Not checked: that the sleep
inhibitor was held during the reload (it is gone once the reload ends, and
no sleep was attempted then). With the trap at the resume, the hang now
costs a ~15 s gap after the wake instead of a dead Wi-Fi until the next
sleep.

### 2026-11-05: Z2i, the driver reports the trap (option 2)

**Kernel.** Commit `9d04fc677`'s upstream copy is on branch
`omamobile-brcmfmac-pcie-trap` (worktree `linux-brcmf-trap`, on
`origin/omamobile`, `Assisted-by: LLM`, unsigned). The new
`brcmf_pcie_check_trap()` reads the shared area's flags word (offset 0),
as `brcmf_sdio_checkdied()` and bcmdhd's `dhdpcie_checkdied()` do. On
`TRAP` (0x400) or `ASSERT` (0x200), but not all ones (link gone), it:
- logs "firmware trap <type> at pc, lr, sp (record <addr>)" from the trap
  record at offset 4 (`struct brcmf_trap_info`: pc at 76, lr at 72, sp at 68);
- logs "firmware stopped; reload the driver stack to recover";
- dumps the firmware console, and marks the bus down so commands fail at
  once ("bus is down") instead of after 2 s each.

It reports once per load. It runs from the BCM4389's poll worker (every
10 ms for 500 ms after each interrupt, doorbell and hot resume). It doesn't
call `brcmf_fw_crashed()`: that arms brcmfmac's bus reset, which doesn't
bring this chip back. The test kernel is `ptest-daily5`
(`ptest-daily4` plus this commit), release `g9d04fc677c07`. It builds with
no warning, and checkpatch is clean.

**Package, device-panther 0.1.9.2 (local).** `omamobile-wifi-check` also
matches the new line, and now reads the kernel log from 10 s before it
started: the kernel reports the trap within 10 ms of the resume, before the
check runs, and then a query fails at once without a timeout line. A
new case in `test/all` covers it.

**Z2i on the phone (one boot: asks for approval, spends a slot B retry).**
1. Install 0.1.9.2 the usual way, then `modules-push` and `push` of
   `ptest-daily5`.
2. Smoke check after boot: release `g9d04fc677c07`, Wi-Fi, Bluetooth,
   charger, screen, no failed units.
3. **No false alarm:** Z2h's loop (`systemctl suspend`), 40 cycles. Pass:
   no "firmware trap" line unless the console shows a real trap.
4. **The real thing, if it comes** (about 2 in 100): "firmware trap 0x4
   at pc 0x0027489a" or similar, the check reloads at once, and Wi-Fi is
   back. If the record's pc matches the console's `TRAP` line, the offsets
   are right.

**Z2i results (2026-11-05, `ptest-daily5`, device-panther 0.1.9.2).**
- Smoke check: release `g9d04fc677c07`; Wi-Fi up, Bluetooth powered,
  charging, screen on, no failed units, no trap line at boot. The two
  brcmfmac errors at load (`WLC_SET_ROAM_TRIGGER` -52, `p2p-dev` add
  iface -5) also appear with `ptest-daily4` at every load.
- **No false alarm: 40/40** with `systemctl suspend` and a 30 s alarm.
  Every wake was the RTC (irq 101). In every cycle the check said "the
  Wi-Fi firmware answers" and the gateway answered the ping. There was no
  console `TRAP INFO`, no "firmware trap" or "firmware stopped" line, no
  "bus is down" and no query timeout. The console was on (1358 console
  lines), so `con=0` means no trap, not a silent console.
  `suspend_stats`: 42 successes, 0 failures this boot. A first run was
  stopped at cycle 2 after a touch on the screen; cycle 1 was clean.
- **The real trap didn't come** (2 so far in about 140 resumes with the
  wake off), so the record's offsets and the reload path under this
  kernel are still unproven on the phone. Next: a longer run (100
  cycles) on the same boot, or a forced trap if the firmware has one.

**Z2i, 100 more cycles on the same boot: 100 of 100.** Same loop, from
21:03. Every wake was the RTC (irq 101), the check said "the Wi-Fi firmware
answers" every time, and the gateway answered every ping. No console
`TRAP INFO`, no "firmware trap" or "firmware stopped", no "bus is down", no
query timeout, with the console on throughout (2973 console lines).
`suspend_stats`: 142 successes, 0 failures this boot.

**The trap may belong to the other way of sleeping.** Every hang so far
(Z2, Z2d, Z2f, Z2g) came from loops that sleep with `rtcwake -m freeze`,
straight into the kernel. Z2h and Z2i sleep with `systemctl suspend`, the
way the phone sleeps in use: systemd's sleep path and the omamobile-sleep
hook run around it. The tally with the wake off:
- `rtcwake -m freeze`: about 60 resumes, 2 traps;
- `systemctl suspend`: 181 resumes (Z2h's 40 on `ptest-daily4`, Z2i's 141
  on `ptest-daily5`), no trap.

If the rate were really 2 in 60, no trap in 181 resumes would happen by
chance well under one time in a hundred. Two traps make a rough rate, but
the sleep path looks like it matters. But the
kernel changed between the two (Z2i runs the trap patch), and nothing
yet says which part of systemd's path does it. Next: 40 cycles of
Z2g's loop (`rtcwake -m freeze`) on this same boot. A trap there both
confirms the split and finally exercises the patch's report; the check
doesn't run on that path, so the reload is started by hand.

### 2026-11-05: Z2j, the freeze path on `ptest-daily5`: the trap, reported

Same boot as Z2i (`g9d04fc677c07`, device-panther 0.1.9.2, Wi-Fi's wake
off, console on). Z2g's loop: `rtcwake -m freeze -s 30`, 40 cycles, stop at
the first Wi-Fi error. A first launch stopped after cycle 1 on a false
error: I had added "bus is down" to the stop list, and on this path that
line comes from every suspend (below). The relaunch counts it per cycle
instead.

**The trap came at cycle 11.** Cycles 1-10 were clean (Wi-Fi connected, 2
of 2 pings). At cycle 11's hot resume:
- the console: `THREADX TRAP INFO`, `TRAP 4(326d68): pc 27489a, lr 27488d,
  sp 326fc0, cpsr 60000193, spsr 60000033`, the same pc and lr as Z2g;
- 7 ms after "hot resume", the patch: `firmware trap 0x84 at pc 0x0022e303,
  lr 0x0022e303, sp 0x00326fc0 (record 0x00326d68)`, then "firmware
  stopped; reload the driver stack to recover";
- one command already in flight still timed out 2 s later; after that,
  every command failed at once with "bus is down" (30 in the next minutes);
- Wi-Fi `disconnected`, 0 of 2 pings, and the loop stopped.

**What it proves.** The detection works: the shared flags word and the
trap record's address (offset 4 of the shared area) are right, the record
pointer matches the console's `326d68`, and `sp` at offset 68 matches. The
bus goes down within 10 ms of the resume.

**What's wrong.** Offsets 72 and 76 aren't the console's lr and pc: both
read `0x0022e303`, which looks like the trap handler's own state. The
console's pc is the exception pc, which `struct brcmf_trap_info` keeps as
`epc` at offset 4, and which `brcmf_sdio_trap_info()` prints as
"type 0x%x @ epc 0x%08x". The type reads `0x84` where the console prints
`4`. So the patch should print the raw type, `epc`, `cpsr`, `spsr` and
`sp`, as sdio.c does, and drop the r14 and pc fields. Those four values
are checked against the console only at the next trap.

**The sleep path.** On the freeze path, NetworkManager isn't told about
the sleep: no sleep line from it during Z2j. Instead, brcmfmac
disconnects inside its own suspend callback, and the country-code
change that follows hits a bus already down for D3: one "bus is down"
in 9 of the 10 clean cycles. With `systemctl suspend`, NetworkManager
puts Wi-Fi to sleep first (400 sleep lines in Z2i's window), and Z2i
had no "bus is down" in 141 suspends. The tally with the wake off:
`rtcwake -m freeze`, 3 traps in about 70 resumes; `systemctl suspend`,
none in 181. The hypothesis, not proven: the trap needs the firmware to
enter D3 in the middle of the driver's own disconnect, and the phone in
use doesn't do that, because NetworkManager disconnects first.

`omamobile-wifi-check` doesn't run on this path (no sleep hook). The
Wi-Fi stays down until the stack is reloaded.

**The reload after a real trap.** By hand, the check's own command under a
sleep inhibitor: `modprobe -r brcmfmac_wcc brcmfmac pcie_gs201 && systemctl
restart omamobile-wifi.service`. It returned 0, Wi-Fi was `connected` 8 s
after the start, the gateway answered 2 of 2 pings, and no trap, timeout
or "bus is down" line followed. So the recovery `omamobile-wifi-check`
uses works after a trap the patch reported.

**The decoding fixed.** Kernel commit `6326a5f48` (the same branch,
amended, still unsigned) prints the record's type, `epc`, `cpsr`, `spsr`
and `sp`, as `brcmf_sdio_trap_info()` does, and no longer prints the r14
and pc fields. The message now says what the phone showed. checkpatch
`--strict` reports only the missing sign-off. The test kernel is
`ptest-daily6` (`ptest-daily4` plus that commit), release
`gfb56a7a880cf`, which builds with no warning; `ptest-daily5` is in
`out-ptest-e/prev`.

**Z2k (one boot: asks for approval, spends a slot B retry).** Boot
`ptest-daily6`, smoke check, then Z2j's freeze loop until a trap. Pass:
the report's `epc`, `cpsr`, `spsr` and `sp` equal the console's pc, cpsr,
spsr and sp, and the type is printed as it is in the record.

**Z2k's boot.** The `push` of `ptest-daily6` found slot B with no retry
left (not counted beforehand), so the phone fell to slot A's stock
recovery. Only the recovery screen came up (`adb devices` listed the
phone as `recovery`); Android itself didn't start. Nothing was accepted
there. `adb reboot bootloader` reached
fastboot: current slot A, B retry 0, not successful, not unbootable.
`bin/omamobile flash` wrote slot B's five images and booted
`gfb56a7a880cf`: system running, Wi-Fi up, Bluetooth powered, charging,
screen on, no failed units, no trap or UFS line. Slot B should have 2
retries now. From here, count them before every push.

### 2026-11-05: Z2k, the decoding against a second trap

`ptest-daily6` (`gfb56a7a880cf`), same loop as Z2j. **The trap came at
cycle 3** (cycles 1-2 clean). The wake IRQ reads 102, which in this boot
is `s2mpg12-pmic`, the RTC alarm's path, so the same wake as before.
- Console: `TRAP 4(326d68): pc 27489a, lr 27488d, sp 326fc0, cpsr
  60000193, spsr 60000033`, the same as Z2g and Z2j.
- Patch, 0.3 ms after "hot resume": `firmware trap type 0x84 @ epc
  0x0022e303, cpsr 0x60000193, spsr 0x60000033, sp 0x00326fc0 (record
  0x00326d68)`.

`cpsr`, `spsr`, `sp` and the record address match. **`epc` doesn't**: it
holds the same `0x0022e303` that Z2j read from the r14 and pc fields. So
by the time the host reads the record, all three pc-like fields hold one
address that is neither the console's pc nor its lr. Most likely the
firmware's handler rewrites them to send the core to its halt loop, but
that is a guess. Either way the faulting pc is only in the console, which
the patch already dumps right after its line. Fix: drop `epc` and print
the type, `cpsr`, `spsr`, `sp` and the record, all of which matched on
the phone. Removing a field needs no new trap to check.

The tally with the wake off: `rtcwake -m freeze`, 4 traps in about 73
resumes; `systemctl suspend`, none in 181.

The same reload by hand as in Z2j: Wi-Fi `connected` 8 s after the start,
2 of 2 pings, no trap, timeout or "bus is down" line after it.

### 2026-11-07: Z2l, the Wi-Fi check from its own unit (0.1.10.1)

Upstream's panther test wants `omamobile-sleep` byte for byte the Pixel 7
Pro's, so the follow-up (branch `panther-wifi-check`, device-panther
0.1.11) starts `omamobile-wifi-check.service` from `suspend.target`
(`After=systemd-suspend.service`, conditions on the keep flag and no
fallback) instead of from the hook. 0.1.10.1 carries that change on top of
0.1.9.2's local files (the hook keeps the wake-off, no longer starts the
check) and was installed as usual: built on the phone, `[omamobile]` left
out, the contributor key stayed out of the keyring.

`ptest-daily6`, 25 cycles of `rtcwake -m no -s 30` and `systemctl
suspend`, screen off, firmware console on:
- **1-20 with the keep flag:** every cycle woke on the alarm (IRQ 102),
  the check ran exactly once ("the Wi-Fi firmware answers"), the ping
  passed. From the journal, each check line came 2.63-2.70 s after
  "systemd-suspend.service: Deactivated", so after the hook's post step.
  (The loop's own `ord=` column read BEFORE every time: `systemctl show`
  returns 0 for these oneshot timestamps, so it compared 0 with 0. The
  journal is the record.)
- **21-25 without it:** the hook unloaded and reloaded Wi-Fi, the check
  didn't run, the ping passed.
- No trap, no query timeout, no UFS error (the one match is the loop's own
  command line, logged by systemd, as in Z2h). The flag is back.

The tally with the wake off: `systemctl suspend`, none in 201.

### 2026-11-07: `ptest-daily8`, today's `omamobile`, and fastboot by `reboot=warm`

`ptest-daily8` (`g8f2f45a8427f`): `omamobile` fe12fd24f (Bluetooth, the
flash LED, `reboot=warm` and the fingerprint node, all merged) plus the
local MAX77759 charger node, #181's display series, #195 as in the PR
(dff02ccde), #201, and the wake and trap commits. The DTS took #195 and
#207's blocks both, as derekross said in #195 (a `merge-file --union`
first dropped the fingerprint node's closing lines; redone by hand, and
the build's `dtc` caught it before any push). The flash LED is now
angelrenefm's merged node, disabled until its overlay.

Pushed with slot B at 2 retries (1 left after). On that boot:
- `/proc/cmdline` has `reboot=warm`, `/sys/kernel/reboot/mode` reads
  `warm`; systemd `running`, no failed units; no kernel error line that
  `ptest-daily6`'s boot didn't have.
- `tools/phone-smoke`: display, GPU, session, lock, touch, keys, Wi-Fi,
  Bluetooth, battery and thermal ok (sound, sensors, cameras skipped). The
  panel at 90 Hz, `max77759-charger` charging.
- One `systemctl suspend` with Wi-Fi kept loaded: woke on the alarm (IRQ
  100, `s2mpg12-pmic` in this boot), `omamobile-wifi-check` ran after the
  resume ("the Wi-Fi firmware answers"), 2 of 2 pings.

**`reboot-to bootloader` reached fastboot in 20 s**, no buttons: #198
holds on this phone too. `getvar`: slot B retry 1, not successful, not
unbootable; slot A retry 2, successful. Then `bin/omamobile flash` (the
five `_b` partitions) and the boot back to Linux on `ptest-daily8`.

Slot B's budget after that, read from Linux without a reboot: `devinfo`
(sdd1, read-only) bytes 0x30-0x37 read `02 0a 00 00 02 04 00 00`. Slot A's
retry byte (0x30) is 2, as `getvar` said; slot B's (0x34) is **2**, the
flash's 3 less this boot.

So from now on a low budget needs no buttons: `reboot-to bootloader`,
`getvar`, `flash`. A push still spends one and refills nothing.

### 2026-11-07: Z6c, standby numbers on `ptest-daily8`

**Passed, the same as Z6b.** `power-ab --detach --unplug 60 --phase 600
--settle 30 --rounds 3 --suspend systemd s2idle`, so each B phase sleeps
through `systemctl suspend` and the Wi-Fi check's unit runs at each
resume. Cable out, screen off, Wi-Fi connected with the keep flag and its
wake off, device-panther 0.1.10.1, battery from 100 % down to 90 %:

| Phase | Charge counter | Reported charge | Sampled (A only) |
| --- | --- | --- | --- |
| A, screen off and awake | 166 mAh over 1707 s: **350 mA** | 354 mA | 345 mA, 1.48 W |
| B, screen off in s2idle | 142 mAh over 1803 s: **284 mA** | 296 mA | (frozen) |

- All three B phases froze for the whole 10 minutes (09:15, 09:35, 09:55),
  with no early wake. `suspend_stats`: 3 successes, 0 failures this boot;
  `sleep-fail-count` 0.
- `omamobile-wifi-check` ran once after each resume, about 3.3 s after
  `PM: suspend exit`, and found the firmware answering each time; no
  reload. No trap, no query timeout, no "unresponsive after D3", no UFS
  error (the `dme-set ... failed 0 retries` line comes at every resume, as
  before). Wi-Fi answered 3 of 3 pings after the replug.
- After the last resume one scan failed (`brcmf_vif_set_mgmt_ie: vndr ie
  set error : -52`, `scan error (-52)`), once; it didn't repeat and the
  connection stayed up. The `p2p-dev` interface fails to come up (-5) at
  every resume, as in earlier boots, with no effect.
- s2idle saves about 19 % over awake (Z6b: 17 %). With 4144 mAh, 284 mA is
  about **14.6 hours** of standby (Z6b: 14.4). The reported charge reads
  only 2-4 % above the charge counter this time (Z6b: about 20 %).
- So today's `omamobile`, the wake and trap commits, and the check from its
  own unit change neither the drain nor the stability. Standby still
  depends on deep sleep, not on s2idle work.

### 2026-11-07: Z6d, where s2idle's 284 mA goes (read-only, one 60 s sleep)

On `ptest-daily8`, from kernel state only (sysfs, debugfs counters; no
register reads, and not `clk_summary`, which reads clock rates from the
CMUs), plus one `rtcwake -m no -s 60` and `systemctl suspend` with
counters taken before and after. Woke on the alarm (`s2mpg12-rtc`, the
only wakeup source with an event).

- **The cores do reach their idle state in s2idle.** Timekeeping stops
  across the sleep (Z6c's monotonic clock moved 0.8 s across each 10-minute
  sleep), which happens only once every online CPU is in s2idle. The
  cpuidle s2idle counters read about 0 ms for the same reason: they count
  in that stopped clock. Each sleep is 2 s2idle entries per CPU, so one
  wake before the alarm that went back to sleep.
- **Nothing deeper exists.** `gs201.dtsi` gives each CPU one idle state,
  `arm,psci-suspend-param = <0x00010000>`, a core power-down; no cluster
  or system level, no `domain-idle-states`. `pm_genpd` is empty: no power
  domain is ever turned off (G3D is left on by the bootloader, as the
  dtsi says, and so are the others). `deep` (PSCI `SYSTEM_SUSPEND`) is
  offered but the phone doesn't wake from it (`10-omamobile.conf`).
- **No memory or bus DVFS.** The only devfreq device is the GPU's, so MIF
  and INT stay where the bootloader left them, asleep and awake.
- **The GPU never runtime-suspends**, on purpose:
  `20-omamobile-gpu-always-on.rules` holds `power/control` at `on`, since
  powering G3D back up needs a secure call this kernel doesn't make
  (device/cheetah/GPU-PLAN.md). This weighs mostly on the awake phase.
- Smaller: the touch supplies (`vdd-ts`, `avdd-ts`) stay enabled with the
  screen off, and the S2MPG12/13 LDOs and BUCKs aren't Linux regulators,
  so nothing puts them in a sleep mode. Runtime-active while awake: UFS,
  the GPU, the Wi-Fi link (kept loaded), and dwc3 on the cable.

So the gap to stock's SYS_SLEEP (32-50 mA) is the SoC and PMIC staying on
around powered-down cores: stock reaches cluster power-down, SICD and the
PMIC's sleep through ACPM, and none of that is in Linux for gs201 (the
Pixel 7 Pro shares `gs201.dtsi`, so the same holds there). No small change
closes it. The levers are a gs201 power-domain driver (which would also
let the GPU suspend) or a working `deep`; why `deep` doesn't wake is the
open question that a read-only look at the stock sleep sequence could
start on.

### 2026-11-08: Z2m, 50 cycles of `systemctl suspend` with the check's unit

On `ptest-daily8` with device-panther 0.1.10.1 (the check from its own
unit) and `wifi-keep-across-sleep`, on the cable: 50 cycles of
`rtcwake -m no -s 30`, `systemctl suspend`, then 12 s, the journal since
the cycle began, and 2 pings over `wlp1s0`, from a detached loop on the
phone (19:25-20:06, about 49 s a cycle).

- **50 of 50.** `suspend_stats` +50 successes, 0 failures;
  `sleep-fail-count` 0; the fallback flag never set.
- The check ran exactly once after each resume and found the firmware
  answering all 50 times; no reload.
- No trap, no "Timeout on response for query command", no "unresponsive
  after D3", no UFS error. 50 of 50 pings passed.
- Each resume logs `brcmf_p2p_create_p2pdev: timeout occurred` once:
  wpa_supplicant re-creating `p2p-dev-wlp1s0`, which the firmware doesn't
  answer (the `-5` seen in Z6c). Station Wi-Fi isn't affected, and the
  check rightly doesn't match it.

The tally with the wake off: `systemctl suspend`, none in 256 (201, plus
`ptest-daily8`'s 1, Z6c's 3, Z6d's 1 and these 50). A real trap caught by
the check on this path still hasn't happened.

### 2026-11-08: Z6e, why `deep` doesn't wake, and two nearer levers (laptop only)

Read against Google's `kernel/google-modules/soc/gs`, branch
`android-gs-pantah-6.1-android16` (057ab18, a sparse checkout in
`~/android/google/gs-soc`), stock's `gs201.dtsi` and `gs201-pm-domains.dtsi`,
and today's `omamobile`.

**`deep`: the answer is already in device/cheetah/SUSPEND-PLAN.md, sections
1 and 5, and holds for panther (same SoC, same firmware path).** Stock goes
through the same PSCI `SYSTEM_SUSPEND` Linux offers, but its `exynos-pm`
syscore step first writes the EINT wake masks (PMU `0x3a80-0x3a88`), clears
`WAKEUP_STAT` and sets `WAKEUP_INT_EN` (`0x3944` = `0x1001f0bf`: RTC, EINT,
EINT_FAR, the AoC mailbox, the PCIe and USB wakes; `0x3964` = `0x1f0`), and
`cal_pm_enter(SYS_SLEEP)` writes CPU_INFORM = 4 (gs201's
`CPU_INFORM_SLEEP`), saves the CMU registers and does the three enter
writes; on wake, the exit sequence releases pad retention. Checked again
today:
- mainline defines `GS101_TOP_INT_EN` (`0x3944`) and nothing writes it;
- `exynos-pmu`'s `suspend_noirq` stops writing CPU_INFORM for a firmware
  suspend and writes no SLEEP hint either;
- stock's cpuidle states are ours (`0x0010000`, core power-down only):
  stock's lower s2idle-like draw comes from its PMU and ACPM work, not
  from deeper PSCI states.
So `deep` stays a PMU sleep driver plus the list in cheetah's section 5:
no short PR.

**Nearer: what the Pixel 6 already did.** linux-omarchy-mobile#9 (merged
2026-10-27) gave gs101 André Draszik's `google,gs101-pd` series with the
blocks nothing uses (TPU, BO, MFC, G2D, the camera pipeline) as disabled
domains that genpd powers off, and set ACPM's MIF to 1014 MHz with
`assigned-clocks` (ABL leaves it at 2028 MHz). Measured there: about 45 mA
less with the domains off, about 70 mA less with MIF at 1014 MHz, screen
on. gs201 has none of it: no `power-domain@` node in `gs201.dtsi`, no
`assigned-clocks` on its ACPM node. The pieces exist: stock's
`gs201-pm-domains.dtsi` lists each domain's PMU offset (AOC, EH, G3D,
embedded G3D, HSI0, HSI2, DISP, DPU, G2D, MFC, CSIS, PDP, G3AA, IPP, ITP,
DNS, MCSC, GDC, TNR, BO, TPU, AUR), and our bindings have
`GS201_CLK_ACPM_DVFS_MIF`. Both would lower the draw awake and in s2idle,
since these blocks and the bus stay on in both.

**Step 1, panther's rates** (debugfs `clk_rate` of the ACPM clocks, which
`clk-acpm` reads with an ACPM DVFS get-rate message, no CMU access), on
`ptest-daily8`, screen on: MIF **2028 MHz**, INT 200, DISP 400, CPU
clusters 1803/1491/1745, G3D 151, TPU 226, BO 95, MFC 100, CAM/INTCAM/TNR
67 MHz. Stock's gs201 `devfreq_mif` has `freq_info = <421000 421000 421000
421000 3172000 1014000>` (initial, default QoS, suspend, min, max, reboot,
kHz): stock idles and suspends MIF at 421 MHz and memlat raises it with CPU
load. So panther, like the Pixel 6 before #9, keeps the memory bus at about
five times stock's idle rate, awake and in s2idle.

For a panther change: `gs-decon` (#181) already holds the `mif` clock and
asks for a 1352 MHz floor whenever the panel runs above 60 Hz, panther's
90 Hz included; that floor was sized for the 7 Pro's 1440x3120 at 120 Hz.
By its own comment, dropping a floor doesn't lower the rate, so a boot rate
from `assigned-clocks` (as on raven) would stay at 1352 MHz once the panel
has run at 90 Hz. Testing any of it takes a DT change and one boot.

**Step 2, the domains.** Stock's `gs201-pm-domains.dtsi` puts them in the
PMU (`0x18060000`) at the offsets `gs101.dtsi` uses since #9: G2D `0x2300`,
MFC `0x2380`, CSIS `0x2400`, PDP `0x2480`, DNS `0x2500`, G3AA `0x2580`,
IPP `0x2600`, ITP `0x2680`, MCSC `0x2700`, GDC `0x2780`, TNR `0x2800`, BO
`0x2880`, TPU `0x2900`; gs201 adds AUR `0x2980`, and EH `0x1c00`, AOC
`0x1880`, G3D `0x1e00`, embedded G3D `0x2000`, HSI0 `0x2080`, HSI2
`0x2180`, DPU `0x2200`, DISP `0x2280`. The driver (`google,gs101-pd`,
André Draszik's series) is in our tree.

| Domain | On panther | For a change |
| --- | --- | --- |
| G2D, MFC | no driver | off |
| PDP, G3AA, IPP, ITP, DNS, MCSC, GDC, TNR | no driver (the ISP pipeline) | off |
| BO, TPU | no driver | off |
| AUR (gs201 only) | no driver | off, to confirm |
| CSIS | not enabled in panther's DT today, but the 7 Pro's camera work runs on it and device-panther has `omamobile-camera-start` | left on (raven turned it off: it uses no camera) |
| EH | unknown (stock's memory compression) | left on |
| AOC, HSI0, HSI2, DPU, DISP, G3D | in use | untouched |

For the change itself:
- `google,gs101-pmu.yaml` exempts `google,gs201-pmu` from `#address-cells`,
  `#size-cells` and `ranges`; `pd` children on gs201 need that adjusted.
- On gs101, IPP's parent is PDP and DNS's is ITP; stock's gs201 file names
  no parents, so the hierarchy needs checking.
- No `samsung,dtzpc`, as in #9: powering off is safe, but a block's driver
  must bring its CMU and D_TZPC before anything powers it back on.

Measuring it takes one boot of a test kernel. Both levers (these domains
and MIF) in one kernel, then `power-ab` as in Z6c, spend one slot B retry
for both. On the Pixel 6: about 45 mA (domains) and 70 mA (MIF), screen
on.

### 2026-11-08: Z6f, standby numbers with MIF at 1014 MHz (`ptest-daily9-mif`)

One change against Z6c's kernel, split from Z6e's plan (one change per
boot): `ptest-daily9-mif` is `ptest-daily8` plus `assigned-clocks =
<&acpm_ipc GS201_CLK_ACPM_DVFS_MIF>; assigned-clock-rates = <1014000000>;`
on panther's `&acpm_ipc` (`7.3.0-rc6-omamobile-push1-gacdfb7d990c3`). The
domains go in a later boot (`ptest-daily9-pd`).

At boot `gs-decon` logs MIF at 1014 MHz; once the panel runs at 90 Hz its
floor raises it to **1352 MHz**, and it stays there (read after the run).
So this measures 1352 MHz, not 1014.

`power-ab --unplug 60 --phase 600 --settle 30 --rounds 3 --suspend systemd
s2idle`, unplugged, screen off, same as Z6c:

| | Z6c (MIF 2028) | Z6f (MIF 1352) | Change |
| --- | --- | --- | --- |
| A, awake, screen off (charge counter) | 350 mA | 303.7 mA (144 mAh over 1707 s) | -46 mA |
| B, s2idle (charge counter) | 284 mA | 243.6 mA (122 mAh over 1803 s) | -40 mA |
| s2idle, about 4300 mAh | about 14.6 h | about 17.5 h | +3 h |

The reported charge gives 316.3 and 251.6 mA, the same direction. Four
suspends, no failures; `omamobile-wifi-check` found the firmware answering
after each resume and no brcmf trap was logged. Right after the last resume,
brcmf logged a `scan error (-52)` and several `Received unexpected monitor
pkt` lines; Wi-Fi stayed up.

Takeaways:
- The bus rate alone is worth about 40-46 mA, awake and in s2idle, close
  to the Pixel 6's 70 mA from 2028 to 1014. (Not shown: see Z6i. Z6h, at
  2028 MHz on another day, came within 16 mA of these figures.)
- `gs-decon`'s 1352 MHz floor at 90 Hz holds back the rest; a lower floor
  for panther's 1080x2400 panel is a separate change for later.
- Next: the domains alone (`ptest-daily9-pd`, on top of `ptest-daily8`).
  Slot B has one retry left, so that kernel goes in through `reboot-to
  bootloader` and `flash`, not `push`.

### 2026-11-08: Z6g, the domains kernel resets the phone in s2idle (`ptest-daily9-pd`)

One change against Z6c's kernel: `ptest-daily9-pd` is `ptest-daily8` plus
the 12 disabled `google,gs101-pd` domains of Z6e step 2 (G2D, MFC, PDP,
G3AA, IPP, ITP, DNS, MCSC, GDC, TNR, BO, TPU), with PDP→IPP and ITP→DNS as
subdomains (`7.3.0-rc6-omamobile-push1-g0d13d5b3cd0f`, flashed through
`reboot-to bootloader` and `flash` with one slot B retry left).

The boot was clean: `phone-smoke` passed, MIF at 2028 MHz as on Z6c, and
genpd listed all 12 domains as `off-0` (TPU's ACPM clock read 0 Hz).
`pd_ignore_unused` is on the command line, so genpd didn't power them off
itself: most likely ABL had left them off and the driver read that state
at probe. That alone would put the gain near zero.

`power-ab` as in Z6c (unplugged, screen off). Phase A ran normally (about
326 mA, 22:02-22:13). The first `systemctl suspend` logged `PM: suspend
entry (s2idle)` at 22:13:04 and nothing more: no `suspend exit`, no oops,
no warning, and `/sys/fs/pstore` empty after the reboot (but see the
correction below: that doesn't mean ramoops caught nothing). The next boot
came up at 22:23:32, about 10.5 minutes later, when the RTC wake was due:
the phone reset on the way into or out of s2idle, most likely on the wake.
The reset spent a slot B retry (one left). No numbers.

Back to `ptest-daily9-mif` through `reboot-to bootloader` and `flash`
(modules first: the domains kernel's `modules-push` had replaced them),
slot B at 2 retries after the boot, and one 30 s `systemctl suspend` on the
cable resumed with Wi-Fi answering.

Lesson: run one short suspend on the cable before every long measurement
on a new kernel, as before Z6f; here it was skipped, and it would have
shown the reset in 30 s.

**Why, read on the laptop (step 3 of Z6e's follow-up).** Most likely
cause, not yet tested:
- `exynos-pm-domains.c` (`google,gs101-pd`) reads each domain's STATUS at
  probe and hands it to `pm_genpd_init`, so `off-0` was the hardware state
  ABL left; nothing in Linux had powered these blocks on or off.
- DNS and IPP are subdomains (`power-domains = <&itp>` and `<&pdp>`). Their
  provider platform devices (`18062500.power-domain`,
  `18062600.power-domain`) are therefore attached to ITP and PDP as
  devices, as genpd's summary showed. No other device sits in any of the 12
  domains.
- genpd's system sleep path: `genpd_finish_suspend` finds ITP and PDP
  already off and does nothing, but `genpd_finish_resume` (`resume_noirq`)
  calls `genpd_sync_power_on` for every device's domain whether or not the
  device is runtime suspended. So on the first wake, ITP and PDP are
  powered **on** for the first time since boot, then the runtime path
  powers them off again.
- Stock's power-on for these blocks (`pmucal_local_enable`, gs201's
  `flexpmu_cal_local_gs201.h`) is the same CONFIGURATION/STATUS write the
  mainline driver does, followed by the D_TZPC restore SMC (`need_smc`,
  D_TZPC base + `0x204`, on every one of these domains) and a restore of
  the block's CMU and Q-channel registers. Our DT has no `samsung,dtzpc`,
  so mainline skips the SMC and restores nothing. Powering ITP and PDP on in
  `resume_noirq` that way is the one hardware action this kernel adds to a
  suspend, and a reset at that point fits it (Z6h confirms the cause).
- The same hierarchy is in `gs101.dtsi`, and raven enables PDP, IPP, ITP
  and DNS. linux-omarchy-mobile#9 says "Not tested: suspend with the domains
  off", so the Pixel 6 may hit this too.

Test for it, one change: `ptest-daily9-pd` without the two parent links
(DNS and IPP as top-level domains). Then no device sits in any domain,
genpd never powers one during suspend, and the blocks stay off. One 30 s
suspend on the cable first, then `power-ab`.

### 2026-11-08: Z6h, flat domains suspend fine (`ptest-daily9-pd2`)

One change against Z6g's kernel: `ptest-daily9-pd2` drops the two parent
links on panther (`/delete-property/ power-domains` on DNS and IPP), so
the 12 domains are top-level and no device sits in any of them
(`7.3.0-rc6-omamobile-push1-g77030b310b66`). Loaded with `push`, then
reflashed through `reboot-to bootloader` and `flash` so that slot B kept
two retries for the check.

genpd lists the 12 domains as `off-0`, with no children and no devices,
before and after every resume. One 30 s `systemctl suspend` on the cable,
then `power-ab` as in Z6c (unplugged, screen off): five suspends in all,
no failures, no reset (6 h uptime afterwards, slot B still at two
retries). `omamobile-wifi-check` found the firmware answering after each
resume, and no brcmf trap was logged. That confirms Z6g's cause: genpd
powering ITP and PDP on at resume.

| | Z6c (`ptest-daily8`) | Z6h (`ptest-daily9-pd2`) | Change |
| --- | --- | --- | --- |
| A, awake, screen off (charge counter) | 350 mA | 320.6 mA (152 mAh over 1707 s) | -29 mA |
| B, s2idle (charge counter) | 284 mA | 259.6 mA (130 mAh over 1803 s) | -24 mA |

MIF ran at 2028 MHz on both kernels. The reported charge gives 329.0 and
267.6 mA. These numbers can't be put down to the domains: ABL had left the
blocks off and this kernel never touches them. More likely the difference
comes from conditions on another day (battery level, temperature, Wi-Fi
network) against Z6c's single baseline. Z6g's phase A on the first domains
kernel, which didn't touch the blocks either, ran at about 326 mA.

Takeaways:
- On panther the domains save nothing that can be measured: the blocks are
  already off. With parent links they reset the phone on resume. Not worth
  a panther PR; MIF is the lever that pays.
- raven enables the same PDP→IPP and ITP→DNS hierarchy, and
  linux-omarchy-mobile#9 lists suspend with the domains off as untested.
- To compare kernels fairly, measure `ptest-daily8` and `ptest-daily9-mif`
  again on the same day under the same conditions.

### 2026-11-09: correction to Z6g, where ramoops goes

Z6g read an empty `/sys/fs/pstore` as "ramoops caught nothing" and leaned
on that for a reset from below the kernel. That reading was wrong.
`systemd-pstore` is enabled on the phone: at every boot it moves the
ramoops record out of `/sys/fs/pstore` into
`/var/lib/systemd/pstore/console-ramoops-0`, always the same file name, so
each boot overwrites the last one's record (derekross/omarchy-mobile#578
found the same on the 8 Pro). By the time it was looked for, the reset's
record had already been replaced by four later boots; checked on
2026-11-09, only the newest file is there.

So Z6g doesn't show whether the kernel logged anything before the reset.
The cause stands on the code reading and on Z6h, not on pstore.

Next time a boot follows a reset, first copy
`/var/lib/systemd/pstore/console-ramoops-0` aside on the phone (it stays
there: it may hold identifiers and is never committed), before any other
reboot.

### 2026-11-09: Z6i, MIF at 1014 MHz at 90 Hz too (`ptest-daily9-mif2`)

One change against Z6f's kernel: `ptest-daily9-mif2` lets a `gs-decon`
mode set carry its own MIF floor above 60 Hz and gives the Pixel 7's
1014 MHz instead of 1352 (kernel commit `c20f7101b`,
`7.3.0-rc6-omamobile-push1-gc20f7101b73d`, flashed through `reboot-to
bootloader` and `flash`). The reasoning: 1080x2400 at 90 Hz reads
0.93 GB/s through DPP0, less than the 7 Pro's 1440x3120 at 60 Hz
(1.08 GB/s, no floor) and well under its 120 Hz (2.16 GB/s, the 1352 MHz
pairing). Stock has no fixed figure to copy: its DPU votes bandwidth
through `bts.ko` and the MIF devfreq picks the rate.

On the phone MIF stayed at **1014 MHz** at 90 Hz. The display, checked by
eye while scrolling and playing video (no flicker, lines or freezes) and
by the `stats` file over 242 s: 21807 frames (90.0 Hz), 6285 flips,
`flips_late` 0, `flip_timeouts` 0, flip latency 5.9 ms on average and
11.7 ms at most. Our driver doesn't count underruns, so the eye is the
check for those. One 30 s suspend on the cable, then `power-ab` as in Z6c:
five suspends in all, no failures, no reset, Wi-Fi answering after each,
MIF still at 1014 MHz afterwards.

| | Z6c (2028, 11-07) | Z6h (2028, 11-08) | Z6f (1352, 11-08) | Z6i (1014, 11-09) |
| --- | --- | --- | --- | --- |
| A, awake, screen off (charge counter) | 350 mA | 320.6 mA | 303.7 mA | 303.9 mA (144 mAh over 1706 s) |
| B, s2idle (charge counter) | 284 mA | 259.6 mA | 243.6 mA | 247.6 mA (124 mAh over 1803 s) |

The reported charge gives 316.5 and 251.6 mA, as in Z6f.

Takeaways:
- 1352 → 1014 MHz makes no difference that can be seen with the screen off
  or in s2idle (0-4 mA, inside the noise).
- 2028 → 1352 MHz isn't shown either (Z6j, the same day, shows 2028 →
  1014 MHz is worth about 50 mA). Z6f's 40-46 mA came against Z6c,
  but Z6h, at 2028 MHz the same day as Z6f, sits only 16 mA above it.
  Runs on different days differ by 25-30 mA, as much as what's being
  measured.
- Before any MIF or `gs-decon` PR: measure `ptest-daily8` (2028 MHz) and
  `ptest-daily9-mif2` (1014 MHz) back to back on the same day. About 40 mA
  would make it worth a PR; under 10 mA would not.

### 2026-11-09: Z6j, MIF 2028 against 1014 MHz on the same evening

Three `power-ab` runs back to back, as in Z6c (unplugged, screen off),
alternating the kernels so drift shows up: `ptest-daily9-mif2` (MIF
1014 MHz at boot and at 90 Hz, Z6i's run), then `ptest-daily8` (MIF
2028 MHz, the same build as Z6c, `g8f2f45a8427f`), then
`ptest-daily9-mif2` again. Each kernel went in through `reboot-to
bootloader` and `flash`, with its modules first; slot B stayed at two
retries.

| | mif2, 20:32 | daily8, 21:47 | mif2, 23:00 |
| --- | --- | --- | --- |
| MIF | 1014 MHz | 2028 MHz | 1014 MHz |
| A, awake, screen off (charge counter) | 303.9 mA | 362.7 mA (172 mAh over 1707 s) | 316.3 mA (150 mAh over 1707 s) |
| B, s2idle (charge counter) | 247.6 mA | 295.5 mA (148 mAh over 1803 s) | 251.4 mA (126 mAh over 1804 s) |
| A, mean power | 1292 mW | 1495 mW | 1282 mW |
| Battery at start | 90 % | 92 %, 30.2 °C | 84 %, 31.1 °C |

The reported charge gives 371.2/303.5 mA for daily8 and 329.0/267.4 mA
for the second mif2 run. Every run: no failed suspend, no reset, Wi-Fi
answering after each resume, no brcmf trap; on mif2 MIF stayed at
1014 MHz with `flips_late` and `flip_timeouts` at 0.

The two mif2 runs agree within 12 mA awake and 4 mA in s2idle (the
battery went from 90 to 75 % across them); daily8 sits 46-59 mA above
both. Against the mean of the two mif2 runs:
- awake, screen off: **-52 mA (-14 %)**, -13 % in power;
- s2idle: **-46 mA (-16 %)**, about 17 h instead of 14.5 h on about
  4300 mAh.

Close to the Pixel 6's 70 mA (linux-omarchy-mobile#9). This compares
2028 against 1014 MHz as a whole; Z6i already shows the 1352 → 1014 step
alone hardly shows with the screen off.

Takeaways:
- The MIF rate is worth a panther PR: `assigned-clocks` at 1014 MHz on
  `&acpm_ipc`, with `gs-decon`'s 1014 MHz floor for the Pixel 7 as its own
  commit (without it the panel's 90 Hz takes MIF back to 1352).
- Same-day, alternating runs are what tell kernels apart: runs on
  different days differed by 25-30 mA.

### 2026-11-10: the GPU under load with MIF at 1014 MHz (`ptest-daily9-mif2`)

For the MIF PR (raven checked a glmark2 minute; the phone has no glmark2,
and nothing gets installed for a check): mpv on Vulkan (panvk, Mali-G710
on panthor) scaling `av://lavfi:testsrc2=s=640x360:r=90` to full screen
with `--profile=high-quality`, `ewa_lanczossharp` for all three scalers,
interpolation and deband, at 90 Hz. A first try with a 1920x1080 source
was CPU-bound (about 10 fps) and is not counted.

Three runs, 60, 60 and 120 s. devfreq's `trans_stat` put the GPU at its
top 848 MHz for about 60, 63.5 and 119.8 s, MIF at 1014 MHz throughout.
DECON stayed at 90 Hz (10820 frames in the 120 s run) with `flips_late`
and `flip_timeouts` at 0; mpv itself managed about 30 fps, CPU-bound, so
the pattern ran at a third of its speed. No panthor, MMU, DECON or DSIM
messages. The pattern looked right on screen and in two photos (bars,
moving shapes and the counter whole, frame numbers matching 90 fps of
content, no lines, offsets or garbage). The photos stay off the repo.

Note: on this kernel the GPU devfreq's `cur_freq` and the ACPM `g3d`
clock in debugfs read 151 MHz all along, also at 848 MHz. Read the time
in each level from `trans_stat` instead.

### 2026-11-12: Z6k, what keeping Wi-Fi across sleep costs (`ptest-daily9-mif2`)

Three `power-ab` runs as in Z6c (unplugged, screen off, `--suspend
systemd`), one evening and night, alternating the sleep hook's two modes on
the same kernel (MIF 1014 MHz): unload (no
`/etc/omamobile/wifi-keep-across-sleep`: the hook unloads Wi-Fi before
sleep and reloads it after), keep (the flag: Wi-Fi stays loaded, its PCI
wake off, `omamobile-wifi-check` after each resume), unload again. Every
run up to Z6j had the flag.

| | unload, 21:48 | keep, 23:05 | unload, 02:05 |
| --- | --- | --- | --- |
| A, awake, screen off (charge counter) | 295.3 mA (140 mAh over 1707 s) | 303.7 mA (144 mAh) | 295.3 mA (140 mAh) |
| B, s2idle (charge counter) | 183.7 mA (92 mAh over 1803 s) | 243.6 mA (122 mAh) | 199.7 mA (100 mAh) |
| A, mean power | 1275 mW | 1271 mW | 1167 mW |
| Battery at start | 95 % | 88 % | 68 % |

The reported charge gives 239.6 mA for keep's B and 203.7 mA for the second
unload's. Every run: three suspends of the full 10 minutes, each woken by
the RTC (IRQ 103), no failure (`suspend_stats` 9 and 0), no trap, no query
timeout, Wi-Fi answering pings at the end. In unload mode the hook logged
"Wi-Fi unloaded for sleep" and "Wi-Fi reload queued" each time, the driver
came back on a new `phyN` about 2 s after resume and reconnected; after
each reload `WLC_SET_ROAM_TRIGGER error (-52)` and the `p2p-dev` failure
(-5), as at boot, with no effect. Once, just before an unload, "Scan abort
failed". In keep mode the check found the firmware answering after each
resume, with the scan error (-52) seen in Z6c.

Awake, the three runs agree within 8 mA, so the evening didn't drift.
Keep's s2idle matches Z6j's (248 and 251 mA). Against the mean of the two
unload runs (191.7 mA):
- s2idle with Wi-Fi kept: **+52 mA (+27 %)**; unloading saves 21 %, about
  22.5 h of s2idle instead of 17.5 h on about 4300 mAh;
- as much as the MIF change (Z6j, 46 mA).

Takeaways:
- With its wake off, keeping Wi-Fi buys only a faster reconnect after a
  resume (no reload, about 2 s of firmware load saved), at 52 mA all the
  time asleep. Unload is the right default while nothing wakes on Wi-Fi.
  The package already behaves so: device-panther doesn't ship the flag.
- Keep mode only earns its cost with a wake through the radio (WoWLAN, the
  wake branch). The wake PR should measure its s2idle against these
  numbers.
- The phone keeps the flag for the trap and wake work.

### 2026-11-13: P7, power off powers off (`ptest-daily10`)

The Pixel 7 Pro's P7 on this phone, on `ptest-daily10`
(`7.3.0-rc6-omamobile-push1-g78a54921b02a`): `omamobile` 82f31d3a7, which
carries linux-omarchy-mobile#233 (the S2MPG12's WTSR and SMPL restarts
disarmed at power off), plus the charger DT, #181 with the 90 Hz series,
#195, the brcmfmac wake and trap commits and the MIF commit. Loaded with
`flash`; its first boot came up at 90 Hz with MIF at 1014 MHz and Wi-Fi
connected, and a 30 s `systemctl suspend` resumed with the Wi-Fi check
passing (the panel stays asleep after an RTC wake; Power brought it back
at 90 Hz, 451 frames in 5 s). Battery 83-86 %.

| Case | Shutdown | Then | Slot B retries |
| --- | --- | --- | --- |
| Cable out (a 30 s `systemd-run` timer, the cable pulled before it fired) | clean: "Reached target System Power Off", `systemd-shutdown` syncing, the journal stopped 10 s after `systemctl poweroff` | **stayed off** until Power was held; a normal boot on slot B | 2 → 1 (a boot from Power spends one) |
| Cable in | clean, the same lines | the bootloader's charger boot on its own: its charging icon for under a second, then our kernel with `androidboot.mode = "charger"` on slot B, the whole phone up (no charger-mode handling in device-panther yet) | 2 → 2 (the charger boot spent none) |

`androidboot.bootreason` read `"reboot", "uvlo", "pmic", "if"` after both
power-ons, and plain `"reboot"` after a `flash` boot (a warm reboot), so
the list belongs to a cold power-on. Not decoded further.

Before #233 power off restarted this phone (NOTES, 2026-10-27 and -28),
as it did the Pixel 7 Pro on `kernel-2026.11.08` (its P7 of 2026-11-12).

Takeaways:
- Power off works on the Pixel 7 once a kernel carries #233. Until a
  kernel release does, the power menu's Shutdown restarts a release phone,
  as on the Pixel 7 Pro.
- Z6a's condition is met on this kernel: the upower drop-in
  (`CriticalPowerAction=PowerOff`, `PercentageAction=3`) can follow once a
  kernel release carries #233.
- With the cable in, the charger boot starts the whole phone. The Pixel 7
  Pro handles `androidboot.mode = "charger"` in its device package
  (#730, device-cheetah 0.1.55, which carried #554's commits); panther needs the same before the drop-in, or a
  phone powered off on the cable comes back up.
