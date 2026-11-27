<!-- SPDX-License-Identifier: MIT -->
# neard (Omamobile build)

neard 0.20, the Linux NFC daemon, with `nfctool`. Neither Arch Linux nor
Arch Linux ARM packages it, so the NFC stages in
`device/cheetah/RADIOS-CAMERA-PLAN.md` (section 3.7, N2 and N3) need this.

Build and install it on the phone:

```sh
tools/phone-install-package packages/neard
```

| Piece | Use |
| --- | --- |
| `nfctool -l` | List NFC adapters (`nfc0`) and their protocols |
| `nfctool -d nfc0 -1` / `-0` | Power the controller up (NCI init) / down |
| `nfctool -d nfc0 -p` | Poll as initiator until a tag or device is found |
| `neard` (`neard.service`) | D-Bus API (`org.neard`): adapters, tags with their `Uid`, NDEF records |

- `neard.service` is installed, not enabled. With upstream's
  `/etc/neard/main.conf` (`DefaultPowered`, `ConstantPoll`), a running neard
  powers every adapter it finds and keeps polling.
- Built without `--enable-ese`: the ST54J's secure element is never driven
  from Linux.
- Never run `nfctool -w` (firmware download). The controller keeps the
  firmware Android installed.
- The kernel's NFC core registers an rfkill switch per adapter (type `nfc`):
  `rfkill block nfc` powers the controller down and keeps it down,
  `rfkill unblock nfc` allows it to be powered again (by neard or `nfctool`).
