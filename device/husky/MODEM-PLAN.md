<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro modem plan (husky, Samsung S5300)

Status (2026-11-08): on hold. Stages S1 to S5e have been run; none of them
hung, oopsed or raised a UFS error (S5c stopped on its own current abort,
see below). No modem step and no power-line step has been run since S5e
ended at 2026-11-07 23:21, and I take none on the 8 Pro until derekross
answers the question on omarchy-mobile#472
(https://github.com/derekross/omarchy-mobile/pull/472#issuecomment-6711065625;
see "Current state: on hold" below).
This file is the record of S1 to S5e: what each step does, its gates, its
stop conditions, the dated result with the kernel release, and what the
result does not prove.

[V] = read in source, stock DT or my captures on the phone. [I] = inferred;
each [I] names the step that would settle it.

Stock references are the GrapheneOS shusky GPL tree
(`android-gs-shusky-6.1-android16`). The modem driver is the stock CPIF
(`modem_ctrl_s5100.c`, `s5300` node), the PCIe side is `pcie-gs201-cp`
from W4HO's stack in linux-omarchy-mobile#187.

## Test kernels

All steps ran from slot B on a test kernel built from my husky e1 branch
plus the #187 stack and the husky device tree, with the modem nodes
disabled unless the step enables them.

| Set | `uname -r` | Used for |
| --- | --- | --- |
| images-plain, images-s1, images-s2 | `7.3.0-rc6-omamobile-push1-gc5b6ae8f4dc2` | boot 1 (plain), S1, S2, S3 (images-s1 again) |
| images-s4 | `7.3.0-rc6-omamobile-push1-g6a203e4b8a67` | S4, S5a to S5e |

Between stages the phone went back to the normal NFC set (release
`...ge98a7`), so a test boot is never the running system for long.
Where a log did not print `uname -r` itself, the table says which image set
was flashed; the lines below say so for each stage.

## Safety (all stages)

Gates, all of which must hold before any stage:

- I am at the phone with the USB cable in. The charger is in too, except in
  S5d and S5e, which are battery-only on purpose.
- Battery 50 % or more; battery temperature under 40 C at the start; SoC at
  or under 62 C (idle SoC is about 53 C). A `THERMAL-PAUSE` file blocks the
  step.
- A current backup of the images and the config is on the desktop
  (`backup-pre-s3-20261107`, five slot-B images as flashed, `/etc` and user
  config, SHA256).
- Retry count read in fastboot: 3 after `set_active b`. Every boot of a
  flashed slot B spends a retry (devinfo byte 0x35 went 06 to 04 at the
  first flash), and at 0 GrapheneOS wipes userdata, so I count boots and
  never run more than two boots of one flash.
- No process holds `/dev/umts_boot0`; no cbd, rfsd or ModemManager runs; no
  suspend.
- Each hardware step (S3, S5a, S5b, S5c, S5d, S5e) needs my explicit go in
  that turn.

Never, in any stage: cbd, rfsd, any firmware or ROM image,
`IOCTL_POWER_ON` or the boot ioctls (they write CP DRAM and there is no way
back), writes to `umts_boot0`, `allow_poweroff=1`, the `cp_on`, `cp_off`
and `atu` debugfs files, the SIM, stock slot A (its first boot can wipe
userdata), and the `efs`, `efs_backup`, `modem_userdata`, `persist`,
`modem_a` and `modem_b` partitions (read-only checks only).

General stop rules: a hang, USB loss, an oops or an rcu stall; any UFS
counter going up or a `ufshcd_err_handler started` line that does not
recover in seconds; a pin or line reading different from what the previous
log said; battery temperature over 45 C. Never reboot with the modem lines
high: `gpio_off` first, reboot only after an all-0 read. A phone that ends
with a dead screen is not woken or rebooted; I run the dead-screen kit
first.

## S1: PCIe controller and PHY loaded, no hardware access (2026-11-07 20:47)

What it does: boots the test kernel with `pcie_0` and its PHY enabled in the
device tree and runs `modprobe pcie-gs201-cp` with `allow_hw=0`. The module
probes and registers; it does not touch the link.

Gates: the general ones; boot 1 of the flash checked first (plain boot up,
Wi-Fi and NFC working, no modem module loaded, 7 fixed regulators, the modem
pins at their baseline: gph1-2 an output at 0, gph1-1 and gph1-7 inputs at
0).

Stop: the general rules; any modem pin changing.

