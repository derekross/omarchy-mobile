<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): suspend

Status (2026-10-16): **S0 and S1 passed; S2 (kernel) next.** Raven follows cheetah's
suspend plan (`device/cheetah/SUSPEND-PLAN.md` on `main`: s2idle first,
SYS_SLEEP later); this file records only what differs on gs101 and the
results. Kernel: `omamobile-gs101-merge-test` (`gb4d96e9c3ab7` on the
phone); the suspend changes will go on a new `omamobile-gs101-suspend`
branch in `~/android/mainline/wt-raven-split`.

Slot A holds GrapheneOS, which can't boot over Omarchy's `userdata`
(NOTES, 2026-10-27): a hang is recovered by holding Power about 30 s,
which boots slot B again while it has retries. Suspend stays hidden in the
menu (`suspend-off`) until S8.

## 1. What cheetah needed, and raven's state

| Cheetah change | On raven |
| --- | --- |
| `mem_sleep_default=s2idle` (`6d41c1f58`): the firmware offers PSCI SYSTEM_SUSPEND, so "mem" means `deep`, which needs a PMU sleep sequence we don't have | missing: `mem_sleep` is `s2idle [deep]`. Never `echo mem` or `systemctl suspend` until it is in |
| exynos-pmu keeps the CPU idle hint in s2idle (`5dc5cbb48`): otherwise the firmware refuses every power-down and the idle loop spins | missing; the driver is shared with gs101, so cherry-pick |
| UFS `spm_lvl` 5 (`d0c08c464`, gs201 only): `gs101_ufs_suspend()` asserts the device reset, so level 3 failed hibern8 exit on resume | missing: `spm_lvl` 3. The same function runs on gs101; `echo 5` at runtime first, then a gs101 default |
| S2MPG12 PMIC and RTC enabled by overlay | already there: `s2mpg10-rtc` is `rtc0` (in sync with NTP), `rtc-alarm0` is a wakeup source |
| PM debug config | already there: `/sys/power/pm_test` exists |
| Wi-Fi D3 as control messages (unpublished cheetah commits) | missing: unload Wi-Fi before every sleep (cheetah's unload mode) |

## 2. S0 results (2026-10-16, `gb4d96e9c3ab7`, read-only)

- `state` `freeze mem disk`, `mem_sleep` `s2idle [deep]`, `pm_test`
  `[none] core processors platform devices freezer`.
- cpuidle `state0`, `state1` (C2); broadcast `mct-comp`.
- UFS: `spm_lvl` 3, `rpm_lvl` 3, the device WLUN runtime-active with
  `control` `auto`.
- Wakeup-enabled: the Wi-Fi PCIe function, the fuel gauge, pmic-1
  (S2MPG10) and its RTC, pmic-2 (S2MPG11), `gpio-keys`. The PMIC and
  `rtc-alarm0` interrupts are at 0 while idle (no storm); the gauge at
  2565 after about 2 h 20 min.
- No `sleep.conf` drop-in and no sleep hook installed; `suspend-off` set.

## 3. Runbook

Common: log to `/var/lib/omamobile/suspend/` and run detached
(`systemd-run`), because USB drops while asleep. Before every stage, unload
Wi-Fi: `modprobe -r brcmfmac_wcc brcmfmac` (expect `lsmod | grep -c brcm`
0); afterwards `modprobe brcmfmac`. After every stage `dmesg | grep -E
"ufshcd_err_handler|hibern8|I/O error"` must be empty. Never `rmmod` the
AoC modules.

**S1: pm_test dry runs on the current kernel (no flash).** `freezer`, then
`devices`, each a 5 s automatic test with no wake source needed.
`platform` waits for the kernel with the exynos-pmu fix (S2), because it
runs the noirq phase that drops the CPU idle hint.

```sh
tools/phone-ssh 'modprobe -r brcmfmac_wcc brcmfmac; lsmod | grep -c brcm
U=$(ls -d /sys/bus/platform/devices/*.ufs); echo 5 > $U/spm_lvl
mkdir -p /var/lib/omamobile/suspend; systemd-run --collect --unit=s1-test sh -c "
  L=/var/lib/omamobile/suspend/s1-\$(date +%H%M%S).log
  echo 1 > /sys/power/pm_print_times; echo 1 > /sys/power/pm_debug_messages
  for t in freezer devices; do
    sync; echo \$t > /sys/power/pm_test; echo == \$t >> \$L; date >> \$L
    echo freeze > /sys/power/state; echo rc=\$? >> \$L; sleep 10
  done
  echo none > /sys/power/pm_test; dmesg | tail -400 >> \$L; sync"'
# USB drops for a few seconds per level; reconnect after about a minute
tools/phone-ssh 'grep -E "^==|rc=" /var/lib/omamobile/suspend/s1-*.log
dmesg | grep -iE "PM:|failed to (suspend|resume)|ufshcd|error" | tail -40; modprobe brcmfmac'
```

- **Screen:** stays lit. gs-decon's system-sleep callback does nothing
  (`platform_pm_resume returned 0 after 0 usecs`), so the panel and
  backlight stay on through every stage; userspace has to turn the panel
  off before sleep (as cheetah's shell does).
- **Pass:** two `rc=0`; no "failed to suspend"; no UFS error; display,
  touch, GPU, audio and Bluetooth work afterwards; Wi-Fi reconnects.
- **Stop:** a device fails to suspend or resume (record which), or the
  phone doesn't answer on USB after 3 min (ask the human to hold Power
  about 30 s).
- **Risk:** low to medium: first suspend of raven's AoC, gs-decon and
  panfrost.

**S1 result (2026-10-16 10:14, `gb4d96e9c3ab7`): passed.** Wi-Fi unloaded
(`brcmutil` stays loaded, harmless), `spm_lvl` 5 at runtime. `freezer` and
`devices` both `rc=0`; devices suspended in 54 ms and resumed in 369 ms; USB
back on its own within 30 s. No UFS error. Afterwards the backlight was on,
Bluetooth powered, the AoC, sensor proxy and speaker protection active, and
Wi-Fi reconnected 15 s after `modprobe brcmfmac`.

**S2 (flash):** `omamobile-gs101-suspend` with the exynos-pmu fix, raven's
`mem_sleep_default=s2idle` and a gs101 `spm_lvl` 5 default; then
`pm_test platform`.

**S2 result (2026-10-16 10:24, `g8ec6110f6eed`): passed.** After the push,
`mem_sleep` reads `[s2idle] deep` and `spm_lvl` 5 at boot. `platform` `rc=0`:
devices suspended in 41 ms and resumed in 368 ms; no UFS error. Afterwards
the backlight was on, the AoC, speaker protection and Bluetooth active, and
Wi-Fi reconnected after `modprobe brcmfmac` (`p2p-dev` add timed out once,
harmless).

**S3 result (2026-10-16 10:24, `g8ec6110f6eed`): passed.** Raven's first
real s2idle: `rtcwake -m freeze -s 30` `rc=0`, timekeeping suspended for
33.6 s, woken by IRQ 111 (gpa0-6, the S2MPG10 PMIC that carries the RTC
alarm). Devices suspended in 49 ms and resumed in 369 ms; no UFS error;
backlight, AoC, speaker protection and Bluetooth fine; Wi-Fi reconnected
after `modprobe brcmfmac`; USB back on its own.

**S4 result (2026-10-16 10:31, `g8ec6110f6eed`): passed.** 10 cycles of
`rtcwake -m freeze -s 20` with 10 s awake between: 10 `rc=0`,
`suspend_stats` 12 success / 0 fail, device resume at most 369 ms, no UFS
error. AoC, speaker protection and Bluetooth stayed active; Wi-Fi
reconnected after `modprobe brcmfmac`. The panel stayed lit throughout
(see Screen above), so these runs say nothing about battery yet.

**Battery, s2idle vs awake (2026-10-16 10:32-11:04, `g8ec6110f6eed`,
cable out, locked, panel off by the power key).** Detached script: 5 min
awake (Wi-Fi loaded), 10 min asleep (Wi-Fi unloaded, `rtcwake -m freeze`
re-armed after each wake), twice; drain from the fuel gauge's
`charge_counter`.

| Phase | Time | Drain | Mean |
|---|---|---|---|
| awake 1 | 300 s | 32 mAh | 384 mA |
| asleep 1 | 603 s | 64 mAh | 382 mA |
| awake 2 | 300 s | 32 mAh | 384 mA |
| asleep 2 | 603 s | 62 mAh | 370 mA |

The phone really was asleep (freezes of 29-385 s, about 593 s of each
600 s), yet s2idle saves almost nothing: about 375 mA asleep against
384 mA awake, where cheetah's s2idle draws 274-286 mA. Wakes came from the
RTC (IRQ 111) and from the fuel gauge's alert line (IRQ 139, gpa9-3,
`max170xx_battery`), a dark wake to look at. 17 suspends, 0 failures, no
UFS error. s2idle only idles the CPUs; whatever holds raven's floor
(MIF at 1014 MHz, the display pipeline's domains, the AoC, rails) keeps
running. Next: find what draws the ~375 mA (POWER-PLAN) before any
sleep policy is worth shipping.

**Why that run saved nothing (2026-10-16, read-only check):** after
`modprobe -r brcmfmac_wcc brcmfmac` the BCM4389 stays powered
(`wlan-reg-on` enabled) with its PCIe link up at 5 GT/s in D0 and no
driver: no power save. Unloading `pcie_gs201` too runs its deinit (PERST#,
PHY off, pwrctrl off): `wlan-reg-on` drops to 0 and the bus goes away;
`modprobe pcie_gs201; modprobe brcmfmac` brings Wi-Fi back and it
reconnects. Unload both for sleep, as cheetah's plan says.

**Second run, Wi-Fi and PCIe unloaded while asleep (11:12-11:44, same
kernel and setup):**

| Phase | Time | Drain | Mean |
|---|---|---|---|
| awake 1 | 300 s | 32 mAh | 384 mA |
| asleep 1 | 602 s | 48 mAh | 287 mA |
| awake 2 | 300 s | 36 mAh | 432 mA |
| asleep 2 | 602 s | 50 mAh | 299 mA |

**s2idle with Wi-Fi powered off draws about 293 mA against about 408 mA
awake (Wi-Fi on): about 115 mA less**, in line with the 274-286 mA reported
for cheetah's s2idle. 21 suspends, 0 failures, no UFS error; wakes: RTC
(IRQ 111) twice, fuel gauge (IRQ 139) twice. The rest of the floor is the
SoC's active state (rails, DRAM, MIF); only SYS_SLEEP (cheetah's section 5,
about 50 mA there) goes below it.

