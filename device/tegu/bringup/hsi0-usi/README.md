<!-- SPDX-License-Identifier: MIT -->
# HSI0 USI bring-up modules (Pixel 9a)

The evidence for the sleep that never woke ([SLEEP-PLAN](../../SLEEP-PLAN.md)
S1, "What is left" item 1, and the notes of 2026-11-12 and 11-13): a register
access to a USI in the first microseconds after its clock gates are opened
never returns, and the noirq resume does exactly that. The fix is
[linux-omarchy-mobile#247](https://github.com/derekross/linux-omarchy-mobile/pull/247),
which keeps the six gates of USI2 and USI3 on. Built out of tree against the
kernel under test:

    make -C <tree> O=<out> ARCH=arm64 LLVM=1 M=$PWD modules

Neither runs on a palmtop before an attended run with the owner's yes
(AGENTS.md, the 9a sleep entry). The first runs of both, on 2026-11-12 and
11-13, did not have one.

- `tegu-hsi0-usi-clk-hold.c` takes a reference on `pclk` and `ipclk` of the
  USIs at 111d00c0 and 111e00c0 (HSI0's USI2 and USI3) while loaded, so the
  clock framework never closes their gates; `ip=0` holds `pclk` alone. It
  reads and writes no register of its own. With it loaded, 300 of 300 sleeps
  woke on the build that had hung at the 70th and the 41st
  (`push1-dbg-gc63fa9271bb8`, 2026-11-12). With #247 in the kernel it changes
  nothing.
- `tegu-hsi0-usi-stress.c` **hangs the SoC by design.** It repeats
  `exynos_usi_enable()`'s sequence on one USI from a thread bound to a CPU:
  both clocks on, `USI_CON` read and written back with the reset bit clear
  (what the driver writes at every resume), 1 us, both clocks off. On the
  build with only the PCLK gates critical (`push1-dbg-g9af120756764`),
  `usi=3` with no wait hung within the first 1,000 rounds, twice of twice,
  and the cluster watchdog reset the palmtop about 40 s later (systemd's
  runtime watchdog was feeding it; without a fed watchdog it waits for the
  buttons). `access=0` (gates switched, no register touched) and
  `delay_us=10` (10 us between the clocks and the access) each ran
  2,000,000 rounds with no hang. On a kernel with #247 the gates never close
  and 2,000,000 rounds passed on each USI.

  It refuses to load on anything but a Pixel 9a (`google,zumapro-tegu`),
  and `usi=` has no default: without `usi=2` or `usi=3` it refuses, so the
  touchscreen's USI is never switched by accident. Run it only with the
  modem off (nothing else uses USI3 then), the filesystems synced, a
  watchdog fed from userspace, and never with `usi=2` while the touchscreen
  is in use:

      insmod tegu-hsi0-usi-stress.ko loops=2000000 report=1000 usi=3 cpu=7 \
             [access=0] [delay_us=10]
