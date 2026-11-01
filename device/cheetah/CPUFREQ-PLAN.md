<!-- SPDX-License-Identifier: MIT -->
# CPU frequency plan: cpufreq-dt on the ACPM DVFS clocks (cheetah / gs201)

Status (2026-10-31): **built offline, nothing run on the phone yet.**
Kernel branch `omamobile-cpufreq` in `~/omamobile-kernel/wt-cpufreq`, four
commits on `d15487384604` (the test kernel the phone runs:
`phonetests` plus the s3c64xx and ACPM-defer fixes), built into
`~/omamobile-kernel/out-cpufreq`, images in
`~/omamobile-kernel/out-cpufreq/images`. Release
`7.3.0-rc6-omamobile-push1-g63c35fb0c871`. The runbook is section 7; C0 is next.

**Goal.** Today the phone has no cpufreq at all
(`/sys/devices/system/cpu/cpufreq` is empty): every core stays at the
bootloader's level, about 1.2 GHz little, 0.9-1.2 GHz mid and 1.0-1.1 GHz
big (ACPM-PLAN section 2), and Whisper transcribes at about 0.4-0.9x real
time (tiny.en: 10 s of speech in 3.9 s; base.en: 8.8 s). Stock runs the
clusters to 1.8, 2.35 and 2.85 GHz.

Path abbreviations, as in ACPM-PLAN:

- `L/` = our kernel, branch `omamobile-cpufreq` (`~/omamobile-kernel/wt-cpufreq`)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel)
- `GS/` = `G/google-modules/soc/gs`
- `R/` = `~/android/reference/cheetah-stock-cp2a-root` (stock live DT and logs)
- `ECT` = the ECT in the phone's own `bl2_a.img` (`cheetah-partition-backup-20261011`)

---

## 1. What we learned first

- **Our own gs101 (Pixel 6) tree already does this**
  (`L/arch/arm64/boot/dts/exynos/google/gs101.dtsi`): each CPU's `clocks` is
  its cluster's ACPM DVFS clock, cpufreq-dt runs on `operating-points-v2`
  tables, and the ACPM TMU driver (`gs101_acpm_tmu`, read-only, channel 9)
  feeds thermal zones with cpufreq cooling maps. Its history is the lesson:
  with passive trips at 85 °C, raven's big cluster went from 51 to over
  110 °C within 6 s of the UI starting and shut down in three boots of
  four; it now polls every 250 ms (100 ms when passive), throttles from
  75 °C, and drops each cluster deep at once at a second trip
  (`d46aba2e36a9`, `0279d4092e4c`).
- **The Pixel 9a's DVFS (kernel #87)** and **the Pixel 8 Pro's (kernel #158)**
  do the same on zumapro and zuma. Review findings that apply here: take the
  levels from the firmware's own table (the ECT) and stop at stock's
  `exynos-acme` `max-freq`, list the ECT levels above it in a comment;
  the power coefficients must match Google's `*-cpu.dtsi`; the "lowest
  level" cooling states must point at real entries of each table; cite
  stock's trips rather than unverifiable firmware ones. Both use cpufreq-dt
  on `clk-acpm` with no `opp-microvolt`, as here.
- **The GPU path (#84, ACPM-PLAN)**: `clk-acpm`'s gs201 variant already
  registers `cpucl0`-`cpucl2` (ids 2-4, `google,gs201-acpm.h`) with
  `CLK_GET_RATE_NOCACHE`, so a rate read asks the firmware. No driver change
  is needed for the CPU clocks.
- **Google's gs201 driver does nothing but ask ACPM**: `exynos-acme`'s
  `set_freq` is `cal_dfs_set_rate()` = one ACPM DVFS request; its
  `pre_scale`/`post_scale` are empty, and the firmware sets the voltages
  from the fused ASV tables (`GS/drivers/cpufreq/exynos-acme.c:75-150`,
  `GS/drivers/soc/google/cal-if/cal-if.c:85-102`). The domains have no
  `need-awake` (R/live.dts:2679-2741).
- **Stock's limits** (`G/devices/google/gs201/dts/gs201-cpu.dtsi`, the same in
  `R/live.dts`): min/max/resume 300/1803/1197 MHz little, 400/2348/1491 mid,
  500/2850/1826 big; dynamic power coefficients 89, 513, 757.
- **Stock's battery current limiter** caps the mid and big clusters at
  1999 and 2252 MHz on a battery voltage droop (vdroop1/vdroop2/smpl_gm), and
  all three at 930/1197/1426 MHz on battery overcurrent (BATOILO)
  (`G/devices/google/gs201/dts/gs201-cloudripper-bcl.dtsi`, `freq_qos`). We
  have no BCL driver.
- **Stock's thermal**: TMU ids 0-6 are BIG, MID, LITTLE, G3D, ISP, TPU, AUR;
  the CPU and GPU zones throttle (PI) from 100 °C and are `hot` at 120 °C
  (`G/devices/google/gs201/dts/gs201-b0.dts:153-560`); the TMU is on ACPM
  channel 9 (`gs201.dtsi`, `acpm_tmu`).
- **Stock's DVFS-manager constraints** (`dm-tables`): when the mid or big
  cluster runs high, stock raises the little cluster's floor (big 2401+ MHz:
  little at least 1401 MHz; mid 2348: 1328). The tables are named `*_perf`;
  we read them as a performance link (on gs201 the cluster's shared logic
  seems to run on CPUCL0's domain; there's no DSU domain, unlike zumapro),
  not a safety limit. **Not implemented**; see 5.4.

