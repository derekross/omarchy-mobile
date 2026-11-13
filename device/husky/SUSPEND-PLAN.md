<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky): suspend

Status (2026-11-12): **draft for review, nothing in section 3 has run on
this unit.** s2idle has run on one 8 Pro already: Lef's `systemctl suspend`
cycles in #640 and #642 (58 s and about 10 min asleep, woken by Power, the
display back at 120 Hz). This file is the runbook Derek asked for on #656
before a first attended suspend test on another unit: what husky has for
the three things he named (Wi-Fi across sleep, UFS `spm_lvl`, NFC), the
stages, and how to get out. It follows cheetah's
[SUSPEND-PLAN](../cheetah/SUSPEND-PLAN.md) (s2idle first, SYS_SLEEP later)
and raven's, and records only what differs on zuma and the results.

Unit: G1MNW, Samsung 128 GB UFS 3.1. Kernel for H0: `7.3.0-rc6-omamobile-push1-g755b5d1c5532`
(Brett's `husky-test-20261109-t1` tag plus the RTC commits merged as
linux-omarchy-mobile#243), `omamobile-device-husky` 0.1.10.

## 1. What cheetah and raven needed, and husky's state

| Needed on cheetah / raven | On husky (H0, read-only) |
| --- | --- |
| s2idle, never `deep`: the firmware offers PSCI SYSTEM_SUSPEND, so "mem" means `deep`, which has no zuma sleep sequence in Linux and would not wake | the H0 kernel reads `s2idle [deep]`; device-husky 0.1.10's `sleep.conf.d` drop-in makes systemd's Suspend use s2idle; `mem_sleep_default=s2idle` is in `zuma-husky.dts` since linux-omarchy-mobile#244. A test that writes `/sys/power/state` must write `freeze`, never `mem` |
| Wi-Fi: a sleep hook (cheetah, raven) that keeps it connected through brcmfmac's D3 handshake, or unloads Wi-Fi and the PCIe host | **no hook**: `/usr/lib/systemd/system-sleep/` has only Omarchy's `unmount-fuse`. Loaded: `brcmfmac_wcc`, `brcmfmac`, `pcie_gs201`, `phy_zuma_pcie`; the BCM4398 at `0000:01:00.0` in D0. Whether the D3 handshake works on zuma is unknown [U]. So every stage below unloads Wi-Fi and the PCIe host first, as raven's second battery run did |
| UFS at `spm_lvl` 5 (at 3, the first hibern8 exit on resume failed and needed a host reset) | `13200000.ufs`: `spm_lvl` 5 at boot, `rpm_lvl` 3, `auto_hibern8` not supported, runtime `active` [V]. Checked again before every stage |
| NFC not polling through s2idle (AGENTS.md, the 9a) | no NFC driver bound and no `/sys/class/nfc` on this kernel [V] (the node is disabled; #208 and #209 are drafts). Checked again before every stage; with a driver bound, stop |
| cpuidle with C2, or s2idle saves nothing | **no cpuidle** (`current_driver` none): the CPUs can't power down, so s2idle here is expected to save little. Lef measured about 0.5 A idle with the screen off (ROADMAP), and the idle-state and power-domain overlays tried so far reboot-looped (ROADMAP, Suspend row). These stages test that the phone sleeps and wakes cleanly, not battery life |
| The AoC modules: never `rmmod` | not loaded on this kernel (no sound series); nothing to do |

Wakeup-enabled on H0: `gpio-keys`, pmic-1 (S2MPG14) and its RTC
(`s2mpg14-rtc`, `rtc0`, alarm interrupt firing on `rtcwake`, checked
2026-11-11), the fuel gauge, the Wi-Fi function, the Bluetooth serdev.
Interrupt counts at idle: pmic-1 and `rtc-alarm0` 0, the gauge 10 (no storm).
`suspend_stats` success 0 / fail 0: this unit has never suspended this boot.
Omarchy's `suspend-off` toggle is set and `omamobile-sleepd` runs, so the
phone doesn't sleep on its own [V]. Inhibitors: NetworkManager, UPower and
Omarchy's lock, all `delay`.

## 2. Rules and recovery

- Attended, with Colin at the phone and the USB cable in. One stage per
  go-ahead; read the result before the next.
- Slot B only, no flash in H1-H4 (the kernel stays the H0 kernel).
- Run every sleep detached with `systemd-run` and log to
  `/var/lib/omamobile/suspend/`: USB (and Wi-Fi, once unloaded) drops while
  asleep. `sync` before every sleep.
- Before every stage: `spm_lvl` 5; no `/sys/class/nfc`; Wi-Fi and PCIe
  unloaded (`modprobe -r brcmfmac_wcc brcmfmac pcie_gs201`, then
  `lsmod | grep -c -E "brcm|pcie_gs201"` is 0; `brcmutil` may stay).
  After every stage: `dmesg | grep -E "ufshcd_err_handler|hibern8|I/O error"`
  is empty, then `modprobe pcie_gs201 && modprobe brcmfmac`.
- Never press Shut down (#578) or Suspend in the menu during these stages.

Recovery:

- **No answer on USB 3 min after the stage should have ended, screen dark,
  no reaction to Power:** hold Power + Volume Up 15-30 s (UFS-PLAN U5: a
  frozen kernel ignores sysrq), then Power + Volume Down for the bootloader.
  The next boot of slot B uses one of its retries (2 left on 2026-11-12);
  refill with `fastboot set_active b` before booting it again.
- **Wakes, but USB doesn't come back:** the session should be on screen;
  restart from the menu's Restart, then read the log.
- **Any UFS error on resume** (error handler, I/O errors, read-only
  remount): restart at once, stop, report. No more sleeps on that kernel.
- **Suspend refuses** (the write returns an error): not dangerous. Read
  `dmesg` for the device and stop.

Stop conditions: any UFS error; an RCU stall, soft lockup or "SMC failed";
a wake that needs the buttons; an interrupt storm on pmic-1 or the gauge;
a device that fails to suspend or resume.

## 3. Runbook

Common helper on the laptop (as cheetah's `freeze_cmd`):

```sh
cd ~/omarchy-mobile
pre='U=/sys/bus/platform/devices/13200000.ufs; [ "$(cat $U/spm_lvl)" = 5 ] || exit 3
[ ! -e /sys/class/nfc ] || exit 4
modprobe -r brcmfmac_wcc brcmfmac pcie_gs201; lsmod | grep -c -E "^brcmfmac|^pcie_gs201"'
freeze_cmd() {   # freeze_cmd NAME [rtcwake-seconds]
  local n=$1 secs=${2:-} enter='echo freeze > /sys/power/state'
  [[ -n $secs ]] && enter="rtcwake -m freeze -s $secs"
  printf '%s' "mkdir -p /var/lib/omamobile/suspend; systemd-run --collect --unit=$n-test sh -c '
    L=/var/lib/omamobile/suspend/$n-\$(date +%H%M%S).log
    cat /sys/power/suspend_stats/success /sys/power/suspend_stats/fail >> \$L
    date >> \$L; sync; $enter; echo rc=\$? >> \$L; date >> \$L
    echo wakeup_irq=\$(cat /sys/power/pm_wakeup_irq 2>&1) >> \$L
    dmesg | tail -300 >> \$L; sync'"
}
```

**H0: read-only state.** Done 2026-11-12 (section 1).

**H1: pm_test dry runs, no real sleep.** `freezer`, `devices`, then
`platform`: each a 5 s automatic test with no wake source needed.

```sh
tools/phone-ssh "$pre"
tools/phone-ssh 'mkdir -p /var/lib/omamobile/suspend; systemd-run --collect --unit=h1-test sh -c "
  L=/var/lib/omamobile/suspend/h1-\$(date +%H%M%S).log
  echo 1 > /sys/power/pm_print_times; echo 1 > /sys/power/pm_debug_messages
  for t in freezer devices platform; do
    sync; echo \$t > /sys/power/pm_test; echo == \$t >> \$L; date >> \$L
    echo freeze > /sys/power/state; echo rc=\$? >> \$L; sleep 10
  done
  echo none > /sys/power/pm_test; dmesg | tail -400 >> \$L; sync"'
# reconnect after about a minute
tools/phone-ssh 'grep -E "^==|rc=" /var/lib/omamobile/suspend/h1-*.log
dmesg | grep -iE "PM:|failed to (suspend|resume)|ufshcd|error" | tail -40
modprobe pcie_gs201 && modprobe brcmfmac'
```

- **Pass:** three `rc=0`; no "failed to suspend"; no UFS error; display,
  touch, Bluetooth and haptics work afterwards; Wi-Fi reconnects.
- **Risk:** low to medium. The CPUs never stop, but at `devices` and
  `platform` every driver runs its suspend and resume callbacks, UFS's
  included (at `spm_lvl` 5 the device powers down and the link goes off).
  The slowest resumes go in the notes (`pm_print_times`).

**H2: one real s2idle, woken by the RTC.** `tools/phone-ssh "$pre"`, then
turn the panel off with one short press of Power (the shell's own path;
gs-decon does nothing at system sleep on gs101, [U] on zuma), then
`tools/phone-ssh "$(freeze_cmd h2 30)"`. Power is the fallback wake.

- **Pass:** `rc=0`; asleep about 30 s; `wakeup_irq` is pmic-1's interrupt;
  no UFS error; the PIN pad comes up on Power; touch, display, Bluetooth
  and haptics work; Wi-Fi reconnects after the reload.
- **Risk:** low to medium: zuma's first s2idle on this unit (Lef's ran on
  another 8 Pro).

**H3: the user's path, `systemctl suspend`, woken by Power.** Wi-Fi
unloaded by hand (no hook yet). As Lef's #642 run: logind sends
PrepareForSleep, the lock and `omamobile-sleepd` see the resume.

```sh
tools/phone-ssh "$pre"
tools/phone-ssh 'systemd-run --collect --unit=h3-test sh -c "sync; systemctl suspend"'
# Colin presses Power once after about 60 s
tools/phone-ssh 'journalctl -k -b -o short-monotonic | grep -E "PM: suspend (entry|exit)" | tail -2
journalctl -b --user -M colin@ -u omamobile-sleepd -n 5 --no-pager; cat /sys/power/pm_wakeup_irq
modprobe pcie_gs201 && modprobe brcmfmac'
```

- **Pass:** asleep until Power, woken by the gpio-keys interrupt, the lock
  screen lit within about a second of the kernel resume (#642: 58 ms to
  sleepd, about 0.5 s for the display), no UFS error.

**H4: ten cycles, unattended between presses but on the cable.**
`rtcwake -m freeze -s 20` with 10 s awake between, Wi-Fi unloaded once
before the loop.

- **Pass:** ten `rc=0`; `suspend_stats` +10 success / 0 fail; no UFS
  error; no stray wake from Volume Up (cheetah's S2 saw one: Volume Up has
  no internal pull there; check husky's `gpio-keys` wakes in the log).

**After H4, not in this runbook:**

- **Battery numbers** (cable out, so attended only): awake vs asleep from
  the gauge's `charge_counter`, as raven's tables. Expect little saving
  without cpuidle; the number is for POWER-PLAN, not a pass mark.
- **A husky sleep hook** in the device package: raven's `omamobile-sleep`
  in unload mode first (unload `brcmfmac_wcc brcmfmac pcie_gs201` before
  sleep, reload on a lit wake), then Wi-Fi across sleep once the zuma D3
  handshake is tested.
- **Auto sleep** (`omamobile-sleepd` with the toggle on): only after H4 and
  the hook.
- **NFC** with its driver bound across s2idle (#209's note), the modem,
  the AoC across sleep, and SYS_SLEEP: separate plans.

## 4. Results

None yet.
