<!-- SPDX-License-Identifier: MIT -->
# flame: WCN3990 Bluetooth bring-up

Status (2026-10-18): controller initialization failed in separate,
out-of-tree Arch development work with kernel `7.0.0-sm8150`.
Kernel source: [postmarketOS SM8150 Linux][kernel], tag `v7.0.0-sm8150`;
packaged inputs and output directories are described in
[BRINGUP-M1](BRINGUP-M1.md). The shipped RAM-only probe keeps Bluetooth
unloaded and offers no native installation path.

[kernel]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/tree/v7.0.0-sm8150

## Measured result

In that separate Arch payload, a guarded manual `hci_uart` load registered
`hci0`; BlueZ was running, but its object tree contained no
`org.bluez.Adapter1`. The kernel's QCA
version command (`0xfc00`) timed out with `-110` on every power-on retry.
This happens before firmware download, so staging a different firmware
filename alone does not address the observed failure. The matching factory
firmware was kept private. No pairing or discovery success is claimed.

The development payload retained a fresh USB SSH connection, and its recovery
timer was stopped after that check. Calibration and modem partitions stayed
protected.
Automatic module loading was blocked by a local development blacklist;
that file is not shipped in this repository. `bluetoothctl` was
absent from that payload; the missing utility is separate from
the controller's initialization failure.

## Next gated checks

Compare the kernel's `uart13` pins, supplies and clock setup against the
matching factory device tree and Google's GPL source, selecting the actual
board revision rather than the first concatenated DTB. Retry alongside
Wi-Fi only under the same backup, watchdog and recovery gates in
[WIFI-PLAN](WIFI-PLAN.md). A shared clock dependency is a hypothesis, not a measured cause.

| Step | Expect / pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Compare source and selected stock DT | UART, pin and supply mapping supported by evidence | Ambiguous board selection | Stop before hardware changes | Low |
| Verify fresh backups and watchdog; stream logs off-device | Protected hashes match; watchdog held; recovery timer armed | Any mismatch or missing safety net | Stop | Low |
| Load one reviewed driver/DT change | QCA version reply and firmware load; fresh recovery SSH works | UART timeout, firmware crash, storage fault or USB loss | Recovery timer/watchdog; physical Android fastboot if needed | Medium |
| Discover and pair a known accessory | BlueZ Adapter1, successful discovery and pairing | Controller reset or errors | Power off Bluetooth through BlueZ | Medium |

Do not enable automatic Bluetooth startup until controller initialization
and repeated recovery checks pass. Never publish addresses, identifiers,
factory firmware or calibration data.