The ECT's CPU level lists (the PLL tables in `bl2_a.img`, parsed with
`GS/drivers/soc/google/ect_parser.c`'s layout; 15/17/21 levels as in
ACPM-PLAN section 2):

| Cluster | ECT levels (MHz) | Stock max |
|---|---|---|
| CPUCL0 (4x A55) | 2196 2098 2024 1950 **1803** 1704 1598 1401 1328 1197 1098 930 738 574 300 | 1803 |
| CPUCL1 (2x A78) | 2466 2393 **2348** 2253 2130 1999 1836 1663 1491 1328 1197 1024 910 799 696 553 400 | 2348 |
| CPUCL2 (2x X1) | 3195 3097 2950 **2850** 2802 2704 2630 2507 2401 2252 2188 2048 1826 1745 1582 1426 1277 1106 984 851 500 | 2850 |

The levels up to each stock max are exactly stock's `pixel-em` lists
(R/live.dts, `pixel_em_table`), which cross-checks the parse.

## 2. Design

Four commits on `omamobile-cpufreq`:

1. `dt-bindings: firmware: google,gs101-acpm-ipc: Add the Tensor G2 TMU`:
   `google,gs201-acpm-tmu`.
2. `thermal: samsung: gs101_acpm_tmu: Add the Tensor G2`: match data for
   the new compatible only (channel 9, seven sensors). gs101 and zumapro keep
   theirs.
3. `arm64: dts: exynos: google: gs201: add the ACPM TMU and thermal zones`:
   the `thermal-sensor` child of `acpm_ipc` and zones for sensors 0-5, each
   critical at 110 °C.
4. `arm64: dts: exynos: google: gs201: add CPU DVFS and CPU cooling`: the
   CPUs' `clocks` (`GS201_CLK_ACPM_DVFS_CPUCL0`-`2`), three shared OPP
   tables, `dynamic-power-coefficient`, `#cooling-cells`, and the CPU zones'
   passive trips and cooling maps.

Everything is in `gs201.dtsi`, so the Pixel 7, 7a and Fold boards inherit it.
Their stock limits and BCL caps are the same (Google's board files don't
override `exynos-acme`), but **only the 7 Pro will have run it**.

No new module: `clk_acpm` (already loaded at boot for the GPU) provides the
clocks, cpufreq-dt is built in and binds once they exist, and
`gs101_acpm_thermal` (`CONFIG_GS101_ACPM_THERMAL=m`, already in
`omamobile.config`) autoloads from the new node. Nothing in
`omamobile-device-cheetah` blacklists it. The default governor is schedutil
(`CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`).

## 3. Levels, caps and trips

**Operating points** (all with `clock-latency-ns = <500000>`, as gs101):

| Cluster | Normal levels (MHz) | turbo-mode (boost) | opp-suspend |
|---|---|---|---|
| little, policy0 (CPUs 0-3) | 300 574 738 930 1098 1197 1328 1401 1598 1704 1803 | none | 1197 |
| mid, policy4 (CPUs 4-5) | 400 553 696 799 910 1024 1197 1328 1491 1663 1836 1999 | 2130 2253 2348 | 1491 |
| big, policy6 (CPUs 6-7) | 500 851 984 1106 1277 1426 1582 1745 1826 2048 2188 2252 | 2401 2507 2630 2704 2802 2850 | 1826 |

