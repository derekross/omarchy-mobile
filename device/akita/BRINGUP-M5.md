<!-- SPDX-License-Identifier: MIT -->
# akita M5: speed (CPU frequency scaling, thermal, the GPU)

**Status (2026-11-15):** **M5 is complete on the phone.** The CPUs scale to the 8a's caps (mid +33 %, big +84 % on one core), nine cores at full load for 3 minutes peaked at 71 C without throttling, and the GPU renders the session. It's "definitely better but not perfectly responsive": what's left is the display path, simpledrm copying every frame, which needs the display driver (the next milestone). See [Results](#results).

The kernel side is linux-omarchy-mobile#264, merged on 2026-11-21: three commits on `omamobile` at `26867fc4e` (CPU DVFS with the 8a's caps; the GPU's levels moved into `zuma.dtsi` for both zuma boards; the 8a's GPU, to 723 MHz), on top of #158 (CPU DVFS, thermal) and #157's GPU commits. The device package's GPU ceiling is omarchy-mobile#832, merged the same day. M4 is complete ([BRINGUP-M4](BRINGUP-M4.md)).

## Goal

1. **CPU frequency scaling on the 8a,** with the 8a's own battery-limiter caps, and thermal zones that throttle it.
2. **The GPU:** panthor on the Mali-G715, a render node, and Hyprland drawing with it.
3. **Measured before and after:** how slow the session was, and how fast it is now; how hot the phone gets under load, with the throttling seen working.

Out of scope:
- the display's DRM driver and 120 Hz (gs-decon, a panel driver for the ak3b): its own milestone;
- cpuidle and suspend;
- video decode (MFC, BigWave);
- a skin-temperature sensor.

Slot A stays stock. Only slot B's boot images and `userdata` are written.

## What akita inherits

- **Kernel, merged on `omamobile`:**
  - **#158:** `zuma.dtsi` has the three CPU clusters' level tables (`cpucl0_opp`, `cpucl1_opp`, `cpucl2_opp`), with each level's power from stock's energy model, the ACPM TMU and the CPU thermal zones. **The tables are only used where a board file points its CPUs at them,** and today only `zuma-husky.dts` does. The reason is the levels marked `turbo-mode`: they're the 8 Pro's battery-limiter (BCL) caps, and "a board whose BCL caps are lower needs tables of its own" (`zuma.dtsi`). The maintainer raised this for the 8a on #158.
  - **#157:** CMU_G3D, the GPU node, zuma's `clk-acpm` variant with the paired "gpu" clock, and a GPU thermal zone. `zuma-husky.dts` enables `&cmu_g3d` and `&gpu` and gives it a 13-level table up to 890 MHz.
- **omarchy-mobile:** husky's device package lets the ACPM GPU clock reach stock's 890 MHz (`omamobile-husky-clk-acpm.conf`).
- **husky's lessons:**
  - software video decode took the SoC to 86 C, so the 8 Pro's test phone runs lowered trips and CPU caps as a stopgap (ROADMAP, Thermal row);
  - panthor logs `no regulator (mali)` for its levels, not yet explained.

## Facts

From R/ (the stock live tree) and G/ (`zuma-akita-bcl.dtsi`):

| Item | akita | husky | Source |
| --- | --- | --- | --- |
| CPU levels | little 324–1704 MHz (10), mid 402–2367 MHz (15), big 500–2914 MHz (15): **the same levels and powers as the 8 Pro's** in stock's default energy model | the same | [V] R/ `pixel-em`; `zuma.dtsi` |
| BCL caps | CPUs **little 1475, mid 1549, big 2147 MHz** on all four events (batoilo, vdroop1, vdroop2, smpl_gm); **GPU 649 (batoilo), 723 (vdroop1), 580 (vdroop2) and 649 MHz (smpl_gm)** | CPUs mid 1945, big 2294 MHz (little uncapped); GPU 890 MHz on vdroop1 | [V] G/ `zuma-akita-bcl.dtsi` `freq_qos`; `zuma.dtsi`'s comment |
| GPU levels | stock's table: 150–890 MHz, max 890 (`gpu_dvfs_max_freq`), the same shader rates as the 8 Pro's. **With the limiter's caps, the 8a's top is 723 MHz** (vdroop1, the highest of its four) | 13 levels to 890 MHz | [V] R/ `gpu_dvfs_table_v1`/`_v2` |
| Thermal sensors | **none yet on akita's running kernel** (built on `2db2bc35b`, before #158): its one zone is the battery's, so phone-smoke's "hottest zone 36 °C" was the battery. Today's `omamobile` gives akita the shared ACPM TMU and its zones: CPU 80 and 95 C passive, 105 C critical; GPU 85 C passive, 105 C critical | the same zones | [V] the phone, 2026-11-15; #158's thread |
| Stock's thermal trips | CPU passive ("control") at 90 C (mid, big) and 95 C (little), GPU 90 C, hot at 115 C | — | [V] R/ `thermal-zones` |

