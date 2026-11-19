<!-- SPDX-License-Identifier: MIT -->
# modemmanager (Omarchy Mobile build)

Arch Linux's ModemManager 1.24.2-2 recipe (`modemmanager`, `libmm-glib`),
built for aarch64 with two upstream fixes that 1.24.2 lacks: commit `9317cbc4`,
"netlink: fix use-after-free calling completion_fn on transaction
completion" (upstream `main`, 2026-10-04), and commit `0edcb916`,
"base-manager: fix cleanup of multiplexed bearers" (upstream `main`).

Why: phones whose modem data path is a multiplexed rmnet link (the OnePlus
7T Pro, `qcom-soc` plugin over IPA) have ModemManager create a `qmapmux`
link over netlink for each data connection. In 1.24.2 the netlink code
freed the finished transaction and then called its completion function
through it, so ModemManager crashed (SIGSEGV) on the second data connection
of each run: mobile data came on once per boot, and turning it off and on
again killed ModemManager (device/hotdog/MODEM-PLAN.md, R6).

The second fix: over IPA every bearer is multiplexed, so the modem's limit
of non-multiplexed active bearers is 0. 1.24.2's cleanup counted a connected
bearer against that limit alone and aborted on its `g_assert`, so
ModemManager dumped core at every stop with mobile data on, at each shutdown
of the 7T Pro (device/hotdog/MODEM-PLAN.md, R9).

Drop this package once Arch's ModemManager carries the fix (1.26 or a 1.24
point release). Changes against Arch's recipe are listed in the PKGBUILD's
header.