- **Why the first-boot ceiling is 1803/1999/2252 MHz:** those are the levels
  stock itself falls back to whenever its BCL sees the battery voltage droop.
  Stock runs above them only because its BCL can pull the clusters back
  within microseconds; we have no BCL driver, and we don't know whether the
  bootloader leaves the PMIC's OCP-triggered clock dividers armed. A load
  step at 2.85 GHz on a weak battery could brown the phone out. The levels
  above are in the table as `turbo-mode`, so cpufreq lists them in
  `scaling_boost_frequencies` and uses them only after
  `echo 1 > /sys/devices/system/cpu/cpufreq/boost` (C6). No rebuild is
  needed to try them, and a reboot turns them off again.
- **Why no `opp-microvolt`:** ACPM picks the voltage per level from the fused
  ASV tables; Linux never sets a CPU rail. Without voltages the energy model
  isn't registered (the coefficients are there, matching stock, for when it
  is: stock's `pixel-em` power column could become `opp-microwatt`). Thermal
  cooling then works on the frequency table (step_wise), and EAS is off.
- **opp-suspend** is stock's `resume-freq`, the level stock's cpufreq holds
  through suspend (`__exynos_cpufreq_suspend`).

**Thermal zones** (sensors 0-5; polling 250 ms, 100 ms passive, as gs101):

| Zone | 75 °C passive | 85 °C passive | Critical |
|---|---|---|---|
| big-thermal → cpu6/7 | state 6 and up (2252 MHz and below: turbo off at once), then step_wise | state 12 = 1426 MHz | 110 °C |
| mid-thermal → cpu4/5 | state 3 and up (1999 MHz and below) | state 8 = 1197 MHz | 110 °C |
| little-thermal → cpu0-3 | step_wise from state 0 | state 7 = 930 MHz | 110 °C |
| gpu, isp, tpu | | | 110 °C |

States count from the top of each table, turbo levels included (cooling
states cover every valid entry). The 85 °C levels are stock's BATOILO caps.
Stock throttles from 100 °C and is `hot` at 120 °C; ours sit below both,
taken from gs101's experience with the same kind of cores.

## 4. Build and gates (2026-10-31)

Head `63c35fb0c871` (commits `df2d02737d38`, `c7d8556e2563`, `8ee64037d66b`,
`63c35fb0c871`), no Signed-off-by: Derek signs off.

- `bin/omamobile kernel`, `modules`, `initramfs`, `images`: clean. The images
  carry the descriptor's 15 overlays, which apply on top of the new nodes;
  `/chosen/bootargs` is unchanged (`mem_sleep_default=s2idle` and all).
- `tools/kernel-pr-check -C ~/omamobile-kernel/wt-cpufreq --build
  ~/omamobile-kernel/out-cpufreq-check d15487384604 HEAD`: subjects, policy
  (identifiers, blobs) ok; checkpatch --strict no errors (only the
  `Co-Authored-By` form warning); **7 device trees build with W=1 and
  dtbs_check with no new warnings**; the only failure is the missing human
  Signed-off-by, as intended. Its W=1 build of `gs101_acpm_tmu.c` failed on the
  host for want of `bc`; the same file built with W=1 in the project container
  has no warnings. `dt_binding_check` of `google,gs101-acpm-ipc.yaml` (run by
  hand with yamllint) reports only the `assigned-clocks` meta-schema note that
  the base already has.
- **DTBs:** `gs101-oriole`, `gs101-raven` and `zuma-husky` are byte-identical
  to the `d15487384604` build; only the four gs201 boards change.
- The cheetah DTB has 44 CPU levels (11 + 15 + 18), 9 of them turbo-mode.

## 5. Risks and what the first boot must check

1. **The TMU on gs201 is untested by us.** ACPM channel 9 was listed usable in
   A1 (14 of 15 channels), and Google's driver uses it, but our kernel has
   never sent a TMU message on gs201. If `gs101_acpm_thermal` fails, cpufreq
   still runs, unthrottled up to the normal ceiling. C1 checks the zones
   within the first minute and caps the CPUs if they're missing. The
   firmware's own TMU hardware trips remain as a last line.
