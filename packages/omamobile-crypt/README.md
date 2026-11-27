<!-- SPDX-License-Identifier: MIT -->
# omamobile-crypt

The phone side of an encrypted root ([SECURITY-PLAN](../../docs/SECURITY-PLAN.md)).
The root on `userdata` is LUKS2; the initramfs asks for the PIN on a touch
PIN pad at power-on and opens it.

- `sudo omamobile-pin` changes the PIN for the disk, the lock screen and
  sudo together: they are one PIN. A plain `passwd` changes only the last two.
- `sudo omamobile-pin --recovery-key` replaces the recovery key (48 digits,
  shown once). It opens the disk if the PIN is forgotten, on the PIN pad or
  over SSH (`tools/phone-unlock`).
- `sudo omamobile-encrypt-hold` makes the next boot stop in the initramfs
  with the root not mounted, so `tools/phone-encrypt` on a laptop can
  encrypt it (or take it back to plain ext4). It never reboots the phone.

Nothing here runs by itself, and nothing is enabled.
