<!-- SPDX-License-Identifier: MIT -->
# dodge modem

Everything here is inert unless `/etc/omamobile/modem-probe.enable` exists.
Default in the package: **off** (no `/etc/omamobile/modem-probe.enable`).
Owners who opt in need their own firmware under `/lib/firmware` and their
own EFS copies (never shipped). On a kernel without an enabled IPA DT node
`omamobile-modem-efs` exits without touching the copies, so rmtfs and the MPSS
are never started and a rollback stays safe even with the flag on.

## Boot sequence (flag present)

1. `adsp-battery.sh` loads `qcom_q6v5_pas`. The MPSS is probed; the CDSP may
   fail its load without firmware (harmless).
2. `omamobile-modem-efs.service` runs before rmtfs when IPA is present. It
   restores the named good EFS *copy set* from
   `/var/lib/omamobile/efs-good/<name>` (name in
   `/etc/omamobile/modem-efs-good`). Good sets are never rotated. Optional
   auto-snapshots under `/var/lib/omamobile/efs-snapshots/` stay on the phone.
3. `omamobile-rmtfs.service` loads `qcom_rmtfs_mem` and runs **only**
   `rmtfs -r -o /var/lib/omamobile/modem-efs -v`: read-only copies of the EFS
   partitions, with modem writes kept in RAM. Never `-P`.
4. `omamobile-tqftpserv.service` serves MCFG from `/lib/firmware`.
5. `omamobile-modem.service` starts the MPSS by name. Do **not** stop the
   modem remoteproc (hard-reset risk on 7.3); the unit has no ExecStop.
6. `omamobile-modem-online.service` provisions SIM slot 1 if needed, goes
   online, waits for registration.
7. ModemManager (drop-in `ModemManager-omamobile.conf`) and the NM profile
   `omamobile-cellular.nmconnection` (APN `internet`, metric 700) bring up
   data on `rmnet_ipa0` / `qmapmux0.0`.

## EFS restore (no blobs in git)

The modem needs the phone's own non-volatile calibration. This repository
ships **units and docs only** — never EFS snapshots, NV backups, or modem
firmware.

On the phone, once, take read-only copies of the current slot's partitions
(`dd if=` only, mode 600) into `/var/lib/omamobile/modem-efs/` (and promote a
known-good set into `/var/lib/omamobile/efs-good/<name>`):

- `oplusstanvbk_<slot>` → `oem_stanvbk`
- `oplusdycnvbk` → `oem_dycnvbk` (per-unit; keep off any shared medium)

A set the modem has written to for a few minutes can crash the next boot
(rtsar), so the good set is restored on every boot. Firmware for the MPSS
belongs under `/lib/firmware/qcom/sm8750/OnePlus/` from the owner's own
OxygenOS / factory image; it is not in git. (`tools/phone-provision` and the
Pixel extract scripts only know Pixel factory images — do not use them for
dodge firmware.)


## Off-phone backups (CONTRIBUTING §3.3)

Before any modem session, keep **off-phone**, read-only copies of:

- `modemst1`, `modemst2`
- `fsg`, `fsc`
- `persist`
- oplus NV (`oplusstanvbk_<slot>`, `oplusdycnvbk`)

Store them with a `SHA256SUMS` and re-check the hashes before each modem
session. Never commit those copies (or any EFS / modem firmware) to git. On
this phone the off-phone set lives outside the repository; the on-phone
`/var/lib/omamobile/efs-good/` set above is a separate, phone-local restore
path used when the opt-in flag is present.

## Install

Copy this directory to the phone and run `./install` as root. It expects
`rmtfs` and `tqftpserv` (linux-msm), the in-tree `rmtfs_mem` module for the
running kernel, and the firmware + EFS copies above.

Turn on: `touch /etc/omamobile/modem-probe.enable`, then reboot. Turn off:
remove the flag and reboot.

## Modules path on a stock modules-push install

`omamobile-modem` (and the Bluetooth helper) currently look for out-of-tree
modules under `/usr/lib/modules/$(uname -r).held/` and
`/usr/local/lib/omamobile/…`. A kernel installed by `modules-push` has
neither path — the scripts fail safely (no load) until the package installs
those modules next to the running release. Until then, treat modem/BT bring-up
on a pure `modules-push` tree as manual.