2. **No BCL.** Hence the 1999/2252 MHz ceiling. Stay at the normal levels on
   battery until C5 has passed; boost (C6) on the charger only.
3. **Boot is busy.** schedutil starts as soon as `clk_acpm` loads, at about the
   same time as the TMU module, so the boot burst runs at up to
   1803/1999/2252 MHz. The heat that takes is far less than raven's 2.8 GHz
   burst, and well under what stock does at boot.
4. **The little-cluster floor (DVFS-manager constraint) isn't implemented.**
   If the shared cluster logic does follow CPUCL0, a big core at 2.2 GHz with
   the little cores at 300 MHz is starved. C4 measures Whisper with and
   without a 1401 MHz little floor; if it matters, the fix is a small
   cpufreq QoS link (kernel) or a floor in `omamobile-device-cheetah`.
5. **The rate the firmware actually runs.** `scaling_cur_freq` is what Linux
   asked for; `cpuinfo_cur_freq` reads the firmware (NOCACHE clock). C2
   compares them at every level. ACPM may refuse a level or pick another
   one; a mismatch is a stop.
6. **Suspend.** The opp-suspend levels are set through ACPM during
   `dpm_suspend`; C7 runs one s2idle cycle.
7. **Other gs201 boards** inherit all of this untested (section 2).

## 6. Rollback

The previous kernel is `~/omamobile-kernel/out-phonetests` (release
`7.3.0-rc6-omamobile-push1-gd15487384604`, images in
`out-phonetests/images`):

```sh
KERNEL_DIR=~/omamobile-kernel/wt-phonetests KERNEL_OUT=~/omamobile-kernel/out-phonetests bin/omamobile push
```

`push` reinstalls that build's modules when the tarball differs. If the new
kernel doesn't come up (no SSH 3 minutes after the reboot): Volume Down +
Power held about 20 s for fastboot, then the same images through
`bin/omamobile flash` (human only). Without a reboot, any step can be undone
at runtime by capping the CPUs to their lowest level:

```sh
tools/phone-ssh 'for p in /sys/devices/system/cpu/cpufreq/policy*; do cat $p/cpuinfo_min_freq > $p/scaling_max_freq; done'
```

## 7. Runbook (gated; run with the user, phone in Arch over USB)

Every step: announce it first (C1 reboots the phone; C3-C6 make it warm and
busy). Keep a kernel log on the laptop from C1 on:

```sh
cd ~/Projects/omarchy-mobile
mkdir -p logs; tools/phone-ssh --fresh 'cat /dev/kmsg' > logs/cpufreq-$(date +%Y%m%d-%H%M).log &
```

### C0. Before the push (read-only, old kernel)

```sh
tools/phone-ssh 'uname -r; ls /sys/devices/system/cpu/cpufreq; ls /sys/class/thermal; cat /sys/class/power_supply/battery/capacity'
ls -l ~/omamobile-kernel/out-cpufreq/images ~/omamobile-kernel/out-cpufreq/modules-*.tar.zst
```

- **Expect:** `7.3.0-rc6-omamobile-push1-gd15487384604`, no cpufreq, no
  thermal zones; battery at least 50 %; the images and the modules tarball
  of `7.3.0-rc6-omamobile-push1-g63c35fb0c871`.