Result [V], kernel `7.3.0-rc6-omamobile-push1-gc5b6ae8f4dc2`: PASS. Probe
rc 0, PMU 0x3ec4 = 0xc0 (the same as on the 9a), PHY 0/0, link 0, IRQ
counts 0, pins unchanged.

Does not prove: that the PHY or the link work (nothing was read from them);
anything about the modem.

## S2: modem node enabled, driver not loaded (2026-11-07 20:52)

What it does: the same kernel with the `modem` node enabled in the device
tree. No cpif module loaded. Reads the seven AP2CP and four CP2AP lines.

Gates and stop: as S1.

Result [V], kernel `7.3.0-rc6-omamobile-push1-gc5b6ae8f4dc2` (image set
images-s2; I did not copy `uname -r` into the S2 log, the set shares the
S1 build): PASS. All 7 AP2CP and 4 CP2AP lines read 0, pins equal baseline,
PMU 0xc0, clean shutdown. After it the phone went back to the NFC set.

Does not prove: anything beyond "the node enabled changes nothing on the
pins before a driver loads".

## S3: one PCIe link attempt with the modem off (2026-11-07 21:15, my go)

What it does: `allow_hw=1`, PHY trace every 100 ms, exactly one
`link_up 1` try. The stock module tries three times; for this step I
rebuilt the module with `CP_LINK_TRIES` 3 to 1 (same vermagic, test only,
not committed; the original module stayed on the phone as
`/root/pcie-gs201-cp.ko.tries3`). The modem is off, so no endpoint is
expected.

Gates: the general ones, plus the backup above, plus a review of the S1/S2
evidence. SoC had peaked at 62 C during backups and builds, so the step
waited for every zone at 62 C or less.

Stop: a hang; an oops; no progress in the PHY trace.

Result [V], kernel `7.3.0-rc6-omamobile-push1-gc5b6ae8f4dc2` (image set
images-s1, flashed again for this step; the kernel is in the S3 dmesg log):
no hang. Trace: PMU bit 0 set (SMC), first PMA read, PLL on, PMA and PCS
tables, external PLL lock 1, PLL lock 1, CDR lock 1, offset calibration
done 1, PMU bit 10 set, DBI ID 0xa5a5144d; then `no L0, LTSSM 0x0` and
`link_up 1: -110` (no endpoint). After: PMU 0x3ec4 = 0x4c1, PHY 1/0, link
0, `link_down` rc 0, 53 C, no oops, Wi-Fi up. The PCIe "active" pinctrl
state changed the function of gph0-0 (PERST, now output 0), gph0-1
(CLKREQ), gpa0-1 (output 0 to input), gpa0-2 (input to output 0), gpa6-5
and gpa7-0; all DAT 0; gph1-1, gph1-2 and gph1-7 untouched.
It also answered one open question: HSI1 and its PHY/controller are
reachable with only the PMU 0x3ec4 bit 0 SMC before the first access (stock
source does the same).

Does not prove: that the PCIe link works. The AP side starts, the link
itself has never been tested, because the modem was off. Not settled: who
powers the modem, what gpa0-1 drives, the S2MPU windows for CP memory.

## S4: cpif loaded, modem stays OFFLINE (2026-11-07 22:10)

What it does: flashes the S4 set (cpif enabled, overlay `modem-s4-cpif`),
then `modprobe pcie-gs201-cp` (`allow_hw=0`), `modprobe shm_ipc`,
`modprobe cpif`. cpif probe sets the seven AP2CP lines as outputs at 0.
No power-on, no link, no firmware.

Gates: the general ones, plus before the load: gph1-2 an output at 0, the
six other lines inputs at DAT 0 with PUD 0x1 (pull-down); UFS stats all 0
and no `ufshcd_err_handler started`; no modem module, no `umts` node; 56 C.

