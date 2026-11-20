<!-- SPDX-License-Identifier: MIT -->
# Power baseline: one comparable measurement per device

The same three readings, taken the same way on every phone, so the numbers from one device can be set beside another's. The recipe is the one proposed in [#867](https://github.com/derekross/omarchy-mobile/issues/867) (Phase 0, "measure and share"); `tools/power-baseline` runs it unchanged and writes the report for the device's issue.

- **Part A**, the static picture: the kernel, the idle driver and its states, the CPU frequency governors, devfreq, every thermal zone with its trips, the cooling devices, Wi-Fi power save and the `pm_genpd` summary.
- **Part B**, the screen-off floor: cable out, screen off, nothing running. After 10 minutes to settle, the gauge's `current_now`, the battery temperature and every thermal zone, every 15 s for 3 minutes. The number to report is the median current.
- **Part C**, who is awake: interrupts and context switches per second over a minute, the top processes, the top wakeup sources, and `powertop` if it is installed.

Nothing on the phone is changed. The one thing the tool adds is a logind sleep inhibitor for the length of the run: the floor is the *awake* screen-off floor, and the shell's auto-sleep (`omamobile-sleepd`) would otherwise suspend the phone 30 s after the screen goes off behind a secure lock, once no SSH login is open. `--no-inhibit` leaves it out, for a run that wants to see what auto-sleep does.

## Running it

From the laptop, with the phone on USB:

```sh
tools/phone-ssh 'cat > /usr/local/bin/power-baseline && chmod +x /usr/local/bin/power-baseline' < tools/power-baseline
tools/phone-ssh 'power-baseline --detach'
```

Then pull the cable and turn the screen off (one press of the power key). The run waits up to 30 minutes for both and starts its 10 minute settle once the battery reads `Discharging` and `bl_power` is not 0. Leave the phone alone; about 15 minutes later it is done. USB may not come back after an unplug on the Tensor phones (USB-C-PLAN), so read the result over Wi-Fi, or after replugging (and a reboot if USB stays down):

```sh
tools/phone-ssh 'cat /var/lib/omamobile/power/*-baseline/progress.txt'
tools/phone-ssh 'cat /var/lib/omamobile/power/*-baseline/report.md'
```

Don't keep an SSH login open during Part B: sshd and Wi-Fi traffic are part of what it would measure. The run itself needs none.

Without the tool, the commands in #867 do the same by hand; they are copied into the tool verbatim, so both give the same numbers.

## Posting it

One issue per device, titled `Power baseline: <device> (<codename>)`. If one exists, add a comment to it rather than a second issue. Paste `report.md`, which already has the conditions, a summary and the three parts in `<details>` blocks, and then check it:

- **Read it before posting.** The report replaces the session user's and the host's names with `<user>` and `<host>`. Check for anything else that names the phone or the network (an SSID, a MAC address, a serial).
- **Add what the tool can't know:** the room temperature, whether the phone was in a case or on a cold surface, and anything that ran that shouldn't have.
- **Say how far the gauge can be trusted.** `Gauge:` in the conditions repeats the kernel's `battery model loaded` or `battery model load failed` line. Without a loaded model the absolute mA are rough; compare them only with runs on the same phone.
- **A missing piece is a result.** No cpuidle driver, an empty `pm_genpd`, a command that failed: post it as it came out.

A second run after every kernel or package change that claims a power win, on the same phone and under the same conditions, is what tells a real win from noise.