- **Stop:** a different running kernel (then the rollback in section 6 needs
  that kernel's build instead), or battery below 50 %.
- **Risk:** none.

### C1. Boot the cpufreq kernel, then read only

Announce: the phone reboots.

```sh
KERNEL_DIR=~/omamobile-kernel/wt-cpufreq KERNEL_OUT=~/omamobile-kernel/out-cpufreq bin/omamobile push
```

Within the first minute after SSH comes back, first the zones (the stop
condition), then the policies:

```sh
tools/phone-ssh --fresh 'uname -r
for z in /sys/class/thermal/thermal_zone*; do echo "$z $(cat $z/type) $(cat $z/temp) $(cat $z/policy)"; done
for c in /sys/class/thermal/cooling_device*; do echo "$c $(cat $c/type) max $(cat $c/max_state) cur $(cat $c/cur_state)"; done'

tools/phone-ssh 'cat /sys/devices/system/cpu/cpufreq/boost
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  echo "$p cpus $(cat $p/related_cpus) $(cat $p/scaling_driver) $(cat $p/scaling_governor) min $(cat $p/cpuinfo_min_freq) max $(cat $p/cpuinfo_max_freq) cur $(cat $p/scaling_cur_freq) fw $(cat $p/cpuinfo_cur_freq)"
  echo "  normal: $(cat $p/scaling_available_frequencies)"
  echo "  boost:  $(cat $p/scaling_boost_frequencies)"
done
dmesg | grep -i -E "acpm|cpufreq|thermal|opp|energy|tmu" | tail -40
dmesg | grep -c ufshcd_err_handler'
```

- **Expect:**
  - six zones `big-thermal`, `mid-thermal`, `little-thermal`, `gpu-thermal`,
    `isp-thermal`, `tpu-thermal`, `step_wise`, reading 30-65 °C;
    `6 thermal zones` from `gs101-acpm-tmu` in dmesg;
  - cooling devices `cpufreq-cpu0` max 10, `cpufreq-cpu4` max 14,
    `cpufreq-cpu6` max 17, all at cur 0 while cool;
  - `boost` 0; policy0 (0-3), policy4 (4-5), policy6 (6-7), `cpufreq-dt`,
    `schedutil`; max 1803000, 1999000, 2252000; normal and boost lists as in
    section 3; `cur` and `fw` the same on each policy;
  - no ACPM errors or timeouts; possibly an energy-model message (no
    voltages: expected).
- **Pass:** all of the above, and the phone works as before (display, touch,
  Wi-Fi, sound).
- **Stop:** no thermal zones, or a zone reading 0, negative or above 90 °C at
  idle: run the cap from section 6 at once, then roll back. ACPM errors,
  `cur` and `fw` disagreeing, or the phone hanging: roll back.
- **Risk:** medium (new kernel; the TMU is a new ACPM client).
- **Rollback:** section 6.

### C2. The firmware follows every level (one policy at a time)

```sh
tools/phone-ssh 'bash -s' <<'EOF'
for p in 6 4 0; do
  d=/sys/devices/system/cpu/cpufreq/policy$p
  echo userspace > $d/scaling_governor
  for f in $(cat $d/scaling_available_frequencies); do
    echo $f > $d/scaling_setspeed; sleep 0.2
    echo "policy$p set $f fw $(cat $d/cpuinfo_cur_freq)"
  done
  echo schedutil > $d/scaling_governor
done
EOF
tools/phone-ssh 'taskset -c 6 openssl speed -seconds 3 sha256 2>/dev/null | tail -1'   # under schedutil
```

- **Expect:** `fw` equals `set` at every normal level; the sha256 rate on
  CPU 6 about twice today's (1.1 → 2.25 GHz).
- **Stop:** a mismatch, an ACPM error, a freeze.
- **Risk:** low (levels stock uses every day; only the normal ones).
- **Rollback:** `echo schedutil > .../scaling_governor`; the cap; section 6.

### C3. All cores loaded, on the charger, with throttling (attended)

Announce: the phone gets warm. Charger connected, battery at least 50 %.

```sh
tools/phone-ssh 'bash -s' <<'EOF'
T=/sys/class/thermal; C=/sys/devices/system/cpu/cpufreq; Z=; D=
for z in $T/thermal_zone*; do case $(cat $z/type) in big-*|mid-*|little-*) Z="$Z $z";; esac; done
for d in $T/cooling_device*; do case $(cat $d/type) in cpufreq-*) D="$D $d";; esac; done
[ -n "$Z" ] && [ -n "$D" ] || { echo "STOP: no CPU zones"; exit 1; }
for c in 0 1 2 3 4 5 6 7; do taskset -c $c timeout 180 sh -c 'while :; do :; done' & done
for i in $(seq 1 185); do
  t=$(for z in $Z; do cat $z/temp; done | tr '\n' ' ')
  f=$(for p in 0 4 6; do cat $C/policy$p/scaling_cur_freq; done | tr '\n' ' ')
  s=$(for d in $D; do cat $d/cur_state; done | tr '\n' ' ')
  echo "$i temp $t freq $f state $s"
  for v in $t; do
    if [ "$v" -ge 95000 ]; then
      echo "STOP: $v"; pkill -f "while :; do :; done"
      for p in $C/policy*; do cat $p/cpuinfo_min_freq > $p/scaling_max_freq; done
      exit 1
    fi
  done
  sleep 1
done
EOF
```

The script picks the big, mid and little zones and the cpufreq cooling
devices by type (the battery has a zone too), and stops itself at 95 °C.

- **Expect:** the clusters at 1803/1999/2252 MHz at first; the zones reach
  75 °C and the cooling states rise (big and mid at once to 6 and 3);
  the temperatures settle at 75-85 °C, briefly above 85 with the deep caps;
  none reaches 95 °C. Afterwards the zones fall below 70 °C within a minute
  and the frequencies come back.
- **Pass:** 180 s without a STOP, a reset or a critical trip.
- **Stop:** the script's 95 °C guard, a reset, ACPM errors,
  `ufshcd_err_handler` lines.
- **Risk:** medium.
- **Rollback:** the guard caps the CPUs itself; then section 6 if needed.

### C4. Whisper, the reason for this plan

```sh
# a fixed 10 s recording, so every run transcribes the same audio
tools/phone-ssh 'command -v voxtype; voxtype --help | head -20'
```

Time tiny.en and base.en on the same 10 s of speech as the 3.9 s / 8.8 s
baseline, through `voxtype` (its file/transcribe mode if the installed
version has one, otherwise the shell's voice sheet with a stopwatch), three
runs each. Then again with a little-cluster floor:

```sh
tools/phone-ssh 'echo 1401000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq'
# ... the same runs ...
tools/phone-ssh 'echo 300000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq'
```

- **Expect:** at least 1.5-2x faster than the baseline. Note the floor's
  effect (5.4).
- **Stop:** as C3.
- **Risk:** low.

### C5. On battery, normal levels (attended)

Unplug (battery at least 50 %). Run C3's script for 60 s instead of 180
(`timeout 60`, `seq 1 65`).

- **Expect:** as C3, and no brownout: no reset, no `uvlo`/`smpl` messages, the
  gauge's voltage (`/sys/class/power_supply/battery/voltage_now`) above
  3.4 V under load.
- **Pass:** this is the gate for leaving schedutil on at the normal levels by
  default.
- **Stop:** a reset (that's a brownout: stay at the normal levels and look at
  the BCL before anything else), a hang.
- **Risk:** medium.

### C6. Boost (turbo levels), on the charger only

```sh
tools/phone-ssh 'echo 1 > /sys/devices/system/cpu/cpufreq/boost; for p in 4 6; do cat /sys/devices/system/cpu/cpufreq/policy$p/cpuinfo_max_freq; done'
```

Repeat C2 for the boost levels of policy4 and policy6 (they appear in
`scaling_available_frequencies` once boost is on), then C3 for 60 s.
Afterwards `echo 0 > /sys/devices/system/cpu/cpufreq/boost`.

- **Expect:** max 2348000 and 2850000; `fw` follows; at 75 °C big and mid
  leave the turbo levels at once.
- **Stop:** as C3; any reset.
- **Risk:** medium-high. Never on battery until a BCL exists.

### C7. One s2idle cycle

```sh
tools/phone-ssh 'rtcwake -m freeze -s 20; for p in 0 4 6; do cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_cur_freq; done; dmesg | tail -30'
```

- **Expect:** the phone wakes after 20 s; the policies back on schedutil;
  no ACPM or cpufreq errors around the freeze.
- **Stop:** no wake (Power wakes it; then roll back), errors.
- **Risk:** low-medium.

## 8. Results

(none yet)

## 9. After this

1. Make it permanent: merge `omamobile-cpufreq` into `omamobile-int`; a
   tmpfiles entry for the governors as raven has
   (`omamobile-raven-cpufreq.conf`) isn't needed (schedutil is the default).
2. GPU cooling on `gpu-thermal` (panthor's devfreq `#cooling-cells`), then
   lift the 572 MHz GPU cap (ACPM-PLAN 8.2).
3. An energy model (`opp-microwatt` from stock's `pixel-em`), then
   power_allocator for the big cluster.
4. The little-cluster floor (5.4), if C4 shows it matters.
5. A BCL driver (S2MPG12/13 OCP and UVLO), before the turbo levels can be
   on by default.