So **akita's levels are husky's; only the turbo-mode marks differ.** Above its caps the 8a would have more levels marked turbo:
- little: 1548 and 1704 MHz, where the 8 Pro has none;
- mid: 1572 MHz and up, where the 8 Pro starts at 2130;
- big: 2294 MHz and up, where the 8 Pro starts at 2363.

**Why the caps matter:** stock lowers the clocks when the battery's voltage droops. We have no BCL driver, so the levels above the caps stay off unless boost is turned on. Running them without a limiter risks a brown-out under a heavy load on a low battery.

## Design

1. **The CPU tables.** Two ways, and the maintainer chooses:
   - **(a) Mark the extra levels in `zuma-akita.dts`:** point the CPUs at `zuma.dtsi`'s tables, and add `turbo-mode;` to the levels above the 8a's caps by node path (`&{/opp-table-cpucl0/opp-1548000000} { turbo-mode; };`). This is small, and the levels and powers stay in one place. It only works because the 8a's caps are lower than the 8 Pro's: the board file can add marks but can't remove husky's.
   - **(b) Give akita its own three tables** in `zuma-akita.dts`, as `zuma.dtsi`'s comment suggests. Longer, but self-contained.

   I'd propose (a), and ask on the PR.
2. **The GPU:** `&cmu_g3d` and `&gpu` as in `zuma-husky.dts`. Its 13-level table is in husky's board file, so either akita gets a copy, or the table moves to `zuma.dtsi`, the maintainer's call. akita's device package gets husky's ACPM clock file (with a byte-for-byte test, as with the USB rescue).
3. **One change per boot,** as before. Thermal comes first (M5.1), before anything can raise the clocks.
4. **Safe defaults:** boost stays off (no turbo levels), and the GPU stops at 723 MHz, the highest of the 8a's BCL caps for it, in both the device tree (the levels above it deleted) and the package's ACPM ceiling (`zuma_gpu_max_khz=723000`). Stock's DVFS top, 890 MHz, is above all four of the 8a's GPU caps.

## Runbook

Each boot needs the human's go and changes one thing. **Each step's results end with slot B's tries left.** Before a step that can reset the phone, B must have at least 2 tries.

### M5.0 Laptop only
- **Read in full:** #157's and #158's diffs and threads; husky's ROADMAP Thermal and GPU rows; Google's `zuma-akita-bcl.dtsi`; stock's thermal trips for the 8a (R/).
- **A baseline on today's kernel,** so there's a "before":
  - boot time (`systemd-analyze`);
  - one CPU benchmark per cluster (a fixed `openssl speed` run, pinned with `taskset`);
  - the TMU zones at idle and under that load;
  - a rough measure of the session's frame rate.
- **Ask the maintainer:** (a) or (b) for the CPU tables, and where the GPU table lives.

