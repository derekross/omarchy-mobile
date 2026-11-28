<!-- SPDX-License-Identifier: MIT -->
# Power-domain bring-up modules (Pixel 9a)

The tools behind [SLEEP-PLAN](../../SLEEP-PLAN.md)'s power-domain entry of
2026-11-18: nothing in Linux manages the 9a's power domains, all 26 read on,
and the unused ones can be switched off from the boot state. Built out of
tree against the kernel under test:

    make -C <tree> O=<out> ARCH=arm64 LLVM=1 M=$PWD modules

**Both go round the kernel's PMU regmap.** Its zumapro tables let through
only a few offsets, so both modules map the PMU (0x15460000) and read it
with plain MMIO, and `tegu-pd-ctl` makes the regmap's write call
(the EL3 call 0x82000504) itself. That is outside the rule that PMU access
goes through the `exynos-pmu` regmap, which is why they are bring-up tools
and not a driver: the driver is a genpd provider with these offsets in the
regmap's tables. Neither runs on a palmtop without the owner's yes, the
owner within reach and a kernel log stream to the laptop first; the offsets
are zumapro's, and both refuse to load on anything but a Pixel 9a
(`google,zumapro-tegu`).

The offsets and the off sequence are from Google's GPL
`flexpmu_cal_local_zuma.h` (`drivers/soc/google/cal-if/zuma/` in
`kernel/google-modules/soc/gs`, branch `android-gs-tegu-6.1-android16`).

- `tegu-pd-status.c` is read-only: it logs each domain's `<NAME>_STATUS`
  word (bit 0 set: on) and refuses to stay loaded. `only=NAME` reads one
  domain, for a first probe. ISPFE's and HSI0's words, the two the regmap
  has, are read through it too as a check of the mapping.

      insmod tegu-pd-status.ko only=tpu
      insmod tegu-pd-status.ko

- `tegu-pd-ctl.c` **writes the PMU**: it switches one domain off (the
  domain CMU's controller option bit 24 cleared, `<NAME>_CONFIGURATION`
  bit 0 cleared, `_STATUS` bit 0 waited for), logs, and refuses to stay
  loaded. Its list is the domains nothing in Linux uses on the 9a: tpu,
  aur, eh, bw, mfc, g2d, the camera stages gdc, gse, mcsc, rgbp, tnr and
  yuvp, and dpuf1 (never switched in the runs so far). With the camera
  stages off libcamera lists no cameras.

      insmod tegu-pd-ctl.ko off=tpu

  It has no way back on, on purpose. The copy that ran on 2026-11-18 had
  one (`on=`): TPU powered on again by hand, and the next off's first read
  of TPU's CMU took a synchronous external abort and reset the palmtop.
  Switch off from the boot state only, one domain per load, with the modem
  stopped cleanly first (a reset with the modem up counts as an unclean
  end); the undo is a reboot. Hold a block sleep inhibitor for as long as
  any domain is off (`systemd-inhibit --what=sleep --mode=block ...`): on
  2026-11-18 the shell's auto-sleep put the palmtop to sleep with twelve
  domains off, and for 42 minutes that looked like a hang. The runs of
  that day also switched several domains in one boot; one change per boot
  is the rule, and a run that breaks it says so in its record.

The copies here differ from the ones that ran in two ways: the Pixel 9a
check, and `on=` removed. They build against the daily bring-up kernel's
tree with `W=1`; they have not run on a palmtop in this form.
