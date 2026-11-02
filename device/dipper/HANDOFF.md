<!-- SPDX-License-Identifier: MIT -->
# Handoff: Omarchy Mobile on Xiaomi Mi 8

Read STATE.md, ../../AGENTS.md, NOTES.md, FLASH-RUNBOOK.md and WIFI-PLAN.md.
The repository-root PORTING-PLAN.md is a historical discovery log.

## Pick up here

Last checked 2026-11-02: Omarchy is running on the phone, and the owner has
confirmed that the display is visible. A fresh USB SSH connection through
tools/phone-ssh --fresh succeeded and sshd is active. The display is exposed as
DSI-1 (405x843 in the current Wayland session). A VNC protocol handshake
succeeded, but rendering and remote input through a user's client have not
been checked.

This repository intentionally contains no owner SSID, LAN address, SSH alias,
SSH key path, password, token, or private backup path. No reboot, flash or
partition write was performed during the 2026-11-02 remote-access checks.
Audio playback, sensors and 3D acceleration still need separate verification;
do not infer them from device enumeration alone.

## Next work

1. Keep device support changes in this repository and submit kernel drivers,
   bindings and DTS changes to the kernel repository as separate subsystem
   branches, following CONTRIBUTING.md.
2. Run the repository checks and the read-only phone smoke test before opening
   a pull request. Record only results, never captures or device identifiers.
3. Continue audio, sensor and GPU validation only from the corresponding
   gated plans, with the verified stock backup available before radio work.

## Stop conditions

- Do not erase or format userdata, or use the shared Pixel installer.
- Do not flash the boot image without a separate explicit decision and the
  phone physically available for recovery.
- Stop radio work if the off-device stock backup cannot be checksum-verified,
  if read-only partition protection is not confirmed, or if live logging and
  SSH recovery are lost.