### M5.1 Today's kernel, thermal only
- **Change:** akita's board file on today's `omamobile` (with #158), nothing else. The CPUs still have no levels, so nothing scales, but the TMU and the CPU/GPU zones appear for the first time, with their 105 C critical trip.
- **Pass:** the zones read sane, close to each other, at idle and under the M5.0 load; no new error lines.

### M5.2 CPU frequency scaling
- **Change:** the CPUs pointed at the tables with akita's turbo marks.
- **Pass:**
  - cpufreq-dt registers three policies (little 0–3, mid 4–7, big 8);
  - `scaling_available_frequencies` matches the levels, and boost is off, so the top usable levels are 1425, 1418 and 2147 MHz;
  - `schedutil` moves the clocks with load and back down at idle;
  - the same benchmark scales as expected against the M5.0 baseline;
  - the thermal zones' cooling devices are bound to the CPUs.

### M5.3 Thermal under load
- **No change to the image:** a measured CPU load with the zones watched every second, with the phone in hand and on the cable.
- **Pass:**
  - the temperatures rise and settle;
  - if a passive trip is reached, the clocks step down (`cur_state` rises) and the temperature holds;
  - the phone stays comfortable to hold.
- **Stop condition:** any zone over 80 C, or the phone hot to the touch: stop the load at once.

### M5.4 The GPU
- **Change:** `&cmu_g3d` and `&gpu` with `zuma.dtsi`'s table less the levels above 723 MHz, plus the ACPM clock file in akita's package.
- **Pass:**
  - panthor binds, and `/dev/dri/renderD128` exists;
  - GL and Vulkan enumerate (`eglinfo`, `vulkaninfo --summary`);
  - Hyprland renders with the GPU, not llvmpipe;
  - devfreq moves the GPU clock with load;
  - the GPU thermal zone reports.

### M5.5 The session (gate i)
- **No change:** the M5.0 measurements again, plus the shell by hand (swipes, app launch, the keyboard).
- **Pass:**
  - clearly faster than M5.0, with numbers;
  - `tools/phone-smoke` reads GPU ok;
  - no new error lines;
  - 10 minutes of normal use without overheating.

## Risks

- **Heat.** There's no skin-temperature sensor and no BCL. husky's SoC reached 86 C on a software video decode. So boost stays off, M5.2 has a hard stop, and the phone is in hand during every load.
- **Brown-outs:** without a limiter, the levels above the caps stay off.
- **ACPM:** the GPU clock is set through the ACPM firmware, as on husky. Only stock's rates are requested, never above the 8a's 723 MHz cap.
- **Slot B's tries:** each change is a boot.

## Open questions

- (a) or (b) for the CPU tables? (the maintainer; proposed in the M5.2 PR rather than asked separately)
- Where does the GPU table live? (the maintainer, in the M5.4 PR)
- Does panthor's `no regulator (mali)` matter? (husky, open)
- ~~Stock's thermal trips against `zuma.dtsi`'s?~~ Ours are lower (80 C passive against stock's 90–95 C), so more cautious (M5.0).

## Results

### 2026-11-15: the baseline (M5.0)

The kernel: `7.3.0-rc6-omamobile-push1-g8136602c700c` (`2db2bc35b` + #246), no cpufreq, no GPU, no SoC thermal zones, on slot B from M4.7's `bin/omamobile flash`. Battery 32.5 C.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 49 | Boot time | `systemd-analyze`: 2.070 s kernel + 3.265 s userspace = 5.335 s; graphical.target at 2.566 s | The "before" |
| 50 | Each cluster's clock, measured | A loop of four dependent adds, pinned with `taskset`: **little ≈1411 MHz, mid ≈1060 MHz, big ≈1156 MHz** (closest levels: 1425, 1065, 1164) | The bootloader leaves the big core below the little ones. With M5.2's tops (1425/1418/2147, boost off), mid gains about a third and big nearly doubles |
| 51 | One core per cluster, `openssl speed -seconds 5 -bytes 16384 sha256` | little 912523 k/s, mid 796137 k/s, big 735764 k/s | The benchmark to repeat in M5.2 |

No session frame-rate number yet: with no GPU, the compositor's own timing isn't a fair measure, so M5.5 will compare the same hand tests (swipes, app launch, keyboard) and time an app launch instead.

Slot B: 2 tries left.

### 2026-11-15: today's kernel, thermal only (M5.1)

The kernel: `7.3.0-rc6-omamobile-push1-g317d87dc2db0`, `omamobile` at `317d87dc2` with nothing added (it has #246 and #158). No gauge-model overlay. On slot B by `bin/omamobile modules-push`, then `bin/omamobile flash`.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 52 | The thermal zones | `gs101-acpm-tmu: 4 thermal zones`: big, mid and little with trips at 80 and 95 C (passive) and 105 C (critical), and gpu at 85 C (passive) and 105 C (critical). 52/52/53/47 C just after boot, settling to 45/45/43/44 C at idle. No cooling devices, since there's no cpufreq yet | akita reads its SoC temperatures for the first time |
| 53 | The M5.0 load again, temperatures every second | sha256 915443 / 795982 / 735292 k/s, within 0.3 % of M5.0. The loaded cluster's zone rose by 1 to 3 C at most (big 45 to 48 C) | The clocks and the "before" are unchanged; one core at the bootloader's rate barely warms the chip |
| 54 | `tools/phone-smoke` | Every required row ok, 2 known error lines and 0 new, thermal ok (hottest zone 46 °C, now the SoC's), battery 90 % charging, GPU not ok as before. The rescue started from the package | No regressions from today's `omamobile` |

Slot B: 2 tries left.

### 2026-11-15: CPU frequency scaling (M5.2)

The kernel: `7.3.0-rc6-omamobile-push1-g03e86b1eb814`, M5.1's plus `03e86b1eb` (the CPUs on `zuma.dtsi`'s tables, with the 8a's six extra turbo marks). On slot B by `modules-push`, then `flash`.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 55 | The policies | `policy0` (CPUs 0-3), `policy4` (4-7), `policy8` (8), all `schedutil`; `boost` 0. Tops (`scaling_max_freq`, `cpuinfo_max_freq`): **1425, 1418 and 2147 MHz**. The levels above them are listed only as boost frequencies (little 1548, 1704; mid 1572 to 2367; big 2294 to 2914). Three CPU cooling devices | The 8a's caps hold with boost off |
| 56 | Idle and one core at a time | Idle: 610/910/500 MHz, 46/46/44 C. Under the dependent-add loop: 1400, 1368 and 1985 MHz. **sha256: little 915333 k/s (+0 %), mid 1055779 (+33 %), big 1356539 (+84 %)** against M5.0. The loaded cluster went to its top and back down within a second of the load ending. The big core's zone reached 55 C under one core, and fell back to 46 C in 10 s | schedutil scales each cluster; mid and big gain what M5.0 predicted |
| 57 | `tools/phone-smoke` | Every required row ok; no oops or BUG; 0 WARN, 2 error lines in dmesg (2 known, 0 new); hottest zone 46 °C; GPU not ok, as before | No regressions |

Slot B: 2 tries left.

### 2026-11-15: thermal under load (M5.3)

The same kernel and boot as M5.2 (`7.3.0-rc6-omamobile-push1-g03e86b1eb814`). All nine cores ran `openssl speed sha256` (one per core, pinned) for 180 s, with the clocks, the three CPU zones, the cooling devices and the battery logged every second, and a stop at 80 C. The phone was on the laptop's cable, in the owner's hand.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 58 | Nine cores at full load for 180 s | **The tops held the whole time** (1425/1418/2147 MHz). The zones rose from 47/47/45 C to about 63 C in 20 s, 66 C at one minute, and **peaked at 71/69/68 C** (big/mid/little) at three minutes, still creeping up by about 1 C a minute. The cooling devices stayed at state 0 (no trip reached). The battery went from 33.4 to 35.2 C, at about 0 A net on the cable. Ten seconds after the load the zones read 51/51/50 C. **The owner: "warm but comfortable to hold"** | Throttling was never needed in 3 minutes; the 80 C passive trip leaves 9 C of margin over this test |

Not tested: a load long enough to reach the 80 C trip, so the throttling itself hasn't been seen working on akita yet. It would take a much longer run, and nothing in normal use loads all nine cores for minutes.

Slot B: 2 tries left.

### 2026-11-15: the GPU (M5.4) and the session (M5.5, gate i)

The kernel: `7.3.0-rc6-omamobile-push1-g0b04e364a09c`, M5.2's plus `0b04e364a` (CMU_G3D and the GPU, 13 levels to 890 MHz; `zuma-akita.dts` blob `210154a07fac`). On slot B by `modules-push`, then `flash`. The package: omamobile-device-akita 0.1.5 as it was then (the ACPM GPU clock's 890 MHz ceiling, since lowered to 723 MHz, test 62), built on the phone from the branch and installed before the boot.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 59 | panthor | "Mali-G715 id 0xb8a2 major 0x1 minor 0x2", `shader_present=0x1110055` (7 cores), CSF firmware interface v2.8.0, "Initialized panthor 1.9.0 … on minor 1"; `/dev/dri/renderD128`. `clk_acpm`'s `zuma_gpu_max_khz` reads 890000. devfreq `simple_ondemand`, 150 to 890 MHz in 13 levels, and it moves: 236 transitions and about 5 s at 890 MHz in the first 15 minutes. A fourth cooling device (the GPU). One error line, `_opp_set_regulators: no regulator (mali) found`, as on the 8 Pro: ACPM sets the GPU's rail | The GPU works, within stock's ceiling |
| 60 | The session | Hyprland's renderer uses the panthor device (`CDRMRenderer(drm): Using device /dev/dri/card1`) and keeps scanning out through simpledrm (`card0`); Hyprland and the shell both hold the render node; no software renderer in the log. `tools/phone-smoke`: **GPU ok** ("render node on panthor"), every required row ok, 3 known error lines and 0 new, hottest zone 50 °C | The session renders on the GPU |
| 61 | By hand (gate i), with a 1 s sampler | **The owner: "the lag is definitely better now but still not gone, it doesn't feel perfectly responsive."** During 15 s of continuous swiping the CPU clocks rose to the tops and the GPU jumped to 890 MHz in bursts; the busiest work was a kernel worker (`events_unbound`, 30 to 50 % of a core), panthor's scheduler workers (20 to 50 %) and the shell (10 to 40 %); Hyprland itself took 10 to 15 % | **Gate (i) passed, with what's left named:** the display path |

Findings:

- **What's still slow is the display path, not the GPU.** Hyprland renders into a linear 1080×2400 buffer on the GPU, and then copies it into a "dumb" buffer on simpledrm, the bootloader's framebuffer, for every frame (its log: "DRM Dumb: created a dumb allocator", "Explicit sync unsupported", `supportsAsyncCommit: false`, no VRR). simpledrm has no vsync and copies about 10 MB per frame with the CPU, which fits the busy kernel worker. The 8 Pro got past this with its display driver (kernel #160: DECON0, DSIM0 and a panel driver). akita needs the same for its ak3b panel: the next milestone.
- **Hyprland asks for a high-priority GLES 3.2 context first,** gets `EGL_BAD_MATCH`, and falls back to GLES 3.0 with normal priority. Harmless.
- `eglinfo` and `vulkaninfo` aren't on the image (`mesa-utils`, `vulkan-tools`), and the phone had no network to add them, so GL and Vulkan weren't enumerated by hand.

Slot B: 2 tries left.

### 2026-11-18: the GPU at the 8a's cap (review of #264 and #832)

The kernel: `7.3.0-rc6-omamobile-push1-g9cf0719104a1`, `omamobile` at `26867fc4e` plus #264's reworked commits: the CPUs as in M5.2; the GPU table moved into `zuma.dtsi`; the 8a's GPU with the levels above 723 MHz deleted. No display nodes. On slot B by `modules-push`, then `flash`. The package: omamobile-device-akita 0.1.5 with `zuma_gpu_max_khz=723000`, built on the phone from the branch and installed before the boot.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 62 | The GPU's top | `clk_acpm`'s `zuma_gpu_max_khz` reads 723000. devfreq: `simple_ondemand`, 150 to 723 MHz, ten levels (150, 302, 337, 376, 419, 467, 521, 580, 649, 723). During 15 s of swiping it went to 723 MHz (1.2 s there in total) and no higher, with 46 transitions, then back to 150 MHz; the zones read 44 to 46 C afterwards. The CPU tops are unchanged (1425, 1418, 2147 MHz). `tools/phone-smoke`: every required row ok, GPU ok, no failed units, 3 known error lines and 0 new | The 8a's GPU stops at its highest BCL cap, held by both the device tree and the package |

Test 62's `tools/phone-smoke` read "hottest zone 65 °C" twelve seconds after boot. On a later boot (2026-11-22, `7.3.0-rc6-omamobile-push1-g82e3cf0b7f74`, `omamobile` at `82e3cf0b7` with nothing added, on slot B by `modules-push`, then `flash`), every zone was read from the first seconds: big/mid/little/gpu were 50/49/49/48 °C at 8 s, **62**/61/59/51 °C at 13 s, 54/55/53/53 °C at 19 s and 50/50/49/49 °C at 24 s, with the battery at 33 °C throughout. So the hottest zone at boot is `big-thermal`, peaking while the session starts and every core is busy, well under its 80 °C trip; test 62's 65 °C was almost certainly that zone in the same startup burst.

Slot B: 2 tries left.