Stop: the general rules; any `poweron`, `link up` or phone_state line in
dmesg (the two `link up` lines at boot are the Wi-Fi's HSI2 link).

Result [V], kernel `7.3.0-rc6-omamobile-push1-g6a203e4b8a67`: PASS. All
seven AP2CP lines are outputs at 0 (CON 0x1), the CP2AP inputs unchanged,
`modem_state` OFFLINE, PMU 0xc0, PHY 0/0, link 0, UFS counters 0 before and
60 s after, no oops, Wi-Fi up, 57 C. `shm_ipc` mapped the three reserved
regions (`cp-rmem@ea400000`, `cp-msi@f6200000`, `cp-rmem1@e8000000`) with
no fault. The probe log matches stock's values: `mif_off_during_volte:1`,
`num_iodevs:54`, `link_attrs:0x000037c8`, `PCIe Channel Number:0`,
`s5300 is created`. `cpif_probe: Failed to register logbuffer!` appears;
it is debug-log registration only and I did not look into it. The reboot
to bootloader ran cpif's shutdown path with the modem OFFLINE.

Does not prove: who powers the modem or in what order; any way to power it
down (stock cpif has none once the modem is on); anything about firmware or
the SIM.

## S5: power lines, in five parts

The hook (test only, not for merge): `modem_ctrl_s5100.c` gets a debugfs
directory `cpif_test/`, created only when cpif is loaded with
`cpif_test_gpio=1`. Files: `lines` (read, the 11 line levels and
`phone_state`), `gpio_off` and `gpio_on` (any write fires them; they call
only the stock `gpio_power_off_cp` and `gpio_power_offon_cp`; `gpio_on` is
refused with -EBUSY unless all 7 AP2CP lines read 0), and from S5c a
`pda_active` file. No state change, no CP memory write
(`clear_boot_stage` and `init_ctrl_msg` are skipped on purpose), no PCIe,
no PMU, no ioctl. cpif has no module_exit, so it cannot be unloaded.

Edges [V] (stock `modem_ctrl_s5100.c:874-903`, non-`CP_WRESET_WA` branch,
confirmed compiled; `CP_WRESET_WA`, `CP_LCD_NOTIFIER` and
`LINK_DEVICE_PCIE_GPIO_WA` are not set in this build):

- `gpio_off` from the all-0 state: one 10 ms pulse of `ap2cp-wakeup`;
  `nreset`, `cp_wrst`, `cp_pwr` and `pm_wrst` are rewritten to 0 (no
  change).
- `gpio_on` from all-0: that pulse, then `pm_wrst` 1, `cp_pwr` 1, `nreset`
  1, `cp_wrst` 1, 10 ms apart, about 130 ms in all.
- `gpio_off` with the lines high: wakeup pulse, `nreset` 0, `cp_wrst` 0,
  `cp_pwr` 0 (30 ms), `pm_wrst` 0 (50 ms).

Setup for each S5 stage: push the new `cpif.ko` (the S4 original kept as
`/root/cpif.ko.s4-original`), write `/etc/modprobe.d/modem-test.conf` (the
blacklist lines), flash images-s4, count 3, stream `dmesg -w` to the desktop,
repeat the S4 pre-checks, then `modprobe pcie-gs201-cp`, `shm_ipc`,
`cpif cpif_test_gpio=1`.

Extra stop rules for S5b to S5e: `gpio_on` returning -EBUSY or -EINVAL (do
not retry, read `lines`, stop); any `IOCTL_`, `poweron`, `link up` or
`SET GPIO ... not valid` line; the modem lines on for more than 60 s in one
cycle; battery down more than 3 % in the stage; if a CP2AP line stays high
after `gpio_off`: do not write `gpio_off` again, do not write
`pda_active` = 0, do not reboot, read `lines` every 10 s for 2 minutes and
stop.

### S5-0: read only (2026-11-07 22:25)

`cat cpif_test/lines`: all 11 lines read 0, `phone_state` 0. No write.
Kernel `7.3.0-rc6-omamobile-push1-g6a203e4b8a67` (`modem-s5-pre.txt`; this
read did not print `uname -r` again). That checks the read path and the
module parameter. It does not show that a later power-on is safe.

### S5a: gpio_off from the all-0 state (2026-11-07 22:25:50, my go)

This is the hook run (one write to `gpio_off` from the all-0 state). The
earlier note that S5a was NO-GO meant the pre-hook plan: cpif has no
software power-off, and `IOCTL_POWER_ON` writes CP DRAM. That plan was not
run. This result is only the hook's `gpio_off`.

What it does: one write to `gpio_off` with everything at 0, to see whether the
way down runs from the all-0 state and leaves the lines at 0.

Result [V], kernel `7.3.0-rc6-omamobile-push1-g6a203e4b8a67`: PASS. The
log shows the 10 ms wakeup pulse and `nreset`, `cp_wrst`, `cp_pwr` and
`pm_wrst` rewritten to 0 as duplicates; "after" all 0; 60 s later all 0,
OFFLINE, UFS counters 0, no error handler start, no oops, Wi-Fi up, 57 C,
battery 92 %.

Does not prove: that `gpio_off` is safe with the modem on (that is only
shown in S5b).

### S5b: first power-on of the lines (2026-11-07 22:34:12, separate go, charger in)

What it does: `/root/s5b.sh` on the phone: one `gpio_on`, one sample per
second of `lines` for 55 s, then `gpio_off`, then samples. `pda_active`
stays at 0 (the hook cannot set it yet).

Stop: the general rules and the S5 rules; `gpio_off` at 55 s whatever
happened.

Result [V], kernel `7.3.0-rc6-omamobile-push1-g6a203e4b8a67` (S4 image set;
the S5b log itself does not print `uname -r`): the edges came in stock
order, 10 ms apart. For the 55 s the four AP2CP power lines read 1 and all
four CP2AP lines (`ps_hold`, `wakeup`, `cp_active`, `cp_wrst`) stayed 0;
`phone_state` OFFLINE; UFS 0 before, during and after; battery 92 %,
battery 35.8 to 36.1 C; no oops, no hang. After `gpio_off` all 11 lines 0,
57 C, Wi-Fi up. (My sleeps were shorter than the labels in the script
output; the tail covered about 20 s, and a check at 22:37 read all 0.)

Does not prove: that the modem has no power. Stock `power_on_cp` sets
`ap2cp-pda-active` to 1 and `dump-noti` to 0 right before the power-on and
clears the shared-memory control blocks (stock `modem_ctrl_s5100.c:990-991`);
S5b did neither. Current was not measured.

### S5c: S5b again with pda_active = 1 and current sampling (2026-11-07 22:44, my go)

What it does: `/root/s5c.sh` (hook with the `pda_active` file): 30 s
baseline of lines, UFS, battery `current_now`, `current_avg` and voltage;
`pda_active` = 1; one `gpio_on`; 1 s samples; `gpio_off`; `pda_active` = 0
only if all four CP2AP lines read 0. Built-in aborts to `gpio_off`: any UFS
counter or error handler start, battery over 45 C, `current_now` more than
300 mA below the baseline.

Result [V], kernel `7.3.0-rc6-omamobile-push1-g6a203e4b8a67`: ended by its
own abort after 24 s (one `current_now` sample at -303 mA against a 117 mA
baseline mean); `gpio_off`, `pda_active` = 0. All four CP2AP lines read 0
in every sample; UFS 0 throughout; no oops; clean end state. A no-write
control run with the same music playing and the charger in showed the same
kind of slide (`current_avg` from +170 mA to about 0, one -377 mA sample),
so the current figures of S5b and S5c are inconclusive.

Does not prove: anything about the modem's current draw. The charger
(holding 92 %) can feed the rail, and music was playing. From here on the
abort rule uses a median of 5 or more samples and the current runs are
battery-only.

### S5d: battery-only current around the power-on (2026-11-07 22:58:17, my go)

What it does: `/root/s5d.sh`, USB cable out, music off, screen off, ssh
over Wi-Fi after an identity check (model and exact test kernel). Phase A
150 s with no writes; phase B `pda_active` = 1 then one `gpio_on`
(23:00:51), 60 s, median-of-5 abort (UFS error, battery over 45 C, or a
5-sample median more than 300 mA below the baseline median); `gpio_off`,
`pda_active` = 0 if the CP2AP lines are 0; phase C 120 s no writes; phase D
120 s no-write control. Battery 92 % at 38.1 C, SoC 59 C.

Result [V], kernel `7.3.0-rc6-omamobile-push1-g6a203e4b8a67` (S4 image set;
the identity check before the run read it, but the S5d log itself does not
print `uname -r`): ran the full 60 s (no abort). Median `current_now` per phase: A -550.6 mA, B -615.9 mA,
C -556.3 mA, D -554.7 mA (negative = discharge). The three no-write phases
agree within about 10 mA; the power-on phase is about 60 to 65 mA deeper (62 against the mean of A, C
and D), with a
sharp start at the `gpio_on` write and a sharp return after `gpio_off`. All
four CP2AP lines 0 in every sample; UFS 0; battery 38.1 to 37.1 C.

Does not prove: that the load is the modem. `pda_active` = 1 was written
immediately before `gpio_on` (back-to-back writes in the script, no timing
recorded), so the two cannot be split; it is one run;
the CP2AP lines never moved. `s5d.sh` has no signal trap, so a killed
script would not have switched the lines off by itself.

### S5e: pda_active separated from gpio_on (2026-11-07 23:12:35, battery only)

What it does: `/root/s5e.sh` (v3, with INT, TERM and HUP trapped into a
safe off, started with `nohup setsid`), USB out, screen off. Phases: A
baseline 90 s | E1 `pda_active` = 1 alone 30 s | B base 60 s | E2 `gpio_on`
with `pda_active` low 60 s | C base | E3 `pda_active` = 1 then `gpio_on`
60 s | D base | E1b replicate of E1 30 s | E base. The script had a
simulated four-case test before the run.

Result [V], kernel `7.3.0-rc6-omamobile-push1-g6a203e4b8a67` (S4 image
set; the log does not print `uname -r`): no phase hit a stop; UFS 0 and all
four CP2AP lines 0 in every sample; clean end state. Median `current_now` (as printed by the script):
A -556.6 mA, E1 -541.3, B -561.3, E2 -607.2, C -550.9, E3 -611.6, D -560.6,
E1b -546.9, E -548.1. `pda_active` alone does not change the current (E1
is about 18 mA less discharge than the mean of A and B and E1b about 8 mA
less than the mean of D and E: noise). `gpio_on` draws about 51 mA extra with `pda_active` low (E2 against
the mean of B and C) and about 56 mA with it high (E3 against C and D); S5d
measured about 60 to 65 mA. The step starts one sample after each `gpio_on` write
and ends one sample after `gpio_off`, all three times. Medians only: the
screen woke during two baseline phases (about 9 s in B, about 11 s in D right
after the E3 `gpio_off`; S5d had the same shape once in C), which makes the
means unreliable but sits against the effect, not for it.

Does not prove: that the load is the S5300. It could be another load on the
same rail, a power stage or level shifters with no modem core behind them,
or the ROM idling. The CP ROM gave no sign of life on any CP2AP line.
Two battery-only runs, three power-on phases, one phone and one gauge.

## Current state: on hold

- No further modem step and no power-line step on the 8 Pro until derekross
  answers the question on omarchy-mobile#472
  (https://github.com/derekross/omarchy-mobile/pull/472#issuecomment-6711065625);
  his instruction to wait is on linux-omarchy-mobile#187.
- The hook is on the branch `husky-modem-cpif-test-hook` of
  Somnius/linux-omarchy-mobile (commit 058a439b3). It is test only and not
  for merge.
- `tools/nv-backup --check` on 2026-11-08: `efs`, `efs_backup`,
  `modem_userdata`, `persist`, `modem_a`, `modem_b`, `trusty_persist` and
  `trusty_userdata` are SAME as the 2026-11-01 10:01 backup. `devinfo` is
  different, as expected (the retry bit and boot counts change with every
  flash).
- The phone is on the normal NFC image set. The first revert boot on
  2026-11-07 had no drivers because a clean-up timer had deleted the
  module folder; I fixed it by hand between 23:26 and 23:35 and checked the module
  tree before every revert since.
- Not run, and not to be run before the answer: S6 (the same power-on plus
  one `link_up` try with the modem powered), a PMIC power-meter reading of
  the modem channel, repeats of the S5 power-ons for more statistics.

## Unknowns

- Whether the 50 to 65 mA is the modem [I]. A control that would split it:
  not available without a way to see the CP side (S6 or the power meter).
- Which rail the lines switch. The stock husky DT has no regulator or
  consumer named cp, modem, rfic, rf, lte, 5g, sub6, vdd_cp or qlink [V];
  `cp_pwr_on` and `pm_wrst_n` are plain pinctrl there, so the rail is
  unknown. The only modem-named items are PMIC power-meter sense channels
  (`VSYS_PWR_MODEM`, `VSYS_PWR_RFFE`, `VSYS_PWR_MMWAVE`), which suggests the
  modem runs from VSYS [I, from the DT only]. The PCIe0 rails are S2MPG14
  LDO16M and LDO18M, which our driver does not cover.
- Whether the CP ROM waits for the shared-memory control blocks or for the
  PCIe link before any CP2AP line moves [I]. Stock `power_on_cp` writes
  `clear_boot_stage` and `init_ctrl_msg` before the lines; the hook skips
  that on purpose. `cp2ap_cp_wrst_n` (gpa0-1) is high while the CP is alive
  in stock logic and stayed 0 here; whether it rises before PCIe training
  is unknown. Source reading, then S6, would settle it.
- What the bootloader does with the modem lines on a forced reboot or a
  hang. Nothing in my notes covers it. Only the power button remains for a
  hung kernel, and the debugfs hook exists only while the test module is
  loaded.
- Whether a power-off edge triggers the UFS error pass on husky (it did on
  cheetah). S5b, S5c, S5d and S5e saw none.
- The husky modem image and partition mapping, the BAR and doorbell layout,
  and who sets up the S2MPU windows for CP memory.
