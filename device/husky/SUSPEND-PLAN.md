<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky): suspend

Status (2026-11-13): **reviewed draft, revised for #724's review; nothing
in section 3 has run on this unit.** s2idle has run on one 8 Pro already,
Lef's (section 4, from #642 and #724). This file is the runbook Derek asked
for on #656 before a first attended suspend test on another unit: what
husky has for the three things he named (Wi-Fi across sleep, UFS
`spm_lvl`, NFC), the stages, and how to get out. It follows cheetah's
[SUSPEND-PLAN](../cheetah/SUSPEND-PLAN.md) (s2idle first, SYS_SLEEP later)
and raven's, keeps the Pixel 9a's sleep-test rule (every sleep through
`systemctl suspend`, attended), and records only what differs on zuma and
the results.

Unit: G1MNW, Samsung 128 GB UFS 3.1. Slot A holds stock Android
(CP3A.261005.005); slot B holds Omarchy, whose root is `userdata`.

Kernels:

- H0 (read-only, 2026-11-12): `7.3.0-rc6-omamobile-push1-g755b5d1c5532`, a
  local build of Brett's `husky-test-20261109-t1` tag plus the RTC commits
  merged as linux-omarchy-mobile#243. Not published; used for H0 only.
- H0b to H4: the published `omamobile` branch of
  derekross/linux-omarchy-mobile at `82f31d3a7` (`7.3.0-rc6-omamobile-push1-g82f31d3a7a35`), unchanged, which has
  the GPU and CPU DVFS series (#157 with #158), the RTC interrupt (#243) and
  `mem_sleep_default=s2idle` (#244). `omamobile-device-husky` 0.1.10.

## 1. What cheetah and raven needed, and husky's state

| Needed on cheetah / raven | On husky (H0, read-only) |
| --- | --- |
| s2idle, never `deep`: the firmware offers PSCI SYSTEM_SUSPEND, so "mem" means `deep`, which has no zuma sleep sequence in Linux and would not wake | the H0 kernel predates #244 and reads `s2idle [deep]`; device-husky 0.1.10's `sleep.conf.d` drop-in makes `systemctl suspend` use s2idle. The published kernel boots with `[s2idle] deep`. Every stage sleeps through `systemctl suspend`; nothing here writes `/sys/power/state` |
| Wi-Fi: a sleep hook (cheetah, raven) that keeps it connected through brcmfmac's D3 handshake, or unloads Wi-Fi and the PCIe host | **no hook**: `/usr/lib/systemd/system-sleep/` has only Omarchy's `unmount-fuse`. Loaded: `brcmfmac_wcc`, `brcmfmac`, `pcie_gs201`, `phy_zuma_pcie`; the BCM4398 at `0000:01:00.0` in D0. Whether the D3 handshake works on zuma is unknown [U] (Lef's sleeps kept Wi-Fi loaded: "hot resume" and `Flowring creation failed` lines, section 4). So every stage unloads Wi-Fi and the PCIe host first, once H0b shows the unload and reload work on their own |
| UFS at `spm_lvl` 5 (at 3, the first hibern8 exit on resume failed and needed a host reset) | `13200000.ufs`: `spm_lvl` 5 at boot, `rpm_lvl` 3, `auto_hibern8` not supported, runtime `active` [V]. Checked again before every stage |
| NFC not polling through s2idle (AGENTS.md, the 9a) | no NFC driver bound and no `/sys/class/nfc` [V] (the node is disabled; #208 and #209 are drafts). Checked again before every stage; with a driver bound, stop |
| cpuidle with C2, or s2idle saves nothing | **no cpuidle** (`current_driver` none): the CPUs can't power down, so s2idle here is expected to save little. Lef measured about 0.5 A idle with the screen off (ROADMAP), and the idle-state and power-domain overlays tried so far reboot-looped (ROADMAP, Suspend row). These stages test that the phone sleeps and wakes cleanly, not battery life |
| The AoC modules: never `rmmod` | not loaded (no sound series on either kernel); nothing to do |

Wakeup-enabled on H0: `gpio-keys`, pmic-1 (S2MPG14) and its RTC
(`s2mpg14-rtc`, `rtc0`), the fuel gauge, the Wi-Fi function, the Bluetooth
serdev. The RTC alarm interrupt was seen to fire only awake: on 2026-11-11,
on the published kernel at `5c8b9e542`, `rtcwake -m on -s 12` returned
after 13 s and pmic-1's interrupt count went from 0 to 1. No sleep was
involved. Interrupt counts at idle on H0: pmic-1 and `rtc-alarm0` 0, the
gauge 10 (no storm). Omarchy's `suspend-off` toggle is set and
`omamobile-sleepd` runs, so the phone doesn't sleep on its own; but
UPower's critical-battery action still does (section 4, 2026-11-13).
Inhibitors: NetworkManager, UPower and Omarchy's lock, all `delay`.

## 2. Rules and recovery

- Attended for every stage and every cycle, with Colin at the phone and
  the USB cable in. One stage per go-ahead; read the result before the
  next. Nothing in this plan runs unattended.
- Slot B only, no flash between H0b and H4. Before H0b, and before any
  stage when fewer than two retries are left, refill slot B to 3 from the
  bootloader: `fastboot -s <serial> set_active b` (as in BATTERY-NOTES).
  Every boot of slot B spends one, clean ones too, and with #578 a power
  off restarts the phone and spends one more.
- Every sleep goes through `systemctl suspend` (logind, the `system-sleep`
  hooks, the 0.1.10 drop-in), started detached with `systemd-run` and
  logged to `/var/lib/omamobile/suspend/`: USB (and Wi-Fi, once unloaded)
  drops while asleep. The RTC wake is armed through sysfs first. Results
  are read from `suspend_stats` and the journal's `PM: suspend entry` and
  `PM: suspend exit` lines.
- Before every sleep: `spm_lvl` 5; no `/sys/class/nfc`; Wi-Fi and PCIe
  unloaded and their modules gone (the `pre` helper stops otherwise). After
  every stage: `dmesg | grep -E "ufshcd_err_handler|hibern8|I/O error"` is
  empty, then `modprobe pcie_gs201 && modprobe brcmfmac`.
- Never press Shut down (#578) or Suspend in the menu during these stages.

Recovery:

- **Slot A:** stock Android. A fallback there (slot B out of retries)
  boots stock, which can't read Omarchy's `userdata` and offers a factory
  reset; accepting it erases `userdata` (UFS-PLAN, U4), and on another 8 Pro
  a fallback did wipe it. Decline any reset, go to the bootloader (Power +
  Volume Down) and `fastboot -s <serial> set_active b`.
- **Dark screen, no answer to Power, but SSH answers** (the 9a's dead-UFS
  wake: a menu restart did nothing there): `echo b > /proc/sysrq-trigger`
  over SSH. On the next boot, read the journal for ext4 recovery
  (`journalctl -b -k | grep -iE "EXT4-fs|recover|orphan"`) and stop.
- **No answer on USB or SSH 3 min after the stage should have ended,
  screen dark, no reaction to Power:** hold Power + Volume Up 15-30 s (a
  frozen kernel ignores sysrq; UFS-PLAN U5), then Power + Volume Down for
  the bootloader, refill slot B, boot it, and read the ext4 recovery as
  above.
- **Wakes, but USB doesn't come back:** the session should be on screen;
  restart from the menu's Restart, then read the log.
- **Any UFS error on resume** (error handler, I/O errors, read-only
  remount): restart at once, stop, report. No more sleeps on that kernel.
- **Suspend refuses** (`suspend_stats` fail goes up, or no
  `PM: suspend entry`): not dangerous. Read `dmesg` for the device and
  stop.

Stop conditions: any UFS error; an RCU stall, soft lockup or "SMC failed";
a wake that needs the buttons or sysrq; an interrupt storm on pmic-1 or the
gauge; a device that fails to suspend or resume.

## 3. Runbook

Helpers on the laptop. `pre` stops (non-zero) unless UFS is at level 5,
NFC is absent and Wi-Fi and its PCIe host are gone; `sleep_cmd` arms the
RTC (or not) and sleeps through systemd, detached.

```sh
cd ~/omarchy-mobile
pre='U=/sys/bus/platform/devices/13200000.ufs
[ "$(cat $U/spm_lvl)" = 5 ] || { echo "spm_lvl not 5"; exit 3; }
[ ! -e /sys/class/nfc ] || { echo "NFC present"; exit 4; }
modprobe -r brcmfmac_wcc brcmfmac pcie_gs201
n=$(lsmod | grep -c -E "^(brcmfmac|brcmfmac_wcc|pcie_gs201) ")
[ "$n" = 0 ] || { echo "Wi-Fi still loaded ($n)"; exit 5; }
echo pre ok'
sleep_cmd() {   # sleep_cmd NAME [rtc-seconds]   (no seconds: wake by Power)
  local n=$1 secs=${2:-} arm='echo 0 > /sys/class/rtc/rtc0/wakealarm'
  [[ -n $secs ]] && arm="$arm; echo +$secs > /sys/class/rtc/rtc0/wakealarm"
  printf '%s' "mkdir -p /var/lib/omamobile/suspend; systemd-run --collect --unit=$n-test sh -c '
    L=/var/lib/omamobile/suspend/$n-\$(date +%H%M%S).log
    echo before success=\$(cat /sys/power/suspend_stats/success) fail=\$(cat /sys/power/suspend_stats/fail) >> \$L
    date >> \$L; sync; $arm; systemctl suspend'"
}
after='L=$(ls -t /var/lib/omamobile/suspend/*.log | head -1); cat $L
echo after success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)
echo wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2>&1)
journalctl -k -b -o short-monotonic | grep -E "PM: suspend (entry|exit)" | tail -2
dmesg | grep -E "ufshcd_err_handler|hibern8|I/O error|failed to (suspend|resume)"
modprobe pcie_gs201 && modprobe brcmfmac'
```

**H0: read-only state.** Done 2026-11-12 (section 1).

**H0b: the Wi-Fi unload and reload on their own, no sleep.** After
refilling slot B and booting the H0b kernel:

```sh
tools/phone-ssh "$pre"
tools/phone-ssh 'modprobe pcie_gs201 && modprobe brcmfmac; sleep 20
lsmod | grep -E "^(brcmfmac|pcie_gs201) "; iw dev | grep -E "Interface|ssid"
nmcli -t -f DEVICE,STATE dev | grep -i wl
dmesg | grep -iE "brcmf|pcie|gs201" | tail -20'
```

- **Pass:** `pre ok`; after the reload both modules are back, the
  interface reconnects to the same network, and `dmesg` shows no PCIe or
  brcmfmac error beyond the known noise (`Ignoring unexpected firmware
  channel`, one `brcmf_p2p_create_p2pdev: timeout`). Then H1 changes only
  one thing.

**H1: pm_test dry runs through systemd.** `freezer`, `devices`, then
`platform`: the kernel waits 5 s at that level and comes back by itself.

```sh
tools/phone-ssh "$pre"
tools/phone-ssh 'mkdir -p /var/lib/omamobile/suspend; systemd-run --collect --unit=h1-test sh -c "
  L=/var/lib/omamobile/suspend/h1-\$(date +%H%M%S).log
  echo 1 > /sys/power/pm_print_times; echo 1 > /sys/power/pm_debug_messages
  for t in freezer devices platform; do
    echo == \$t success=\$(cat /sys/power/suspend_stats/success) fail=\$(cat /sys/power/suspend_stats/fail) >> \$L
    sync; echo \$t > /sys/power/pm_test; systemctl suspend; sleep 20
  done
  echo none > /sys/power/pm_test
  echo end success=\$(cat /sys/power/suspend_stats/success) fail=\$(cat /sys/power/suspend_stats/fail) >> \$L
  dmesg | tail -400 >> \$L; sync"'
# reconnect after about a minute
tools/phone-ssh "$after"
```

- **Pass:** three `PM: suspend entry`/`exit` pairs and `suspend_stats` fail
  unchanged; no "failed to suspend"; no UFS error; display, touch, GPU,
  Bluetooth and haptics work afterwards; Wi-Fi reconnects after the reload.
- **Risk:** low to medium. The CPUs never stop, but at `devices` and
  `platform` every driver runs its suspend and resume callbacks, UFS's
  included (at `spm_lvl` 5 the device powers down and the link goes off).
  The slowest resumes go in the notes (`pm_print_times`).

**H2: one real s2idle, woken by the RTC.** `tools/phone-ssh "$pre"`, turn
the panel off with one short press of Power (gs-decon does nothing at
system sleep on gs101; [U] on zuma), then
`tools/phone-ssh "$(sleep_cmd h2 30)"`. Power is the fallback wake.
Reconnect after about a minute and run `tools/phone-ssh "$after"`.

- **Pass:** one `PM: suspend entry` and `exit` about 30 s apart; success
  +1, fail +0; `wakeup_irq` is pmic-1's interrupt; no UFS error; the PIN pad
  comes up on Power; touch, display, GPU, Bluetooth and haptics work; Wi-Fi
  reconnects after the reload.
- **Risk:** low to medium: the first RTC-woken s2idle on an 8 Pro (Lef's
  had no RTC device).

**H3: woken by Power.** `pre`, then `sleep_cmd h3` (no alarm); Colin
presses Power once after about 60 s. Then:

```sh
tools/phone-ssh "$after"
tools/phone-ssh 'journalctl -b --user -M <user>@ -u omamobile-sleepd -n 5 --no-pager'
```

- **Pass:** asleep until Power, woken by the gpio-keys interrupt, the lock
  screen lit within about a second of the kernel resume (#642: 58 ms to
  sleepd, about 0.5 s for the display), no UFS error.

**H4: ten cycles, attended throughout.** `pre` once, then ten
`sleep_cmd h4-<n> 20`, each started only after the previous one's `after`
reads clean, with Colin at the phone for the whole run.

- **Pass:** ten entry/exit pairs; `suspend_stats` +10 success / 0 fail; no
  UFS error; no stray wake from Volume Up (cheetah's S2 saw one: Volume Up
  has no internal pull there; check the wake IRQs in the logs).

**After H4, not in this runbook:**

- **Battery numbers** (cable out, so attended only): awake vs asleep from
  the gauge's `charge_counter`, as raven's tables. Expect little saving
  without cpuidle; the number is for POWER-PLAN, not a pass mark.
- **A husky sleep hook** in the device package: raven's `omamobile-sleep`
  in unload mode first (unload `brcmfmac_wcc brcmfmac pcie_gs201` before
  sleep, reload on a lit wake), then Wi-Fi across sleep once the zuma D3
  handshake is tested.
- **Auto sleep** (`omamobile-sleepd` with the toggle on), and anything
  unattended: a later plan, after H4 and the hook.
- **UPower's critical action** (section 4, 2026-11-13): whether it should
  suspend at all on husky before H4 has passed, as cheetah keeps its
  drop-in off.
- **NFC** with its driver bound across s2idle (#209's note), the modem,
  the AoC across sleep, and SYS_SLEEP: separate plans.

## 4. Results

**Lef's 8 Pro, 2026-11-10 (reported on #724).** Kernel
`7.3.0-rc6-omamobile-push1-ga291900124c4`, a local, unpublished build of
`omamobile` from about 2026-11-04 with his test commits (the AoC sound
work, the ST54L/clkout node, the S2MPG15 sub-PMIC, the GNSS node disabled,
the zuma power domains and C2 idle states both off by default, and a
PS_HOLD poweroff test for #578). It predates #243 and #244: no RTC device,
s2idle chosen by hand with `echo s2idle > /sys/power/mem_sleep`, Wi-Fi
never unloaded. One boot, `suspend_stats` 0 to 8 successes, 0 failures:

- `pm_test` freezer, devices and platform by direct `echo freeze`: each
  rc=0.
- Three real s2idle sleeps by direct `echo freeze`: 28 s, 10 s and 58 s,
  each woken by Power (IRQ 100, gpa4), devices back in 69 to 76 ms. (#642
  describes the 58 s one as `systemctl suspend`; it was a direct freeze.)
- Two sleeps through `systemctl suspend`: 756 s and 619 s, both woken by
  Power.
- At each resume: brcmfmac "hot resume" with a few `Flowring creation
  failed, code 65535`, and one UFS `dme-set: attr-id 0x4021 val 0x1 failed
  0 retries`; `spm_lvl` 5, `rpm_lvl` 3. In the 58 s run wpa_supplicant lost
  the link at suspend and rejoined after the wake (one join failed with
  firmware error -14). A tap on the dark screen did not wake it.

**This unit, 2026-11-13, unplanned (not a stage of this plan).** On the H0
kernel, off the charger overnight, the battery ran down. At 04:25 UPower's
critical-battery action asked logind to suspend; the journal ends with
`PM: suspend entry (s2idle)` and no exit. The phone was next seen at 4 %
when it was plugged in about 8.5 h later, and booted again. Whether it slept
until the battery was empty or hung in suspend can't be told from this:
there is no exit line and no later log. It shows that UPower's critical
action reaches s2idle on husky with `suspend-off` set.