**S5, Wi-Fi across sleep (2026-10-16, `g8ec6110f6eed`): passed.** Raven's
kernel already carries cheetah's brcmfmac D3 work (control-message mailbox
data with its epoch byte, ACK after RX, `synchronize_irq()` before
masking); firmware 20.101.91. One `rtcwake -m freeze -s 30` with Wi-Fi
connected: `rc=0`, "D3 ACK by control message after 13564 us", "hot
resume", connected, ping working. Then 10 cycles (`-s 20`, 8 s awake): 10
`rc=0`, connected every time, 9 of 10 single pings answered, 11 D3 ACKs,
0 suspend failures, no commonring or UFS error.

**Auto sleep (device-raven 0.1.7-0.1.8, shell 0.2.9):** `omamobile-sleepd`
(user, behind `omarchy-toggle omamobile-sleep`) suspends once locked and
dark for 10 s with no USB host and no SSH over a live link; the hook keeps
Wi-Fi connected (0.1.8; unloading saved about 115 mA but took 7-10 s to
reconnect) and falls back to unloading after a Wi-Fi D3 failure. A power
press that came after Omarchy's lock had blanked the panel flashed it on
and off: the lock lit the panel on the key a moment after the press, and
`omamobile-keys` judged the release by the lit panel; shell 0.2.9 judges by
the panel at the press.

**S3:** the first real freeze, `rtcwake -m freeze -s
30`, unattended (the RTC already works). Then cheetah's S4-S8 (loop, AoC
and sensors, battery numbers, userspace).
